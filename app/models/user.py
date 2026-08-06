from __future__ import annotations

from datetime import date, datetime
from enum import Enum
from typing import TYPE_CHECKING

from sqlalchemy import Boolean, Date, DateTime, Index, Integer, String, Text, text
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .base import Base

if TYPE_CHECKING:
    from .user_session import UserSession
    from .message import Message
    from .audit_log import AuditLog
    from .group import GroupMember


class UserStatus(str, Enum):
    ACTIVE = "active"
    SUSPENDED = "suspended"
    DEACTIVATED = "deactivated"


class UserRole(str, Enum):
    SOLDIER = "soldier"
    NCO = "nco"            # Non-Commissioned Officer
    OFFICER = "officer"
    ADMIN = "admin"
    SUPERADMIN = "superadmin"


class User(Base):
    """Military user account.

    Sensitive fields (hashed_military_id, device_fingerprint) are stored encrypted
    at the application layer before insert, in addition to pgcrypto column-level
    encryption applied in the init SQL (see scripts/init_db.sql).

    Fable5-Enhancement: token_version is an integer that increments on every forced
    logout / device wipe. The JWT embeds the version at issue time; any token whose
    version < current is rejected without a DB blocklist — O(1) invalidation at scale.
    """

    __tablename__ = "users"

    # ── Identity ───────────────────────────────────────────────────────────────
    phone_number: Mapped[str] = mapped_column(
        String(20), unique=True, nullable=False, index=True
    )
    full_name: Mapped[str] = mapped_column(String(100), nullable=False)
    username: Mapped[str | None] = mapped_column(String(50), unique=True, nullable=True)
    department: Mapped[str | None] = mapped_column(
        String(80), nullable=True, index=True,
        comment="Organizational unit — admin filters and targeted broadcasts",
    )
    fcm_token: Mapped[str | None] = mapped_column(
        String(512), nullable=True,
        comment="Firebase Cloud Messaging device token; refreshed by the app",
    )

    # Military-specific — stored as bcrypt hash (never reversible)
    hashed_military_id: Mapped[str] = mapped_column(
        Text,
        nullable=False,
        comment="bcrypt hash of the military service number — never store plaintext",
    )

    # ── Security ───────────────────────────────────────────────────────────────
    hashed_password: Mapped[str] = mapped_column(Text, nullable=False)
    device_fingerprint: Mapped[str | None] = mapped_column(
        Text,
        nullable=True,
        comment="SHA-256 of (user-agent + OS build + screen resolution); used for anomalous login detection",
    )
    token_version: Mapped[int] = mapped_column(
        Integer, nullable=False, default=1, server_default="1"
    )

    # ── Account state ──────────────────────────────────────────────────────────
    status: Mapped[str] = mapped_column(
        String(20),
        nullable=False,
        default=UserStatus.ACTIVE,
        server_default=UserStatus.ACTIVE.value,
        index=True,
    )
    role: Mapped[str] = mapped_column(
        String(20),
        nullable=False,
        default=UserRole.SOLDIER,
        server_default=UserRole.SOLDIER.value,
    )
    expiry_date: Mapped[date | None] = mapped_column(
        Date,
        nullable=True,
        comment="Account hard-expiry (e.g. contract end date). NULL = no expiry.",
    )
    last_seen_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    is_online: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )
    avatar_object_key: Mapped[str | None] = mapped_column(
        String(500), nullable=True, comment="MinIO object key; resolve to pre-signed URL on read"
    )

    # ── OTP / MFA ─────────────────────────────────────────────────────────────
    # Fable5-Enhancement: OTP state kept in Redis (TTL-based), NOT in the DB row.
    # This removes the need for DB writes on every OTP request and prevents timing
    # attacks from diffing updated_at on the user row.
    mfa_enabled: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default="true"
    )

    # ── Relationships ──────────────────────────────────────────────────────────
    sessions: Mapped[list[UserSession]] = relationship(
        "UserSession", back_populates="user", cascade="all, delete-orphan"
    )
    sent_messages: Mapped[list[Message]] = relationship(
        "Message", foreign_keys="Message.sender_id", back_populates="sender"
    )
    audit_logs: Mapped[list[AuditLog]] = relationship(
        "AuditLog", back_populates="actor", foreign_keys="AuditLog.actor_id"
    )
    group_memberships: Mapped[list[GroupMember]] = relationship(
        "GroupMember", back_populates="user", cascade="all, delete-orphan"
    )

    __table_args__ = (
        Index("ix_users_status_role", "status", "role"),
        Index("ix_users_expiry_date", "expiry_date"),
    )
