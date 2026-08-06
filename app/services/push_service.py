from __future__ import annotations

import asyncio

import structlog

from app.config import settings

logger = structlog.get_logger("push")

_initialized = False
_available = False


def _ensure_init() -> bool:
    """Lazy Firebase Admin init — the app runs fine without FCM configured
    (pushes become no-ops with a warning), so local dev needs no Firebase."""
    global _initialized, _available
    if _initialized:
        return _available
    _initialized = True

    if not settings.FIREBASE_CREDENTIALS_FILE:
        logger.warning("fcm_disabled", reason="FIREBASE_CREDENTIALS_FILE not set")
        return False
    try:
        import firebase_admin
        from firebase_admin import credentials

        cred = credentials.Certificate(settings.FIREBASE_CREDENTIALS_FILE)
        firebase_admin.initialize_app(cred)
        _available = True
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
