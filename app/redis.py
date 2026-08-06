import redis
import json
import logging
from typing import Set

logger = logging.getLogger(__name__)

# Redis client singleton
_redis_client = None

def get_redis_client():
    global _redis_client
    if _redis_client is None:
        _redis_client = redis.Redis(
            host='redis',
            port=6379,
            db=0,
            decode_responses=True  # So we get strings instead of bytes
        )
    return _redis_client

def get_user_keywords(user_id: str) -> Set[str]:
    """
    Retrieve a user's OCR keywords from Redis.
    Stored as a Redis SET: user:<user_id>:ocr_keywords
    Returns a set of strings.
    """
    try:
        r = get_redis_client()
        key = f"user:{user_id}:ocr_keywords"
        # SMEMBERS returns a set of strings (with decode_responses=True)
        return set(r.smembers(key))
    except Exception as e:
        logger.error(f"Failed to get OCR keywords for user {user_id}: {e}")
        return set()

def set_user_keywords(user_id: str, keywords: Set[str]) -> bool:
    """
    Set a user's OCR keywords in Redis.
    Overwrites any existing set.
    Returns True on success.
    """
    try:
        r = get_redis_client()
        key = f"user:{user_id}:ocr_keywords"
        # Remove old set and add new one
        r.delete(key)
        if keywords:
            r.sadd(key, *keywords)
        return True
    except Exception as e:
        logger.error(f"Failed to set OCR keywords for user {user_id}: {e}")
        return False

def publish_ocr_alert(file_id: str, user_id: str, keyword: str) -> bool:
    """
    Publish an OCR alert to the Redis channel 'ocr:alerts'.
    The message is a JSON string: {"file_id": ..., "user_id": ..., "keyword": ...}
    Returns True on success.
    """
    try:
        r = get_redis_client()
        channel = "ocr:alerts"
        message = json.dumps({
            "file_id": file_id,
            "user_id": user_id,
            "keyword": keyword
        })
        r.publish(channel, message)
        return True
    except Exception as e:
        logger.error(f"Failed to publish OCR alert for file {file_id}: {e}")
        return False

def set_alert_flag(file_id: str, ttl: int = 300) -> bool:
    """
    Set a short-lived flag in Redis to indicate that an alert has been sent for a file.
    Key: ocr:alert:<file_id>
    Value: 1 (or any) with TTL seconds (default 5 minutes).
    This can be used to avoid duplicate alerts for the same file.
    Returns True on success.
    """
    try:
        r = get_redis_client()
        key = f"ocr:alert:{file_id}"
        r.set(key, "1", ex=ttl)
        return True
    except Exception as e:
        logger.error(f"Failed to set alert flag for file {file_id}: {e}")
        return False