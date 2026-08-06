from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Path, status
from pydantic import BaseModel

from app.api.deps import get_current_user
from app.core.redis import redis_pubsub
from app.models import User, GroupMember
from app.services import message_service
from app.services.ws_manager import connection_manager  # assuming a global instance

router = APIRouter(tags=["receipts"])


class TypingUpdate(BaseModel):
    typing: bool


def _user_channel(user_id: UUID | str) -> str:
    return f"chan:user:{user_id}"


async def _verify_chat_participant(
    message_id: UUID, user_id: UUID, db
) -> tuple[UUID, UUID | None, UUID | None]:
    """Return (message_id, sender_id, recipient_id/group_id) if user is a participant.
    Raises HTTPException if not.
    """
    from app.models import Message  # local import to avoid circular
    msg = await db.scalar(
        select(Message).where(Message.id == message_id)
    )
    if msg is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Message not found")
    # Determine if user is participant
    is_participant = False
    if msg.group_id is not None:
        # Group chat: check membership
        member = await db.scalar(
            select(GroupMember).where(
                GroupMember.group_id == msg.group_id,
                GroupMember.user_id == user_id,
            )
        )
        is_participant = member is not None
        group_id = msg.group_id
        recipient_id = None
    else:
        # Direct message
        is_participant = (msg.sender_id == user_id) or (msg.recipient_id == user_id)
        group_id = None
        recipient_id = msg.recipient_id
    if not is_participant:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not a participant of this chat")
    return msg.id, msg.sender_id, recipient_id


@router.post(
    "/chats/{chat_id}/messages/{message_id}/delivered",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def mark_message_delivered(
    chat_id: UUID = Path(...),
    message_id: UUID = Path(...),
    current_user: User = Depends(get_current_user),
):
    """Mark a message as delivered by the current user (recipient)."""
    from app.models import Message  # local import to avoid circular
    from app.core.database import AsyncSessionLocal

    async with AsyncSessionLocal() as db:
        # Verify that the message belongs to the chat and user is recipient
        msg = await db.scalar(
            select(Message).where(
                Message.id == message_id,
                ((Message.recipient_id == current_user.id) & (Message.group_id.is_(None))) |
                ((Message.group_id == chat_id) & (Message.recipient_id.is_(None)))  # placeholder for group delivered? we'll treat per-user later
            )
        )
        # Simpler: just verify user is recipient of the message (direct) or a member of the group
        # We'll reuse the helper but we need sender_id etc.
        # Let's do a manual check:
        if msg is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Message not found or not in this chat")
        # Determine if user is recipient (for direct) or group member
        is_recipient = False
        if msg.group_id is None:
            if msg.recipient_id == current_user.id:
                is_recipient = True
        else:
            # check group membership
            member = await db.scalar(
                select(GroupMember).where(
                    GroupMember.group_id == msg.group_id,
                    GroupMember.user_id == current_user.id,
                )
            )
            is_recipient = member is not None
        if not is_recipient:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="You are not the recipient of this message")
        # Mark delivered
        updated = await message_service.mark_delivered(db, message_id, current_user.id)
        if updated is None:
            raise HTTPException(status_code=status.HTTP_304_NOT_MODIFIED, detail="Already delivered or read")
        # Notify sender via WS using connection manager
        await connection_manager.broadcast_delivered(chat_id, message_id, updated.sender_id)
        return None


@router.post(
    "/chats/{chat_id}/messages/{message_id}/read",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def mark_message_read(
    chat_id: UUID = Path(...),
    message_id: UUID = Path(...),
    current_user: User = Depends(get_current_user),
):
    """Mark a message as read by the current user (recipient)."""
    from app.models import Message
    from app.core.database import AsyncSessionLocal

    async with AsyncSessionLocal() as db:
        msg = await db.scalar(
            select(Message).where(Message.id == message_id)
        )
        if msg is None:
            raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="Message not found")
        # Verify user is recipient (direct) or group member
        is_recipient = False
        if msg.group_id is None:
            if msg.recipient_id == current_user.id:
                is_recipient = True
        else:
            member = await db.scalar(
                select(GroupMember).where(
                    GroupMember.group_id == msg.group_id,
                    GroupMember.user_id == current_user.id,
                )
            )
            is_recipient = member is not None
        if not is_recipient:
            raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="You are not the recipient of this message")
        updated = await message_service.mark_read(db, message_id, current_user.id)
        if updated is None:
            raise HTTPException(status_code=status.HTTP_304_NOT_MODIFIED, detail="Already read")
        # Notify via WS using connection manager (broadcast read to group members)
        await connection_manager.broadcast_read(chat_id, message_id, current_user.id)
        return None


@router.post(
    "/chats/{chat_id}/typing",
    status_code=status.HTTP_204_NO_CONTENT,
)
async def update_typing(
    chat_id: UUID = Path(...),
    body: TypingUpdate = ...,
    current_user: User = Depends(get_current_user),
):
    """Broadcast typing indicator to other participants in the chat."""
    from app.models import Message, GroupMember
    from app.core.database import AsyncSessionLocal

    async with AsyncSessionLocal() as db:
        # Verify user is participant of the chat
        # Check if there exists any message in this chat where user is participant (simplify)
        # We'll instead check group membership or existence of a direct message with user.
        # For simplicity, we'll allow typing if user is a member of the group (if chat_id corresponds to a group)
        # or if there exists a direct message between user and another user with chat_id representing the other user?
        # Since chat_id is UUID, we need to know if it's a group ID or a user ID (for direct).
        # In our current design, chat_id in the URL is actually the group ID for groups, and for direct messages we use the other user's ID?
        # Looking at existing routes: we have /chats/{chat_id} used elsewhere? Let's check websocket route: they use ticket, not chat_id.
        # We'll assume chat_id is group ID for groups, and for direct messages we use a placeholder? Actually we don't have a chat concept; we have direct messages via recipient_id.
        # The frontend likely uses a chat identifier that is either group ID or the other user's ID.
        # To keep it simple, we'll treat chat_id as group ID; if it's not a group, we'll try to find a direct message where the other participant's ID matches chat_id and current user is participant.
        # We'll implement both.

        # First, try as group ID
        from app.models import Group
        group = await db.scalar(
            select(Group).where(Group.id == chat_id)
        )
        if group is not None:
            member = await db.scalar(
                select(GroupMember).where(
                    GroupMember.group_id == chat_id,
                    GroupMember.user_id == current_user.id,
                )
            )
            if member is None:
                raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Not a member of this group")
        else:
            # treat as direct message with the other user
            other_user_id = chat_id
            # Verify that there is a direct message (or at least that a direct chat exists) between current_user and other_user_id
            # We'll check if there exists any message where sender and recipient are these two users (group_id null)
            exists = await db.scalar(
                select(Message.id).where(
                    ((Message.sender_id == current_user.id) & (Message.recipient_id == other_user_id)) |
                    ((Message.sender_id == other_user_id) & (Message.recipient_id == current_user.id)),
                    Message.group_id.is_(None),
                ).limit(1)
            )
            if exists is None:
                raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="No direct chat with this user")
        # Now broadcast typing to each participant via connection manager
        await connection_manager.broadcast_typing(chat_id, current_user.id, body.typing)
        return None