from __future__ import annotations

from datetime import datetime
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import get_db
from app.models import Broadcast, BroadcastAck, User

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


@router.post("/{broadcast_id}/ack", status_code=status.HTTP_204_NO_CONTENT)
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


@router.post("/fcm-token", status_code=status.HTTP_204_NO_CONTENT)
async def register_fcm_token(
    body: FcmTokenIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> None:
    """Called by the app on every launch and on FCM token rotation."""
    user.fcm_token = body.token
    await db.commit()
