from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, Index, String, Text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from .base import Base


class Broadcast(Base):
    """Urgent push broadcast from a super-admin.

    Shown as a persistent banner above all conversations on every target
    device; it stays until the user taps it (acknowledged — see BroadcastAck).
    """

    __tablename__ = "broadcasts"

    title: Mapped[str] = mapped_column(String(120), nullable=False)
    body: Mapped[str] = mapped_column(Text, nullable=False)
    department: Mapped[str | None] = mapped_column(
        String(80), nullable=True, index=True,
        comment="NULL = all users; else only this department",
    )
    priority: Mapped[str] = mapped_column(
        String(20), nullable=False, default="urgent", server_default="urgent"
    )
    created_by_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="SET NULL"), nullable=True
    )
    expires_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True,
        comment="Optional auto-expiry; NULL = manual ack only",
    )


class BroadcastAck(Base):
    """Per-user acknowledgement — the banner disappears only after this row exists."""

    __tablename__ = "broadcast_acks"

    broadcast_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("broadcasts.id", ondelete="CASCADE"), nullable=False
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True), ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )

    __table_args__ = (
        Index("ix_broadcast_ack_unique", "broadcast_id", "user_id", unique=True),
        Index("ix_broadcast_ack_user", "user_id"),
    )
