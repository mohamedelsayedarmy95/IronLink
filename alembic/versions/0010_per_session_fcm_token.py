"""Push tokens belong to a device, not to an account

`users.fcm_token` is a single column, so the second device to sign in
overwrote the first one's token and silently stopped it receiving anything.
Everyone with a phone and a tablet had exactly one of them working, and which
one depended on the order they last launched the app.

It also made the push delivery rate unmeasurable, which is why docs/SLO.md
declines to set an objective for it — measuring it would have measured the bug.

Expand, not replace. This adds the column and leaves `users.fcm_token` alone.
The application writes both and reads only the new one, so a rollback to the
previous release finds the old column still populated and keeps working. The
contract step that drops it is a separate migration, taken after this has run
long enough that no deployed client is registering against the old path.

Revision ID: 0010_per_session_fcm_token
Revises: 0009_message_idempotency
Create Date: 2026-08-17
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0010_per_session_fcm_token"
down_revision: str | None = "0009_message_idempotency"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "user_sessions",
        sa.Column(
            "fcm_token",
            sa.String(512),
            nullable=True,
            comment=(
                "Firebase token for this device. Null until the app registers "
                "one, and for sessions that are not app installs."
            ),
        ),
    )
    # Every message to an offline recipient fans out over their sessions, so
    # this lookup runs on the delivery path rather than on an admin screen.
    op.create_index(
        "idx_user_sessions_fcm",
        "user_sessions",
        ["user_id"],
        postgresql_where=sa.text("fcm_token IS NOT NULL"),
    )


def downgrade() -> None:
    op.drop_index("idx_user_sessions_fcm", table_name="user_sessions")
    op.drop_column("user_sessions", "fcm_token")
