from __future__ import annotations

from urllib.parse import urlsplit, urlunsplit

from redis.asyncio import Redis, ConnectionPool

from app.config import settings


def _url_with_db(url: str, db: int) -> str:
    """Point a Redis URL at a specific database index.

    This replaces the path component outright. The previous approach —
    str.replace(f"/{REDIS_DB}", f"/{db}") — silently did nothing against a
    managed connection string that carries no path (Render hands out a bare
    redis://host:port), collapsing all three pools onto database 0 and letting
    OTP, session, and pub/sub keys share one keyspace.

    Note that credentials containing "/" must be percent-encoded, as in any
    URL; an unencoded slash breaks netloc parsing here and everywhere else.
    """
    return urlunsplit(urlsplit(url)._replace(path=f"/{db}"))


def _make_pool(db: int) -> ConnectionPool:
    # from_url lets URL-derived options override **kwargs, so the index has to
    # be baked into the URL rather than passed as db=.
    return ConnectionPool.from_url(
        _url_with_db(settings.redis_url, db),
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
