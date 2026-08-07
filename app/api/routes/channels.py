from __future__ import annotations

from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import get_db
from app.models import User
from app.models.channel import (
    Channel,
    ChannelAnalytics,
    ChannelPost,
    ChannelSubscription,
)
from app.schemas.channel import (
    ChannelAnalyticsResponse,
    ChannelCreate,
    ChannelPostCreate,
    ChannelPostResponse,
    ChannelResponse,
    ChannelSubscriptionCreate,
    ChannelSubscriptionResponse,
    ChannelUpdate,
)

router = APIRouter(prefix="/channels", tags=["channels"])


async def _get_channel_or_404(db: AsyncSession, channel_id: UUID) -> Channel:
    channel = await db.scalar(select(Channel).where(Channel.id == channel_id))
    if channel is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Channel not found")
    return channel


def _require_owner(channel: Channel, user: User) -> None:
    if channel.owner_id != user.id:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Not enough permissions")


# ── Channel CRUD ───────────────────────────────────────────────────────────────

@router.post("", response_model=ChannelResponse, status_code=status.HTTP_201_CREATED)
async def create_channel(
    body: ChannelCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> Channel:
    channel = Channel(
        name=body.name,
        description=body.description,
        channel_type=body.channel_type,
        category=body.category,
        owner_id=user.id,
    )
    db.add(channel)
    await db.flush()
    await db.refresh(channel)
    return channel


@router.get("", response_model=list[ChannelResponse])
async def read_channels(
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> list[Channel]:
    result = await db.scalars(
        select(Channel).order_by(Channel.created_at.desc()).offset(skip).limit(limit)
    )
    return list(result)


@router.get("/{channel_id}", response_model=ChannelResponse)
async def read_channel(
    channel_id: UUID,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> Channel:
    return await _get_channel_or_404(db, channel_id)


@router.patch("/{channel_id}", response_model=ChannelResponse)
async def update_channel(
    channel_id: UUID,
    body: ChannelUpdate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> Channel:
    channel = await _get_channel_or_404(db, channel_id)
    _require_owner(channel, user)

    # is_verified is deliberately absent from ChannelUpdate — a channel owner
    # must not be able to mark their own channel verified.
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(channel, field, value)
    await db.flush()
    await db.refresh(channel)
    return channel


@router.delete("/{channel_id}", status_code=status.HTTP_204_NO_CONTENT, response_model=None)
async def delete_channel(
    channel_id: UUID,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> None:
    channel = await _get_channel_or_404(db, channel_id)
    _require_owner(channel, user)
    await db.delete(channel)


# ── Posts ──────────────────────────────────────────────────────────────────────

@router.post(
    "/{channel_id}/posts",
    response_model=ChannelPostResponse,
    status_code=status.HTTP_201_CREATED,
)
async def create_channel_post(
    channel_id: UUID,
    body: ChannelPostCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> ChannelPost:
    channel = await _get_channel_or_404(db, channel_id)
    # A channel is a broadcast surface: only the owner publishes.
    _require_owner(channel, user)

    post = ChannelPost(
        channel_id=channel_id,
        author_id=user.id,
        content=body.content,
        media_key=body.media_key,
        mime_type=body.mime_type,
        scheduled_at=body.scheduled_at,
        is_scheduled=bool(body.scheduled_at) and body.is_scheduled,
    )
    db.add(post)
    await db.flush()
    await db.refresh(post)
    return post


@router.get("/{channel_id}/posts", response_model=list[ChannelPostResponse])
async def read_channel_posts(
    channel_id: UUID,
    skip: int = Query(0, ge=0),
    limit: int = Query(100, ge=1, le=200),
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> list[ChannelPost]:
    await _get_channel_or_404(db, channel_id)
    result = await db.scalars(
        select(ChannelPost)
        .where(ChannelPost.channel_id == channel_id)
        .order_by(ChannelPost.created_at.desc())
        .offset(skip)
        .limit(limit)
    )
    return list(result)


# ── Subscriptions ──────────────────────────────────────────────────────────────

@router.post(
    "/{channel_id}/subscribe",
    response_model=ChannelSubscriptionResponse,
    status_code=status.HTTP_201_CREATED,
)
async def subscribe_to_channel(
    channel_id: UUID,
    body: ChannelSubscriptionCreate,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> ChannelSubscription:
    channel = await _get_channel_or_404(db, channel_id)

    existing = await db.scalar(
        select(ChannelSubscription).where(
            ChannelSubscription.channel_id == channel_id,
            ChannelSubscription.user_id == user.id,
        )
    )
    if existing is not None:
        raise HTTPException(
            status.HTTP_409_CONFLICT, "Already subscribed to this channel"
        )

    subscription = ChannelSubscription(
        channel_id=channel_id,
        user_id=user.id,
        subscription_plan_id=body.subscription_plan_id,
    )
    db.add(subscription)
    channel.subscriber_count += 1
    await db.flush()
    await db.refresh(subscription)
    return subscription


@router.delete("/{channel_id}/subscribe", status_code=status.HTTP_204_NO_CONTENT, response_model=None)
async def unsubscribe_from_channel(
    channel_id: UUID,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> None:
    channel = await _get_channel_or_404(db, channel_id)
    subscription = await db.scalar(
        select(ChannelSubscription).where(
            ChannelSubscription.channel_id == channel_id,
            ChannelSubscription.user_id == user.id,
        )
    )
    if subscription is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "Not subscribed to this channel")

    await db.delete(subscription)
    # Clamp at zero so a double-decrement can never produce a negative count.
    channel.subscriber_count = max(0, channel.subscriber_count - 1)


# ── Analytics ──────────────────────────────────────────────────────────────────

@router.get("/{channel_id}/analytics", response_model=ChannelAnalyticsResponse)
async def read_channel_analytics(
    channel_id: UUID,
    db: AsyncSession = Depends(get_db),
    user: User = Depends(get_current_user),
) -> ChannelAnalytics:
    channel = await _get_channel_or_404(db, channel_id)
    _require_owner(channel, user)

    analytics = await db.scalar(
        select(ChannelAnalytics)
        .where(ChannelAnalytics.channel_id == channel_id)
        .order_by(ChannelAnalytics.created_at.desc())
        .limit(1)
    )
    if analytics is None:
        analytics = ChannelAnalytics(channel_id=channel_id)
        db.add(analytics)
        await db.flush()
        await db.refresh(analytics)
    return analytics
