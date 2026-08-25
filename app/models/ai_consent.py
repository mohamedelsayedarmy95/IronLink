from __future__ import annotations

import uuid
from datetime import datetime
from enum import Enum

from sqlalchemy import DateTime, ForeignKey, Index, String, text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column

from .base import Base


class AiScopeType(str, Enum):
    DIRECT = "direct"
    GROUP = "group"


class AiConsent(Base):
    """One person's agreement that a conversation's text may be sent to the
    AI provider.

    WHY THIS TABLE EXISTS

    Every other part of this product is built so the server cannot read
    messages. The AI features work the only way they can under that
    constraint: the client decrypts and posts the plaintext, and the server
    forwards it to Hugging Face. That is a real disclosure to a third party,
    and it was previously undocumented in the interface and unenforced
    anywhere — a summary request simply worked.

    WHY CONSENT IS PER CONVERSATION AND NOT A PROFILE SETTING

    Because what is disclosed is a conversation, not a preference. Agreeing
    that one chat may be summarised says nothing about another.

    WHY BOTH PARTIES

    A summary of a conversation contains the other person's words. If one
    side could switch this on alone, they would be sending someone else's
    messages to a third party on their behalf — which is exactly the thing
    the encryption exists to prevent, done from inside. So a row here is one
    person's half of the agreement, and the AI routes require every
    participant's half before anything is transmitted.

    The cost is that these features are unavailable until everyone opts in,
    which is the correct trade and deliberately not the convenient one.
    """

    __tablename__ = "ai_consents"
    __table_args__ = (
        # One LIVE consent per person per conversation. Partial, so a
        # withdrawn row does not block a later re-grant: the two periods stay
        # separate rows rather than one being toggled back and forth, which is
        # what makes "exposed between these dates" answerable.
        Index(
            "uq_ai_consent_scope",
            "user_id",
            "scope_type",
            "scope_id",
            unique=True,
            postgresql_where=text("revoked_at IS NULL"),
        ),
        # Enforcement asks "who has agreed for this conversation", so this
        # one leads with the scope.
        Index("ix_ai_consents_scope", "scope_type", "scope_id"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )

    scope_type: Mapped[str] = mapped_column(String(10), nullable=False)

    #: The peer's user id for a direct conversation, or the group's id.
    scope_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), nullable=False)

    granted_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )

    #: Set instead of deleting the row, so "this conversation was exposed
    #: between these dates" stays answerable. Withdrawal cannot un-send what
    #: already went, and the record is what makes that legible.
    revoked_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    @property
    def is_active(self) -> bool:
        return self.revoked_at is None
