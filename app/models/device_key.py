from __future__ import annotations

from datetime import datetime
from uuid import UUID as PyUUID

from sqlalchemy import DateTime, ForeignKey, Index, Integer, String, Text, UniqueConstraint
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from .base import Base


class UserKeyBundle(Base):
    """Signal Protocol PUBLIC key material — the server's key directory.

    SECURITY CONTRACT — read before changing anything here:

    Every column in this table and in OneTimePreKey is PUBLIC key material.
    Private keys are generated on the device, stored in the platform keystore
    (flutter_secure_storage), and MUST NEVER be transmitted to or stored by
    the server. A server that holds private keys can decrypt every message,
    which defeats the entire point of end-to-end encryption.

    The previous implementation stored `{"public": ..., "private": ...}` pairs
    in Redis and substituted server-generated mock keys for whatever the client
    uploaded. That was not E2EE — it was the inverse. Do not reintroduce it.

    Signature verification: the signed pre-key signature is verified by the
    RECEIVING CLIENT (libsignal's SessionBuilder.processPreKeyBundle rejects a
    bundle whose signature does not match the identity key). That is the
    security boundary — it is what stops a malicious or compromised server from
    substituting its own keys to mount a man-in-the-middle attack. The server
    performs structural validation only; it deliberately does not claim to be
    the authority on signature validity, because a server verifying its own
    substituted keys would prove nothing.

    Single-device scope: one bundle per user. Multi-device requires one bundle
    per device (Signal's actual model) plus fan-out encryption to every device
    of the recipient — an extension, not a change to this contract.
    """

    __tablename__ = "user_key_bundles"

    user_id: Mapped[PyUUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        unique=True,
        index=True,
    )

    # libsignal registration id — identifies this installation
    registration_id: Mapped[int] = mapped_column(Integer, nullable=False)

    # Long-term identity public key (base64). Changes only on reinstall/reset,
    # at which point peers see a "safety number changed" warning.
    identity_key: Mapped[str] = mapped_column(Text, nullable=False)

    # Medium-term signed pre-key, rotated periodically by the client.
    signed_prekey_id: Mapped[int] = mapped_column(Integer, nullable=False)
    signed_prekey_public: Mapped[str] = mapped_column(Text, nullable=False)
    signed_prekey_signature: Mapped[str] = mapped_column(Text, nullable=False)

    user: Mapped["User"] = relationship("User")  # noqa: F821


class OneTimePreKey(Base):
    """Single-use pre-keys, consumed one per new session (X3DH).

    Public keys only — see the contract on UserKeyBundle.

    Consumption is a delete, not a soft flag: a one-time pre-key handed to two
    different senders would let both derive the same initial root key, which
    breaks the forward-secrecy guarantee the "one-time" name is promising.
    """

    __tablename__ = "one_time_prekeys"

    user_id: Mapped[PyUUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    key_id: Mapped[int] = mapped_column(Integer, nullable=False)
    public_key: Mapped[str] = mapped_column(Text, nullable=False)

    __table_args__ = (
        UniqueConstraint("user_id", "key_id", name="uq_one_time_prekey_user_key"),
        Index("ix_one_time_prekeys_user_id_id", "user_id", "id"),
    )


class ConsumedOneTimePreKey(Base):
    """Identity-scoped tombstone for a one-time pre-key that was consumed.

    Deleting a claimed pre-key is what makes it single-use, but deletion alone
    is not enough: the client retries an earlier bundle upload whenever the
    original response was lost, and that upload still contains the claimed
    key. Without a record of the claim, the retry would insert the key again
    and hand the same one-time key to a second sender.

    The tombstone is scoped by identity key, not just by key id. Pre-key ids
    are generated per installation, so a new identity may legitimately reuse
    the same numeric id; only the same identity and id together identify the
    consumed key. `created_at` is the consumption time. Only public material
    is stored — see the contract on UserKeyBundle.

    Rows are retained across identity changes on purpose: switching away from
    an identity does not make keys consumed under it safe to republish.
    """

    __tablename__ = "one_time_prekey_consumptions"

    user_id: Mapped[PyUUID] = mapped_column(
        UUID(as_uuid=True),
        ForeignKey("users.id", ondelete="CASCADE"),
        nullable=False,
        index=True,
    )
    identity_key: Mapped[str] = mapped_column(Text, nullable=False)
    key_id: Mapped[int] = mapped_column(Integer, nullable=False)
    public_key: Mapped[str] = mapped_column(Text, nullable=False)

    __table_args__ = (
        UniqueConstraint(
            "user_id",
            "identity_key",
            "key_id",
            name="uq_one_time_prekey_consumption_user_identity_key",
        ),
    )
