from __future__ import annotations

import uuid
from datetime import datetime
from enum import Enum
from typing import TYPE_CHECKING

from sqlalchemy import (
    BigInteger,
    Boolean,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    Text,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .base import Base

if TYPE_CHECKING:
    from .user import User
    from .group import Group


class MessageType(str, Enum):
    TEXT = "text"
    IMAGE = "image"
    VIDEO = "video"
    AUDIO = "audio"
    FILE = "file"
    LOCATION = "location"
    SYSTEM = "system"


class MessageStatus(str, Enum):
    SENT = "sent"
    DELIVERED = "delivered"
    READ = "read"
    FAILED = "failed"


class Message(Base):
    """Encrypted message record.

    Content is end-to-end encrypted before reaching the server; the server stores
    the ciphertext only (content_ciphertext). The server never has access to
    the plaintext — decryption happens on the client using the recipient's key.

    Fable5-Enhancement: self-destruct is implemented at two layers:
      1. destruct_at column — queried by a scheduled cleanup worker (pg_cron or APScheduler)
      2. Redis keyspace notification (KEX) on the session key — fires a real-time
         DELETE event to all connected clients without polling the DB.
    This dual approach ensures messages vanish even when clients are offline.
    """

    __tablename__ = "messages"

    # ── Parties ────────────────────────────────────────────────────────────────
    sender_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,   # NULL after user deletion; message record kept for audit
        index=True,
    )
    # Exactly ONE of recipient_id / group_id is non-null (enforced by CHECK constraint in migration)
    recipient_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=True,
        index=True,
    )
    group_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("groups.id", ondelete="CASCADE"),
        nullable=True,
        index=True,
    )

    # ── Content ────────────────────────────────────────────────────────────────
    message_type: Mapped[str] = mapped_column(
        String(20), nullable=False, default=MessageType.TEXT
    )
    content_ciphertext: Mapped[str | None] = mapped_column(
        Text,
        nullable=True,
        comment="E2E encrypted blob; NULL for system messages",
    )
    # For media messages: MinIO object key, also encrypted
    media_object_key: Mapped[str | None] = mapped_column(String(500), nullable=True)
    media_mime_type: Mapped[str | None] = mapped_column(String(100), nullable=True)
    media_size_bytes: Mapped[int | None] = mapped_column(BigInteger, nullable=True)

    # ── Reply / thread ─────────────────────────────────────────────────────────
    reply_to_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("messages.id", ondelete="SET NULL"),
        nullable=True,
    )

    # ── Delivery state ─────────────────────────────────────────────────────────
    status: Mapped[str] = mapped_column(
        String(20),
        nullable=False,
        default=MessageStatus.SENT,
        index=True,
    )
    delivered_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    read_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    # ── Self-destruct ──────────────────────────────────────────────────────────
    is_self_destruct: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )
    destruct_after_seconds: Mapped[int | None] = mapped_column(
        Integer,
        nullable=True,
        comment="Seconds after first read; NULL = no timer",
    )
    destruct_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        comment="Absolute UTC timestamp when message must be wiped",
        index=True,   # Cleanup worker queries this column
    )
    is_destructed: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )

    # ── Soft delete ────────────────────────────────────────────────────────────
    deleted_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
        comment="Soft-delete timestamp; message row retained for audit trail",
    )
    deleted_for_everyone: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )

    # ── Edit history ───────────────────────────────────────────────────────────
    is_edited: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=False, server_default="false"
    )
    edit_count: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default="0"
    )

    # ── Relationships ──────────────────────────────────────────────────────────
    sender: Mapped[User | None] = relationship(
        "User", foreign_keys=[sender_id], back_populates="sent_messages"
    )
    group: Mapped[Group | None] = relationship("Group", back_populates="messages")

    # Fable5-Enhancement: composite indexes designed for the two hottest query patterns
    # at 7000 users / 500 concurrent:
    #   1. Fetch conversation between two users (sorted by time)   → ix_msg_dm_conv
    #   2. Fetch group messages with pagination                    → ix_msg_group_conv
    #   3. Cleanup worker: find expired self-destruct messages     → ix_msg_destruct
    __table_args__ = (
        Index(
            "ix_msg_dm_conv",
            "sender_id", "recipient_id", "created_at",
        ),
        Index(
            "ix_msg_group_conv",
            "group_id", "created_at",
        ),
        Index(
            "ix_msg_destruct",
            "destruct_at",
            postgresql_where="is_destructed = false AND destruct_at IS NOT NULL",
        ),
        Index("ix_msg_status", "status"),
    )
