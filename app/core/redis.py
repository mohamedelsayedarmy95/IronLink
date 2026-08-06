from __future__ import annotations

from redis.asyncio import Redis, ConnectionPool

from app.config import settings


def _make_pool(db: int) -> ConnectionPool:
    return ConnectionPool.from_url(
        settings.redis_url.replace(f"/{settings.REDIS_DB}", f"/{db}"),
        max_connections=50,
        decode_responses=True,
    )


# Three isolated Redis DB indices — see config.py for rationale
_pool_pubsub   = _make_pool(settings.REDIS_DB_PUBSUB)
_pool_otp      = _make_pool(settings.REDIS_DB_OTP)
_pool_sessions = _make_pool(settings.REDIS_DB_SESSIONS)

redis_pubsub:   Redis = Redis(connection_pool=_pool_pubsub)
redis_otp:      Redis = Redis(connection_pool=_pool_otp)
redis_sessions: Redis = Redis(connection_pool=_pool_sessions)


async def close_redis() -> None:
    await redis_pubsub.aclose()
    await redis_otp.aclose()
    await redis_sessions.aclose()
