"""H-04A-S: key-directory retries, consumption and identity-scoped tombstones.

The bug these tests pin down: a bundle upload re-inserted every pre-key it
carried. Retrying an upload whose response was lost therefore raised
`uq_one_time_prekey_user_key`, and retrying after the keys had been consumed
put them back into the directory. Both outcomes break the single-use promise
of X3DH pre-keys.

The real HTTP routes and the real PostgreSQL schema are used. Identical
uploads must be idempotent; conflicting material under a reused key id must be
rejected; consumed keys must never become available again.
"""
from __future__ import annotations

import asyncio
import base64
import os
from types import SimpleNamespace
from uuid import uuid4

import httpx
import pytest
import pytest_asyncio
from fastapi import FastAPI
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.api.deps import get_current_user
from app.api.routes import keys
from app.core.database import get_db
from app.models import (
    ConsumedOneTimePreKey,
    OneTimePreKey,
    User,
    UserKeyBundle,
)
from app.models.base import Base
from tests.conftest import requires_db

pytestmark = [requires_db, pytest.mark.asyncio]


def _b64(n: int = 33, seed: int = 1) -> str:
    return base64.b64encode(
        bytes(((seed + i) % 256) for i in range(n))
    ).decode()


def _prekey(key_id: int, seed: int) -> dict:
    return {"key_id": key_id, "public_key": _b64(33, seed)}


IDENTITY_A = _b64(33, 1)
IDENTITY_B = _b64(33, 2)
SIGNED_A = _b64(33, 10)
SIGNED_B = _b64(33, 12)
SIGNATURE_A = _b64(64, 20)
SIGNATURE_B = _b64(64, 22)
PREKEYS_A = [_prekey(1, 100), _prekey(2, 110), _prekey(3, 120)]
PUBLIC_A = {pk["key_id"]: pk["public_key"] for pk in PREKEYS_A}


def _payload(
    *,
    identity: str = IDENTITY_A,
    signed_id: int = 1,
    signed_public: str = SIGNED_A,
    signature: str = SIGNATURE_A,
    prekeys: list[dict] | None = None,
) -> keys.KeyBundleUpload:
    return keys.KeyBundleUpload(
        registration_id=4242,
        identity_key=identity,
        signed_prekey_id=signed_id,
        signed_prekey_public=signed_public,
        signed_prekey_signature=signature,
        one_time_prekeys=PREKEYS_A if prekeys is None else prekeys,
    )


def _new_user(name: str) -> User:
    return User(
        phone_number="+999" + str(uuid4().int)[:15],
        full_name=f"H04AS {name}",
        hashed_military_id="synthetic",
        hashed_password="synthetic",
    )


class _FlushOnCommit:
    """Keep the test's outer transaction open while the route commits.

    The routes commit explicitly so a live 204 never precedes the database
    commit. Tests still need rollback isolation, so commit is mapped to flush:
    the SQL is exercised, while the fixture's outer transaction still owns the
    final rollback.
    """

    def __init__(self, session):
        self._session = session

    def __getattr__(self, name):
        return getattr(self._session, name)

    async def commit(self) -> None:
        await self._session.flush()


@pytest_asyncio.fixture
async def world(db):
    app = FastAPI()
    app.include_router(keys.router, prefix="/api/v1")
    current = {"user": None}

    async def database():
        yield _FlushOnCommit(db)

    async def who():
        return current["user"]

    app.dependency_overrides[get_db] = database
    app.dependency_overrides[get_current_user] = who

    owner = _new_user("owner")
    sender = _new_user("sender")
    db.add_all([owner, sender])
    await db.flush()

    async with httpx.AsyncClient(
        transport=httpx.ASGITransport(app=app),
        base_url="http://test",
    ) as client:
        yield SimpleNamespace(
            client=client,
            db=db,
            owner=owner,
            sender=sender,
            current=current,
        )


def _as(world, user: User) -> None:
    world.current["user"] = user


async def _publish(world, user: User, body: keys.KeyBundleUpload):
    _as(world, user)
    return await world.client.post(
        "/api/v1/keys/bundle", json=body.model_dump()
    )


async def _replenish(world, user: User, body: keys.PreKeysUpload):
    _as(world, user)
    return await world.client.post(
        "/api/v1/keys/prekeys", json=body.model_dump()
    )


async def _fetch(world, viewer: User, target_id):
    _as(world, viewer)
    return await world.client.get(f"/api/v1/keys/bundle/{target_id}")


async def _active_ids(world, user: User) -> list[int]:
    rows = await world.db.execute(
        select(OneTimePreKey.key_id)
        .where(OneTimePreKey.user_id == user.id)
        .order_by(OneTimePreKey.key_id)
    )
    return list(rows.scalars().all())


async def _active_material(world, user: User) -> dict[int, str]:
    rows = await world.db.execute(
        select(OneTimePreKey.key_id, OneTimePreKey.public_key)
        .where(OneTimePreKey.user_id == user.id)
    )
    return {row.key_id: row.public_key for row in rows}


async def _consumed_ids(
    world, user: User, identity_key: str
) -> list[int]:
    rows = await world.db.execute(
        select(ConsumedOneTimePreKey.key_id)
        .where(
            ConsumedOneTimePreKey.user_id == user.id,
            ConsumedOneTimePreKey.identity_key == identity_key,
        )
        .order_by(ConsumedOneTimePreKey.key_id)
    )
    return list(rows.scalars().all())


async def _consume_all(world, viewer: User, owner: User) -> list[int]:
    claimed: list[int] = []
    for _ in range(3):
        response = await _fetch(world, viewer, owner.id)
        assert response.status_code == 200, response.text
        claimed.append(response.json()["one_time_prekey_id"])
    return claimed


# ── The nine required scenarios ───────────────────────────────────────────────


async def test_first_publication_persists_public_bundle_and_prekeys(world):
    response = await _publish(world, world.owner, _payload())
    assert response.status_code == 204, response.text

    bundle = await world.db.scalar(
        select(UserKeyBundle).where(UserKeyBundle.user_id == world.owner.id)
    )
    assert bundle is not None
    assert bundle.identity_key == IDENTITY_A
    assert bundle.signed_prekey_id == 1
    assert bundle.signed_prekey_public == SIGNED_A
    assert await _active_ids(world, world.owner) == [1, 2, 3]
    assert await _consumed_ids(world, world.owner, IDENTITY_A) == []


async def test_identical_retry_is_idempotent(world):
    body = _payload()
    assert (await _publish(world, world.owner, body)).status_code == 204
    response = await _publish(world, world.owner, body)
    assert response.status_code == 204, response.text
    assert await _active_ids(world, world.owner) == [1, 2, 3]

    count = await world.db.scalar(
        select(func.count())
        .select_from(OneTimePreKey)
        .where(OneTimePreKey.user_id == world.owner.id)
    )
    assert count == 3, "an idempotent retry must not duplicate pre-key rows"


async def test_response_lost_retry_is_idempotent(world):
    """The server committed, but the client never saw the 204."""
    body = _payload()
    assert (await _publish(world, world.owner, body)).status_code == 204

    # The client still believes it is unpublished and retries the same body.
    response = await _publish(world, world.owner, body)
    assert response.status_code == 204, response.text

    bundle = await world.db.scalar(
        select(UserKeyBundle).where(UserKeyBundle.user_id == world.owner.id)
    )
    assert bundle.identity_key == IDENTITY_A
    assert await _active_ids(world, world.owner) == [1, 2, 3]


async def test_retry_after_consumption_does_not_resurrect_keys(world):
    body = _payload()
    assert (await _publish(world, world.owner, body)).status_code == 204
    claimed = await _consume_all(world, world.sender, world.owner)
    assert sorted(claimed) == [1, 2, 3]
    assert await _active_ids(world, world.owner) == []
    assert await _consumed_ids(world, world.owner, IDENTITY_A) == [1, 2, 3]

    response = await _publish(world, world.owner, body)
    assert response.status_code == 204, response.text
    assert await _active_ids(world, world.owner) == [], (
        "a bundle retry must not re-advertise consumed pre-keys"
    )

    exhausted = await _fetch(world, world.sender, world.owner.id)
    assert exhausted.status_code == 200
    assert exhausted.json()["one_time_prekey_id"] is None


async def test_bundle_retry_without_tombstones_still_does_not_resurrect(world):
    """Pre-0015 consumption left no tombstone; the retry must still be safe."""
    body = _payload()
    assert (await _publish(world, world.owner, body)).status_code == 204
    assert sorted(await _consume_all(world, world.sender, world.owner)) == [1, 2, 3]

    # Simulate keys consumed before this migration existed: delete the evidence
    # that a modern server would have. The bundle endpoint's same-identity rule
    # must still refuse to insert the keys.
    await world.db.execute(
        delete(ConsumedOneTimePreKey).where(
            ConsumedOneTimePreKey.user_id == world.owner.id
        )
    )
    await world.db.flush()
    assert await _active_ids(world, world.owner) == []

    response = await _publish(world, world.owner, body)
    assert response.status_code == 204, response.text
    assert await _active_ids(world, world.owner) == []
    exhausted = await _fetch(world, world.sender, world.owner.id)
    assert exhausted.status_code == 200
    assert exhausted.json()["one_time_prekey_id"] is None


async def test_signed_prekey_rotation_preserves_active_prekeys(world):
    assert (await _publish(world, world.owner, _payload())).status_code == 204
    first = await _fetch(world, world.sender, world.owner.id)
    consumed = first.json()["one_time_prekey_id"]
    assert consumed is not None

    rotated = _payload(
        signed_id=2,
        signed_public=SIGNED_B,
        signature=SIGNATURE_B,
        prekeys=[],
    )
    response = await _publish(world, world.owner, rotated)
    assert response.status_code == 204, response.text

    bundle = await world.db.scalar(
        select(UserKeyBundle).where(UserKeyBundle.user_id == world.owner.id)
    )
    assert bundle.signed_prekey_id == 2
    assert bundle.signed_prekey_public == SIGNED_B
    assert await _active_ids(world, world.owner) == sorted(
        {1, 2, 3} - {consumed}
    )
    assert await _consumed_ids(world, world.owner, IDENTITY_A) == [consumed]


async def test_replenishment_adds_only_new_keys_and_is_idempotent(world):
    assert (await _publish(world, world.owner, _payload())).status_code == 204
    addition = keys.PreKeysUpload(
        one_time_prekeys=[_prekey(4, 140), _prekey(5, 150)]
    )
    assert (await _replenish(world, world.owner, addition)).status_code == 204
    assert await _active_ids(world, world.owner) == [1, 2, 3, 4, 5]

    # A dropped replenishment response is retried with the same body.
    assert (await _replenish(world, world.owner, addition)).status_code == 204
    assert await _active_ids(world, world.owner) == [1, 2, 3, 4, 5]

    first = await _fetch(world, world.sender, world.owner.id)
    consumed = first.json()["one_time_prekey_id"]
    assert consumed is not None

    # Replaying the replenishment after one of its keys was claimed must not
    # put that key back.
    assert (await _replenish(world, world.owner, addition)).status_code == 204
    assert await _active_ids(world, world.owner) == sorted(
        {1, 2, 3, 4, 5} - {consumed}
    )


async def test_conflicting_material_under_reused_key_id_is_rejected(world):
    assert (await _publish(world, world.owner, _payload())).status_code == 204

    active_conflict = keys.PreKeysUpload(
        one_time_prekeys=[_prekey(2, 999)]
    )
    response = await _replenish(world, world.owner, active_conflict)
    assert response.status_code == 409, response.text

    bundle_conflict = _payload(prekeys=[_prekey(2, 999)])
    response = await _publish(world, world.owner, bundle_conflict)
    assert response.status_code == 409, response.text

    first = await _fetch(world, world.sender, world.owner.id)
    consumed = first.json()["one_time_prekey_id"]
    assert consumed is not None

    consumed_conflict = keys.PreKeysUpload(
        one_time_prekeys=[_prekey(consumed, 999)]
    )
    response = await _replenish(world, world.owner, consumed_conflict)
    assert response.status_code == 409, response.text

    same_material = keys.PreKeysUpload(
        one_time_prekeys=[_prekey(consumed, 100 + (consumed - 1) * 10)]
    )
    assert same_material.one_time_prekeys[0].public_key == PUBLIC_A[consumed]
    response = await _replenish(world, world.owner, same_material)
    assert response.status_code == 204, response.text
    assert consumed not in await _active_ids(world, world.owner)


async def test_identity_change_is_identity_scoped(world):
    assert (await _publish(world, world.owner, _payload())).status_code == 204
    first = await _fetch(world, world.sender, world.owner.id)
    consumed = first.json()["one_time_prekey_id"]
    assert consumed is not None

    prekeys_b = [_prekey(1, 300), _prekey(2, 310), _prekey(3, 320)]
    body_b = _payload(
        identity=IDENTITY_B,
        signed_public=_b64(33, 14),
        signature=_b64(64, 24),
        prekeys=prekeys_b,
    )
    response = await _publish(world, world.owner, body_b)
    assert response.status_code == 204, response.text

    bundle = await world.db.scalar(
        select(UserKeyBundle).where(UserKeyBundle.user_id == world.owner.id)
    )
    assert bundle.identity_key == IDENTITY_B

    # Same numeric ids are legal under a new identity; the old identity's
    # tombstones must neither block them nor disappear.
    assert await _active_ids(world, world.owner) == [1, 2, 3]
    material = await _active_material(world, world.owner)
    assert set(material.values()) == {
        pk["public_key"] for pk in prekeys_b
    }
    assert await _consumed_ids(world, world.owner, IDENTITY_A) == [consumed]
    assert await _consumed_ids(world, world.owner, IDENTITY_B) == []

    for _ in range(3):
        response = await _fetch(world, world.sender, world.owner.id)
        assert response.status_code == 200
        body = response.json()
        assert body["identity_key"] == IDENTITY_B
        assert body["one_time_prekey"] in {
            pk["public_key"] for pk in prekeys_b
        }


# ── Concurrency against separate connections ─────────────────────────────────


@pytest_asyncio.fixture
async def durable():
    url = os.environ.get("TEST_DATABASE_URL")
    if url is None:
        pytest.skip("TEST_DATABASE_URL is not set")

    engine = create_async_engine(url, future=True)
    session_factory = async_sessionmaker(engine, expire_on_commit=False)
    async with engine.begin() as connection:
        await connection.run_sync(Base.metadata.create_all)

    async with session_factory() as setup:
        user = _new_user("durable")
        setup.add(user)
        await setup.commit()
        user_id = user.id

    try:
        yield SimpleNamespace(
            engine=engine,
            Session=session_factory,
            user_id=user_id,
        )
    finally:
        async with session_factory() as cleanup:
            await cleanup.execute(delete(User).where(User.id == user_id))
            await cleanup.commit()
        await engine.dispose()


async def test_concurrent_duplicate_publication_is_serialized(durable):
    body = _payload()
    start = asyncio.Event()

    async def publish() -> None:
        await start.wait()
        async with durable.Session() as session:
            await keys.publish_key_bundle(
                body,
                SimpleNamespace(id=durable.user_id),
                session,
            )

    tasks = [asyncio.create_task(publish()) for _ in range(5)]
    start.set()
    results = await asyncio.gather(*tasks, return_exceptions=True)
    failures = [result for result in results if isinstance(result, BaseException)]
    assert not failures, failures

    async with durable.Session() as session:
        ids = list(
            (
                await session.execute(
                    select(OneTimePreKey.key_id)
                    .where(OneTimePreKey.user_id == durable.user_id)
                    .order_by(OneTimePreKey.key_id)
                )
            ).scalars().all()
        )
    assert ids == [1, 2, 3]


async def test_concurrent_claims_are_distinct(durable):
    prekeys = [_prekey(i, 400 + i * 10) for i in range(1, 6)]
    body = _payload(prekeys=prekeys)
    async with durable.Session() as session:
        await keys.publish_key_bundle(
            body,
            SimpleNamespace(id=durable.user_id),
            session,
        )

    start = asyncio.Event()

    async def claim():
        await start.wait()
        async with durable.Session() as session:
            return await keys.fetch_key_bundle(
                durable.user_id,
                SimpleNamespace(id=uuid4()),
                session,
            )

    tasks = [asyncio.create_task(claim()) for _ in range(5)]
    start.set()
    results = await asyncio.gather(*tasks, return_exceptions=True)
    failures = [result for result in results if isinstance(result, BaseException)]
    assert not failures, failures

    claimed = sorted(result.one_time_prekey_id for result in results)
    assert claimed == [1, 2, 3, 4, 5], (
        "concurrent claims must never hand the same pre-key to two senders"
    )

    async with durable.Session() as session:
        remaining = await session.scalar(
            select(func.count())
            .select_from(OneTimePreKey)
            .where(OneTimePreKey.user_id == durable.user_id)
        )
    assert remaining == 0
