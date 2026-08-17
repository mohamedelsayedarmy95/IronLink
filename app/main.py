from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager
from collections.abc import AsyncGenerator

import structlog
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.responses import JSONResponse
from sqlalchemy import text

from app.api.routes import (
    admin,
    ai,
    auth,
    broadcasts,
    channels,
    chats,
    communities,
    contacts,
    moderation,
    group_entry,
    group_messages,
    groups,
    keys,
    media,
    ocr,
    receipts,
    websocket,
)
from app.api.routes.websocket import manager
from app.config import settings
from app.core import observability
from app.core.database import AsyncSessionLocal
from app.core.redis import close_redis, redis_sessions
from app.services.self_destruct_worker import SelfDestructWorker

_self_destruct = SelfDestructWorker()
_log = structlog.get_logger("infra")


@asynccontextmanager
async def lifespan(app: FastAPI) -> AsyncGenerator[None, None]:
    _self_destruct.start()
    # Start OCR alert listener
    asyncio.create_task(manager.listen_ocr_alerts())
    yield
    await _self_destruct.stop()
    await close_redis()


app = FastAPI(
    title=settings.APP_NAME,
    version="0.1.0",
    docs_url="/api/docs" if settings.DEBUG else None,
    redoc_url="/api/redoc" if settings.DEBUG else None,
    openapi_url="/api/openapi.json" if settings.DEBUG else None,
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE"],
    allow_headers=["Authorization", "Content-Type", "X-Request-ID"],
)

if settings.ENV == "production":
    # settings.allowed_hosts, not ALLOWED_ORIGINS — the middleware compares
    # against the Host header, which has no scheme. See config.allowed_hosts.
    app.add_middleware(TrustedHostMiddleware, allowed_hosts=settings.allowed_hosts)


app.include_router(auth.router, prefix=settings.API_PREFIX)
app.include_router(chats.router, prefix=settings.API_PREFIX)
app.include_router(groups.router, prefix=settings.API_PREFIX)
app.include_router(group_entry.router, prefix=settings.API_PREFIX)
app.include_router(group_messages.router, prefix=settings.API_PREFIX)
app.include_router(contacts.router, prefix=settings.API_PREFIX)
app.include_router(moderation.router, prefix=settings.API_PREFIX)
app.include_router(media.router, prefix=settings.API_PREFIX)
app.include_router(broadcasts.router, prefix=settings.API_PREFIX)
app.include_router(admin.router, prefix=settings.API_PREFIX)
app.include_router(ocr.router, prefix=settings.API_PREFIX)
app.include_router(receipts.router, prefix=settings.API_PREFIX)
app.include_router(keys.router, prefix=settings.API_PREFIX)
app.include_router(channels.router, prefix=settings.API_PREFIX)
app.include_router(communities.router, prefix=settings.API_PREFIX)
app.include_router(ai.router, prefix=settings.API_PREFIX)
app.include_router(websocket.router)


# Metrics, structured logging, and request correlation. Installed after the
# routers so the middleware sees the matched route template and can label by it
# rather than by the raw path, which carries identifiers.
observability.install(app)


@app.get("/health", tags=["infra"])
async def health_check() -> dict[str, str]:
    """Liveness. Answers as long as the process can serve a request.

    Deliberately shallow, and deliberately separate from readiness below. The
    platform restarts the container when this fails, so making it depend on
    Postgres or Redis would turn a thirty-second dependency blip into a restart
    loop — the container is killed, comes back, still cannot reach the
    dependency, and is killed again, while the dependency recovers on its own
    into a service that is now cold.
    """
    return {"status": "ok", "env": settings.ENV}


@app.get("/health/ready", tags=["infra"])
async def readiness() -> JSONResponse:
    """Readiness. Answers only when this instance can actually do its job.

    A health check that cannot fail is not a health check, and the one that
    existed here could not: it returned ok whether or not the database was
    reachable. This one asks Postgres and Redis, names which of them is down,
    and returns 503 so a load balancer stops sending it traffic.

    The failure detail is a dependency name and nothing else. The exception
    text is deliberately not returned — connection errors carry hostnames,
    ports, and sometimes credentials, and this endpoint is unauthenticated.
    """
    checks: dict[str, str] = {}

    try:
        async with AsyncSessionLocal() as session:
            await session.execute(text("SELECT 1"))
        checks["database"] = "ok"
    except Exception:  # noqa: BLE001 — the detail is logged, never returned
        _log.error("readiness_check_failed", dependency="database", exc_info=True)
        checks["database"] = "unavailable"

    try:
        await redis_sessions.ping()
        checks["redis"] = "ok"
    except Exception:  # noqa: BLE001
        _log.error("readiness_check_failed", dependency="redis", exc_info=True)
        checks["redis"] = "unavailable"

    healthy = all(state == "ok" for state in checks.values())
    return JSONResponse(
        {"status": "ok" if healthy else "degraded", "checks": checks},
        status_code=200 if healthy else 503,
    )