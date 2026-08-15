from __future__ import annotations

from datetime import datetime, timedelta, timezone
from uuid import UUID

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Message, UserBlock
from app.models.message import MessageStatus, MessageType

UNSEND_WINDOW = timedelta(minutes=5)


class UnsendDenied(Exception):
    """Raised when the unsend window has passed or the caller is not the sender."""


class BlockedDelivery(Exception):
    """Raised when a block stands between the two parties.

    Carries no detail about which direction the block runs: telling a sender
    they were blocked turns a quiet boundary into a confrontation, which is
    the outcome blocking exists to avoid.
    """


async def _blocked_between(db: AsyncSession, a: UUID, b: UUID) -> bool:
    """Whether either party has blocked the other.

    Symmetric at enforcement even though a block is directional: if A blocked
    B, B must not be able to message A either, or the block only stops the
    person who did not ask for it.
    """
    row = await db.scalar(
        select(UserBlock.id).where(
            or_(
                (UserBlock.blocker_id == a) & (UserBlock.blocked_id == b),
                (UserBlock.blocker_id == b) & (UserBlock.blocked_id == a),
            )
        ).limit(1)
    )
    return row is not None


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
    enforce_blocks: bool = True,
) -> Message:
    # Enforced here rather than in the route, because this is the single
    # point every message passes through — REST and WebSocket both. A check
    # in one caller would leave the other open.
    #
    # enforce_blocks is off for one case only: group sender-key distribution.
    # Group messages are deliberately not blocked — silencing someone in a
    # shared group would turn a personal boundary into a way to disrupt
    # everyone's conversation — so withholding the key that decrypts them
    # would not stop anything, it would just make the group unreadable for
    # one member with no explanation anywhere.
    if (
        enforce_blocks
        and recipient_id is not None
        and await _blocked_between(db, sender_id, recipient_id)
    ):
        raise BlockedDelivery

    now = datetime.now(timezone.utc)
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
            now + timedelta(seconds=destruct_after_seconds)
            if destruct_after_seconds
            else None
        ),
        delivered_at=now,  # Server considers message delivered upon successful storage and send
    )
    db.add(msg)
    await db.commit()
    await db.refresh(msg)
    return msg


async def mark_delivered(db: AsyncSession, message_id: UUID, user_id: UUID) -> Message | None:
    """Mark a message as delivered by the given user (recipient or group member)."""
    msg = await db.scalar(select(Message).where(Message.id == message_id))
    if msg is None:
        return None
    # Verify user is participant
    from app.models import GroupMember
    is_participant = False
    if msg.group_id is not None:
        member = await db.scalar(
            select(GroupMember).where(
                GroupMember.group_id == msg.group_id,
                GroupMember.user_id == user_id,
            )
        )
        is_participant = member is not None
    else:
        is_participant = (msg.sender_id == user_id) or (msg.recipient_id == user_id)
    if not is_participant:
        return None
    if msg.delivered_at is None:
        msg.delivered_at = datetime.now(timezone.utc)
        await db.commit()
    return msg


async def mark_read(db: AsyncSession, message_id: UUID, user_id: UUID) -> Message | None:
    """Mark a message as read by the given user (recipient or group member)."""
    msg = await db.scalar(select(Message).where(Message.id == message_id))
    if msg is None:
        return None
    # Verify user is participant
    from app.models import GroupMember
    is_participant = False
    if msg.group_id is not None:
        member = await db.scalar(
            select(GroupMember).where(
                GroupMember.group_id == msg.group_id,
                GroupMember.user_id == user_id,
            )
        )
        is_participant = member is not None
    else:
        is_participant = (msg.sender_id == user_id) or (msg.recipient_id == user_id)
    if not is_participant:
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