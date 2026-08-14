from __future__ import annotations

import uuid
from datetime import datetime
from enum import Enum
from typing import TYPE_CHECKING

from sqlalchemy import Boolean, DateTime, ForeignKey, Index, Integer, String, Text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .base import Base

if TYPE_CHECKING:
    from .user import User
    from .message import Message


class GroupRole(str, Enum):
    # Fable5-Enhancement: OBSERVER is a read-only rank — sees everything, can
    # write nothing. Used for oversight officers auditing a unit's channel
    # without polluting it. Enforced server-side in the WS handler, not just UI.
    OBSERVER = "observer"
    MEMBER = "member"
    MODERATOR = "moderator"
    ADMIN = "admin"
    OWNER = "owner"


# Ranks ordered for permission comparisons (can_post, can_manage checks)
GROUP_ROLE_RANK: dict[str, int] = {
    GroupRole.OBSERVER: 0,
    GroupRole.MEMBER: 1,
    GroupRole.MODERATOR: 2,
    GroupRole.ADMIN: 3,
    GroupRole.OWNER: 4,
}


class JoinRequestStatus(str, Enum):
    PENDING = "pending"
    APPROVED = "approved"
    REJECTED = "rejected"
    # Admin asked the requester to amend their answers; the request stays alive
    # and returns to PENDING on resubmission.
    MORE_INFO_NEEDED = "more_info_needed"
    # Passed request_expiry_days with no admin decision. Kept rather than
    # deleted so an admin can still see what they missed.
    EXPIRED = "expired"


class GroupJoinMode(str, Enum):
    """How a group admits people.

    Supersedes the older `join_approval_required` boolean, which could not
    express "invite only". That column is retained and kept in sync so
    existing clients and queries keep working — see Group.join_mode.
    """

    OPEN = "open"
    INVITE_ONLY = "invite_only"
    REQUEST_APPROVAL = "request_approval"


class GroupType(str, Enum):
    UNIT = "unit"           # Military unit (auto-populated from org chart)
    CHANNEL = "channel"     # Broadcast channel; only admins post
    DIRECT = "direct"       # 1-to-1 DM implemented as a 2-member group
    TASK_FORCE = "task_force"  # Temporary operational group


class Group(Base):
    """Chat group / channel.

    Fable5-Enhancement: A separate Group model (not just a flag on Message) gives us:
      - Per-group permission matrices (who can post, who can add members)
      - GroupMember table with per-member roles and mute states
      - Efficient fan-out: fetch group members once → publish to N Redis channels
    This is superior to the original design of a single conversation table because
    group admin operations (kick, mute, promote) don't require scanning the messages table.
    """

    __tablename__ = "groups"

    name: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str | None] = mapped_column(Text, nullable=True)
    avatar_object_key: Mapped[str | None] = mapped_column(String(500), nullable=True)
    group_type: Mapped[str] = mapped_column(
        String(20), nullable=False, default=GroupType.TASK_FORCE, index=True
    )

    # Max members enforced in application layer, not DB (flexible per group type)
    max_members: Mapped[int] = mapped_column(
        Integer, nullable=False, default=200, server_default="200"
    )

    # ── Settings ───────────────────────────────────────────────────────────────
    is_archived: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )
    only_admins_can_post: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )
    is_announcement_group: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false",
        comment="Announcement channel: only ADMIN+ can post; members read-only",
    )
    join_approval_required: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default="true",
        comment=(
            "Legacy flag, superseded by join_mode. Kept in sync on write so "
            "existing clients and queries continue to work; read join_mode."
        ),
    )
    join_mode: Mapped[str] = mapped_column(
        String(20),
        nullable=False,
        default=GroupJoinMode.REQUEST_APPROVAL,
        server_default=GroupJoinMode.REQUEST_APPROVAL.value,
        index=True,
        comment="open | invite_only | request_approval",
    )
    verification_form_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("verification_forms.id", ondelete="SET NULL"),
        nullable=True,
        comment="Active form for this group; NULL means no questions are asked",
    )
    request_expiry_days: Mapped[int] = mapped_column(
        Integer, nullable=False, default=14, server_default="14"
    )
    allow_rejoin: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=False,
        server_default="false",
        comment="Whether a rejected user may submit a fresh request",
    )
    only_admins_can_add_members: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default="true"
    )
    disappearing_messages_seconds: Mapped[int | None] = mapped_column(
        Integer,
        nullable=True,
        comment="Group-level default for self-destruct timer; NULL = disabled",
    )

    # ── Relationships ──────────────────────────────────────────────────────────
    members: Mapped[list[GroupMember]] = relationship(
        "GroupMember", back_populates="group", cascade="all, delete-orphan"
    )
    messages: Mapped[list[Message]] = relationship(
        "Message", back_populates="group"
    )

    __table_args__ = (
        Index("ix_groups_type_archived", "group_type", "is_archived"),
    )


class GroupMember(Base):
    """Junction table: user ↔ group with per-membership metadata."""

    __tablename__ = "group_members"

    group_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("groups.id", ondelete="CASCADE"),
        nullable=False,
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    role: Mapped[str] = mapped_column(
        String(20), nullable=False, default=GroupRole.MEMBER
    )
    added_by_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
    )
    joined_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
    is_muted: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )
    muted_until: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    last_read_message_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), nullable=True,
        comment="Used for unread-count computation without a full messages scan",
    )

    # ── Relationships ──────────────────────────────────────────────────────────
    group: Mapped[Group] = relationship("Group", back_populates="members")
    user: Mapped[User] = relationship("User", foreign_keys=[user_id], back_populates="group_memberships")

    __table_args__ = (
        Index("ix_group_members_unique", "group_id", "user_id", unique=True),
        Index("ix_group_members_user", "user_id"),
    )

    def can_post(self, group: Group) -> bool:
        rank = GROUP_ROLE_RANK.get(self.role, 0)
        if self.role == GroupRole.OBSERVER:
            return False
        if group.is_announcement_group or group.only_admins_can_post:
            return rank >= GROUP_ROLE_RANK[GroupRole.ADMIN]
        return True

    def can_manage_members(self) -> bool:
        return GROUP_ROLE_RANK.get(self.role, 0) >= GROUP_ROLE_RANK[GroupRole.ADMIN]


class GroupJoinRequest(Base):
    """Pending membership request for groups with join_approval_required."""

    __tablename__ = "group_join_requests"

    group_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("groups.id", ondelete="CASCADE"),
        nullable=False,
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    status: Mapped[str] = mapped_column(
        String(20), nullable=False, default=JoinRequestStatus.PENDING,
        server_default=JoinRequestStatus.PENDING.value, index=True,
    )
    message: Mapped[str | None] = mapped_column(
        String(300), nullable=True, comment="Optional free-text note to the admin"
    )

    # ── Verification form answers ──────────────────────────────────────────────
    form_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("verification_forms.id", ondelete="SET NULL"),
        nullable=True,
        comment=(
            "The form this request answered, snapshotted at submission. Editing "
            "a group's active form must not change what a pending request was "
            "asked, so the request keeps its own reference."
        ),
    )
    answers: Mapped[dict | None] = mapped_column(
        JSONB,
        nullable=True,
        comment='{"<field_id>": value} — validated against form_id at submit time',
    )

    # ── Admin decision trail ───────────────────────────────────────────────────
    admin_notes: Mapped[str | None] = mapped_column(
        Text, nullable=True, comment="Shown to the requester when more info is needed"
    )
    rejection_reason: Mapped[str | None] = mapped_column(Text, nullable=True)

    decided_by_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    decided_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    expires_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True, index=True
    )

    __table_args__ = (
        Index("ix_join_req_group_status", "group_id", "status"),
        Index("ix_join_req_unique_pending", "group_id", "user_id", unique=True),
        Index("ix_join_req_expires", "expires_at"),
    )

    def is_actionable(self) -> bool:
        """Whether an admin decision may still be applied.

        Guards the spec's rule that an expired request cannot be approved after
        the fact — the window closing is the whole point of having one.
        """
        return self.status in (
            JoinRequestStatus.PENDING,
            JoinRequestStatus.MORE_INFO_NEEDED,
        )
