from __future__ import annotations

from datetime import datetime, timedelta, timezone
from uuid import UUID

import structlog
from sqlalchemy import and_, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core import observability
from app.models import Message, UserBlock
from app.models.message import MessageStatus, MessageType

logger = structlog.get_logger("messages")

UNSEND_WINDOW = timedelta(minutes=5)

#: The longest lifetime a caller may request. Seven days matches the group
#: route's schema, and gives one ceiling for both transports.
MAX_DESTRUCT_AFTER_SECONDS = 7 * 24 * 60 * 60


class InvalidDestructTTL(ValueError):
    """Raised when a self-destruct lifetime is not a positive bounded integer."""


def validate_destruct_after_seconds(value: int | None) -> int | None:
    """Validate and return a self-destruct lifetime.

    The WebSocket path receives raw JSON, so it cannot rely on Pydantic the
    way the HTTP group route can. Validation therefore lives here, where both
    paths meet, and a bad value is rejected instead of becoming a timer in the
    past or a 500 later in the worker.
    """
    if value is None:
        return None
    if isinstance(value, bool) or not isinstance(value, int):
        raise InvalidDestructTTL("destruct_after must be an integer number of seconds")
    if not 1 <= value <= MAX_DESTRUCT_AFTER_SECONDS:
        raise InvalidDestructTTL(
            "destruct_after must be between 1 and "
            f"{MAX_DESTRUCT_AFTER_SECONDS} seconds"
        )
    return value


def _as_utc(value: datetime) -> datetime:
    """Treat a naive timestamp as UTC instead of comparing it to an aware one."""
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def is_expired(message: Message, *, now: datetime | None = None) -> bool:
    """Whether a message's lifetime has ended, even if the sweep has not run.

    Expiry is a read-time property, not something that waits for a background
    job. A message whose `destruct_at` has passed is already gone to every
    caller; the worker only removes the bytes afterwards.
    """
    if message.is_destructed:
        return True
    if message.destruct_at is None:
        return False
    return _as_utc(message.destruct_at) <= _as_utc(now or datetime.now(timezone.utc))


def visible_message_clause(*, now: datetime | None = None):
    """SQL predicate for messages that may still be shown.

    Use this instead of `Message.is_destructed.is_(False)` in every read path.
    The sweeper runs on an interval, so there is always a window in which a
    message is past `destruct_at` but `is_destructed` is still false. During
    that window the database still holds ciphertext, and returning it would
    keep the product's promise false for up to a minute.
    """
    cutoff = _as_utc(now or datetime.now(timezone.utc))
    return and_(
        Message.is_destructed.is_(False),
        or_(Message.destruct_at.is_(None), Message.destruct_at > cutoff),
    )


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
    client_ref: str | None = None,
    reply_to_id: UUID | None = None,
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

    ttl = validate_destruct_after_seconds(destruct_after_seconds)

    # Idempotency. A client that loses the socket between the server storing a
    # message and the ack arriving cannot know which happened, so it resends
    # on reconnect — correct of it, and the reason the server has to be what
    # refuses the duplicate. Returning the original means the resend gets the
    # same ack, and the recipient is not shown the same thing twice.
    if client_ref is not None:
        existing = await db.scalar(
            select(Message).where(
                Message.sender_id == sender_id,
                Message.client_ref == client_ref,
            )
        )
        if existing is not None:
            return existing

    now = datetime.now(timezone.utc)
    msg = Message(
        client_ref=client_ref,
        sender_id=sender_id,
        recipient_id=recipient_id,
        group_id=group_id,
        message_type=message_type,
        content_ciphertext=content_ciphertext,
        media_object_key=media_object_key,
        media_mime_type=media_mime_type,
        reply_to_id=reply_to_id,
        status=MessageStatus.SENT,
        is_self_destruct=ttl is not None,
        destruct_after_seconds=ttl,
        # Deliberately no destruct_at here. For a direct message the timer is
        # burn-after-reading: it starts in mark_read, on the recipient's first
        # read. Setting it at send time made the read-time branch below
        # unreachable and turned the feature into a send-time TTL.
        destruct_at=None,
        delivered_at=now,  # Server considers message delivered upon successful storage and send
    )
    db.add(msg)
    await db.commit()
    await db.refresh(msg)
    # Counted after the commit, so the number means "accepted and durable"
    # rather than "attempted". Labelled by whether it is a direct or a group
    # conversation and by nothing else — a sender or a chat in a label would
    # publish who is talking and to whom, which is the one thing this product
    # exists to keep off the server.
    observability.messages_accepted.labels(
        kind="group" if group_id is not None else "direct"
    ).inc()
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
    msg.media_mime_type = None
    msg.deleted_for_everyone = True
    msg.deleted_at = datetime.now(timezone.utc)

    # The attachment body has to go too, and the pointer is only cleared once
    # it has.
    #
    # This used to null `media_object_key` and stop there. The encrypted object
    # stayed in the bucket, and nulling the key was what made it permanent —
    # nothing knew its name any more, so no sweep could ever find it. A user
    # who pressed "delete for everyone" left a body behind that would outlive
    # their account, and the bucket grew by one orphan per retraction.
    #
    # The delete is attempted here so it is usually immediate, but a failure
    # does not fail the retraction: the message is already marked deleted for
    # both parties, and the key is deliberately left in place so the sweeper
    # can finish the job. Object storage being briefly unreachable must not
    # mean the user's deletion silently did not happen.
    if msg.media_object_key:
        from app.config import settings
        from app.services.storage_service import StorageService

        try:
            StorageService().delete_object(
                settings.S3_BUCKET_ATTACHMENTS, msg.media_object_key
            )
            msg.media_object_key = None
        except Exception as exc:  # noqa: BLE001 — retried by the sweeper
            observability.orphaned_attachments.inc()
            logger.warning(
                "unsend_object_delete_failed",
                message_id=str(msg.id),
                error=str(exc),
            )

    await db.commit()
    return msg