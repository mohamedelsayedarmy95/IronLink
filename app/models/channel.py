from __future__ import annotations

import uuid
from datetime import datetime
from enum import Enum
from typing import TYPE_CHECKING

from sqlalchemy import Boolean, DateTime, Float, ForeignKey, Index, Integer, String, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .base import Base

if TYPE_CHECKING:
    from .creator import SubscriptionPlan
    from .user import User


class ChannelType(str, Enum):
    PUBLIC = "public"
    PRIVATE = "private"


class Channel(Base):
    """Broadcast channel — one owner publishes, many subscribers read."""

    __tablename__ = "channels"

    name: Mapped[str] = mapped_column(String(100), nullable=False, index=True)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    channel_type: Mapped[str] = mapped_column(
        String(20), nullable=False, default=ChannelType.PUBLIC, index=True
    )
    owner_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    is_verified: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    category: Mapped[str | None] = mapped_column(String(50), nullable=True, index=True)
    subscriber_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)

    posts: Mapped[list[ChannelPost]] = relationship(
        back_populates="channel", cascade="all, delete-orphan"
    )
    subscriptions: Mapped[list[ChannelSubscription]] = relationship(
        back_populates="channel", cascade="all, delete-orphan"
    )
    analytics: Mapped[list[ChannelAnalytics]] = relationship(
        back_populates="channel", cascade="all, delete-orphan"
    )


class ChannelPost(Base):
    __tablename__ = "channel_posts"

    channel_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("channels.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    author_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    content: Mapped[str] = mapped_column(Text, nullable=False)
    media_key: Mapped[str | None] = mapped_column(String(255), nullable=True)
    mime_type: Mapped[str | None] = mapped_column(String(100), nullable=True)
    scheduled_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    is_scheduled: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    view_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)

    channel: Mapped[Channel] = relationship(back_populates="posts")
    author: Mapped[User] = relationship()

    # Channel timelines are always read newest-first for one channel.
    __table_args__ = (
        Index("ix_channel_posts_channel_created", "channel_id", "created_at"),
    )


class ChannelSubscription(Base):
    __tablename__ = "channel_subscriptions"

    channel_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("channels.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    subscription_plan_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("subscription_plans.id", ondelete="SET NULL"),
        nullable=True,
    )

    channel: Mapped[Channel] = relationship(back_populates="subscriptions")
    user: Mapped[User] = relationship()
    subscription_plan: Mapped[SubscriptionPlan | None] = relationship(
        back_populates="subscriptions"
    )

    # One subscription row per (channel, user) — the route relies on this.
    __table_args__ = (
        Index(
            "uq_channel_subscription_channel_user",
            "channel_id",
            "user_id",
            unique=True,
        ),
    )


class ChannelAnalytics(Base):
    __tablename__ = "channel_analytics"

    channel_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("channels.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    new_subscribers: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    total_views: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    total_posts: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    engagement_rate: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)

    channel: Mapped[Channel] = relationship(back_populates="analytics")
