"""WebAuthn hardware security keys

Adds the credential directory for passwordless authentication. Each row holds
one authenticator's public key and counter; private keys never leave the key.

The credential id is globally unique (not merely unique per user) because the
usernameless authentication ceremony starts with no account identifier and
uses this column to find the one account that can verify the assertion.

Revision ID: 0013_webauthn_credentials
Revises: 0012_retention_limits
Create Date: 2026-10-29
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0013_webauthn_credentials"
down_revision: str | None = "0012_retention_limits"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "webauthn_credentials",
        sa.Column(
            "id",
            postgresql.UUID(as_uuid=True),
            server_default=sa.text("gen_random_uuid()"),
            nullable=False,
        ),
        sa.Column("user_id", postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column(
            "credential_id",
            sa.LargeBinary(),
            nullable=False,
            comment="Raw authenticator credential id; unique across all accounts",
        ),
        sa.Column(
            "public_key",
            sa.LargeBinary(),
            nullable=False,
            comment="COSE-encoded public key only; private keys stay on the key",
        ),
        sa.Column(
            "sign_count",
            sa.Integer(),
            server_default=sa.text("0"),
            nullable=False,
            comment="Authenticator signature counter used for clone detection",
        ),
        sa.Column(
            "transports",
            postgresql.JSONB(astext_type=sa.Text()),
            server_default=sa.text("'[]'::jsonb"),
            nullable=False,
            comment="Authenticator transports reported at registration",
        ),
        sa.Column("aaguid", sa.String(length=36), nullable=True),
        sa.Column(
            "credential_type",
            sa.String(length=32),
            server_default=sa.text("'public-key'"),
            nullable=False,
        ),
        sa.Column(
            "user_verified",
            sa.Boolean(),
            server_default=sa.text("false"),
            nullable=False,
        ),
        sa.Column(
            "backup_eligible",
            sa.Boolean(),
            server_default=sa.text("false"),
            nullable=False,
        ),
        sa.Column(
            "backup_state",
            sa.Boolean(),
            server_default=sa.text("false"),
            nullable=False,
        ),
        sa.Column("nickname", sa.String(length=100), nullable=True),
        sa.Column(
            "last_used_at", sa.DateTime(timezone=True), nullable=True
        ),
        sa.Column(
            "created_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("NOW()"),
            nullable=False,
        ),
        sa.Column(
            "updated_at",
            sa.DateTime(timezone=True),
            server_default=sa.text("NOW()"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ["user_id"], ["users.id"], ondelete="CASCADE"
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint(
            "credential_id",
            name="uq_webauthn_credentials_credential_id",
        ),
        comment=(
            "Public WebAuthn credential material. A row without the physical "
            "key cannot authenticate."
        ),
    )
    op.create_index(
        "ix_webauthn_credentials_user_created",
        "webauthn_credentials",
        ["user_id", "created_at"],
    )


def downgrade() -> None:
    op.drop_index(
        "ix_webauthn_credentials_user_created",
        table_name="webauthn_credentials",
    )
    op.drop_table("webauthn_credentials")
