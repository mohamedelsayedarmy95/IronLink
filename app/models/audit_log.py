from __future__ import annotations

import uuid
from datetime import datetime
from enum import Enum
from typing import Any

from sqlalchemy import DateTime, ForeignKey, Index, String, Text
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .base import Base


class AuditAction(str, Enum):
    # Auth
    LOGIN_SUCCESS = "auth.login.success"
    LOGIN_FAILED = "auth.login.failed"
    LOGOUT = "auth.logout"
    TOKEN_REFRESH = "auth.token.refresh"
    MFA_CHALLENGED = "auth.mfa.challenge"
    MFA_PASSED = "auth.mfa.passed"
    MFA_FAILED = "auth.mfa.failed"
    SESSION_REVOKED = "auth.session.revoked"

    # User management
    USER_CREATED = "user.created"
    USER_UPDATED = "user.updated"
    USER_SUSPENDED = "user.suspended"
    USER_REACTIVATED = "user.reactivated"
    ROLE_CHANGED = "user.role.changed"
    PASSWORD_CHANGED = "user.password.changed"
    DEVICE_FINGERPRINT_CHANGED = "user.device_fingerprint.changed"

    # Messaging
    MESSAGE_DELETED = "message.deleted"
    MESSAGE_DELETED_FOR_EVERYONE = "message.deleted_for_everyone"
    GROUP_CREATED = "group.created"
    GROUP_MEMBER_ADDED = "group.member.added"
    GROUP_MEMBER_REMOVED = "group.member.removed"
    GROUP_MEMBER_ROLE_CHANGED = "group.member.role_changed"

    # Administration
    ADMIN_IMPERSONATE = "admin.impersonate"
    EXPORT_DATA = "admin.data.export"
    CONFIG_CHANGED = "admin.config.changed"

    # Security
    SUSPICIOUS_LOGIN = "security.suspicious_login"
    RATE_LIMIT_HIT = "security.rate_limit"
    FORCE_DISCONNECT = "security.force_disconnect"


class AuditLog(Base):
    """Immutable security audit trail.

    Fable5-Enhancement: This table uses PostgreSQL Row Security + a dedicated
    audit_writer role that has INSERT but no UPDATE/DELETE. The application
    connects as audit_writer for log inserts; no application code path can
    delete or modify rows. Retention is enforced by pg_cron archiving to cold
    storage (S3/MinIO), not by deleting rows.

    JSONB `before_state` / `after_state` let security reviewers reconstruct the
    exact record state at change time without a separate change-history table.
    """

    __tablename__ = "audit_logs"

    # ── Who ────────────────────────────────────────────────────────────────────
    actor_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
        index=True,
        comment="NULL = system-generated event",
    )
    actor_role: Mapped[str | None] = mapped_column(
        String(20),
        nullable=True,
        comment="Snapshot of actor role at action time (role may change later)",
    )
    impersonator_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        nullable=True,
        comment="Set when an admin acts on behalf of another user",
    )

    # ── What ───────────────────────────────────────────────────────────────────
    action: Mapped[str] = mapped_column(
        String(80), nullable=False, index=True
    )
    resource_type: Mapped[str | None] = mapped_column(
        String(50), nullable=True,
        comment="E.g. 'user', 'message', 'group'",
    )
    resource_id: Mapped[str | None] = mapped_column(
        String(36),
        nullable=True,
        comment="UUID string of the affected resource",
    )
    description: Mapped[str | None] = mapped_column(Text, nullable=True)

    # JSONB snapshots — nullable for events with no entity state (e.g. login attempts)
    before_state: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    after_state: Mapped[dict | None] = mapped_column(JSONB, nullable=True)
    metadata_: Mapped[dict | None] = mapped_column(
        "metadata", JSONB, nullable=True,
        comment="Extra context: geo, device, flags — keyed arbitrarily",
    )

    # ── Where / How ────────────────────────────────────────────────────────────
    ip_address: Mapped[str | None] = mapped_column(String(45), nullable=True)
    user_agent: Mapped[str | None] = mapped_column(String(512), nullable=True)
    session_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), nullable=True,
        comment="Links the log entry to the UserSession that was active",
    )

    # ── Outcome ────────────────────────────────────────────────────────────────
    success: Mapped[bool] = mapped_column(nullable=False, default=True)
    error_code: Mapped[str | None] = mapped_column(String(50), nullable=True)

    # ── Relationships ──────────────────────────────────────────────────────────
    actor: Mapped[Any] = relationship(
        "User", foreign_keys=[actor_id], back_populates="audit_logs"
    )

    __table_args__ = (
        Index("ix_audit_actor_action", "actor_id", "action"),
        Index("ix_audit_resource", "resource_type", "resource_id"),
        Index("ix_audit_created", "created_at"),
        Index("ix_audit_ip", "ip_address"),
        # Fable5-Enhancement: partial index on failed actions only — the most common
        # query pattern for security dashboards is "show me all failures in last 24h".
        Index(
            "ix_audit_failures",
            "action", "created_at",
            postgresql_where="success = false",
        ),
    )
