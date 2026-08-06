import redis
from app.config import settings

# Global Redis connection pool
_redis_pool = None

def get_redis_pool():
    global _redis_pool
    if _redis_pool is None:
        _redis_pool = redis.ConnectionPool.from_url(
            settings.REDIS_URL, decode_responses=False
        )
    return _redis_pool

def redis_conn():
    """
    Get a Redis connection from the pool.
    """
    return redis.Redis(connection_pool=get_redis_pool())

# OCR-specific helper functions (if needed) can be added here.
# For now, we have the helper functions in media.py, but we can move them here if desired.
# We'll keep them in media.py for simplicity, but we need to import redis_conn from here.
# Let's also add a function to set up keyword sets for users (if needed by other parts of the app).