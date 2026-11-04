"""Legacy server-side keyword/alert storage.

STATUS: deprecated. See docs/SMART_KEYWORD_ALERT_AUDIT.md.

Keyword matching moved on-device once encryption became the default for every
chat: the server holds no key, so it cannot read an attachment, and storing a
user's private watchwords here in the clear is precisely the exposure the
feature exists to avoid. This module survives only for deployments that
deliberately run plaintext attachments with SERVER_SIDE_OCR_ENABLED on.

It is kept correct rather than left to rot, because a half-working fallback is
worse than none. Four defects were fixed here at once, all with one root cause
— this file built its own Redis client instead of using the application's:

* ``redis.Redis(host="redis", port=6379)`` hardcoded a docker-compose service
  name. Production runs on Render and configures REDIS_URL, so the connection
  could never be established and every call fell into the except branch.
* The client was the *synchronous* one, called from async request handlers and
  from an async background task, blocking the event loop for each round trip.
* Being synchronous, its return values were not awaitable — yet
  ``app/api/routes/ocr.py`` awaited them, so all three keyword endpoints
  raised TypeError and returned 500 on every call.
* It published on database 0 while ``ws_manager`` subscribes on
  ``redis_sessions`` (REDIS_DB_SESSIONS). Even with a reachable server, an
  alert published here could never arrive there.

Using the shared ``redis_sessions`` client removes all four: same URL, same
database as the subscriber, async, awaitable.
"""
from __future__ import annotations

import json
import logging
from typing import Set

from app.core.redis import redis_sessions

logger = logging.getLogger(__name__)

ALERT_CHANNEL = "ocr:alerts"


def _keywords_key(user_id: str) -> str:
    return f"user:{user_id}:ocr_keywords"


async def get_user_keywords(user_id: str) -> Set[str]:
    """The user's keyword set, or an empty set if Redis is unreachable.

    Degrading to "no keywords" rather than raising is deliberate: a Redis
    outage should cost alerts, not the upload the caller is in the middle of.
    """
    try:
        return set(await redis_sessions.smembers(_keywords_key(user_id)))
    except Exception as exc:
        logger.error("keyword_read_failed user_id=%s error=%s", user_id, exc)
        return set()


async def set_user_keywords(user_id: str, keywords: Set[str]) -> bool:
    """Replace the user's keyword set.

    Delete-then-add in one transaction, so a concurrent reader sees either the
    old set or the new one and never the empty window between them.
    """
    key = _keywords_key(user_id)
    try:
        async with redis_sessions.pipeline(transaction=True) as pipe:
            pipe.delete(key)
            if keywords:
                pipe.sadd(key, *keywords)
            await pipe.execute()
        return True
    except Exception as exc:
        logger.error("keyword_write_failed user_id=%s error=%s", user_id, exc)
        return False


async def add_user_keywords(user_id: str, keywords: Set[str]) -> bool:
    """Add without disturbing what is already there."""
    if not keywords:
        return True
    try:
        await redis_sessions.sadd(_keywords_key(user_id), *keywords)
        return True
    except Exception as exc:
        logger.error("keyword_add_failed user_id=%s error=%s", user_id, exc)
        return False


async def remove_user_keywords(user_id: str, keywords: Set[str]) -> bool:
    """Remove specific keywords, leaving the rest of the set intact."""
    if not keywords:
        return True
    try:
        await redis_sessions.srem(_keywords_key(user_id), *keywords)
        return True
    except Exception as exc:
        logger.error("keyword_remove_failed user_id=%s error=%s", user_id, exc)
        return False


async def publish_ocr_alert(file_id: str, user_id: str, keyword: str) -> bool:
    """Fan an alert out to the user's live WebSocket connections.

    Published on the same client ws_manager subscribes with; see the module
    docstring for why that had to change.
    """
    try:
        await redis_sessions.publish(
            ALERT_CHANNEL,
            json.dumps({"file_id": file_id, "user_id": user_id, "keyword": keyword}),
        )
        return True
    except Exception as exc:
        logger.error("alert_publish_failed file_id=%s error=%s", file_id, exc)
        return False


async def claim_alert(file_id: str, ttl: int = 300) -> bool:
    """Reserve the right to alert about this file, once.

    SET NX returns true only for the caller that created the key, so a
    re-processed upload is suppressed instead of alerting twice. This replaces
    ``set_alert_flag``, which wrote a flag that no code path ever read — the
    duplicate suppression it implied did not exist.
    """
    try:
        return bool(
            await redis_sessions.set(f"ocr:alert:{file_id}", "1", ex=ttl, nx=True)
        )
    except Exception as exc:
        logger.error("alert_claim_failed file_id=%s error=%s", file_id, exc)
        # Fail open: an unreachable Redis should not silence every alert.
        return True
