from __future__ import annotations

import os

# Set required env vars BEFORE app.config is imported anywhere.
os.environ.setdefault("POSTGRES_PASSWORD", "test_pg_password")
os.environ.setdefault("REDIS_PASSWORD", "test_redis_password")
os.environ.setdefault("MINIO_ROOT_PASSWORD", "test_minio_password")
os.environ.setdefault("DB_ENCRYPTION_KEY", "test_encryption_key_32_chars_min_xx")
os.environ.setdefault("SECRET_KEY", "test_secret_key_for_jwt_signing_only_in_tests_xxxxxxxxxxxxxxxxxxx")
os.environ.setdefault("CONTACT_HASH_SALT", "test_contact_salt_at_least_32_chars_long_xx")


# ── A real database, for the journeys that need one ──────────────────────────
#
# Every other test in this suite runs against fakes, which is what keeps it
# fast and what lets it assert on failure paths — an unreachable Redis is
# easier to fake than to arrange. But a fake cannot answer the question an
# end-to-end journey asks: does a message survive a send, a delivery, a
# retraction, and a history read, through the real schema?
#
# So this is Postgres and not SQLite. The models use `postgresql.UUID` and
# `postgresql.JSONB`, and a SQLite stand-in would either fail to create the
# schema or silently accept types the real database rejects — a test that
# passes against a database the product does not use is worse than no test.
#
# Skipped, not failed, when there is nothing to connect to. A developer
# without a local Postgres should still get the other 400 tests; CI provides
# one, so the journeys always run somewhere.

import pytest
import pytest_asyncio


def pytest_sessionfinish(session, exitstatus):
    if os.environ.get("IRONLINK_REQUIRE_POSTGRES_SECURITY") == "1":
        reporter = session.config.pluginmanager.get_plugin("terminalreporter")
        # The mandatory invocation contains only security tests. Any skip,
        # including setup or collection skips, invalidates the entire gate.
        if (reporter is None or not os.environ.get("IRONLINK_TEST_ADMIN_URL") or
                session.testscollected == 0 or (reporter and any(
                    reporter.stats.get(kind) for kind in ("skipped", "xfailed", "deselected")))):
            session.exitstatus = pytest.ExitCode.TESTS_FAILED


def _test_database_url() -> str | None:
    return os.environ.get("TEST_DATABASE_URL")


requires_db = pytest.mark.skipif(
    _test_database_url() is None,
    reason="TEST_DATABASE_URL is not set; CI provides one",
)


@pytest_asyncio.fixture()
async def db():
    """A session on a real database, rolled back when the test ends.

    The engine is built **per test**, which looks wasteful and is not.
    pytest-asyncio gives every test its own event loop, and an asyncpg
    connection belongs to the loop that opened it — a session-scoped engine
    hands the second test a connection from the first test's loop, which fails
    as "another operation is in progress" or "attached to a different loop".
    Those errors name the symptom and not the cause, and chasing them costs
    far more than the engine setup this avoids.

    `create_all` runs with `checkfirst`, so only the first test in a run
    actually issues DDL and the rest pay one round trip of introspection.

    Writes are rolled back rather than truncated: faster, and two tests cannot
    leak into each other even when one fails part-way through.
    """
    url = _test_database_url()
    if url is None:
        pytest.skip("TEST_DATABASE_URL is not set")

    from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine

    import app.models  # noqa: F401 — registers every table on the metadata
    from app.models.base import Base

    engine = create_async_engine(url, future=True)
    try:
        async with engine.begin() as conn:
            # create_all rather than `alembic upgrade head`. The migrations are
            # tested separately for being additive; what these journeys need is
            # the schema the models describe, and running migrations here would
            # make one unrelated migration bug fail every journey.
            await conn.run_sync(Base.metadata.create_all)
            # The old retention tests exercise the real bounded SQL function
            # inside their rollback transaction. This owner-only fixture is not
            # used as evidence of runtime permissions; test_postgres_bootstrap
            # verifies those using independent, non-superuser connections.
            from sqlalchemy import text
            from app.core.database_bootstrap import retention_function_sql
            from app.config import settings
            await conn.execute(text("CREATE SCHEMA IF NOT EXISTS ironlink_maintenance"))
            await conn.execute(text(retention_function_sql(settings.AUDIT_LOG_RETENTION_DAYS)))
            await conn.execute(text(
                "REVOKE ALL ON FUNCTION ironlink_maintenance.prune_audit_logs(timestamptz) FROM PUBLIC"
            ))

        async with engine.connect() as conn:
            transaction = await conn.begin()
            session = AsyncSession(bind=conn, expire_on_commit=False)
            try:
                yield session
            finally:
                await session.close()
                await transaction.rollback()
    finally:
        await engine.dispose()
