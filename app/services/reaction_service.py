"""Reactions.

A reaction is stored as a message whose `message_type` is `reaction` and whose
`reply_to_id` names what it reacts to. That is not a shortcut; it is the design.

WHY IT IS A MESSAGE

A reaction is content. An emoji says something about what was said — often
something the sender would not want a server to know, since "somebody laughed at
this" and "somebody was angry about this" are exactly the kind of inference a
metadata-only adversary is trying to draw.

So it has to be encrypted, and the encrypted path already exists: a Signal
session for a direct chat, a sender key for a group. Reusing it means reactions
inherit idempotency, fan-out, ordering and retraction from code that is already
tested, and — more importantly while RISK-01 is open — it means no new
cryptographic construction was invented to carry them.

The server ends up storing a reaction it cannot read. It learns that somebody
reacted to something, which it already knew from the conversation graph, and
not what they said.

ONE PER PERSON PER MESSAGE

Reacting again replaces the previous reaction rather than adding to it, which
is what most people expect and what makes the aggregate legible. Sending an
empty reaction removes it.

The replacement is a delete-then-insert rather than an update, because the row
carries a `client_ref` for idempotency and reusing it would make a genuine
resend indistinguishable from a change of mind.
"""

from __future__ import annotations

from uuid import UUID

import structlog
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import Message
from app.models.message import MessageType
from app.services import message_service

logger = structlog.get_logger("reactions")


class ReactionTargetMissing(Exception):
    """The message being reacted to does not exist, or is not visible."""


async def set_reaction(
    db: AsyncSession,
    *,
    sender_id: UUID,
    target_id: UUID,
    recipient_id: UUID | None,
    group_id: UUID | None,
    content_ciphertext: str | None,
    client_ref: str | None = None,
) -> Message | None:
    """Records, replaces, or clears one person's reaction to one message.

    Returns the stored reaction, or None when it was cleared.
    """
    target = await db.scalar(select(Message).where(Message.id == target_id))
    if target is None:
        raise ReactionTargetMissing

    # Reacting to a retracted message is refused. The message is gone for
    # everyone; a reaction to it would render against nothing and would keep a
    # reference to something the sender asked to have removed.
    if target.deleted_for_everyone or target.is_destructed:
        raise ReactionTargetMissing

    # Replace rather than accumulate. Delete first, unconditionally, so
    # clearing and changing are the same operation up to this point.
    await db.execute(
        delete(Message).where(
            Message.sender_id == sender_id,
            Message.reply_to_id == target_id,
            Message.message_type == MessageType.REACTION.value,
        )
    )

    if not content_ciphertext:
        await db.commit()
        logger.info("reaction_cleared")
        return None

    reaction = await message_service.save_message(
        db,
        sender_id=sender_id,
        recipient_id=recipient_id,
        group_id=group_id,
        message_type=MessageType.REACTION.value,
        content_ciphertext=content_ciphertext,
        client_ref=client_ref,
        reply_to_id=target_id,
        # Blocks are enforced on the message being reacted to, not here. A
        # person who can see a message can react to it; if they could not see
        # it, they could not have obtained its id.
        enforce_blocks=True,
    )
    logger.info("reaction_set")
    return reaction


async def for_messages(
    db: AsyncSession, message_ids: list[UUID]
) -> list[Message]:
    """Every reaction attached to any of [message_ids].

    Fetched separately from the message page rather than inline, because
    reactions would otherwise consume the page budget: a message with twenty
    reactions would push nineteen real messages off a page of fifty, and a
    conversation would appear to have gaps that are not there.
    """
    if not message_ids:
        return []

    rows = await db.scalars(
        select(Message).where(
            Message.message_type == MessageType.REACTION.value,
            Message.reply_to_id.in_(message_ids),
            Message.is_destructed.is_(False),
        )
    )
    return list(rows.all())
