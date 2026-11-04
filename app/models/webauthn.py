from __future__ import annotations

from datetime import datetime
from typing import TYPE_CHECKING
from uuid import UUID

from sqlalchemy import (
    Boolean,
    DateTime,
    ForeignKey,
    Index,
    Integer,
    LargeBinary,
    String,
    text,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID as PGUUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .base import Base

if TYPE_CHECKING:
    from .user import User


class WebAuthnCredential(Base):
    """A hardware security key registered to one account.

    SECURITY CONTRACT

    `public_key` is the COSE-encoded public key returned by the authenticator.
    The private key never leaves the key itself; this server cannot sign an
    assertion, and a database dump cannot be replayed as a login. There is
    deliberately no column capable of holding private or symmetric key
    material.

    `credential_id` is the authenticator's opaque identifier. It is not secret,
    but it is globally unique: the authentication ceremony uses it to find the
    one account and public key that can verify the assertion.

    DISCOVERABLE CREDENTIALS

    Registration requests a resident (discoverable) credential. Authentication
    starts with an empty `allowCredentials` list, so the browser offers every
    resident credential it holds and the server identifies the account from the
    returned credential id. That is what makes login usernameless, and it is
    also why authentication cannot be used to enumerate phone numbers: no
    request ever carries an account identifier.

    CLONE DETECTION

    `sign_count` is the authenticator's monotonic signature counter, checked by
    the WebAuthn library on every assertion. A counter that fails to advance is
    rejected rather than silently accepted. Authenticators that always report
    zero (some platform keys) remain usable; the library only enforces the
    counter once either side has reported a non-zero value.

    BACKUP STATE

    Passkeys may be synced by the platform. `backup_eligible` records whether
    the credential *could* be backed up, and `backup_state` records whether it
    currently is. These are informational; they do not change the trust decision.
    """

    __tablename__ = "webauthn_credentials"

    user_id: Mapped[UUID] = mapped_column(
        PGUUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
    )
    credential_id: Mapped[bytes] = mapped_column(
        LargeBinary,
        nullable=False,
        unique=True,
        comment="Raw authenticator credential id; unique across all accounts",
    )
    public_key: Mapped[bytes] = mapped_column(
        LargeBinary,
        nullable=False,
        comment="COSE-encoded public key only; private keys stay on the key",
    )
    sign_count: Mapped[int] = mapped_column(
        Integer,
        nullable=False,
        default=0,
        server_default="0",
        comment="Authenticator signature counter used for clone detection",
    )
    transports: Mapped[list[str]] = mapped_column(
        JSONB,
        nullable=False,
        default=list,
        server_default=text("'[]'::jsonb"),
        comment="Authenticator transports reported at registration",
    )
    aaguid: Mapped[str | None] = mapped_column(
        String(36),
        nullable=True,
        comment="Authenticator model identifier (AAGUID), not a user identifier",
    )
    credential_type: Mapped[str] = mapped_column(
        String(32),
        nullable=False,
        default="public-key",
        server_default="public-key",
    )
    user_verified: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=False,
        server_default="false",
        comment="Whether the authenticator performed user verification at registration",
    )
    backup_eligible: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=False,
        server_default="false",
        comment="WebAuthn BE flag: credential may be backed up/synced",
    )
    backup_state: Mapped[bool] = mapped_column(
        Boolean,
        nullable=False,
        default=False,
        server_default="false",
        comment="WebAuthn BS flag: credential is currently backed up",
    )
    nickname: Mapped[str | None] = mapped_column(
        String(100),
        nullable=True,
        comment="User-facing label such as 'YubiKey 5C'",
    )
    last_used_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True), nullable=True
    )

    user: Mapped[User] = relationship("User", back_populates="webauthn_credentials")

    __table_args__ = (
        Index(
            "ix_webauthn_credentials_user_created",
            "user_id",
            "created_at",
        ),
    )
