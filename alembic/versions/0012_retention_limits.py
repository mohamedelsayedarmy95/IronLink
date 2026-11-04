"""Retention limits, and two columns that should never have existed

`audit_logs` and `user_sessions` grew without bound. The engineering standard
requires retention limits defined per data type and *enforced*; these had
neither. `docs/DATA_CLASSIFICATION.md` recorded the gap rather than hiding it,
and this closes it.

DROPPING geo_lat AND geo_lon

`user_sessions` declared `geo_lat` and `geo_lon` as NUMERIC(7,4). Four decimal
places of latitude is roughly eleven metres — building precision — while the
model's own docstring three lines above them promised "approximate coordinates
(city-level, not GPS) ... without pinpointing user location".

Nothing writes them. A search across the whole backend finds no assignment to
either column: they have been NULL in every row since the schema was created,
and the docstring describing what they store was describing something that has
never happened.

So they go. Data minimisation is not only about what you collect; a column that
exists is a column something eventually fills, and the next person to add
geo-anomaly detection would have found two conveniently-named columns and put
GPS coordinates in them without ever reading the paragraph that forbids it.
Removing them makes the policy structural instead of aspirational.

This is a contract step and the only non-additive migration in the project. It
is safe because nothing reads or writes these columns — verified, not assumed —
and the downgrade restores them, empty, which is exactly what they contained.

`geo_city` and `geo_country` stay: they appear in the session API contract. They
are also never populated, which is recorded rather than fixed here.

INDEXES

Retention sweeps run against `created_at` and against revoked/expired sessions.
Without indexes each daily pass is a sequential scan of a table whose whole
problem is that it is large.

Revision ID: 0012_retention_limits
Revises: 0011_account_deletion
Create Date: 2026-08-18
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0012_retention_limits"
down_revision: str | None = "0011_account_deletion"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.drop_column("user_sessions", "geo_lat")
    op.drop_column("user_sessions", "geo_lon")

    # The sweep selects old rows oldest-first and deletes in batches.
    op.create_index("ix_audit_logs_created", "audit_logs", ["created_at"])

    # Partial: live sessions are never swept, so they do not belong in the
    # index the sweep uses. Keeping them out makes it smaller and makes it
    # structurally impossible for the sweep's own index to point at a session
    # somebody is holding.
    op.create_index(
        "ix_user_sessions_finished",
        "user_sessions",
        ["updated_at"],
        postgresql_where=sa.text("revoked_at IS NOT NULL"),
    )


def downgrade() -> None:
    op.drop_index("ix_user_sessions_finished", table_name="user_sessions")
    op.drop_index("ix_audit_logs_created", table_name="audit_logs")

    # Restored empty, which is what they always were.
    op.add_column(
        "user_sessions", sa.Column("geo_lon", sa.Numeric(7, 4), nullable=True)
    )
    op.add_column(
        "user_sessions", sa.Column("geo_lat", sa.Numeric(7, 4), nullable=True)
    )
