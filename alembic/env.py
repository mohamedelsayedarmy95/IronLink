from __future__ import annotations

import asyncio
from logging.config import fileConfig

from sqlalchemy import pool
from sqlalchemy.engine import Connection
from sqlalchemy.ext.asyncio import async_engine_from_config

from alembic import context

from app.config import settings
from app.models import Base   # noqa: F401 — imports all models so metadata is populated

config = context.config
# Online migrations run through async_engine_from_config, which rejects a sync
# driver ("the asyncio extension requires an async driver"), so the configured
# URL must be the asyncpg one. Offline mode only renders SQL.
# Startup supplies its validated owner URL. Standalone Alembic remains usable
# for offline rendering/test tooling; restricted runtime cannot perform DDL.
migration_url = config.attributes.get("database_url")
if migration_url is None:
    migration_url = (
        settings.migration_connection_url().render_as_string(hide_password=False)
        if settings.MIGRATION_DATABASE_URL or settings.MIGRATION_POSTGRES_USER
        else settings.database_url
    )
# ConfigParser treats percent-encoded credentials as interpolation syntax.
config.set_main_option("sqlalchemy.url", migration_url.replace("%", "%%"))

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

target_metadata = Base.metadata


def run_migrations_offline() -> None:
    context.configure(
        url=migration_url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        compare_type=True,
        compare_server_default=True,
    )
    with context.begin_transaction():
        context.run_migrations()


def do_run_migrations(connection: Connection) -> None:
    context.configure(
        connection=connection,
        target_metadata=target_metadata,
        compare_type=True,
        compare_server_default=True,
    )
    with context.begin_transaction():
        context.run_migrations()


async def run_async_migrations() -> None:
    connectable = async_engine_from_config(
        config.get_section(config.config_ini_section, {}),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )
    async with connectable.connect() as connection:
        await connection.exec_driver_sql("SET search_path TO public")
        await connection.commit()
        await connection.run_sync(do_run_migrations)
    await connectable.dispose()


def run_migrations_online() -> None:
    connection = config.attributes.get("connection")
    if connection is not None:
        do_run_migrations(connection)
    else:
        asyncio.run(run_async_migrations())


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
