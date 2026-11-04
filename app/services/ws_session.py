"""Session-controlled socket I/O; Redis notifications are only an accelerator."""
from __future__ import annotations

import asyncio
import json

from fastapi import WebSocket
from redis.exceptions import RedisError
from sqlalchemy.exc import SQLAlchemyError
import structlog

from app.core.database import AsyncSessionLocal
from app.core.redis import redis_pubsub
from app.core.session_auth import SessionIdentity, SessionInvalid, authenticated_session

logger = structlog.get_logger('ws_session')
SESSION_CHECK_INTERVAL_SECONDS = 15
AUTHORIZATION_TIMEOUT_SECONDS = 5
IO_TIMEOUT_SECONDS = 5
WS_SESSION_INVALID = 4421


class AuthorizationUnavailable(Exception):
    """Fail closed while retaining client credentials for ordinary recovery."""


async def validate(identity: SessionIdentity) -> None:
    try:
        async with asyncio.timeout(AUTHORIZATION_TIMEOUT_SECONDS):
            async with AsyncSessionLocal() as db:
                await authenticated_session(db, identity)
    except (SQLAlchemyError, TimeoutError, OSError):
        raise AuthorizationUnavailable() from None


async def notify_revocation(user_id, session_id=None) -> None:
    """Call only AFTER the revocation transaction commits; never trust Pub/Sub durability."""
    try:
        async with asyncio.timeout(IO_TIMEOUT_SECONDS):
            payload = ({'type': 'session_revoked', 'session_id': str(session_id)}
                       if session_id is not None else {'type': 'account_suspended'})
            await redis_pubsub.publish(f'chan:user:{user_id}', json.dumps(payload))
    except (RedisError, TimeoutError):
        # Authority is already committed; per-action checks/periodic validation
        # enforce it even when the notification cannot be delivered.
        logger.warning('ws_revocation_notification_unavailable')


class SessionSocket:
    """All registered local delivery paths use this sink, including OCR alerts."""
    def __init__(self, websocket: WebSocket, identity: SessionIdentity):
        self.websocket = websocket
        self.identity = identity
        self.invalid = False
        self.closed = False
        self._send_lock = asyncio.Lock()

    async def authorize(self) -> None:
        if self.invalid or self.closed:
            raise SessionInvalid()
        try:
            await validate(self.identity)
        except SessionInvalid:
            self.invalid = True
            raise
        if self.invalid or self.closed:
            raise SessionInvalid()

    async def send_json(self, payload: dict) -> None:
        # Queued deliveries validate after taking the send lock, not when they
        # were enqueued. No protected frame is intentionally sent once invalid
        # is known. A send already in flight cannot be recalled.
        async with self._send_lock:
            if self.invalid or self.closed:
                raise SessionInvalid()
            if payload.get('type') != 'pong':
                await self.authorize()
            async with asyncio.timeout(IO_TIMEOUT_SECONDS):
                await self.websocket.send_json(payload)

    async def close(self, *, invalid: bool = False) -> None:
        self.invalid |= invalid  # Set before waiting behind an in-flight send.
        async with self._send_lock:
            if self.closed:
                return
            self.closed = True
            try:
                async with asyncio.timeout(IO_TIMEOUT_SECONDS):
                    if self.invalid:
                        await self.websocket.send_json({'type': 'session_revoked'})
                    await self.websocket.close(code=WS_SESSION_INVALID if self.invalid else 1013,
                                               reason='Sign in again' if self.invalid else 'Service unavailable')
            except (RuntimeError, OSError, TimeoutError):
                pass  # The peer may already have disconnected.
