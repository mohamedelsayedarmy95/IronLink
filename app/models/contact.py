from __future__ import annotations

import uuid
from datetime import datetime
from enum import Enum
from typing import TYPE_CHECKING

from sqlalchemy import (
    Boolean,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    String,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .base import Base

if TYPE_CHECKING:
    from .user import User

#: Length of a hex-encoded SHA-256 digest. Every hash column is fixed at this
#: width so a raw phone number — which is never 64 hex characters — cannot be
#: written into one by accident and pass unnoticed.
PHONE_HASH_LENGTH = 64


class DiscoverabilityLevel(str, Enum):
    """Who may find this user by phone number.

    Defaults to CONTACTS_OF_CONTACTS rather than EVERYONE: discovery is a
    convenience, and the safe default for a high-trust product is the narrower
    one. A user who wants to be broadly findable can opt in.
    """

    EVERYONE = "everyone"
    CONTACTS_OF_CONTACTS = "contacts_of_contacts"
    NOBODY = "nobody"


class UserPhoneIndex(Base):
    """Hashed index of registered users, used as the matching target.

    SECURITY CONTRACT — read before changing anything here:

    This table holds a salted SHA-256 hash of a registered user's phone
    number, never the number itself. The `users.phone_number` column exists
    because the account has to be reachable for OTP; this index exists so
    that *other* people's contact books can be matched without either side
    uploading a plaintext number.

    The salt is global to the index (not per-user), because matching requires
    that the same number hashes identically no matter who submitted it. That
    is a deliberate trade-off: a per-user salt would defeat matching entirely.
    The salt lives in configuration, never in this table, so a database dump
    alone cannot be brute-forced against the (small) space of phone numbers.
    """

    __tablename__ = "user_phone_index"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    phone_hash: Mapped[str] = mapped_column(
        String(PHONE_HASH_LENGTH), nullable=False
    )
    allows_discovery: Mapped[str] = mapped_column(
        String(24),
        nullable=False,
        default=DiscoverabilityLevel.CONTACTS_OF_CONTACTS,
        server_default=DiscoverabilityLevel.CONTACTS_OF_CONTACTS.value,
    )

    user: Mapped[User] = relationship("User")

    __table_args__ = (
        UniqueConstraint("user_id", name="uq_phone_index_user"),
        # The matching query looks up by hash, so this index carries the
        # whole feature's read path.
        Index("ix_phone_index_hash", "phone_hash"),
    )


class ContactHash(Base):
    """One hashed entry from a user's own contact book.

    Only hashes are stored — see the contract on UserPhoneIndex. A row here
    means "this user has *someone* in their contacts whose number hashes to
    this", which is exactly enough to compute matches and nothing more: the
    server cannot recover the number, the contact's name, or anything else
    from the address book.
    """

    __tablename__ = "contact_hashes"

    owner_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    phone_hash: Mapped[str] = mapped_column(
        String(PHONE_HASH_LENGTH), nullable=False
    )

    __table_args__ = (
        # Re-syncing the same book must not multiply rows.
        UniqueConstraint("owner_id", "phone_hash", name="uq_contact_hash"),
        Index("ix_contact_hashes_owner", "owner_id"),
        Index("ix_contact_hashes_hash", "phone_hash"),
    )


class ContactRelation(Base):
    """A resolved link: owner has contact_user in their address book.

    Materialised rather than computed per request so that "who joined that I
    know" can be answered without re-running a join across both hash tables
    on every open.
    """

    __tablename__ = "contact_relations"

    owner_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    contact_user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    source: Mapped[str] = mapped_column(
        String(20),
        nullable=False,
        default="phone",
        server_default="phone",
        comment="phone | username | qr — how the link was established",
    )

    #: Cleared once the owner has seen the discovery, so "X joined IronLink"
    #: is announced once rather than on every sync.
    notified_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    __table_args__ = (
        UniqueConstraint("owner_id", "contact_user_id", name="uq_contact_relation"),
        Index("ix_contact_relations_owner", "owner_id"),
        Index("ix_contact_relations_contact", "contact_user_id"),
    )


class ContactInvite(Base):
    """An invitation sent to a number that is not registered yet.

    Keyed by hash like everything else: the whole point is that the server
    never learns who was invited unless they install and register, at which
    point the hash matches and the link resolves normally.
    """

    __tablename__ = "contact_invites"

    inviter_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    phone_hash: Mapped[str] = mapped_column(
        String(PHONE_HASH_LENGTH), nullable=False
    )
    invite_token: Mapped[str] = mapped_column(
        String(64), nullable=False, comment="Opaque token embedded in the deep link"
    )
    installed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    __table_args__ = (
        UniqueConstraint("invite_token", name="uq_invite_token"),
        Index("ix_contact_invites_inviter", "inviter_id"),
        Index("ix_contact_invites_hash", "phone_hash"),
    )


class ContactSyncState(Base):
    """Per-user sync bookkeeping.

    Exists so the client can do incremental syncs and so opting out can be
    made verifiable: `synced_at` going NULL alongside zero contact_hashes
    rows is what "we deleted your data" actually looks like.
    """

    __tablename__ = "contact_sync_state"

    user_id: Mapped[uuid.UUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    sync_enabled: Mapped[bool] = mapped_column(
        Boolean, nullable=False, default=True, server_default="true"
    )
    synced_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )
    contact_count: Mapped[int] = mapped_column(
        Integer, nullable=False, default=0, server_default="0",
        comment="How many hashes this user last submitted; shown back to them "
                "so 'we hold N entries' is checkable rather than asserted",
    )

    __table_args__ = (
        UniqueConstraint("user_id", name="uq_contact_sync_state_user"),
    )
