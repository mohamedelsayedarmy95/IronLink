from __future__ import annotations

from datetime import datetime, time, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.api.routes.websocket import manager, publish
from app.core.database import get_db
from app.models import AuditLog, Broadcast, Message, User
from app.models.audit_log import AuditAction
from app.models.user import UserRole, UserStatus
from app.services import push_service

router = APIRouter(prefix="/admin", tags=["admin"])


# ── Guard ─────────────────────────────────────────────────────────────────────

async def require_superadmin(user: User = Depends(get_current_user)) -> User:
    """Fable5-Enhancement: admin endpoints are additionally IP-restrictable at
    the Nginx layer (location /api/v1/admin { allow <ops-subnet>; deny all; })
    — defense in depth on top of this role check. Documented in README_Sprint3."""
    if user.role not in (UserRole.ADMIN, UserRole.SUPERADMIN):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "superadmin role required")
    return user


# ── Schemas ───────────────────────────────────────────────────────────────────

class AdminUserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    full_name: str
    phone_number: str
    department: str | None
    role: str
    status: str
    last_seen_at: datetime | None
    created_at: datetime


class SetStatusIn(BaseModel):
    action: str = Field(..., pattern="^(suspend|activate)$")
    reason: str = Field(..., min_length=5, max_length=500,
                        description="Mandatory — stored in the audit log")


class StatsOut(BaseModel):
    online_now: int
    total_users: int
    active_users: int
    suspended_users: int
    messages_today: int
    storage_used_bytes: int


class BroadcastIn(BaseModel):
    title: str = Field(..., min_length=2, max_length=120)
    body: str = Field(..., min_length=2, max_length=2000)
    department: str | None = Field(default=None, max_length=80,
                                   description="NULL = every user")


class BroadcastOut(BaseModel):
    id: UUID
    title: str
    target_users: int
    push_delivered: int


# ── Users ─────────────────────────────────────────────────────────────────────

@router.get("/users", response_model=list[AdminUserOut])
async def list_users(
    department: str | None = Query(default=None),
    user_status: str | None = Query(default=None, alias="status"),
    q: str | None = Query(default=None, max_length=80, description="name/phone search"),
    limit: int = Query(default=50, le=200),
    offset: int = Query(default=0, ge=0),
    _admin: User = Depends(require_superadmin),
    db: AsyncSession = Depends(get_db),
) -> list[AdminUserOut]:
    query = select(User).order_by(User.created_at.desc()).limit(limit).offset(offset)
    if department:
        query = query.where(User.department == department)
    if user_status:
        query = query.where(User.status == user_status)
    if q:
        query = query.where(or_(
            User.full_name.ilike(f"%{q}%"),
            User.phone_number.ilike(f"%{q}%"),
        ))
    users = (await db.scalars(query)).all()
    return [AdminUserOut.model_validate(u) for u in users]


@router.post("/users/{user_id}/status", response_model=AdminUserOut)
async def set_user_status(
    user_id: UUID,
    body: SetStatusIn,
    admin: User = Depends(require_superadmin),
    db: AsyncSession = Depends(get_db),
) -> AdminUserOut:
    target = await db.scalar(select(User).where(User.id == user_id))
    if target is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "user not found")
    if target.role == UserRole.SUPERADMIN and admin.role != UserRole.SUPERADMIN:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "cannot modify a superadmin")

    if body.action == "suspend":
        target.status = UserStatus.SUSPENDED
        # Nuclear invalidation: every token on every device dies instantly
        target.token_version += 1
        action = AuditAction.USER_SUSPENDED
        # Live sockets get told to drop immediately
        await publish(target.id, {"type": "account_suspended"})
    else:
        target.status = UserStatus.ACTIVE
        action = AuditAction.USER_REACTIVATED

    db.add(AuditLog(
        actor_id=admin.id,
        actor_role=admin.role,
        action=action,
        resource_type="user",
        resource_id=str(target.id),
        description=body.reason,          # mandatory reason, as specified
        success=True,
    ))
    await db.commit()
    await db.refresh(target)
    return AdminUserOut.model_validate(target)


# ── Live stats ────────────────────────────────────────────────────────────────

@router.get("/stats", response_model=StatsOut)
async def live_stats(
    _admin: User = Depends(require_superadmin),
    db: AsyncSession = Depends(get_db),
) -> StatsOut:
    today_start = datetime.combine(
        datetime.now(timezone.utc).date(), time.min, tzinfo=timezone.utc
    )

    total = await db.scalar(select(func.count(User.id))) or 0
    active = await db.scalar(
        select(func.count(User.id)).where(User.status == UserStatus.ACTIVE)
    ) or 0
    suspended = await db.scalar(
        select(func.count(User.id)).where(User.status == UserStatus.SUSPENDED)
    ) or 0
    messages_today = await db.scalar(
        select(func.count(Message.id)).where(Message.created_at >= today_start)
    ) or 0
    # Fable5-Enhancement: storage figure comes from the DB column sum, not from
    # walking the MinIO bucket — O(1) on an indexed aggregate vs. an S3 LIST
    # that would take seconds at 7000-user scale.
    storage = await db.scalar(
        select(func.coalesce(func.sum(Message.media_size_bytes), 0))
    ) or 0

    return StatsOut(
        online_now=await manager.online_count(),
        total_users=total,
        active_users=active,
        suspended_users=suspended,
        messages_today=messages_today,
        storage_used_bytes=int(storage),
    )


# ── Urgent broadcast ──────────────────────────────────────────────────────────

@router.post("/broadcast", response_model=BroadcastOut, status_code=status.HTTP_201_CREATED)
async def send_broadcast(
    body: BroadcastIn,
    admin: User = Depends(require_superadmin),
    db: AsyncSession = Depends(get_db),
) -> BroadcastOut:
    broadcast = Broadcast(
        title=body.title,
        body=body.body,
        department=body.department,
        created_by_id=admin.id,
    )
    db.add(broadcast)
    await db.flush()

    target_q = select(User).where(User.status == UserStatus.ACTIVE)
    if body.department:
        target_q = target_q.where(User.department == body.department)
    targets = (await db.scalars(target_q)).all()

    db.add(AuditLog(
        actor_id=admin.id,
        actor_role=admin.role,
        action="admin.broadcast.sent",
        resource_type="broadcast",
        resource_id=str(broadcast.id),
        metadata_={"department": body.department, "targets": len(targets)},
        success=True,
    ))
    await db.commit()

    # Online devices: instant WS frame on the global broadcast channel
    frame = {
        "type": "broadcast",
        "broadcast_id": str(broadcast.id),
        "title": body.title,
        "body": body.body,
        "department": body.department,
    }
    from app.api.routes.websocket import publish_broadcast
    await publish_broadcast(frame)

    # Offline devices: FCM push
    tokens = [u.fcm_token for u in targets if u.fcm_token]
    delivered = await push_service.send_broadcast_push(
        tokens, title=body.title, body=body.body, broadcast_id=str(broadcast.id)
    )

    return BroadcastOut(
        id=broadcast.id,
        title=broadcast.title,
        target_users=len(targets),
        push_delivered=delivered,
    )
