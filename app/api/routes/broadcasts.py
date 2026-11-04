from __future__ import annotations

from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_session, get_current_user
from app.core.database import get_db
from app.models import Broadcast, BroadcastAck, User, UserSession

router = APIRouter(prefix="/broadcasts", tags=["broadcasts"])


class BroadcastItemOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    title: str
    body: str
    priority: str
    created_at: datetime


class FcmTokenIn(BaseModel):
    token: str = Field(..., min_length=32, max_length=512)


@router.get("/unacked", response_model=list[BroadcastItemOut])
async def unacked_broadcasts(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[BroadcastItemOut]:
    """Broadcasts this user has NOT tapped yet — the client shows a persistent
    banner for each, above all conversations, until acknowledged."""
    acked = select(BroadcastAck.broadcast_id).where(BroadcastAck.user_id == user.id)
    rows = (await db.scalars(
        select(Broadcast)
        .where(
            Broadcast.id.notin_(acked),
            or_(
                Broadcast.department.is_(None),
                Broadcast.department == user.department,
            ),
        )
        .order_by(Broadcast.created_at.desc())
    )).all()
    return [BroadcastItemOut.model_validate(b) for b in rows]


@router.post("/{broadcast_id}/ack", status_code=status.HTTP_204_NO_CONTENT, response_model=None)
async def ack_broadcast(
    broadcast_id: UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> None:
    broadcast = await db.scalar(select(Broadcast).where(Broadcast.id == broadcast_id))
    if broadcast is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "broadcast not found")

    existing = await db.scalar(
        select(BroadcastAck).where(
            BroadcastAck.broadcast_id == broadcast_id,
            BroadcastAck.user_id == user.id,
        )
    )
    if existing is None:
        db.add(BroadcastAck(broadcast_id=broadcast_id, user_id=user.id))
        await db.commit()


@router.post("/fcm-token", status_code=status.HTTP_204_NO_CONTENT, response_model=None)
async def register_fcm_token(
    body: FcmTokenIn,
    user: User = Depends(get_current_user),
    session: UserSession = Depends(get_current_session),
    db: AsyncSession = Depends(get_db),
) -> None:
    """Called by the app on every launch and on FCM token rotation.

    The token is recorded against the *session*, because it identifies an
    installation rather than an account. It used to be one column on `users`,
    so a phone and a tablet had exactly one of them receiving notifications,
    decided by whichever launched the app last.

    `users.fcm_token` is still written. This is the expand half of an
    expand-migrate-contract: nothing reads it any more, but a rollback to the
    previous release would, and it must not find the column stale. The write
    goes away with the migration that drops the column.
    """
    session.fcm_token = body.token
    user.fcm_token = body.token
    await db.commit()
