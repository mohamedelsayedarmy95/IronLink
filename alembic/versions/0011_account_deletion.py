"""Make account deletion possible without destroying other people's records

There was no way to delete an account. Adding one turned out to require two
schema changes first, because a plain DELETE would have taken things with it
that do not belong to the person leaving.

WHAT A PLAIN DELETE WOULD HAVE DESTROYED

`group_audit_logs.performed_by_id` cascaded. A group's audit trail exists so its
other members can see who admitted whom and who removed whom; an admin deleting
their account would have erased their own entries from everyone else's record.
The same table already used SET NULL for `target_user_id`, so the intent was
plainly to anonymise rather than delete — one column was simply inconsistent
with the other. Now both are SET NULL.

`platform_bans.user_id` cascaded too, which made ban evasion a one-step process:
get banned, delete the account, register the same phone number again. A ban
system that can be undone by the banned person is decorative.

HOW THE BAN SURVIVES WITHOUT RETAINING AN IDENTITY

The row keeps a salted SHA-256 of the phone number and drops the user id. That
is the same construction `user_phone_index` already uses, with the salt in
configuration rather than in the table, so a database dump alone cannot be
brute-forced against the small space of phone numbers.

This is a deliberate, disclosed retention. Privacy outranks abuse prevention in
the engineering hierarchy, and the resolution is not to skip the retention but
to make it minimal and honest: a hash, no identifier, and the deletion response
tells the user in plain words that it happened. `docs/DATA_CLASSIFICATION.md`
records it.

Additive: both columns become nullable and gain a new column. No data is
dropped, and application code from before this migration still works, because
nothing it reads has changed shape.

Revision ID: 0011_account_deletion
Revises: 0010_per_session_fcm_token
Create Date: 2026-08-18
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0011_account_deletion"
down_revision: str | None = "0010_per_session_fcm_token"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # ── A group's audit trail outlives the people in it ──────────────────────
    op.drop_constraint(
        "group_audit_logs_performed_by_id_fkey",
        "group_audit_logs",
        type_="foreignkey",
    )
    op.alter_column(
        "group_audit_logs", "performed_by_id", existing_type=sa.UUID(), nullable=True
    )
    op.create_foreign_key(
        "group_audit_logs_performed_by_id_fkey",
        "group_audit_logs",
        "users",
        ["performed_by_id"],
        ["id"],
        ondelete="SET NULL",
    )

    # ── A ban outlives the account it was placed on ──────────────────────────
    op.add_column(
        "platform_bans",
        sa.Column(
            "phone_hash",
            sa.String(64),
            nullable=True,
            comment=(
                "Salted SHA-256 of the banned phone number, written when the "
                "account is deleted so the ban cannot be evaded by deleting "
                "and re-registering. Never the number itself."
            ),
        ),
    )
    op.create_index(
        "ix_platform_bans_phone_hash",
        "platform_bans",
        ["phone_hash"],
        postgresql_where=sa.text("phone_hash IS NOT NULL"),
    )

    op.drop_constraint(
        "platform_bans_user_id_fkey", "platform_bans", type_="foreignkey"
    )
    op.alter_column(
        "platform_bans", "user_id", existing_type=sa.UUID(), nullable=True
    )
    op.create_foreign_key(
        "platform_bans_user_id_fkey",
        "platform_bans",
        "users",
        ["user_id"],
        ["id"],
        ondelete="SET NULL",
    )

    # The old uniqueness was one ban per user, which a NULL user_id no longer
    # constrains — Postgres treats NULLs as distinct. Replaced with a partial
    # index so the rule still holds for live accounts, plus one on the hash so a
    # deleted-and-rebanned number cannot accumulate duplicates.
    op.drop_constraint("uq_platform_ban_user", "platform_bans", type_="unique")
    op.create_index(
        "uq_platform_ban_user",
        "platform_bans",
        ["user_id"],
        unique=True,
        postgresql_where=sa.text("user_id IS NOT NULL"),
    )
    op.create_index(
        "uq_platform_ban_phone",
        "platform_bans",
        ["phone_hash"],
        unique=True,
        postgresql_where=sa.text("phone_hash IS NOT NULL"),
    )

    # ── The banned_by reference has the same problem, one step removed ───────
    # An admin deleting their own account should not delete the bans they
    # issued, which would silently unban everyone they had ever acted against.
    op.drop_constraint(
        "platform_bans_banned_by_id_fkey", "platform_bans", type_="foreignkey"
    )
    op.alter_column(
        "platform_bans", "banned_by_id", existing_type=sa.UUID(), nullable=True
    )
    op.create_foreign_key(
        "platform_bans_banned_by_id_fkey",
        "platform_bans",
        "users",
        ["banned_by_id"],
        ["id"],
        ondelete="SET NULL",
    )


def downgrade() -> None:
    op.drop_constraint(
        "platform_bans_banned_by_id_fkey", "platform_bans", type_="foreignkey"
    )
    op.alter_column(
        "platform_bans", "banned_by_id", existing_type=sa.UUID(), nullable=False
    )
    op.create_foreign_key(
        "platform_bans_banned_by_id_fkey",
        "platform_bans",
        "users",
        ["banned_by_id"],
        ["id"],
        ondelete="CASCADE",
    )

    op.drop_index("uq_platform_ban_phone", table_name="platform_bans")
    op.drop_index("uq_platform_ban_user", table_name="platform_bans")
    # Rows orphaned by a deletion cannot be restored to a user, so they are
    # removed rather than left violating the NOT NULL this restores. Stated
    # rather than silent: downgrading past this migration discards bans whose
    # account is gone.
    op.execute("DELETE FROM platform_bans WHERE user_id IS NULL")
    op.create_unique_constraint(
        "uq_platform_ban_user", "platform_bans", ["user_id"]
    )

    op.drop_constraint(
        "platform_bans_user_id_fkey", "platform_bans", type_="foreignkey"
    )
    op.alter_column(
        "platform_bans", "user_id", existing_type=sa.UUID(), nullable=False
    )
    op.create_foreign_key(
        "platform_bans_user_id_fkey",
        "platform_bans",
        "users",
        ["user_id"],
        ["id"],
        ondelete="CASCADE",
    )

    op.drop_index("ix_platform_bans_phone_hash", table_name="platform_bans")
    op.drop_column("platform_bans", "phone_hash")

    op.drop_constraint(
        "group_audit_logs_performed_by_id_fkey",
        "group_audit_logs",
        type_="foreignkey",
    )
    op.execute("DELETE FROM group_audit_logs WHERE performed_by_id IS NULL")
    op.alter_column(
        "group_audit_logs", "performed_by_id", existing_type=sa.UUID(), nullable=False
    )
    op.create_foreign_key(
        "group_audit_logs_performed_by_id_fkey",
        "group_audit_logs",
        "users",
        ["performed_by_id"],
        ["id"],
        ondelete="CASCADE",
    )
