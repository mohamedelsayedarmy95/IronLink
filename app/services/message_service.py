from __future__ import annotations

from datetime import datetime, timedelta, timezone
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Message
from app.models.message import MessageStatus, MessageType

UNSEND_WINDOW = timedelta(minutes=5)


class UnsendDenied(Exception):
    """Raised when the unsend window has passed or the caller is not the sender."""


async def save_message(
    db: AsyncSession,
    *,
    sender_id: UUID,
    recipient_id: UUID | None,
    group_id: UUID | None,
    message_type: str,
    content_ciphertext: str | None,
    media_object_key: str | None = None,
    media_mime_type: str | None = None,
    destruct_after_seconds: int | None = None,
) -> Message:
    msg = Message(
        sender_id=sender_id,
        recipient_id=recipient_id,
        group_id=group_id,
        message_type=message_type,
        content_ciphertext=content_ciphertext,
        media_object_key=media_object_key,
        media_mime_type=media_mime_type,
        status=MessageStatus.SENT,
        is_self_destruct=destruct_after_seconds is not None,
        destruct_after_seconds=destruct_after_seconds,
        destruct_at=(
            datetime.now(timezone.utc) + timedelta(seconds=destruct_after_seconds)
            if destruct_after_seconds
            else None
        ),
    )
    db.add(msg)
    await db.commit()
    await db.refresh(msg)
    return msg


async def mark_delivered(db: AsyncSession, message_id: UUID, recipient_id: UUID) -> Message | None:
    msg = await db.scalar(
        select(Message).where(
            Message.id == message_id,
            Message.recipient_id == recipient_id,
        )
    )
    if msg is None or msg.status == MessageStatus.READ:
        return None
    if msg.status != MessageStatus.DELIVERED:
        msg.status = MessageStatus.DELIVERED
        msg.delivered_at = datetime.now(timezone.utc)
        await db.commit()
    return msg


async def mark_read(db: AsyncSession, message_id: UUID, recipient_id: UUID) -> Message | None:
    msg = await db.scalar(
        select(Message).where(
            Message.id == message_id,
            Message.recipient_id == recipient_id,
        )
    )
    if msg is None:
        return None
    if msg.status != MessageStatus.READ:
        msg.status = MessageStatus.READ
        msg.read_at = datetime.now(timezone.utc)
        if msg.delivered_at is None:
            msg.delivered_at = msg.read_at
        # Fable5-Enhancement: a read self-destruct message starts its timer at
        # READ time, not send time — "burn after reading" semantics.
        if msg.is_self_destruct and msg.destruct_after_seconds and msg.destruct_at is None:
            msg.destruct_at = msg.read_at + timedelta(seconds=msg.destruct_after_seconds)
        await db.commit()
    return msg


async def unsend_message(db: AsyncSession, message_id: UUID, sender_id: UUID) -> Message:
    """Delete-for-everyone within UNSEND_WINDOW.

    Fable5-Enhancement: the row is NOT hard-deleted. The ciphertext and media
    pointers are wiped (content is unrecoverable) but a tombstone row remains,
    because a military audit trail must be able to prove that a message
    existed and was retracted, by whom, and when. Content gone, evidence kept.
    """
    msg = await db.scalar(
        select(Message).where(
            Message.id == message_id,
            Message.sender_id == sender_id,
        )
    )
    if msg is None:
        raise UnsendDenied("message not found or not owned by caller")

    created = msg.created_at
    if created.tzinfo is None:
        created = created.replace(tzinfo=timezone.utc)
    if datetime.now(timezone.utc) - created > UNSEND_WINDOW:
        raise UnsendDenied("unsend window (5 minutes) has passed")

    msg.content_ciphertext = None
    msg.media_object_key = None
    msg.media_mime_type = None
    msg.deleted_for_everyone = True
    msg.deleted_at = datetime.now(timezone.utc)
    await db.commit()
    return msg
