from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile, status
from sqlalchemy.orm import Session
from typing import List, Optional
import uuid
import asyncio
from app.api import deps
from app.core.redis import get_redis, redis_conn
from app.core.minio import minio_client, BUCKET_NAME
from app.models.chat import Chat
from app.models.user import User
from app.models.group import GroupMember
from app.services.ws_manager import manager
import json
import os
from datetime import datetime, timedelta

router = APIRouter()

# OCR settings
OCR_DEBOUNCE_SECONDS = 5
OCR_ALERT_HISTORY_LIMIT = 50
OCR_ALERT_HISTORY_TTL = 24 * 60 * 60  # 24 hours in seconds

# Helper functions for OCR keyword processing
def extract_text(file_path: str) -> str:
    """
    Extract text from a file using OCR.
    This is a placeholder function. In a real implementation, we would use
    Tesseract or a HuggingFace model.
    For the purpose of this example, we'll return a dummy string.
    """
    # TODO: Implement actual OCR
    # For now, we return a sample text for testing
    return "This is a sample text with the word urgent and another word."

def get_user_keywords(user_id: int) -> set:
    """
    Fetch OCR keywords for a user from Redis.
    Returns a set of keywords (in lowercase).
    """
    r = redis_conn()
    # We store keywords as a Redis set: user:{user_id}:ocr_keywords
    keywords = r.smembers(f"user:{user_id}:ocr_keywords")
    # Convert to lowercase strings
    return {k.decode('utf-8').lower() for k in keywords}

def add_ocr_alert(user_id: int, alert: dict):
    """
    Add an OCR alert to the user's alert history in Redis.
    """
    r = redis_conn()
    key = f"user:{user_id}:ocr_alerts"
    # Push to the front of the list
    r.lpush(key, json.dumps(alert))
    # Trim to the last OCR_ALERT_HISTORY_LIMIT items
    r.ltrim(key, 0, OCR_ALERT_HISTORY_LIMIT - 1)
    # Set expire to OCR_ALERT_HISTORY_TTL (refresh on each add)
    r.expire(key, OCR_ALERT_HISTORY_TTL)

def is_ocr_debounced(file_id: str, user_id: int) -> bool:
    """
    Check if we have sent an OCR alert for this file and user recently.
    Returns True if debounced (we should skip), False otherwise.
    """
    r = redis_conn()
    key = f"ocr:debounce:{file_id}:{user_id}"
    if r.exists(key):
        return True
    # Set the debounce key with OCR_DEBOUNCE_SECONDS
    r.setex(key, OCR_DEBOUNCE_SECONDS, 1)
    return False

async def process_ocr(
    file_id: str,
    file_name: str,
    file_path: str,
    uploader_id: int,
    chat_id: Optional[int] = None,
    group_id: Optional[int] = None,
    db: Session = None
):
    """
    Background task to process OCR on an uploaded file and send alerts.
    """
    # Extract text from the file
    text = extract_text(file_path)
    # We'll use the whole text for keyword matching (could be optimized by taking first/last chunks)
    text_lower = text.lower()

    # Determine which users to check
    user_ids_to_check = set()
    if group_id is not None:
        # Group upload: check all group members
        # Fetch group member IDs from the database
        members = db.query(GroupMember.user_id).filter(GroupMember.group_id == group_id).all()
        user_ids_to_check = {m[0] for m in members}
    elif chat_id is not None:
        # Direct chat: check the recipient(s) (excluding the uploader)
        chat = db.query(Chat).filter(Chat.id == chat_id).first()
        if chat:
            # Assuming Chat has user1_id and user2_id
            user_ids_to_check = {chat.user1_id, chat.user2_id}
            # Remove the uploader (we only want to alert the recipient in direct chats)
            user_ids_to_check.discard(uploader_id)
        else:
            # If chat not found, fallback to just the uploader? But we should not alert in this case.
            user_ids_to_check = set()
    else:
        # Standalone upload: check only the uploader
        user_ids_to_check = {uploader_id}

    # For each user, check their keywords
    for user_id in user_ids_to_check:
        # Skip if debounced for this file and user
        if is_ocr_debounced(file_id, user_id):
            continue

        # Get the user's keywords
        keywords = get_user_keywords(user_id)
        if not keywords:
            continue

        # Check for any keyword match in the text
        # We split the text into words and check for intersection (for single-word keywords)
        # Note: This assumes keywords are single words. We'll improve if needed.
        words = set(text_lower.split())
        matched_keywords = words & keywords

        if matched_keywords:
            # Take the first matched keyword for simplicity
            keyword = next(iter(matched_keywords))
            # Extract a snippet around the keyword (20 chars before and after)
            idx = text_lower.find(keyword)
            if idx != -1:
                start = max(0, idx - 20)
                end = min(len(text), idx + len(keyword) + 20)
                snippet = text[start:end]
            else:
                snippet = text[:100]  # fallback

            # Prepare alert payload
            alert = {
                "type": "ocr_alert",
                "file_id": file_id,
                "file_name": file_name,
                "matched_keyword": keyword,
                "group_id": group_id,
                "chat_id": chat_id,
                "snippet": snippet,
                "user_id": user_id,  # the user this alert is for
                "timestamp": datetime.utcnow().isoformat() + "Z"
            }

            # Add to user's alert history
            add_ocr_alert(user_id, alert)

            # Send alert via WebSocket to the specific user
            await manager.send_personal_message(alert, user_id)

    # Clean up the temporary file if needed
    try:
        os.remove(file_path)
    except Exception:
        pass

@router.post("/upload", response_model=dict)
async def upload_media(
    file: UploadFile = File(...),
    chat_id: Optional[int] = Form(None),
    group_id: Optional[int] = Form(None),
    current_user: User = Depends(deps.get_current_active_user),
    db: Session = Depends(deps.get_db),
):
    """
    Upload a file (image, PDF, etc.) and trigger OCR processing.
    """
    # Validate input: either chat_id or group_id must be provided (or neither for standalone?)
    # We'll allow standalone uploads (neither chat_id nor group_id) for now.

    # Generate a unique file ID (we'll use this as the MinIO object name)
    file_id = str(uuid.uuid4())
    # Preserve the original file extension
    file_extension = os.path.splitext(file.filename)[1]
    object_name = f"{file_id}{file_extension}"

    # Read the file content
    content = await file.read()
    file_size = len(content)

    # Upload to MinIO (with SSE-S3 encryption)
    try:
        minio_client.put_object(
            bucket_name=BUCKET_NAME,
            object_name=object_name,
            data=io.BytesIO(content),
            length=file_size,
            content_type=file.content_type
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to upload file to MinIO: {str(e)}"
        )

    # Save file metadata to the database (if we have a model for media)
    # We'll skip for now and assume we only need the file_id and object_name for OCR

    # Create a temporary file path for OCR processing
    temp_file_path = f"/tmp/{object_name}"
    try:
        with open(temp_file_path, "wb") as f:
            f.write(content)
    except Exception as e:
        # Clean up MinIO object if we fail to write temp file
        minio_client.remove_object(BUCKET_NAME, object_name)
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Failed to create temporary file: {str(e)}"
        )

    # Trigger OCR processing as a background task
    asyncio.create_task(
        process_ocr(
            file_id=file_id,
            file_name=file.filename,
            file_path=temp_file_path,
            uploader_id=current_user.id,
            chat_id=chat_id,
            group_id=group_id,
            db=db
        )
    )

    return {
        "file_id": file_id,
        "object_name": object_name,
        "message": "File uploaded successfully. OCR processing started."
    }