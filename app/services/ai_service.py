from __future__ import annotations

import hashlib
import json
import logging
from typing import Any

import httpx
from redis.asyncio import Redis

from app.config import settings
from app.core.redis import redis_sessions

logger = logging.getLogger(__name__)

# Model configurations
SUMMARIZATION_MODEL = "facebook/bart-large-cnn"
TRANSLATION_MODEL = "facebook/nllb-200-distilled-600M"  # Supports many languages
SMART_REPLY_MODEL = "microsoft/DialoGPT-medium"
MODERATION_MODEL = "unitary/toxic-bert"

_DEFAULT_REPLIES = ["Thanks!", "Sounds good", "Let me know"]


def _cache_key(kind: str, *parts: str) -> str:
    """Stable cache key.

    Python's builtin hash() is salted per process (PYTHONHASHSEED), so keys
    built from it never survive a restart and differ between workers — every
    lookup would miss. A digest is deterministic across both.
    """
    digest = hashlib.sha256("\x00".join(parts).encode("utf-8")).hexdigest()[:32]
    return f"ai:{kind}:{digest}"


class AIService:
    """Hugging Face Inference API client with a Redis-backed response cache.

    Every method degrades gracefully: a missing token, a timeout, or an HF
    outage returns a sensible fallback rather than propagating an exception
    into the request path.
    """

    def __init__(self, redis: Redis | None = None) -> None:
        # Cache lives in the sessions DB alongside other long-lived app state
        # (see app.core.redis); keys are namespaced under "ai:".
        self._redis = redis if redis is not None else redis_sessions
        self._timeout = settings.HF_TIMEOUT_SECONDS

    @property
    def enabled(self) -> bool:
        return bool(settings.HF_API_TOKEN)

    async def _call_hf_api(self, model: str, payload: Any) -> Any:
        if not self.enabled:
            raise RuntimeError("HF_API_TOKEN not configured")

        headers = {"Authorization": f"Bearer {settings.HF_API_TOKEN}"}
        async with httpx.AsyncClient(timeout=self._timeout) as client:
            response = await client.post(
                f"{settings.HF_API_URL}/{model}",
                headers=headers,
                json=payload,
            )
            if response.status_code != 200:
                logger.error(
                    "HF API error: %s - %s", response.status_code, response.text[:300]
                )
                raise RuntimeError(f"HF API request failed: {response.status_code}")
            return response.json()

    # The Redis pools are created with decode_responses=True, so reads already
    # come back as str — no .decode() anywhere below.

    async def summarize_messages(self, messages: list[str], max_length: int = 150) -> str:
        if not messages:
            return ""

        combined = " ".join(messages[-100:])
        fallback = combined[:200] + "..." if len(combined) > 200 else combined

        key = _cache_key("summary", combined, str(max_length))
        cached = await self._redis.get(key)
        if cached:
            return cached

        payload = {
            "inputs": combined,
            "parameters": {
                "max_length": max_length,
                "min_length": 30,
                "do_sample": False,
            },
        }
        try:
            result = await self._call_hf_api(SUMMARIZATION_MODEL, payload)
            summary = (
                result[0].get("summary_text", "")
                if isinstance(result, list) and result
                else ""
            )
            if not summary:
                return fallback
            await self._redis.setex(key, 300, summary)
            return summary
        except Exception as exc:
            logger.error("Summarization failed: %s", exc)
            return fallback

    async def translate_message(self, text: str, target_lang: str) -> str:
        """Translate text. ``target_lang`` is an NLLB code, e.g. 'fra_Latn'."""
        if not text:
            return ""

        key = _cache_key("translate", text, target_lang)
        cached = await self._redis.get(key)
        if cached:
            return cached

        payload = {
            "inputs": text,
            # Source language is assumed English; NLLB needs it stated.
            "parameters": {"src_lang": "eng_Latn", "tgt_lang": target_lang},
        }
        try:
            result = await self._call_hf_api(TRANSLATION_MODEL, payload)
            translation = (
                result[0].get("translation_text", "")
                if isinstance(result, list) and result
                else ""
            )
            if not translation:
                return text
            await self._redis.setex(key, 86400, translation)
            return translation
        except Exception as exc:
            logger.error("Translation failed: %s", exc)
            return text

    async def generate_smart_replies(
        self, context: str, num_replies: int = 3
    ) -> list[str]:
        if not context:
            return []

        key = _cache_key("smartreply", context, str(num_replies))
        cached = await self._redis.get(key)
        if cached:
            return json.loads(cached)

        payload = {
            "inputs": context,
            "parameters": {
                "max_length": 50,
                "num_return_sequences": num_replies,
                "temperature": 0.7,
            },
        }
        try:
            result = await self._call_hf_api(SMART_REPLY_MODEL, payload)
            replies: list[str] = []
            if isinstance(result, list):
                for item in result:
                    if not isinstance(item, dict):
                        continue
                    generated = item.get("generated_text", "")
                    # The model echoes the prompt back — strip it.
                    if generated.startswith(context):
                        generated = generated[len(context):].strip()
                    if generated and generated not in replies:
                        replies.append(generated)
            if not replies:
                return list(_DEFAULT_REPLIES)
            replies = replies[:num_replies]
            await self._redis.setex(key, 600, json.dumps(replies))
            return replies
        except Exception as exc:
            logger.error("Smart reply generation failed: %s", exc)
            return list(_DEFAULT_REPLIES)

    async def moderate_message(self, text: str) -> dict[str, float]:
        """Return {label: score}. Empty dict means 'no verdict' — callers must
        treat that as unmoderated, never as 'safe'."""
        if not text:
            return {}

        key = _cache_key("moderation", text)
        cached = await self._redis.get(key)
        if cached:
            return json.loads(cached)

        try:
            result = await self._call_hf_api(MODERATION_MODEL, {"inputs": text})
            # toxic-bert nests its output one level deep for single inputs.
            if isinstance(result, list) and result and isinstance(result[0], list):
                result = result[0]

            scores: dict[str, float] = {}
            if isinstance(result, list):
                for item in result:
                    if not isinstance(item, dict):
                        continue
                    label = str(item.get("label", "")).lower()
                    if label:
                        scores[label] = float(item.get("score", 0.0))
            if scores:
                await self._redis.setex(key, 3600, json.dumps(scores))
            return scores
        except Exception as exc:
            logger.error("Moderation failed: %s", exc)
            return {}


# Singleton instance
ai_service = AIService()
