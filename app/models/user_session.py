from __future__ import annotations

import uuid
from datetime import datetime
from typing import TYPE_CHECKING

from sqlalchemy import DateTime, ForeignKey, Index, Numeric, String, Text, text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .base import Base

if TYPE_CHECKING:
    from .user import User


class UserSession(Base):
    """Records every authenticated session.

    Stored for security auditing and anomalous-access detection.
    Approximate coordinates (city-level, not GPS) are stored — sufficient for
    geo-anomaly detection without pinpointing user location.

    Fable5-Enhancement: ws_connection_id links the DB session to the in-memory
    Redis WebSocket registry so an admin can force-disconnect a specific device
    without knowing the socket internals. Revocation flow:
      1. Admin sets session.revoked_at
      2. Worker reads Redis SESSIONS db → publishes DISCONNECT to that connection ID
      3. Client receives close frame; re-auth required.
    """

    __tablename__ = "user_sessions"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    refresh_token_hash: Mapped[str] = mapped_column(
        Text,
        nullable=False,
        unique=True,
        comment="SHA-256 of the refresh token — never store plaintext",
    )

    #: The hash this one replaced, kept solely to notice a replay.
    #:
    #: Rotation alone makes a stolen refresh token usable at most once, but it
    #: cannot tell theft from an ordinary retry: once the hash is overwritten,
    #: the old token simply matches nothing. Keeping the previous hash turns
    #: that silence into a signal — a token that was already exchanged is
    #: being presented again, by someone.
    previous_refresh_token_hash: Mapped[str | None] = mapped_column(
        Text, nullable=True, index=True
    )

    # ── Device & network context ───────────────────────────────────────────────
    ip_address: Mapped[str] = mapped_column(String(45), nullable=False)  # IPv6-safe
    user_agent: Mapped[str | None] = mapped_column(String(512), nullable=True)
    device_type: Mapped[str | None] = mapped_column(
        String(50),
        nullable=True,
        comment="mobile | tablet | desktop | unknown",
    )
    device_name: Mapped[str | None] = mapped_column(String(200), nullable=True)
    os_version: Mapped[str | None] = mapped_column(String(100), nullable=True)
    app_version: Mapped[str | None] = mapped_column(String(20), nullable=True)

    # City-level geo; resolved from IP at login time via GeoIP2 (no GPS stored)
    geo_country: Mapped[str | None] = mapped_column(String(2), nullable=True)   # ISO 3166-1
    geo_city: Mapped[str | None] = mapped_column(String(100), nullable=True)
    geo_lat: Mapped[float | None] = mapped_column(Numeric(7, 4), nullable=True)
    geo_lon: Mapped[float | None] = mapped_column(Numeric(7, 4), nullable=True)

    # ── Lifecycle ─────────────────────────────────────────────────────────────
    last_active_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    expires_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
    revoked_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        comment="Set by admin force-logout or user sign-out; NULL = active",
    )

    # ── WebSocket linkage ──────────────────────────────────────────────────────
    ws_connection_id: Mapped[str | None] = mapped_column(
        String(64),
        nullable=True,
        comment="Redis WS session key for remote disconnect",
    )

    # ── Relationships ──────────────────────────────────────────────────────────
    user: Mapped[User] = relationship("User", back_populates="sessions")

    __table_args__ = (
        Index("ix_sessions_user_revoked", "user_id", "revoked_at"),
        Index("ix_sessions_expires", "expires_at"),
        Index("ix_sessions_ip", "ip_address"),
    )
