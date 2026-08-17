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
    peer_id: str,
) -> None:
    """Offline-message notification. Carries who, never what.

    There is no `preview` parameter, and that is the point. This function used
    to take one and set it as the notification body, and the value it was given
    was the message field straight off the wire — the ciphertext envelope when
    encryption was on, and the plaintext message when it was off. So the
    encrypted case put a blob of JSON on the user's lock screen, and the
    unencrypted case handed the message itself to Google.

    A notification is the one part of a messenger that renders outside the
    application, on a locked screen, through an infrastructure nobody here
    controls. Content does not belong in it.

    The title is the sender's name and there is no body. A generic body would
    have to be written in some language, and the server does not know the
    recipient's — a notification reading "New message" to someone whose phone
    is in Arabic is worse than a notification that simply says who it is from.
    """
    if not _ensure_init():
        return

    from firebase_admin import messaging

    msg = messaging.Message(
        token=fcm_token,
        notification=messaging.Notification(title=sender_name),
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


async def send_ocr_push(user_id: str, file_id: str) -> None:
    """Wake the app so it can check a document — nothing more.

    THE KEYWORD USED TO TRAVEL IN HERE, AND MUST NOT

    This previously sent ``data={"type": ..., "file_id": ..., "keyword": ...}``.
    A user's private keyword is the single most sensitive thing this feature
    touches: it states exactly what its owner is watching for. Putting it in a
    push payload sent it to Google's delivery infrastructure, where it sat in
    transit logs and — on Android — could be rendered on a lock screen by any
    handler that decided to show it. §7.1 requires notification privacy and
    P-1 requires the keyword be visible to nobody but its owner; that payload
    broke both, silently, for every alert.

    It carries no keyword now, and no matched text. The push is a wake-up: the
    device already holds the rules and the decrypted document, so it can work
    out what to show, and everything it shows is derived on-device.

    The file identifier stays because the client needs to know which
    attachment to look at, and it is an opaque storage key that reveals
    nothing about the content — a recipient who cannot decrypt the object
    learns nothing from its name.
    """
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
        # Data-only, with no notification block: a notification block would let
        # the OS draw the payload on the lock screen before the app ever sees
        # it, which is exactly the control §7.1 says the user must keep.
        data={"type": "ocr_alert", "file_id": file_id},
        android=messaging.AndroidConfig(priority="high"),
    )
    try:
        await asyncio.to_thread(messaging.send, msg)
    except Exception as exc:
        # The error, never the payload. A logged push body is a logged keyword.
        logger.error("ocr_push_failed", error=str(exc), user_id=user_id)
