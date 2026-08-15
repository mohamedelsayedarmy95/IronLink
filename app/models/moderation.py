from __future__ import annotations

import uuid
from datetime import datetime
from enum import Enum
from typing import TYPE_CHECKING

from sqlalchemy import (
    DateTime,
    ForeignKey,
    Index,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .base import Base

if TYPE_CHECKING:
    from .user import User


class UserBlock(Base):
    """One user has blocked another.

    Directional on purpose: A blocking B says nothing about whether B has
    blocked A, and collapsing the two would let one person's action silently
    change the other's settings.

    Enforcement is server-side. A block that only hides messages in the UI
    is not a block — the sender would still reach the recipient's device, and
    anyone running a modified client would bypass it entirely.
    """

    __tablename__ = "user_blocks"

    blocker_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    blocked_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )

    #: Kept private to the blocker. Never surfaced to the blocked user, who is
    #: not told they were blocked at all — being informed turns a quiet exit
    #: into a confrontation, which is the outcome blocking exists to avoid.
    reason: Mapped[str | None] = mapped_column(Text, nullable=True)

    blocker: Mapped[User] = relationship("User", foreign_keys=[blocker_id])
    blocked: Mapped[User] = relationship("User", foreign_keys=[blocked_id])

    __table_args__ = (
        UniqueConstraint("blocker_id", "blocked_id", name="uq_user_block"),
        # The send-path check queries "has X blocked Y", so the index leads
        # with blocked_id to answer it directly.
        Index("ix_user_blocks_pair", "blocked_id", "blocker_id"),
        Index("ix_user_blocks_blocker", "blocker_id"),
    )


class ReportReason(str, Enum):
    SPAM = "spam"
    HARASSMENT = "harassment"
    IMPERSONATION = "impersonation"
    SCAM = "scam"
    ILLEGAL_CONTENT = "illegal_content"
    #: Specific to this deployment: classified material posted where it does
    #: not belong is an incident, not ordinary abuse, and has to be separable
    #: in the queue rather than buried under "other".
    LEAKED_CLASSIFIED = "leaked_classified"
    OTHER = "other"


class ReportStatus(str, Enum):
    OPEN = "open"
    REVIEWING = "reviewing"
    ACTIONED = "actioned"
    DISMISSED = "dismissed"


class ContentReport(Base):
    """A report of a user or a specific message.

    The reported text is snapshotted here at submission time. Without that,
    a reporter's evidence disappears the moment the sender deletes the
    message — which is precisely what someone sending abuse would do.

    That snapshot is the one place the server holds message plaintext, and
    only because the reporter chose to hand it over. It is scoped to the
    reported message, written only on an explicit report, and never derived
    from traffic the server observes.
    """

    __tablename__ = "content_reports"

    reporter_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    reported_user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    #: Null when reporting a user rather than one message.
    message_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("messages.id", ondelete="SET NULL"),
        nullable=True,
    )

    reason: Mapped[str] = mapped_column(String(32), nullable=False)
    details: Mapped[str | None] = mapped_column(Text, nullable=True)

    content_snapshot: Mapped[str | None] = mapped_column(
        Text,
        nullable=True,
        comment=(
            "Plaintext supplied by the reporter so evidence survives the "
            "sender deleting the message"
        ),
    )

    status: Mapped[str] = mapped_column(
        String(20),
        nullable=False,
        default=ReportStatus.OPEN,
        server_default=ReportStatus.OPEN.value,
        index=True,
    )
    reviewed_by_id: Mapped[uuid.UUID | None] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="SET NULL"),
        nullable=True,
    )
    reviewed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    moderator_notes: Mapped[str | None] = mapped_column(Text, nullable=True)

    __table_args__ = (
        Index("ix_reports_status_created", "status", "created_at"),
        Index("ix_reports_reported_user", "reported_user_id"),
        # One report per reporter per message: re-reporting the same thing
        # inflates the queue without adding information. Reporting the same
        # *user* repeatedly is still allowed, since each incident differs.
        Index(
            "ix_reports_unique_message",
            "reporter_id",
            "message_id",
            unique=True,
            postgresql_where=Text("message_id IS NOT NULL"),
        ),
    )
