"""Contact sync and auto-discovery

Privacy-preserving contact matching: the device hashes each normalized phone
number and uploads only the digest. Every column here is fixed at 64
characters — the width of a hex SHA-256 — so a raw phone number cannot be
written into one and pass unnoticed.

Revision ID: 0004_contact_discovery
Revises: 0003_controlled_group_entry
Create Date: 2026-08-15
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = '0004_contact_discovery'
down_revision: str | None = '0003_controlled_group_entry'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

HASH_LEN = 64


def _base_columns() -> list[sa.Column]:
    return [
        sa.Column('id', postgresql.UUID(as_uuid=True),
                  server_default=sa.text('gen_random_uuid()'), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True),
                  server_default=sa.text('NOW()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True),
                  server_default=sa.text('NOW()'), nullable=False),
    ]


def upgrade() -> None:
    op.create_table(
        'user_phone_index',
        *_base_columns(),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('phone_hash', sa.String(length=HASH_LEN), nullable=False),
        sa.Column('allows_discovery', sa.String(length=24),
                  server_default='contacts_of_contacts', nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('user_id', name='uq_phone_index_user'),
    )
    op.create_index('ix_phone_index_hash', 'user_phone_index', ['phone_hash'])

    op.create_table(
        'contact_hashes',
        *_base_columns(),
        sa.Column('owner_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('phone_hash', sa.String(length=HASH_LEN), nullable=False),
        sa.ForeignKeyConstraint(['owner_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        # Re-syncing the same address book must not multiply rows.
        sa.UniqueConstraint('owner_id', 'phone_hash', name='uq_contact_hash'),
    )
    op.create_index('ix_contact_hashes_owner', 'contact_hashes', ['owner_id'])
    op.create_index('ix_contact_hashes_hash', 'contact_hashes', ['phone_hash'])

    op.create_table(
        'contact_relations',
        *_base_columns(),
        sa.Column('owner_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('contact_user_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('source', sa.String(length=20),
                  server_default='phone', nullable=False),
        sa.Column('notified_at', sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(['owner_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['contact_user_id'], ['users.id'],
                                ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('owner_id', 'contact_user_id',
                            name='uq_contact_relation'),
    )
    op.create_index('ix_contact_relations_owner', 'contact_relations', ['owner_id'])
    op.create_index('ix_contact_relations_contact', 'contact_relations',
                    ['contact_user_id'])

    op.create_table(
        'contact_invites',
        *_base_columns(),
        sa.Column('inviter_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('phone_hash', sa.String(length=HASH_LEN), nullable=False),
        sa.Column('invite_token', sa.String(length=64), nullable=False),
        sa.Column('installed_at', sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(['inviter_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('invite_token', name='uq_invite_token'),
    )
    op.create_index('ix_contact_invites_inviter', 'contact_invites', ['inviter_id'])
    op.create_index('ix_contact_invites_hash', 'contact_invites', ['phone_hash'])

    op.create_table(
        'contact_sync_state',
        *_base_columns(),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('sync_enabled', sa.Boolean(), server_default='true',
                  nullable=False),
        sa.Column('synced_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('contact_count', sa.Integer(), server_default='0',
                  nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('user_id', name='uq_contact_sync_state_user'),
    )


def downgrade() -> None:
    op.drop_table('contact_sync_state')
    op.drop_index('ix_contact_invites_hash', table_name='contact_invites')
    op.drop_index('ix_contact_invites_inviter', table_name='contact_invites')
    op.drop_table('contact_invites')
    op.drop_index('ix_contact_relations_contact', table_name='contact_relations')
    op.drop_index('ix_contact_relations_owner', table_name='contact_relations')
    op.drop_table('contact_relations')
    op.drop_index('ix_contact_hashes_hash', table_name='contact_hashes')
    op.drop_index('ix_contact_hashes_owner', table_name='contact_hashes')
    op.drop_table('contact_hashes')
    op.drop_index('ix_phone_index_hash', table_name='user_phone_index')
    op.drop_table('user_phone_index')
