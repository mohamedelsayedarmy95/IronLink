"""Idempotent message delivery

The client now queues frames written while the socket is down and replays
them on reconnect. That is the right behaviour — it is what stops a message
typed during a network handover from vanishing — but it introduces a case
the server has to answer: a client that loses the connection after the server
stored a message and before the ack arrived cannot know which happened, so it
resends.

Without an idempotency key that resend became a second message, and the
recipient saw the same thing said twice. With one, the resend returns the
original and gets the same ack.

Unique per sender rather than globally: two people can independently generate
"ref_3". Partial on NOT NULL, because server-generated messages have no
client_ref and must not all collide.

Revision ID: 0009_message_idempotency
Revises: 0008_session_bound_tokens
Create Date: 2026-08-16
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = '0009_message_idempotency'
down_revision: str | None = '0008_session_bound_tokens'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        'messages', sa.Column('client_ref', sa.String(length=64), nullable=True)
    )
    op.create_index(
        'uq_msg_sender_client_ref',
        'messages',
        ['sender_id', 'client_ref'],
        unique=True,
        postgresql_where=sa.text('client_ref IS NOT NULL'),
    )


def downgrade() -> None:
    op.drop_index('uq_msg_sender_client_ref', table_name='messages')
    op.drop_column('messages', 'client_ref')
