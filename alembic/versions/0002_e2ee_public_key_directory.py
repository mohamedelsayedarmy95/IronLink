"""E2EE public key directory

Replaces the previous key handling, which stored Signal private keys and
session state server-side in Redis and substituted server-generated mock keys
for whatever the client uploaded. That design let the server decrypt every
message; these tables deliberately hold public key material only.

No data migration: the old key material lived in Redis (never in Postgres) and
was mock values, so there is nothing worth carrying over. Clients republish a
real bundle on next launch.

Revision ID: 0002_e2ee_public_key_directory
Revises: 0001_initial_schema
Create Date: 2026-08-09
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql


revision: str = '0002_e2ee_public_key_directory'
down_revision: str | None = '0001_initial_schema'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        'user_key_bundles',
        sa.Column('id', postgresql.UUID(as_uuid=True), server_default=sa.text('gen_random_uuid()'), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()'), nullable=False),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('registration_id', sa.Integer(), nullable=False),
        sa.Column('identity_key', sa.Text(), nullable=False),
        sa.Column('signed_prekey_id', sa.Integer(), nullable=False),
        sa.Column('signed_prekey_public', sa.Text(), nullable=False),
        sa.Column('signed_prekey_signature', sa.Text(), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('user_id'),
    )
    op.create_index('ix_user_key_bundles_user_id', 'user_key_bundles', ['user_id'])

    op.create_table(
        'one_time_prekeys',
        sa.Column('id', postgresql.UUID(as_uuid=True), server_default=sa.text('gen_random_uuid()'), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()'), nullable=False),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('key_id', sa.Integer(), nullable=False),
        sa.Column('public_key', sa.Text(), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('user_id', 'key_id', name='uq_one_time_prekey_user_key'),
    )
    op.create_index('ix_one_time_prekeys_user_id', 'one_time_prekeys', ['user_id'])
    # Supports the ordered LIMIT 1 claim in GET /keys/bundle/{user_id}.
    op.create_index('ix_one_time_prekeys_user_id_id', 'one_time_prekeys', ['user_id', 'id'])


def downgrade() -> None:
    op.drop_index('ix_one_time_prekeys_user_id_id', table_name='one_time_prekeys')
    op.drop_index('ix_one_time_prekeys_user_id', table_name='one_time_prekeys')
    op.drop_table('one_time_prekeys')
    op.drop_index('ix_user_key_bundles_user_id', table_name='user_key_bundles')
    op.drop_table('user_key_bundles')
