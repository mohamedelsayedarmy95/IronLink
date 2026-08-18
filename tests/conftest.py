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


def _test_database_url() -> str | None:
    return os.environ.get("TEST_DATABASE_URL")


requires_db = pytest.mark.skipif(
    _test_database_url() is None,
    reason="TEST_DATABASE_URL is not set; CI provides one",
)


@pytest_asyncio.fixture(scope="session")
async def db_engine():
    url = _test_database_url()
    if url is None:
        pytest.skip("TEST_DATABASE_URL is not set")

    from sqlalchemy.ext.asyncio import create_async_engine

    from app.models.base import Base
    import app.models  # noqa: F401 — registers every table on the metadata

    engine = create_async_engine(url, future=True)
    async with engine.begin() as conn:
        # create_all rather than `alembic upgrade head`. The migrations are
        # tested separately for being additive; what these journeys need is the
        # schema the models currently describe, and running migrations here
        # would make an unrelated migration bug fail every journey test.
        await conn.run_sync(Base.metadata.create_all)
    yield engine
    await engine.dispose()


@pytest_asyncio.fixture()
async def db(db_engine):
    """A session whose writes are rolled back when the test ends.

    Rollback rather than truncation: it is faster, and it means two tests
    cannot leak state into each other even if one fails part-way through.
    """
    from sqlalchemy.ext.asyncio import AsyncSession

    async with db_engine.connect() as conn:
        transaction = await conn.begin()
        session = AsyncSession(bind=conn, expire_on_commit=False)
        try:
            yield session
        finally:
            await session.close()
            await transaction.rollback()
