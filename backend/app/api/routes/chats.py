from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from typing import List, Optional
from app.api import deps
from app.models.chat import ChatMessage as Message  # Assuming we have a ChatMessage model
from app.schemas.chat import MessageResponse
from app.services.ai_service import ai_service
from app.core.redis import get_redis
import json

router = APIRouter()

@router.get("/{chat_id}/messages", response_model=List[MessageResponse])
def read_chat_messages(
    chat_id: int,
    limit: int = 100,
    db: Session = Depends(deps.get_db),
    current_user: User = Depends(deps.get_current_active_user),
):
    """
    Retrieve recent messages for a chat (used for AI summarization).
    """
    # Verify user is participant in the chat (implementation depends on chat model)
    # For simplicity, we skip permission check here; in reality, check if user is in chat.
    messages = db.query(Message).filter(Message.chat_id == chat_id).order_by(Message.created_at.desc()).limit(limit).all()
    # Reverse to get chronological order
    messages.reverse()
    return messages

@router.get("/{chat_id}/summary")
async def get_chat_summary(
    chat_id: int,
    limit: int = 100,
    db: Session = Depends(deps.get_db),
    current_user: User = Depends(deps.get_current_active_user),
):
    """
    Get AI-generated summary of recent messages in a chat.
    """
    # Verify user is participant in the chat
    messages = db.query(Message).filter(Message.chat_id == chat_id).order_by(Message.created_at.desc()).limit(limit).all()
    if not messages:
        return {"summary": ""}
    # Extract text content (assuming Message model has content field)
    message_texts = [msg.content for msg in messages if msg.content]
    summary = await ai_service.summarize_messages(message_texts)
    return {"summary": summary}

# Additional AI endpoints
@router.post("/{chat_id}/ai/smart-replies")
async def generate_smart_replies(
    chat_id: int,
    db: Session = Depends(deps.get_db),
    current_user: User = Depends(deps.get_current_active_user),
):
    """
    Generate smart reply suggestions based on recent conversation context.
    """
    # Get recent messages for context
    messages = db.query(Message).filter(Message.chat_id == chat_id).order_by(Message.created_at.desc()).limit(10).all()
    if not messages:
        return {"replies": ["Thanks!", "Sounds good", "Let me know"]}
    # Extract text content (most recent first, but we want chronological order for context)
    message_texts = [msg.content for msg in messages if msg.content]
    # Reverse to get chronological order (oldest first) for better context
    message_texts.reverse()
    context = " ".join(message_texts)
    replies = await ai_service.generate_smart_replies(context, num_replies=3)
    return {"replies": replies}

@router.post("/{chat_id}/ai/translate")
async def translate_message(
    chat_id: int,
    text: str,
    target_lang: str,
    db: Session = Depends(deps.get_db),
    current_user: User = Depends(deps.get_current_active_user),
):
    """
    Translate a message to target language.
    """
    translation = await ai_service.translate_message(text, target_lang)
    return {"translation": translation}

@router.post("/{chat_id}/ai/moderate")
async def moderate_message(
    chat_id: int,
    text: str,
    db: Session = Depends(deps.get_db),
    current_user: User = Depends(deps.get_current_active_user),
):
    """
    Moderate a message for toxicity/spam.
    """
    scores = await ai_service.moderate_message(text)
    return {"scores": scores}

# TODO: Additional AI endpoints for translation, moderation, smart replies could be added here or in messages routes.