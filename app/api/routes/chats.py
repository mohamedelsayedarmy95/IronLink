from __future__ import annotations

from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, ConfigDict
from sqlalchemy import and_, desc, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.api.routes.websocket import manager
from app.core.database import get_db
from app.models import Message, User

router = APIRouter(prefix="/chats", tags=["chats"])


class ConversationOut(BaseModel):
    peer_id: UUID
    peer_name: str
    peer_avatar_url: str | None = None
    is_online: bool
    last_message_preview: str | None
    last_message_at: datetime | None
    unread_count: int


class MessageOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    sender_id: UUID | None
    recipient_id: UUID | None
    message_type: str
    content_ciphertext: str | None
    status: str
    created_at: datetime
    deleted_for_everyone: bool


@router.get("", response_model=list[ConversationOut])
async def list_conversations(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[ConversationOut]:
    """Distinct DM partners, most recent first, with online flag from Redis."""
    peer_expr = func.coalesce(
        func.nullif(Message.sender_id, user.id), Message.recipient_id
    )
    latest = (
        select(
            peer_expr.label("peer_id"),
            func.max(Message.created_at).label("last_at"),
        )
        .where(
            or_(Message.sender_id == user.id, Message.recipient_id == user.id),
            Message.group_id.is_(None),
            Message.is_destructed.is_(False),
        )
        .group_by("peer_id")
        .subquery()
    )

    rows = (await db.execute(
        select(User, latest.c.last_at)
        .join(latest, latest.c.peer_id == User.id)
        .order_by(desc(latest.c.last_at))
    )).all()

    out: list[ConversationOut] = []
    for peer, last_at in rows:
        last_msg = await db.scalar(
            select(Message)
            .where(
                or_(
                    and_(Message.sender_id == user.id, Message.recipient_id == peer.id),
                    and_(Message.sender_id == peer.id, Message.recipient_id == user.id),
                ),
                Message.is_destructed.is_(False),
            )
            .order_by(desc(Message.created_at))
            .limit(1)
        )
        unread = await db.scalar(
            select(func.count(Message.id)).where(
                Message.sender_id == peer.id,
                Message.recipient_id == user.id,
                Message.status != "read",
                Message.is_destructed.is_(False),
            )
        ) or 0

        # No preview from the server, ever.
        #
        # This used to return `content_ciphertext[:20]`, and a twenty-character
        # fragment of a Signal envelope cannot be decrypted by anybody —
        # including the recipient it was sent to. The conversation list was
        # rendering that fragment as though it were text.
        #
        # It is not a leak; the fragment is as useless to an attacker as it is
        # to the user. It is a preview that was designed against a model where
        # the server could read messages, and never revisited when it could
        # not. The client holds the decrypted history and renders the preview
        # from there.
        #
        # The message *kind* is still worth sending: it lets the list show
        # "photo" or "voice note" for a conversation the device has no local
        # copy of, which is the one case the client cannot cover itself.
        preview = None
        if last_msg is not None and not last_msg.deleted_for_everyone:
            if last_msg.message_type != "text":
                preview = f"[{last_msg.message_type}]"

        out.append(ConversationOut(
            peer_id=peer.id,
            peer_name=peer.full_name,
            is_online=await manager.is_online(peer.id),
            last_message_preview=preview,
            last_message_at=last_at,
            unread_count=unread,
        ))
    return out


@router.get("/{peer_id}/messages", response_model=list[MessageOut])
async def message_history(
    peer_id: UUID,
    before: datetime | None = Query(default=None),
    limit: int = Query(default=50, le=100),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[MessageOut]:
    peer = await db.scalar(select(User).where(User.id == peer_id))
    if peer is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="peer not found")

    q = (
        select(Message)
        .where(
            or_(
                and_(Message.sender_id == user.id, Message.recipient_id == peer_id),
                and_(Message.sender_id == peer_id, Message.recipient_id == user.id),
            ),
            Message.is_destructed.is_(False),
        )
        .order_by(desc(Message.created_at))
        .limit(limit)
    )
    if before is not None:
        q = q.where(Message.created_at < before)

    messages = list((await db.scalars(q)).all())
    messages.reverse()   # chronological for the client
    return [MessageOut.model_validate(m) for m in messages]
