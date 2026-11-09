"""Identity-scoped tombstones for consumed one-time pre-keys.

A pre-key is consumed by deleting its row. Deletion is what makes it
single-use, but it also erases the evidence that the key existed. A client
whose bundle-upload response was lost retries the same upload later; without
a tombstone the retry inserts the already-consumed key and hands it to a
second sender.

There is deliberately no backfill. Which keys were consumed before this
migration is not recorded anywhere, so it cannot be reconstructed. Bundle
retries are nevertheless safe from resurrection because the bundle endpoint
no longer inserts pre-keys when the identity is unchanged; new pre-keys come
from the replenishment endpoint, whose retries are protected by these rows.

Revision ID: 0015_prekey_tombstones
Revises: 0014_channel_media_keys
Create Date: 2026-11-09
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql


revision: str = '0015_prekey_tombstones'
down_revision: str | None = '0014_channel_media_keys'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        'one_time_prekey_consumptions',
        sa.Column('id', postgresql.UUID(as_uuid=True), server_default=sa.text('gen_random_uuid()'), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True), server_default=sa.text('NOW()'), nullable=False),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('identity_key', sa.Text(), nullable=False),
        sa.Column('key_id', sa.Integer(), nullable=False),
        sa.Column('public_key', sa.Text(), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint(
            'user_id', 'identity_key', 'key_id',
            name='uq_one_time_prekey_consumption_user_identity_key',
        ),
    )
    op.create_index(
        'ix_one_time_prekey_consumptions_user_id',
        'one_time_prekey_consumptions',
        ['user_id'],
    )


def downgrade() -> None:
    op.drop_index(
        'ix_one_time_prekey_consumptions_user_id',
        table_name='one_time_prekey_consumptions',
    )
    op.drop_table('one_time_prekey_consumptions')
