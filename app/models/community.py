from __future__ import annotations

import uuid
from datetime import datetime
from enum import Enum
from typing import TYPE_CHECKING

from sqlalchemy import Boolean, DateTime, ForeignKey, Index, Integer, String, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .base import Base

if TYPE_CHECKING:
    from .user import User


class CommunityRole(str, Enum):
    OWNER = "owner"
    ADMIN = "admin"
    MODERATOR = "moderator"
    MEMBER = "member"


# Ranks ordered for permission comparisons, mirroring GROUP_ROLE_RANK.
COMMUNITY_ROLE_RANK: dict[str, int] = {
    CommunityRole.MEMBER: 0,
    CommunityRole.MODERATOR: 1,
    CommunityRole.ADMIN: 2,
    CommunityRole.OWNER: 3,
}


class Community(Base):
    __tablename__ = "communities"

    name: Mapped[str] = mapped_column(String(100), nullable=False, index=True)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    owner_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    is_verified: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    category: Mapped[str | None] = mapped_column(String(50), nullable=True, index=True)
    member_count: Mapped[int] = mapped_column(Integer, nullable=False, default=0)

    members: Mapped[list[CommunityMember]] = relationship(
        back_populates="community", cascade="all, delete-orphan"
    )
    permissions: Mapped[list[CommunityPermission]] = relationship(
        back_populates="community", cascade="all, delete-orphan"
    )
    events: Mapped[list[CommunityEvent]] = relationship(
        back_populates="community", cascade="all, delete-orphan"
    )
    resources: Mapped[list[CommunityResource]] = relationship(
        back_populates="community", cascade="all, delete-orphan"
    )


class CommunityMember(Base):
    __tablename__ = "community_members"

    community_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("communities.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    role: Mapped[str] = mapped_column(
        String(20), nullable=False, default=CommunityRole.MEMBER
    )

    community: Mapped[Community] = relationship(back_populates="members")
    user: Mapped[User] = relationship()

    # Membership is looked up by (community, user) on every permission check.
    __table_args__ = (
        Index(
            "uq_community_members_community_user",
            "community_id",
            "user_id",
            unique=True,
        ),
    )


class CommunityPermission(Base):
    __tablename__ = "community_permissions"

    community_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("communities.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    role: Mapped[str] = mapped_column(String(20), nullable=False)
    can_post: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    can_comment: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    can_delete_own_posts: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False
    )
    can_delete_any_posts: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False
    )
    can_mute_members: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False
    )
    can_ban_members: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False
    )
    can_invite_members: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False
    )
    can_change_settings: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False
    )

    community: Mapped[Community] = relationship(back_populates="permissions")

    __table_args__ = (
        Index(
            "uq_community_permissions_community_role",
            "community_id",
            "role",
            unique=True,
        ),
    )


class CommunityEvent(Base):
    __tablename__ = "community_events"

    community_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("communities.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    start_time: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, index=True
    )
    end_time: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    location: Mapped[str | None] = mapped_column(String(255), nullable=True)
    created_by: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )

    community: Mapped[Community] = relationship(back_populates="events")
    creator: Mapped[User] = relationship()
    rsvps: Mapped[list[CommunityEventRSVP]] = relationship(
        back_populates="event", cascade="all, delete-orphan"
    )


class CommunityEventRSVP(Base):
    __tablename__ = "community_event_rsvps"

    event_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("community_events.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    response: Mapped[str] = mapped_column(String(20), nullable=False)

    event: Mapped[CommunityEvent] = relationship(back_populates="rsvps")
    user: Mapped[User] = relationship()

    __table_args__ = (
        Index(
            "uq_community_event_rsvps_event_user",
            "event_id",
            "user_id",
            unique=True,
        ),
    )


class CommunityResource(Base):
    __tablename__ = "community_resources"

    community_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("communities.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    resource_type: Mapped[str | None] = mapped_column(String(50), nullable=True)
    created_by: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )

    community: Mapped[Community] = relationship(back_populates="resources")
    creator: Mapped[User] = relationship()
