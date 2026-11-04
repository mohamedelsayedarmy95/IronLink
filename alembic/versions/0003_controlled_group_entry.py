"""Controlled group entry: verification forms, audit log, bans

Adds the admin-defined verification form system described in the Controlled
Group Entry spec, plus the audit trail and ban tables it depends on.

Deviation from the spec worth recording: the spec names the requests table
`join_requests`, but `group_join_requests` already exists and is deployed
under 0001. This migration extends that table rather than creating a parallel
one — a rename would break the live database and every existing query for no
functional gain.

Likewise `groups.join_approval_required` is kept alongside the new
`join_mode`. Dropping it would break any client still reading it; it is
backfilled here and kept in sync by the application on write.

Revision ID: 0003_controlled_group_entry
Revises: 0002_e2ee_public_key_directory
Create Date: 2026-08-14
"""
from __future__ import annotations

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = '0003_controlled_group_entry'
down_revision: str | None = '0002_e2ee_public_key_directory'
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # ── Verification forms ────────────────────────────────────────────────
    op.create_table(
        'verification_forms',
        sa.Column('id', postgresql.UUID(as_uuid=True),
                  server_default=sa.text('gen_random_uuid()'), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True),
                  server_default=sa.text('NOW()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True),
                  server_default=sa.text('NOW()'), nullable=False),
        sa.Column('name', sa.String(length=255), nullable=False),
        sa.Column('description', sa.Text(), nullable=True),
        sa.Column('is_template', sa.Boolean(), server_default='false', nullable=False),
        sa.Column('created_by_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.ForeignKeyConstraint(['created_by_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_verification_forms_created_by', 'verification_forms',
                    ['created_by_id'])
    op.create_index('ix_verification_forms_template', 'verification_forms',
                    ['is_template'])

    op.create_table(
        'verification_form_fields',
        sa.Column('id', postgresql.UUID(as_uuid=True),
                  server_default=sa.text('gen_random_uuid()'), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True),
                  server_default=sa.text('NOW()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True),
                  server_default=sa.text('NOW()'), nullable=False),
        sa.Column('form_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('field_type', sa.String(length=50), nullable=False),
        sa.Column('label', sa.Text(), nullable=False),
        sa.Column('placeholder', sa.Text(), nullable=True),
        sa.Column('helper_text', sa.Text(), nullable=True),
        sa.Column('is_required', sa.Boolean(), server_default='true', nullable=False),
        sa.Column('validation_rules', postgresql.JSONB(), nullable=True),
        sa.Column('options', postgresql.JSONB(), nullable=True),
        sa.Column('icon', sa.String(length=50), nullable=True),
        sa.Column('order_index', sa.Integer(), server_default='0', nullable=False),
        sa.ForeignKeyConstraint(['form_id'], ['verification_forms.id'],
                                ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        # A duplicated order would make the rendered field sequence depend on
        # insertion order, which is not stable across reads.
        sa.UniqueConstraint('form_id', 'order_index', name='uq_form_field_order'),
    )
    op.create_index('ix_form_fields_form_order', 'verification_form_fields',
                    ['form_id', 'order_index'])

    # ── Group columns ─────────────────────────────────────────────────────
    op.add_column('groups', sa.Column(
        'join_mode', sa.String(length=20),
        server_default='request_approval', nullable=False))
    op.add_column('groups', sa.Column(
        'verification_form_id', postgresql.UUID(as_uuid=True), nullable=True))
    op.add_column('groups', sa.Column(
        'request_expiry_days', sa.Integer(), server_default='14', nullable=False))
    op.add_column('groups', sa.Column(
        'allow_rejoin', sa.Boolean(), server_default='false', nullable=False))
    op.create_foreign_key(
        'fk_groups_verification_form', 'groups', 'verification_forms',
        ['verification_form_id'], ['id'], ondelete='SET NULL')
    op.create_index('ix_groups_join_mode', 'groups', ['join_mode'])

    # Derive join_mode from the legacy boolean so existing groups keep their
    # current behaviour instead of silently switching to approval-required.
    op.execute("""
        UPDATE groups
           SET join_mode = CASE
               WHEN join_approval_required THEN 'request_approval'
               ELSE 'open'
           END
    """)

    # ── Join request columns ──────────────────────────────────────────────
    op.add_column('group_join_requests', sa.Column(
        'form_id', postgresql.UUID(as_uuid=True), nullable=True))
    op.add_column('group_join_requests', sa.Column(
        'answers', postgresql.JSONB(), nullable=True))
    op.add_column('group_join_requests', sa.Column(
        'admin_notes', sa.Text(), nullable=True))
    op.add_column('group_join_requests', sa.Column(
        'rejection_reason', sa.Text(), nullable=True))
    op.add_column('group_join_requests', sa.Column(
        'expires_at', sa.DateTime(timezone=True), nullable=True))
    op.create_foreign_key(
        'fk_join_requests_form', 'group_join_requests', 'verification_forms',
        ['form_id'], ['id'], ondelete='SET NULL')
    op.create_index('ix_join_req_expires', 'group_join_requests', ['expires_at'])

    # ── Audit log ─────────────────────────────────────────────────────────
    op.create_table(
        'group_audit_logs',
        sa.Column('id', postgresql.UUID(as_uuid=True),
                  server_default=sa.text('gen_random_uuid()'), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True),
                  server_default=sa.text('NOW()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True),
                  server_default=sa.text('NOW()'), nullable=False),
        sa.Column('group_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('action', sa.String(length=50), nullable=False),
        sa.Column('performed_by_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('target_user_id', postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column('details', postgresql.JSONB(), nullable=True),
        sa.ForeignKeyConstraint(['group_id'], ['groups.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['performed_by_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['target_user_id'], ['users.id'], ondelete='SET NULL'),
        sa.PrimaryKeyConstraint('id'),
    )
    op.create_index('ix_audit_group_created', 'group_audit_logs',
                    ['group_id', 'created_at'])
    op.create_index('ix_audit_performed_by', 'group_audit_logs', ['performed_by_id'])
    op.create_index('ix_audit_group_action', 'group_audit_logs',
                    ['group_id', 'action'])

    # ── Bans ──────────────────────────────────────────────────────────────
    op.create_table(
        'group_bans',
        sa.Column('id', postgresql.UUID(as_uuid=True),
                  server_default=sa.text('gen_random_uuid()'), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True),
                  server_default=sa.text('NOW()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True),
                  server_default=sa.text('NOW()'), nullable=False),
        sa.Column('group_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('banned_by_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('reason', sa.Text(), nullable=True),
        sa.Column('is_permanent', sa.Boolean(), server_default='true', nullable=False),
        sa.Column('expires_at', sa.DateTime(timezone=True), nullable=True),
        sa.ForeignKeyConstraint(['group_id'], ['groups.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['banned_by_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('group_id', 'user_id', name='uq_group_ban_user'),
    )
    op.create_index('ix_group_bans_group_user', 'group_bans', ['group_id', 'user_id'])

    op.create_table(
        'platform_bans',
        sa.Column('id', postgresql.UUID(as_uuid=True),
                  server_default=sa.text('gen_random_uuid()'), nullable=False),
        sa.Column('created_at', sa.DateTime(timezone=True),
                  server_default=sa.text('NOW()'), nullable=False),
        sa.Column('updated_at', sa.DateTime(timezone=True),
                  server_default=sa.text('NOW()'), nullable=False),
        sa.Column('user_id', postgresql.UUID(as_uuid=True), nullable=False),
        sa.Column('banned_by_id', postgresql.UUID(as_uuid=True), nullable=False),
        # NOT NULL unlike group_bans.reason: a platform-wide restriction is
        # severe enough that an unexplained one should be impossible to create.
        sa.Column('reason', sa.Text(), nullable=False),
        sa.ForeignKeyConstraint(['user_id'], ['users.id'], ondelete='CASCADE'),
        sa.ForeignKeyConstraint(['banned_by_id'], ['users.id'], ondelete='CASCADE'),
        sa.PrimaryKeyConstraint('id'),
        sa.UniqueConstraint('user_id', name='uq_platform_ban_user'),
    )


def downgrade() -> None:
    op.drop_table('platform_bans')
    op.drop_index('ix_group_bans_group_user', table_name='group_bans')
    op.drop_table('group_bans')

    op.drop_index('ix_audit_group_action', table_name='group_audit_logs')
    op.drop_index('ix_audit_performed_by', table_name='group_audit_logs')
    op.drop_index('ix_audit_group_created', table_name='group_audit_logs')
    op.drop_table('group_audit_logs')

    op.drop_index('ix_join_req_expires', table_name='group_join_requests')
    op.drop_constraint('fk_join_requests_form', 'group_join_requests',
                       type_='foreignkey')
    op.drop_column('group_join_requests', 'expires_at')
    op.drop_column('group_join_requests', 'rejection_reason')
    op.drop_column('group_join_requests', 'admin_notes')
    op.drop_column('group_join_requests', 'answers')
    op.drop_column('group_join_requests', 'form_id')

    op.drop_index('ix_groups_join_mode', table_name='groups')
    op.drop_constraint('fk_groups_verification_form', 'groups', type_='foreignkey')
    op.drop_column('groups', 'allow_rejoin')
    op.drop_column('groups', 'request_expiry_days')
    op.drop_column('groups', 'verification_form_id')
    op.drop_column('groups', 'join_mode')

    op.drop_index('ix_form_fields_form_order', table_name='verification_form_fields')
    op.drop_table('verification_form_fields')
    op.drop_index('ix_verification_forms_template', table_name='verification_forms')
    op.drop_index('ix_verification_forms_created_by', table_name='verification_forms')
    op.drop_table('verification_forms')
