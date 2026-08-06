from __future__ import annotations

import uuid

import pytest

from app.services.ws_manager import ConnectionManager
from tests.fakes import FakeRedis


class FakeWebSocket:
    def __init__(self) -> None:
        self.sent: list[dict] = []

    async def send_json(self, payload: dict) -> None:
        self.sent.append(payload)


@pytest.fixture
def redis() -> FakeRedis:
    return FakeRedis()


@pytest.fixture
def manager(redis: FakeRedis) -> ConnectionManager:
    return ConnectionManager(redis)  # type: ignore[arg-type]


@pytest.mark.asyncio
async def test_register_marks_user_online(manager: ConnectionManager):
    user_id = uuid.uuid4()
    conn_id = await manager.register(user_id, FakeWebSocket())  # type: ignore[arg-type]

    assert len(conn_id) == 32   # token_hex(16)
    assert await manager.is_online(user_id)
    assert await manager.online_count() == 1


@pytest.mark.asyncio
async def test_multi_device_stays_online_until_last_disconnect(
    manager: ConnectionManager,
):
    user_id = uuid.uuid4()
    conn1 = await manager.register(user_id, FakeWebSocket())  # type: ignore[arg-type]
    conn2 = await manager.register(user_id, FakeWebSocket())  # type: ignore[arg-type]

    await manager.unregister(user_id, conn1)
    assert await manager.is_online(user_id)   # second device still connected

    await manager.unregister(user_id, conn2)
    assert not await manager.is_online(user_id)
    assert await manager.online_count() == 0


@pytest.mark.asyncio
async def test_online_count_across_users(manager: ConnectionManager):
    for _ in range(3):
        await manager.register(uuid.uuid4(), FakeWebSocket())  # type: ignore[arg-type]
    assert await manager.online_count() == 3


@pytest.mark.asyncio
async def test_send_local_unknown_connection_returns_false(
    manager: ConnectionManager,
):
    assert await manager.send_local("nonexistent", {"type": "x"}) is False


@pytest.mark.asyncio
async def test_send_local_delivers(manager: ConnectionManager):
    ws = FakeWebSocket()
    conn_id = await manager.register(uuid.uuid4(), ws)  # type: ignore[arg-type]
    ok = await manager.send_local(conn_id, {"type": "welcome"})
    assert ok
    assert ws.sent == [{"type": "welcome"}]
