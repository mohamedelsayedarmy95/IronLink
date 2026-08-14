from __future__ import annotations

import asyncio
from contextlib import asynccontextmanager
from collections.abc import AsyncGenerator

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware

from app.api.routes import (
    admin,
    ai,
    auth,
    broadcasts,
    channels,
    chats,
    communities,
    group_entry,
    groups,
    keys,
    media,
    ocr,
    receipts,
    websocket,
)
from app.api.routes.websocket import manager
from app.config import settings
from app.core.redis import close_redis
from app.services.self_destruct_worker import SelfDestructWorker

_self_destruct = SelfDestructWorker()


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


@app.get("/health", tags=["infra"])
async def health_check() -> dict[str, str]:
    return {"status": "ok", "env": settings.ENV}