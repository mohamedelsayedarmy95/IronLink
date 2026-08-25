"""Per-conversation consent for sending text to the AI provider

The AI features are the only place message plaintext leaves the device and
reaches a third party: the client decrypts, posts to this server, and the
server forwards to Hugging Face. Nothing gated that.

A row here is ONE person's half of the agreement. The routes require every
participant's half, because a summary — or a translation, or a toxicity
score — is made of other people's words, and one side cannot consent on the
other's behalf.

Revision ID: 0007_ai_consent
Revises: 0006_group_members_epoch
Create Date: 2026-08-16
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = '0007_ai_consent'
down_revision: str | None = '0006_group_members_epoch'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        'ai_consents',
        sa.Column('id', postgresql.UUID(as_uuid=True),
                  server_default=sa.text('gen_random_uuid()'), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True),
                  server_default=sa.text('NOW()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True),
                  server_default=sa.text('NOW()'), nullable=False),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('scope_type', sa.String(length=10), nullable=False),
        sa.Column('scope_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('granted_at', sa.DateTime(timezone=True), nullable=False),
        # Stamped rather than deleting the row: withdrawal stops future
        # transmission but cannot un-send what already went, and the dates are
        # what keep that answerable.
        sa.Column('revoked_at', sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.CheckConstraint(
            "scope_type IN ('direct', 'group')", name='ck_ai_scope_type'
        ),
    )
    op.create_index('ix_ai_consents_user_id', 'ai_consents', ['user_id'])
    # Enforcement asks "who has agreed for this conversation", so the index
    # leads with the scope.
    op.create_index(
        'ix_ai_consents_scope', 'ai_consents', ['scope_type', 'scope_id']
    )
    # One LIVE consent per person per conversation. Partial, so a withdrawn
    # row does not block a later re-grant — the periods stay distinct rather
    # than one row being toggled back and forth.
    op.create_index(
        'uq_ai_consent_scope', 'ai_consents',
        ['user_id', 'scope_type', 'scope_id'],
        unique=True,
        postgresql_where=sa.text('revoked_at IS NULL'),
    )


def downgrade() -> None:
    op.drop_index('uq_ai_consent_scope', table_name='ai_consents')
    op.drop_index('ix_ai_consents_scope', table_name='ai_consents')
    op.drop_index('ix_ai_consents_user_id', table_name='ai_consents')
    op.drop_table('ai_consents')
