from __future__ import annotations

from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import get_db
from app.models import User
from app.services import group_message_service

router = APIRouter(prefix="/groups", tags=["group-messages"])


class GroupMessageIn(BaseModel):
    """A group message, already encrypted by the sender.

    content is a sender-key ciphertext. The server stores and routes it and
    cannot read it — there is deliberately no field here for anything the
    server would need to understand.
    """

    content: str | None = Field(default=None, max_length=64_000)
    message_type: str = Field(default="text", max_length=20)
    media_key: str | None = Field(default=None, max_length=500)
    media_mime: str | None = Field(default=None, max_length=100)
    destruct_after: int | None = Field(default=None, ge=1, le=604_800)


class GroupMessageOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    sender_id: UUID
    message_type: str
    content_ciphertext: str | None
    media_object_key: str | None
    media_mime_type: str | None
    created_at: datetime
    deleted_for_everyone: bool


@router.post(
    "/{group_id}/messages",
    response_model=GroupMessageOut,
    status_code=status.HTTP_201_CREATED,
)
async def send_group_message(
    group_id: UUID,
    body: GroupMessageIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> GroupMessageOut:
    """Send to a group over HTTP.

    The WebSocket path is the normal one; this exists so a send still works
    when the socket is down, and so the two share one service rather than
    one of them growing its own rules.

    Note that it does not fan out over Pub/Sub — members receive it when
    they next load history. Duplicating the fan-out here would mean two
    places to keep correct.
    """
    try:
        msg = await group_message_service.save_group_message(
            db,
            group_id=group_id,
            sender_id=user.id,
            message_type=body.message_type,
            content_ciphertext=body.content,
            media_object_key=body.media_key,
            media_mime_type=body.media_mime,
            destruct_after_seconds=body.destruct_after,
        )
    except group_message_service.NotAMember:
        raise HTTPException(
            status.HTTP_404_NOT_FOUND, "group not found"
        ) from None
    except group_message_service.PostingNotAllowed:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN, "only admins can post in this group"
        ) from None

    return GroupMessageOut.model_validate(msg)


@router.get("/{group_id}/messages", response_model=list[GroupMessageOut])
async def group_history(
    group_id: UUID,
    limit: int = Query(default=50, ge=1, le=100),
    before: datetime | None = None,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[GroupMessageOut]:
    try:
        messages = await group_message_service.history(
            db, group_id=group_id, user_id=user.id, limit=limit, before=before
        )
    except group_message_service.NotAMember:
        # Same 404 as a group that does not exist — otherwise this is an
        # oracle for which group ids are real.
        raise HTTPException(
            status.HTTP_404_NOT_FOUND, "group not found"
        ) from None

    return [GroupMessageOut.model_validate(m) for m in messages]
