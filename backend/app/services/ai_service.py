import os
import json
import logging
import asyncio
from typing import List, Dict, Any, Optional
import httpx
from app.core.redis import get_redis

logger = logging.getLogger(__name__)

# Hugging Face API configuration
HF_API_URL = "https://api-inference.huggingface.co/models"
HF_TOKEN = os.getenv("HF_API_TOKEN", "")  # Should be set in environment

# Model configurations
SUMMARIZATION_MODEL = "facebook/bart-large-cnn"
TRANSLATION_MODEL = "facebook/nllb-200-distilled-600M"  # Supports many languages
SMART_REPLY_MODEL = "microsoft/DialoGpt-medium"  # For conversational responses
MODERATION_MODEL = "unitary/toxic-bert"

# Headers for HF API
def get_hf_headers():
    return {"Authorization": f"Bearer {HF_TOKEN}"} if HF_TOKEN else {}

class AIService:
    def __init__(self):
        self.redis = get_redis()
        self.timeout = 30.0  # seconds

    async def _call_hf_api(self, model: str, payload: Any) -> Any:
        """Make a request to Hugging Face Inference API."""
        async with httpx.AsyncClient(timeout=self.timeout) as client:
            response = await client.post(
                f"{HF_API_URL}/{model}",
                headers=get_hf_headers(),
                json=payload,
            )
            if response.status_code != 200:
                logger.error(f"HF API error: {response.status_code} - {response.text}")
                raise Exception(f"HF API request failed: {response.status_code}")
            return response.json()

    async def summarize_messages(self, messages: List[str], max_length: int = 150) -> str:
        """
        Summarize a list of messages.
        Returns a summary string.
        """
        if not messages:
            return ""
        # Combine messages with separator
        combined = " ".join(messages[-100:])  # Limit to last 100 messages
        # Check cache
        cache_key = f"ai:summary:{hash(combined)}"
        cached = await self.redis.get(cache_key)
        if cached:
            return cached.decode('utf-8')
        # Call HF API
        payload = {
            "inputs": combined,
            "parameters": {"max_length": max_length, "min_length": 30, "do_sample": False}
        }
        try:
            result = await self._call_hf_api(SUMMARIZATION_MODEL, payload)
            # HF summarization returns a list of dicts with 'summary_text'
            summary = result[0]['summary_text'] if isinstance(result, list) and len(result) > 0 else ""
            # Cache for 5 minutes
            await self.redis.setex(cache_key, 300, summary)
            return summary
        except Exception as e:
            logger.error(f"Summarization failed: {e}")
            # Fallback: return first 200 chars
            return combined[:200] + "..." if len(combined) > 200 else combined

    async def translate_message(self, text: str, target_lang: str) -> str:
        """
        Translate text to target language.
        target_lang should be a language code supported by NLLB (e.g., 'eng_Latn', 'fra_Latn').
        """
        if not text:
            return ""
        # Check cache
        cache_key = f"ai:translate:{hash(text)}:{target_lang}"
        cached = await self.redis.get(cache_key)
        if cached:
            return cached.decode('utf-8')
        # NLLB expects src_lang and tgt_lang parameters; we assume source is English for simplicity.
        # In a real app, detect source language or require user to specify.
        payload = {
            "inputs": text,
            "parameters": {
                "src_lang": "eng_Latn",  # Assume English source
                "tgt_lang": target_lang,
            }
        }
        try:
            result = await self._call_hf_api(TRANSLATION_MODEL, payload)
            # Translation returns list of dicts with 'translation_text'
            translation = result[0]['translation_text'] if isinstance(result, list) and len(result) > 0 else ""
            # Cache for 1 day (translations are static)
            await self.redis.setex(cache_key, 86400, translation)
            return translation
        except Exception as e:
            logger.error(f"Translation failed: {e}")
            return text  # Fallback: return original

    async def generate_smart_replies(self, context: str, num_replies: int = 3) -> List[str]:
        """
        Generate smart reply suggestions based on conversation context.
        """
        if not context:
            return []
        # Check cache
        cache_key = f"ai:smartreply:{hash(context)}:{num_replies}"
        cached = await self.redis.get(cache_key)
        if cached:
            return json.loads(cached.decode('utf-8'))
        # For DialoGPT, we need to format as conversation history
        # Simplified: just pass the last user message as input
        payload = {
            "inputs": context,
            "parameters": {"max_length": 50, "num_return_sequences": num_replies, "temperature": 0.7}
        }
        try:
            result = await self._call_hf_api(SMART_REPLY_MODEL, payload)
            # DialoGPT returns list of dicts with 'generated_text'
            replies = []
            if isinstance(result, list):
                for item in result:
                    generated = item.get('generated_text', '')
                    # Remove the input context from the generated text if it's appended
                    if generated.startswith(context):
                        generated = generated[len(context):].strip()
                    if generated and generated not in replies:
                        replies.append(generated)
            # Ensure we have at least some replies
            if not replies:
                replies = ["Thanks!", "Sounds good", "Let me know"]
            # Cache for 10 minutes
            await self.redis.setex(cache_key, 600, json.dumps(replies))
            return replies[:num_replies]
        except Exception as e:
            logger.error(f"Smart reply generation failed: {e}")
            return ["Thanks!", "Sounds good", "Let me know"]

    async def moderate_message(self, text: str) -> Dict[str, float]:
        """
        Moderate a message for toxicity/spam.
        Returns a dictionary of labels and scores.
        """
        if not text:
            return {}
        # Check cache
        cache_key = f"ai:moderation:{hash(text)}"
        cached = await self.redis.get(cache_key)
        if cached:
            return json.loads(cached.decode('utf-8'))
        payload = {"inputs": text}
        try:
            result = await self._call_hf_api(MODERATION_MODEL, payload)
            # Toxic-BERT returns list of dicts with label and score
            scores = {}
            if isinstance(result, list):
                for item in result:
                    label = item.get('label', '').lower()
                    score = item.get('score', 0.0)
                    scores[label] = score
            # Cache for 1 hour
            await self.redis.setex(cache_key, 3600, json.dumps(scores))
            return scores
        except Exception as e:
            logger.error(f"Moderation failed: {e}")
            return {}

# Singleton instance
ai_service = AIService()