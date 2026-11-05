"""Retain immutable channel media scope across post/channel deletion."""
from alembic import op
import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

revision = '0014_channel_media_keys'
down_revision = '0013_webauthn_credentials'
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        'channel_media_keys',
        sa.Column('id', postgresql.UUID(as_uuid=True), primary_key=True,
                  server_default=sa.text('gen_random_uuid()')),
        sa.Column('media_key', sa.String(255), nullable=False, unique=True),
        sa.Column('channel_id', postgresql.UUID(as_uuid=True), nullable=True),
        sa.Column('created_at', sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text('NOW()')),
        sa.Column('updated_at', sa.DateTime(timezone=True), nullable=False,
                  server_default=sa.text('NOW()')),
        sa.ForeignKeyConstraint(['channel_id'], ['channels.id'], ondelete='SET NULL'),
    )
    op.create_index('ix_channel_media_keys_channel_id', 'channel_media_keys', ['channel_id'])
    # Ambiguous historical keys spanning channels fail closed. Re-uploading
    # under a fresh key resolves these without guessing an access policy.
    op.execute('''
        INSERT INTO channel_media_keys (media_key, channel_id)
        SELECT media_key,
               CASE WHEN count(DISTINCT channel_id) = 1
                    THEN (array_agg(channel_id))[1] ELSE NULL END
        FROM channel_posts WHERE media_key IS NOT NULL GROUP BY media_key
    ''')


def downgrade() -> None:
    op.drop_index('ix_channel_media_keys_channel_id', table_name='channel_media_keys')
    op.drop_table('channel_media_keys')
