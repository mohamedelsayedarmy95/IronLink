import os
import logging
from typing import Optional

import firebase_admin
from firebase_admin import credentials, messaging
from sqlalchemy import select

from app.core.database import AsyncSessionLocal
from app.models import User

logger = logging.getLogger(__name__)

_firebase_app = None


def _initialize_firebase() -> bool:
    """Initialize Firebase Admin SDK if credentials are present.
    Returns True if successful, False otherwise."""
    global _firebase_app
    if _firebase_app is not None:
        return True

    proj = os.getenv("FIREBASE_PROJECT_ID")
    client_email = os.getenv("FIREBASE_CLIENT_EMAIL")
    private_key = os.getenv("FIREBASE_PRIVATE_KEY")
    if not all([proj, client_email, private_key]):
        logger.warning(
            "Firebase credentials not fully set; OCR push notifications will be disabled."
        )
        return False

    # Replace escaped newlines in the private key
    private_key = private_key.replace("\\n", "\n")
    cred = credentials.Certificate(
        {
            "type": "service_account",
            "project_id": proj,
            "private_key": private_key,
            "client_email": client_email,
            # other fields optional
        }
    )
    try:
        _firebase_app = firebase_admin.initialize_app(cred)
        logger.info("Firebase Admin SDK initialized for OCR push notifications.")
        return True
    except Exception as e:
        logger.error(f"Failed to initialize Firebase Admin SDK: {e}")
        return False


async def _get_fcm_token(user_id: str) -> Optional[str]:
    """Retrieve the FCM token for a user from the database."""
    try:
        async with AsyncSessionLocal() as db:
            stmt = select(User.fcm_token).where(User.id == user_id)
            result = await db.execute(stmt)
            token = result.scalar_one_or_none()
            return token
    except Exception as e:
        logger.error(f"Error fetching FCM token for user {user_id}: {e}")
        return None


async def send_ocr_push(user_id: str, file_id: str, keyword: str) -> None:
    """Send a data-only FCM notification with OCR alert info.
    Silently fails if Firebase is not configured or token missing."""
    if not _initialize_firebase():
        return

    token = await _get_fcm_token(user_id)
    if not token:
        logger.debug(f"No FCM token for user {user_id}; skipping OCR push.")
        return

    data_payload = {
        "type": "ocr_alert",
        "file_id": file_id,
        "keyword": keyword,
    }
    message = messaging.Message(data=data_payload, token=token)

    try:
        messaging.send(message)
        logger.info(f"Sent OCR push to user {user_id} for file {file_id}, keyword '{keyword}'.")
    except Exception as e:
        logger.error(f"Failed to send OCR push to user {user_id}: {e}")