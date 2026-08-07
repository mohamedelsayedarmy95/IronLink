from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import get_db
from app.models import User
from app.models.community import (
    Community,
    CommunityEvent,
    CommunityEventRSVP,
    CommunityMember,
    CommunityPermission,
    CommunityResource,
    CommunityRole,
)
from app.schemas.community import (
    CommunityCreate,
    CommunityEventCreate,
    CommunityEventRSVPCreate,
    CommunityEventRSVPResponse,
    CommunityEventResponse,
    CommunityMemberCreate,
    CommunityMemberResponse,
    CommunityResourceCreate,
    CommunityResourceResponse,
    CommunityResponse,
    CommunityUpdate,
)

router = APIRouter(prefix="/communities", tags=["communities"])

_MANAGER_ROLES = (CommunityRole.OWNER, CommunityRole.ADMIN)

# Default permission matrix applied when a community is created.
_DEFAULT_PERMISSIONS: dict[str, dict[str, bool]] = {
    CommunityRole.OWNER: {
        "can_post": True,
        "can_comment": True,
        "can_delete_own_posts": True,
        "can_delete_any_posts": True,
        "can_mute_members": True,
        "can_ban_members": True,
        "can_invite_members": True,
        "can_change_settings": True,
    },
    CommunityRole.ADMIN: {
        "can_post": True,
        "can_comment": True,
        "can_delete_own_posts": True,
        "can_delete_any_posts": True,
        "can_mute_members": True,
        "can_ban_members": True,
        "can_invite_members": True,
        "can_change_settings": True,
    },
    CommunityRole.MODERATOR: {
        "can_post": True,
        "can_comment": True,
        "can_delete_own_posts": True,
        "can_delete_any_posts": False,
        "can_mute_members": True,
        "can_ban_members": False,
        "can_invite_members": True,
        "can_change_settings": False,
    },
    CommunityRole.MEMBER: {
        "can_post": True,
        "can_comment": True,
        "can_delete_own_posts": True,
        "can_delete_any_posts": False,
        "can_mute_members": False,
        "can_ban_members": False,
        "can_invite_members": False,
        "can_change_settings": False,
    },
}


async def _get_community_or_404(db: AsyncSession, community_id: UUID) -> Community:
    community = await db.scalar(select(Community).where(Community.id == community_id))
    if community is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Community not found")
    return community


async def _get_membership(
    db: AsyncSession, community_id: UUID, user_id: UUID
) -> CommunityMember | None:
    return await db.scalar(
        select(CommunityMember).where(
            CommunityMember.community_id == community_id,
            CommunityMember.user_id == user_id,
        )
    )


async def _require_member(
    db: AsyncSession, community_id: UUID, user: User
) -> CommunityMember:
    member = await _get_membership(db, community_id, user.id)
    if member is None:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN, "You must be a member of this community"
        )
    return member


async def _require_manager(
    db: AsyncSession, community_id: UUID, user: User
) -> CommunityMember:
    member = await _require_member(db, community_id, user)
    if member.role not in _MANAGER_ROLES:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Not enough permissions")
    return member


# ── Community CRUD ─────────────────────────────────────────────────────────────

@router.post("", response_model=CommunityResponse, status_code=status.HTTP_201_CREATED)
async def create_community(
    body: CommunityCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> Community:
    community = Community(
        name=body.name,
        description=body.description,
        category=body.category,
        owner_id=user.id,
        member_count=1,
    )
    db.add(community)
    await db.flush()

    db.add(
        CommunityMember(
            community_id=community.id,
            user_id=user.id,
            role=CommunityRole.OWNER,
        )
    )
    for role, perms in _DEFAULT_PERMISSIONS.items():
        db.add(CommunityPermission(community_id=community.id, role=role, **perms))

    await db.flush()
    await db.refresh(community)
    return community


@router.get("", response_model=list[CommunityResponse])
async def read_communities(
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> list[Community]:
    result = await db.scalars(
        select(Community)
        .order_by(Community.created_at.desc())
        .offset(skip)
        .limit(limit)
    )
    return list(result)


@router.get("/{community_id}", response_model=CommunityResponse)
async def read_community(
    community_id: UUID,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> Community:
    return await _get_community_or_404(db, community_id)


@router.patch("/{community_id}", response_model=CommunityResponse)
async def update_community(
    community_id: UUID,
    body: CommunityUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> Community:
    community = await _get_community_or_404(db, community_id)
    if community.owner_id != user.id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Not enough permissions")

    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(community, field, value)
    await db.flush()
    await db.refresh(community)
    return community


@router.delete("/{community_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_community(
    community_id: UUID,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> None:
    community = await _get_community_or_404(db, community_id)
    if community.owner_id != user.id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Not enough permissions")
    await db.delete(community)


# ── Members ────────────────────────────────────────────────────────────────────

@router.post(
    "/{community_id}/members",
    response_model=CommunityMemberResponse,
    status_code=status.HTTP_201_CREATED,
)
async def add_community_member(
    community_id: UUID,
    body: CommunityMemberCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> CommunityMember:
    community = await _get_community_or_404(db, community_id)
    await _require_manager(db, community_id, user)

    # Only an owner may mint another owner.
    if body.role == CommunityRole.OWNER and community.owner_id != user.id:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN, "Only the owner can grant owner role"
        )

    target = await db.scalar(select(User).where(User.id == body.user_id))
    if target is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "User not found")

    if await _get_membership(db, community_id, body.user_id) is not None:
        raise HTTPException(status.HTTP_409_CONFLICT, "User is already a member")

    member = CommunityMember(
        community_id=community_id,
        user_id=body.user_id,
        role=body.role,
    )
    db.add(member)
    community.member_count += 1
    await db.flush()
    await db.refresh(member)
    return member


@router.get("/{community_id}/members", response_model=list[CommunityMemberResponse])
async def read_community_members(
    community_id: UUID,
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> list[CommunityMember]:
    await _get_community_or_404(db, community_id)
    await _require_member(db, community_id, user)
    result = await db.scalars(
        select(CommunityMember)
        .where(CommunityMember.community_id == community_id)
        .offset(skip)
        .limit(limit)
    )
    return list(result)


# ── Events ─────────────────────────────────────────────────────────────────────

@router.post(
    "/{community_id}/events",
    response_model=CommunityEventResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_community_event(
    community_id: UUID,
    body: CommunityEventCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> CommunityEvent:
    await _get_community_or_404(db, community_id)
    await _require_manager(db, community_id, user)

    if body.end_time is not None and body.end_time <= body.start_time:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY, "end_time must be after start_time"
        )

    event = CommunityEvent(
        community_id=community_id,
        title=body.title,
        description=body.description,
        start_time=body.start_time,
        end_time=body.end_time,
        location=body.location,
        created_by=user.id,
    )
    db.add(event)
    await db.flush()
    await db.refresh(event)
    return event


@router.get("/{community_id}/events", response_model=list[CommunityEventResponse])
async def read_community_events(
    community_id: UUID,
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> list[CommunityEvent]:
    await _get_community_or_404(db, community_id)
    await _require_member(db, community_id, user)
    result = await db.scalars(
        select(CommunityEvent)
        .where(CommunityEvent.community_id == community_id)
        .order_by(CommunityEvent.start_time)
        .offset(skip)
        .limit(limit)
    )
    return list(result)


@router.post(
    "/{community_id}/events/{event_id}/rsvp",
    response_model=CommunityEventRSVPResponse,
    status_code=status.HTTP_201_CREATED,
)
async def rsvp_to_community_event(
    community_id: UUID,
    event_id: UUID,
    body: CommunityEventRSVPCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> CommunityEventRSVP:
    await _get_community_or_404(db, community_id)
    await _require_member(db, community_id, user)

    event = await db.scalar(
        select(CommunityEvent).where(
            CommunityEvent.id == event_id,
            CommunityEvent.community_id == community_id,
        )
    )
    if event is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Event not found")

    # Re-RSVP updates the existing response rather than 409-ing, which is what
    # users expect when they change their mind.
    rsvp = await db.scalar(
        select(CommunityEventRSVP).where(
            CommunityEventRSVP.event_id == event_id,
            CommunityEventRSVP.user_id == user.id,
        )
    )
    if rsvp is None:
        rsvp = CommunityEventRSVP(
            event_id=event_id, user_id=user.id, response=body.response
        )
        db.add(rsvp)
    else:
        rsvp.response = body.response

    await db.flush()
    await db.refresh(rsvp)
    return rsvp


# ── Resources ──────────────────────────────────────────────────────────────────

@router.post(
    "/{community_id}/resources",
    response_model=CommunityResourceResponse,
    status_code=status.HTTP_201_CREATED,
)
async def add_community_resource(
    community_id: UUID,
    body: CommunityResourceCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> CommunityResource:
    await _get_community_or_404(db, community_id)
    await _require_manager(db, community_id, user)

    resource = CommunityResource(
        community_id=community_id,
        title=body.title,
        url=body.url,
        resource_type=body.resource_type,
        created_by=user.id,
    )
    db.add(resource)
    await db.flush()
    await db.refresh(resource)
    return resource


@router.get(
    "/{community_id}/resources", response_model=list[CommunityResourceResponse]
)
async def read_community_resources(
    community_id: UUID,
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> list[CommunityResource]:
    await _get_community_or_404(db, community_id)
    await _require_member(db, community_id, user)
    result = await db.scalars(
        select(CommunityResource)
        .where(CommunityResource.community_id == community_id)
        .offset(skip)
        .limit(limit)
    )
    return list(result)
