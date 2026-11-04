"""User blocks and content reports

Blocks are enforced server-side at the message-save path, so this table is
load-bearing rather than a UI preference: a block that only hides messages in
the client would be bypassed by any modified build.

Reports snapshot the reported text, supplied by the reporter. The server
cannot decrypt content_ciphertext, so without that snapshot a report's
evidence disappears the moment the sender deletes the message — which is
exactly what someone sending abuse does.

Revision ID: 0005_blocks_and_reports
Revises: 0004_contact_discovery
Create Date: 2026-08-15
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = '0005_blocks_and_reports'
down_revision: str | None = '0004_contact_discovery'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


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
        'user_blocks',
        *_base_columns(),
        sa.Column('blocker_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('blocked_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('reason', sa.Text(), nullable=True),
        sa.ForeignKeyConstraint(['blocker_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['blocked_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('blocker_id', 'blocked_id', name='uq_user_block'),
        # Blocking yourself is meaningless and would make the send-path check
        # reject your own notes-to-self.
        sa.CheckConstraint('blocker_id <> blocked_id', name='ck_block_not_self'),
    )
    # The send path asks "has anyone blocked this pair", so the index leads
    # with blocked_id to answer it without a scan.
    op.create_index('ix_user_blocks_pair', 'user_blocks',
                    ['blocked_id', 'blocker_id'])
    op.create_index('ix_user_blocks_blocker', 'user_blocks', ['blocker_id'])

    op.create_table(
        'content_reports',
        *_base_columns(),
        sa.Column('reporter_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('reported_user_id', postgresql.UUID(as_uuid=True),
                  nullable=False),
        sa.Column('message_id', postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column('reason', sa.String(length=32), nullable=False),
        sa.Column('details', sa.Text(), nullable=True),
        sa.Column('content_snapshot', sa.Text(), nullable=True),
        sa.Column('status', sa.String(length=20), server_default='open',
                  nullable=False),
        sa.Column('reviewed_by_id', postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column('reviewed_at', sa.DateTime(timezone=True), nullable=True),
        sa.Column('moderator_notes', sa.Text(), nullable=True),
        sa.ForeignKeyConstraint(['reporter_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['reported_user_id'], ['users.id'],
                                ondelete='CASCADE'),
        # SET NULL, not CASCADE: a report must survive the reported message
        # being deleted, or deleting the evidence deletes the complaint.
        sa.ForeignKeyConstraint(['message_id'], ['messages.id'],
                                ondelete='SET NULL'),
        sa.ForeignKeyConstraint(['reviewed_by_id'], ['users.id'],
                                ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id'),
        sa.CheckConstraint('reporter_id <> reported_user_id',
                           name='ck_report_not_self'),
    )
    op.create_index('ix_reports_status_created', 'content_reports',
                    ['status', 'created_at'])
    op.create_index('ix_reports_reported_user', 'content_reports',
                    ['reported_user_id'])
    # One report per reporter per message. Reporting the same *user* again is
    # still allowed, since each incident is different information.
    op.create_index(
        'ix_reports_unique_message', 'content_reports',
        ['reporter_id', 'message_id'],
        unique=True,
        postgresql_where=sa.text('message_id IS NOT NULL'),
    )


def downgrade() -> None:
    op.drop_index('ix_reports_unique_message', table_name='content_reports')
    op.drop_index('ix_reports_reported_user', table_name='content_reports')
    op.drop_index('ix_reports_status_created', table_name='content_reports')
    op.drop_table('content_reports')
    op.drop_index('ix_user_blocks_blocker', table_name='user_blocks')
    op.drop_index('ix_user_blocks_pair', table_name='user_blocks')
    op.drop_table('user_blocks')
