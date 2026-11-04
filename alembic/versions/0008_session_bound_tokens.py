"""Refresh-token rotation support

Adds the one column reuse detection needs.

Rotation alone makes a stolen refresh token usable at most once, but it cannot
distinguish theft from an ordinary retry: once the hash is overwritten the old
token matches nothing, and the request just fails. Keeping the hash it
replaced turns that silence into a signal — a token that was already exchanged
is being presented again, and the session is revoked.

Revision ID: 0008_session_bound_tokens
Revises: 0007_ai_consent
Create Date: 2026-08-16
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = '0008_session_bound_tokens'
down_revision: str | None = '0007_ai_consent'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        'user_sessions',
        sa.Column('previous_refresh_token_hash', sa.Text(), nullable=True),
    )
    # Looked up only on the failure path, but that path must stay cheap: it is
    # what an attacker replaying tokens would be hitting repeatedly.
    op.create_index(
        'ix_user_sessions_previous_refresh',
        'user_sessions',
        ['previous_refresh_token_hash'],
    )


def downgrade() -> None:
    op.drop_index(
        'ix_user_sessions_previous_refresh', table_name='user_sessions'
    )
    op.drop_column('user_sessions', 'previous_refresh_token_hash')
