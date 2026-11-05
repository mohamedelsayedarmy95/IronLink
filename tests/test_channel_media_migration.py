"""Real PG16 upgrade/backfill, retained deletion scope and reversible DDL."""
from uuid import uuid4

from alembic import command
from sqlalchemy import create_engine, inspect, select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session
import pytest

from app.core import database_bootstrap as bootstrap
from app.core.database_config import sync_url
from app.models import Channel, ChannelMediaKey, ChannelPost, User
from tests.test_postgres_bootstrap import database  # noqa: F401 — isolated cluster fixture


def test_channel_media_migration_backfill_constraints_and_roundtrip(database):
    owner_url = database.migration_connection_url()
    engine = create_engine(sync_url(owner_url))
    config = bootstrap.alembic_config()
    config.attributes['database_url'] = owner_url.render_as_string(hide_password=False)
    try:
        with engine.connect() as conn:
            config.attributes['connection'] = conn
            command.upgrade(config, '0013_webauthn_credentials')
        with Session(engine, expire_on_commit=False) as db:
            user = User(phone_number='synthetic-' + uuid4().hex[:10], full_name='migration',
                        hashed_password='synthetic', hashed_military_id='synthetic')
            db.add(user)
            db.flush()
            private = Channel(name='private', owner_id=user.id, channel_type='private')
            public = Channel(name='public', owner_id=user.id, channel_type='public')
            db.add_all([private, public])
            db.flush()
            for key, ch in [('single', private), ('duplicate', private), ('duplicate', private),
                            ('ambiguous', private), ('ambiguous', public)]:
                db.add(ChannelPost(channel_id=ch.id, author_id=user.id, content='synthetic', media_key=key))
            db.commit()
            private_id = private.id
        with engine.connect() as conn:
            config.attributes['connection'] = conn
            command.upgrade(config, 'head')
            rows = dict(conn.execute(select(ChannelMediaKey.media_key, ChannelMediaKey.channel_id)).all())
            assert rows == {'single': private_id, 'duplicate': private_id, 'ambiguous': None}
            with pytest.raises(IntegrityError):
                with conn.begin_nested():
                    conn.execute(text("INSERT INTO channel_media_keys (media_key) VALUES ('single')"))
            conn.execute(text('DELETE FROM channels WHERE id=:id'), {'id': private_id})
            conn.commit()
            assert conn.execute(text("SELECT channel_id FROM channel_media_keys WHERE media_key='single'")).one() == (None,)
            assert conn.scalar(text('SELECT count(*) FROM channel_media_keys')) == 3
            conn.commit()
            command.downgrade(config, '0013_webauthn_credentials')
            assert not inspect(conn).has_table('channel_media_keys')
            conn.commit()
            command.upgrade(config, 'head')
            assert inspect(conn).has_table('channel_media_keys')
            conn.commit()
            command.downgrade(config, 'base')
            assert not inspect(conn).has_table('channels')
            conn.commit()
            command.upgrade(config, 'head')
            assert conn.scalar(text('SELECT count(*) FROM channel_media_keys')) == 0
    finally:
        engine.dispose()
