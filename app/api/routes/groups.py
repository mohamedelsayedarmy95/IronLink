from __future__ import annotations

from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, ConfigDict, Field
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import get_db
from app.models import (
    AuditLog,
    Group,
    GroupJoinRequest,
    GroupMember,
    User,
)
from app.models.audit_log import AuditAction
from app.models.group import GroupRole, JoinRequestStatus

router = APIRouter(prefix="/groups", tags=["groups"])


# ── Schemas ───────────────────────────────────────────────────────────────────

class GroupOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str
    description: str | None
    group_type: str
    is_announcement_group: bool
    join_approval_required: bool
    member_count: int = 0
    my_role: str | None = None


class MemberOut(BaseModel):
    user_id: UUID
    full_name: str
    role: str
    is_muted: bool


class CreateGroupIn(BaseModel):
    name: str = Field(..., min_length=2, max_length=200)
    description: str | None = Field(default=None, max_length=1000)
    is_announcement_group: bool = False
    join_approval_required: bool = True


class JoinRequestIn(BaseModel):
    message: str | None = Field(default=None, max_length=300)


class JoinRequestOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    user_id: UUID
    status: str
    message: str | None
    created_at: datetime


class DecideJoinIn(BaseModel):
    approve: bool


# ── Helpers ───────────────────────────────────────────────────────────────────

async def _membership(
    db: AsyncSession, group_id: UUID, user_id: UUID
) -> GroupMember | None:
    return await db.scalar(
        select(GroupMember).where(
            GroupMember.group_id == group_id,
            GroupMember.user_id == user_id,
        )
    )


async def _require_admin_member(
    db: AsyncSession, group_id: UUID, user_id: UUID
) -> GroupMember:
    member = await _membership(db, group_id, user_id)
    if member is None or not member.can_manage_members():
        raise HTTPException(status.HTTP_403_FORBIDDEN, "group admin role required")
    return member


# ── Endpoints ─────────────────────────────────────────────────────────────────

@router.get("", response_model=list[GroupOut])
async def my_groups(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[GroupOut]:
    rows = (await db.execute(
        select(Group, GroupMember.role)
        .join(GroupMember, GroupMember.group_id == Group.id)
        .where(GroupMember.user_id == user.id, Group.is_archived.is_(False))
        .order_by(Group.created_at.desc())
    )).all()

    out = []
    for group, my_role in rows:
        count = await db.scalar(
            select(func.count(GroupMember.id)).where(GroupMember.group_id == group.id)
        ) or 0
        g = GroupOut.model_validate(group)
        g.member_count = count
        g.my_role = my_role
        out.append(g)
    return out


@router.post("", response_model=GroupOut, status_code=status.HTTP_201_CREATED)
async def create_group(
    body: CreateGroupIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> GroupOut:
    group = Group(
        name=body.name,
        description=body.description,
        is_announcement_group=body.is_announcement_group,
        join_approval_required=body.join_approval_required,
        group_type="task_force",
    )
    db.add(group)
    await db.flush()

    db.add(GroupMember(
        group_id=group.id,
        user_id=user.id,
        role=GroupRole.OWNER,
        joined_at=datetime.now(timezone.utc),
    ))
    db.add(AuditLog(
        actor_id=user.id,
        actor_role=user.role,
        action=AuditAction.GROUP_CREATED,
        resource_type="group",
        resource_id=str(group.id),
        success=True,
    ))
    await db.commit()
    await db.refresh(group)

    g = GroupOut.model_validate(group)
    g.member_count = 1
    g.my_role = GroupRole.OWNER
    return g


@router.get("/{group_id}/members", response_model=list[MemberOut])
async def group_members(
    group_id: UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[MemberOut]:
    if await _membership(db, group_id, user.id) is None:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "not a member of this group")

    rows = (await db.execute(
        select(GroupMember, User.full_name)
        .join(User, User.id == GroupMember.user_id)
        .where(GroupMember.group_id == group_id)
        .order_by(GroupMember.joined_at)
    )).all()
    return [
        MemberOut(
            user_id=m.user_id,
            full_name=name,
            role=m.role,
            is_muted=m.is_muted,
        )
        for m, name in rows
    ]


@router.post("/{group_id}/join", response_model=JoinRequestOut, status_code=status.HTTP_201_CREATED)
async def request_join(
    group_id: UUID,
    body: JoinRequestIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> JoinRequestOut:
    group = await db.scalar(select(Group).where(Group.id == group_id))
    if group is None or group.is_archived:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "group not found")
    if await _membership(db, group_id, user.id) is not None:
        raise HTTPException(status.HTTP_409_CONFLICT, "already a member")

    existing = await db.scalar(
        select(GroupJoinRequest).where(
            GroupJoinRequest.group_id == group_id,
            GroupJoinRequest.user_id == user.id,
        )
    )
    if existing is not None and existing.status == JoinRequestStatus.PENDING:
        raise HTTPException(status.HTTP_409_CONFLICT, "request already pending")

    if not group.join_approval_required:
        # Open group — join immediately, record an auto-approved request row
        db.add(GroupMember(
            group_id=group_id, user_id=user.id,
            role=GroupRole.MEMBER, joined_at=datetime.now(timezone.utc),
        ))

    req = existing or GroupJoinRequest(group_id=group_id, user_id=user.id)
    req.message = body.message
    req.status = (
        JoinRequestStatus.APPROVED
        if not group.join_approval_required
        else JoinRequestStatus.PENDING
    )
    if existing is None:
        db.add(req)
    await db.commit()
    await db.refresh(req)
    return JoinRequestOut.model_validate(req)


@router.get("/{group_id}/join-requests", response_model=list[JoinRequestOut])
async def pending_requests(
    group_id: UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[JoinRequestOut]:
    await _require_admin_member(db, group_id, user.id)
    rows = (await db.scalars(
        select(GroupJoinRequest).where(
            GroupJoinRequest.group_id == group_id,
            GroupJoinRequest.status == JoinRequestStatus.PENDING,
        )
    )).all()
    return [JoinRequestOut.model_validate(r) for r in rows]


@router.post("/{group_id}/join-requests/{request_id}", response_model=JoinRequestOut)
async def decide_request(
    group_id: UUID,
    request_id: UUID,
    body: DecideJoinIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> JoinRequestOut:
    await _require_admin_member(db, group_id, user.id)

    req = await db.scalar(
        select(GroupJoinRequest).where(
            GroupJoinRequest.id == request_id,
            GroupJoinRequest.group_id == group_id,
            GroupJoinRequest.status == JoinRequestStatus.PENDING,
        )
    )
    if req is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "pending request not found")

    req.status = (
        JoinRequestStatus.APPROVED if body.approve else JoinRequestStatus.REJECTED
    )
    req.decided_by_id = user.id
    req.decided_at = datetime.now(timezone.utc)

    if body.approve:
        db.add(GroupMember(
            group_id=group_id, user_id=req.user_id,
            role=GroupRole.MEMBER, joined_at=datetime.now(timezone.utc),
        ))
        db.add(AuditLog(
            actor_id=user.id,
            actor_role=user.role,
            action=AuditAction.GROUP_MEMBER_ADDED,
            resource_type="group",
            resource_id=str(group_id),
            metadata_={"new_member": str(req.user_id)},
            success=True,
        ))
    await db.commit()
    await db.refresh(req)
    return JoinRequestOut.model_validate(req)
