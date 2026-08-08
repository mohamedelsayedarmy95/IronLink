from __future__ import annotations

import asyncio
import json

import structlog
from sqlalchemy import select

from app.config import settings
from app.core.database import AsyncSessionLocal
from app.models import User

logger = structlog.get_logger("push")

_initialized = False
_available = False


def ensure_initialized() -> bool:
    """Public entry point — also used by app.api.routes.auth to verify Firebase
    Phone Auth ID tokens, which needs the same Admin SDK app initialised."""
    return _ensure_init()


def _ensure_init() -> bool:
    """Lazy Firebase Admin init — the app runs fine without FCM configured
    (pushes become no-ops with a warning), so local dev needs no Firebase."""
    global _initialized, _available
    if _initialized:
        return _available
    _initialized = True

    if not settings.firebase_configured:
        logger.warning(
            "fcm_disabled",
            reason="neither FIREBASE_CREDENTIALS_JSON nor FIREBASE_CREDENTIALS_FILE set",
        )
        return False
    try:
        import firebase_admin
        from firebase_admin import credentials

        # credentials.Certificate accepts either a parsed dict or a path.
        # Prefer the inline JSON: a managed platform can inject an env var but
        # cannot place a file in the image, so the path form is unusable there.
        if settings.FIREBASE_CREDENTIALS_JSON:
            cred = credentials.Certificate(
                json.loads(settings.FIREBASE_CREDENTIALS_JSON)
            )
            source = "json_env"
        else:
            cred = credentials.Certificate(settings.FIREBASE_CREDENTIALS_FILE)
            source = "file"

        firebase_admin.initialize_app(cred)
        _available = True
        logger.info("fcm_initialised", source=source)
    except json.JSONDecodeError as exc:
        # Worth its own branch: a truncated or shell-mangled paste is the most
        # common failure, and "Expecting value: line 1" alone is unhelpful.
        logger.error("fcm_init_failed", error=f"FIREBASE_CREDENTIALS_JSON is not valid JSON: {exc}")
        _available = False
    except Exception as exc:
        logger.error("fcm_init_failed", error=str(exc))
        _available = False
    return _available


async def send_message_push(
    fcm_token: str,
    *,
    sender_name: str,
    preview: str,
    peer_id: str,
) -> None:
    """Offline-message notification. Tapping opens the conversation directly
    (the app routes on the peer_id in the data payload)."""
    if not _ensure_init():
        return

    from firebase_admin import messaging

    msg = messaging.Message(
        token=fcm_token,
        notification=messaging.Notification(
            title=sender_name,
            body=preview[:80],
        ),
        data={"kind": "dm", "peer_id": peer_id},
        android=messaging.AndroidConfig(priority="high"),
    )
    # firebase_admin is sync — keep the event loop free
    await asyncio.to_thread(messaging.send, msg)


async def send_broadcast_push(
    fcm_tokens: list[str],
    *,
    title: str,
    body: str,
    broadcast_id: str,
) -> int:
    """Urgent admin broadcast to many devices. Returns delivered count."""
    if not _ensure_init() or not fcm_tokens:
        return 0

    from firebase_admin import messaging

    delivered = 0
    # FCM caps multicast at 500 tokens per call
    for i in range(0, len(fcm_tokens), 500):
        batch = messaging.MulticastMessage(
            tokens=fcm_tokens[i:i + 500],
            notification=messaging.Notification(title=title, body=body[:120]),
            data={"kind": "broadcast", "broadcast_id": broadcast_id},
            android=messaging.AndroidConfig(priority="high"),
        )
        response = await asyncio.to_thread(messaging.send_each_for_multicast, batch)
        delivered += response.success_count
    return delivered


async def send_ocr_push(user_id: str, file_id: str, keyword: str) -> None:
    """Data-only OCR keyword-match alert — the background/killed-app fallback
    for the live WebSocket ticker (see app.redis.publish_ocr_alert)."""
    if not _ensure_init():
        return

    async with AsyncSessionLocal() as db:
        stmt = select(User.fcm_token).where(User.id == user_id)
        result = await db.execute(stmt)
        token = result.scalar_one_or_none()
    if not token:
        logger.debug("ocr_push_skipped", reason="no fcm_token", user_id=user_id)
        return

    from firebase_admin import messaging

    msg = messaging.Message(
        token=token,
        data={"type": "ocr_alert", "file_id": file_id, "keyword": keyword},
        android=messaging.AndroidConfig(priority="high"),
    )
    try:
        await asyncio.to_thread(messaging.send, msg)
    except Exception as exc:
        logger.error("ocr_push_failed", error=str(exc), user_id=user_id)
