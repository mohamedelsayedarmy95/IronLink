"""Group messaging.

The server routes group messages; it never reads them. A group message is
encrypted once by the sender with a sender key that only members hold, and
this module fans the resulting ciphertext out to the members' channels.

What the server does own is membership, and therefore the epoch — see
Group.members_epoch. Clients cannot be trusted to notice a removal on their
own, and the server cannot rotate keys for them, so the one useful thing it
can do is make the change loud.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from uuid import UUID

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Group, GroupMember, Message
from app.models.message import MessageStatus

#: Sender-key distribution messages. Delivered over the ordinary one-to-one
#: path (pairwise encrypted, one per recipient) but never shown as chat: they
#: are key material, not something anyone said.
SKDM_MESSAGE_TYPE = "skdm"


class NotAMember(Exception):
    """The caller is not in the group, or the group does not exist.

    One exception for both, deliberately: distinguishing them would let
    anyone probe which group ids exist.
    """


class PostingNotAllowed(Exception):
    """The group is announcement-only and the caller is not an admin."""


async def assert_member(
    db: AsyncSession, group_id: UUID, user_id: UUID
) -> GroupMember:
    member = await db.scalar(
        select(GroupMember).where(
            GroupMember.group_id == group_id,
            GroupMember.user_id == user_id,
        )
    )
    if member is None:
        raise NotAMember
    return member


async def member_ids(db: AsyncSession, group_id: UUID) -> list[UUID]:
    return list(
        (
            await db.scalars(
                select(GroupMember.user_id).where(
                    GroupMember.group_id == group_id
                )
            )
        ).all()
    )


async def bump_epoch(db: AsyncSession, group_id: UUID) -> int:
    """Records that the membership changed, and returns the new epoch.

    Called on join, leave, removal and ban. Missing one of those is not a
    cosmetic bug: it leaves a departed member able to read everything that
    follows, because no sender is told to rotate.

    The increment is done in SQL rather than read-modify-write so two
    concurrent membership changes cannot land on the same epoch — which
    would look to clients like nothing had happened at all.
    """
    result = await db.execute(
        update(Group)
        .where(Group.id == group_id)
        .values(members_epoch=Group.members_epoch + 1)
        .returning(Group.members_epoch)
    )
    epoch = result.scalar_one_or_none()
    return int(epoch) if epoch is not None else 0


async def save_group_message(
    db: AsyncSession,
    *,
    group_id: UUID,
    sender_id: UUID,
    message_type: str,
    content_ciphertext: str | None,
    media_object_key: str | None = None,
    media_mime_type: str | None = None,
    destruct_after_seconds: int | None = None,
) -> Message:
    """Stores a group message after checking the sender may post.

    Blocks are deliberately not consulted here. Blocking someone stops them
    reaching you directly; letting it also silence them in a shared group
    would turn a personal boundary into a way to disrupt everyone else's
    conversation.
    """
    member = await assert_member(db, group_id, sender_id)

    group = await db.scalar(select(Group).where(Group.id == group_id))
    if group is None:
        raise NotAMember
    if group.only_admins_can_post and member.role not in ("admin", "owner"):
        raise PostingNotAllowed

    now = datetime.now(timezone.utc)
    # A group-wide disappearing-message setting applies to every message in
    # it, so a member cannot opt their own messages out of the group's rule.
    ttl = destruct_after_seconds or group.disappearing_messages_seconds

    msg = Message(
        sender_id=sender_id,
        recipient_id=None,
        group_id=group_id,
        message_type=message_type,
        content_ciphertext=content_ciphertext,
        media_object_key=media_object_key,
        media_mime_type=media_mime_type,
        status=MessageStatus.SENT,
        is_self_destruct=ttl is not None,
        destruct_after_seconds=ttl,
        destruct_at=now + timedelta(seconds=ttl) if ttl else None,
        delivered_at=now,
    )
    db.add(msg)
    await db.commit()
    await db.refresh(msg)
    return msg


async def history(
    db: AsyncSession,
    *,
    group_id: UUID,
    user_id: UUID,
    limit: int = 50,
    before: datetime | None = None,
) -> list[Message]:
    """Messages in a group, newest first.

    Only members, and only from the point they joined: a group's past is not
    something a new member is entitled to, and under encryption they could
    not read it anyway — the sender keys they hold start at their arrival.
    Returning rows they can never decrypt would only look like corruption.
    """
    member = await assert_member(db, group_id, user_id)

    stmt = (
        select(Message)
        .where(
            Message.group_id == group_id,
            Message.created_at >= member.joined_at,
            Message.message_type != SKDM_MESSAGE_TYPE,
        )
        .order_by(Message.created_at.desc())
        .limit(limit)
    )
    if before is not None:
        stmt = stmt.where(Message.created_at < before)

    return list((await db.scalars(stmt)).all())
