"""Group membership epoch, for sender-key rotation

Group messages are encrypted with a per-sender key that every member holds a
copy of. That is what makes a group message one encryption instead of one per
member — and it is also why removing someone from a group does nothing on its
own: the key they already hold decrypts every later message from that sender.

Access ends only when each remaining sender mints a new key. This column is
how a client learns it must: it is compared against the epoch its current
sender key was minted for. Every membership change bumps it.

The server cannot perform the rotation — it never sees the keys. What it can
do is make the change impossible to miss.

Revision ID: 0006_group_members_epoch
Revises: 0005_blocks_and_reports
Create Date: 2026-08-15
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = '0006_group_members_epoch'
down_revision: str | None = '0005_blocks_and_reports'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        'groups',
        sa.Column(
            'members_epoch',
            sa.Integer(),
            server_default='1',
            nullable=False,
        ),
    )
    # Group history is read newest-first for one group, and the sender-key
    # distribution messages are filtered out of it.
    op.create_index(
        'ix_messages_group_created',
        'messages',
        ['group_id', 'created_at'],
        postgresql_where=sa.text('group_id IS NOT NULL'),
    )


def downgrade() -> None:
    op.drop_index('ix_messages_group_created', table_name='messages')
    op.drop_column('groups', 'members_epoch')
