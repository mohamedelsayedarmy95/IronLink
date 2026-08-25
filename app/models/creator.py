from __future__ import annotations

import uuid
from datetime import datetime
from enum import Enum
from typing import TYPE_CHECKING

from sqlalchemy import Boolean, DateTime, Float, ForeignKey, Integer, String, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .base import Base

if TYPE_CHECKING:
    from .channel import ChannelSubscription
    from .user import User


class PayoutStatus(str, Enum):
    PENDING = "pending"
    PROCESSING = "processing"
    COMPLETED = "completed"
    FAILED = "failed"


class SubscriptionPlan(Base):
    __tablename__ = "subscription_plans"

    name: Mapped[str] = mapped_column(String(100), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    # Money is stored as Float here to match the original schema. Anything that
    # actually settles funds should move to Numeric(12, 2) before launch —
    # binary floats cannot represent cents exactly.
    price: Mapped[float] = mapped_column(Float, nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False, default="USD")
    interval: Mapped[str] = mapped_column(String(20), nullable=False, default="month")
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)

    subscriptions: Mapped[list[ChannelSubscription]] = relationship(
        back_populates="subscription_plan"
    )


class CreatorDashboard(Base):
    __tablename__ = "creator_dashboards"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        unique=True,
        index=True,
    )
    total_earnings: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    total_subscribers: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    total_views: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
    total_posts: Mapped[int] = mapped_column(Integer, nullable=False, default=0)

    user: Mapped[User] = relationship()
    payouts: Mapped[list[Payout]] = relationship(
        back_populates="creator_dashboard", cascade="all, delete-orphan"
    )


class Payout(Base):
    __tablename__ = "payouts"

    creator_dashboard_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("creator_dashboards.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    creator_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    amount: Mapped[float] = mapped_column(Float, nullable=False)
    currency: Mapped[str] = mapped_column(String(3), nullable=False, default="USD")
    status: Mapped[str] = mapped_column(
        String(20), nullable=False, default=PayoutStatus.PENDING, index=True
    )
    processed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    creator_dashboard: Mapped[CreatorDashboard] = relationship(
        back_populates="payouts"
    )
    creator: Mapped[User] = relationship(foreign_keys=[creator_id])
