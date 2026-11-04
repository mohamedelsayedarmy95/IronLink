from __future__ import annotations

import uuid
import asyncio
import json
from types import SimpleNamespace
from unittest.mock import AsyncMock

import pytest
from fastapi import WebSocket
from redis.exceptions import ConnectionError as RedisConnectionError

from app.services.ws_manager import ConnectionManager
from app.services import ws_session
from app.core.session_auth import SessionIdentity, SessionInvalid
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
    conn_id = await manager.register(user_id, FakeWebSocket(), session_id=uuid.uuid4())  # type: ignore[arg-type]

    assert len(conn_id) == 32   # token_hex(16)
    assert await manager.is_online(user_id)
    assert await manager.online_count() == 1


@pytest.mark.asyncio
async def test_multi_device_stays_online_until_last_disconnect(
    manager: ConnectionManager,
):
    user_id = uuid.uuid4()
    conn1 = await manager.register(user_id, FakeWebSocket(), session_id=uuid.uuid4())  # type: ignore[arg-type]
    conn2 = await manager.register(user_id, FakeWebSocket(), session_id=uuid.uuid4())  # type: ignore[arg-type]

    await manager.unregister(user_id, conn1)
    assert await manager.is_online(user_id)   # second device still connected

    await manager.unregister(user_id, conn2)
    assert not await manager.is_online(user_id)
    assert await manager.online_count() == 0


@pytest.mark.asyncio
async def test_online_count_across_users(manager: ConnectionManager):
    for _ in range(3):
        await manager.register(uuid.uuid4(), FakeWebSocket(), session_id=uuid.uuid4())  # type: ignore[arg-type]
    assert await manager.online_count() == 3


@pytest.mark.asyncio
async def test_send_local_unknown_connection_returns_false(
    manager: ConnectionManager,
):
    assert await manager.send_local("nonexistent", {"type": "x"}) is False


@pytest.mark.asyncio
async def test_send_local_delivers(manager: ConnectionManager):
    ws = FakeWebSocket()
    conn_id = await manager.register(uuid.uuid4(), ws, session_id=uuid.uuid4())  # type: ignore[arg-type]
    ok = await manager.send_local(conn_id, {"type": "welcome"})
    assert ok
    assert ws.sent == [{"type": "welcome"}]


@pytest.mark.asyncio
async def test_failed_registration_never_retains_local_socket(manager, redis, monkeypatch):
    pipeline = redis.pipeline()
    pipeline.execute = AsyncMock(side_effect=RedisConnectionError())
    monkeypatch.setattr(redis, 'pipeline', lambda: pipeline)
    with pytest.raises(RedisConnectionError):
        await manager.register(uuid.uuid4(), FakeWebSocket(), session_id=uuid.uuid4())
    assert manager._local == {}


@pytest.mark.asyncio
async def test_local_delivery_checks_authority(manager, monkeypatch):
    raw = FakeWebSocket()
    identity = SessionIdentity(uuid.uuid4(), uuid.uuid4(), 1)
    socket = ws_session.SessionSocket(raw, identity)
    connection = await manager.register(identity.user_id, socket, session_id=identity.session_id)
    monkeypatch.setattr(ws_session, 'validate', AsyncMock(side_effect=SessionInvalid()))
    with pytest.raises(SessionInvalid):
        await manager.send_local(connection, {'type': 'ocr_alert', 'content': 'protected'})
    assert raw.sent == []


@pytest.mark.asyncio
async def test_invalid_local_session_does_not_abort_ocr_delivery_to_valid_sibling(manager, redis, monkeypatch):
    bad = ws_session.SessionSocket(FakeWebSocket(), SessionIdentity(uuid.uuid4(), uuid.uuid4(), 1))
    bad.invalid = True
    good = FakeWebSocket()
    manager._local.update(bad=bad, good=good)
    async def listen():
        yield {'type': 'message', 'data': json.dumps({
            'file_id': 'synthetic-file', 'user_id': str(bad.identity.user_id), 'keyword': 'synthetic',
        })}
    pubsub = SimpleNamespace(subscribe=AsyncMock(), unsubscribe=AsyncMock(), aclose=AsyncMock(), listen=listen)
    monkeypatch.setattr(redis, 'pubsub', lambda: pubsub, raising=False)
    monkeypatch.setattr(redis, 'smembers', AsyncMock(return_value=['bad', 'good']))
    await manager.listen_ocr_alerts()
    assert len(good.sent) == 1 and good.sent[0]['type'] == 'ocr_alert'


@pytest.mark.asyncio
async def test_queued_delivery_cannot_overtake_known_revocation(monkeypatch):
    raw = FakeWebSocket()
    raw.close = AsyncMock()
    socket = ws_session.SessionSocket(raw, SessionIdentity(uuid.uuid4(), uuid.uuid4(), 1))
    monkeypatch.setattr(ws_session, 'validate', AsyncMock())
    await socket._send_lock.acquire()
    delivery = asyncio.create_task(socket.send_json({'type': 'message', 'content': 'protected'}))
    await asyncio.sleep(0)
    closing = asyncio.create_task(socket.close(invalid=True))
    await asyncio.sleep(0)
    socket._send_lock.release()
    with pytest.raises(SessionInvalid):
        await delivery
    await closing
    assert raw.sent == [{'type': 'session_revoked'}]
    assert raw.close.call_args.kwargs['code'] == 4421


@pytest.mark.asyncio
@pytest.mark.parametrize('query', [b'ticket=synthetic-ticket-123456&v=bad',
                                 b'ticket=synthetic-ticket-123456&v=1',
                                 b'ticket=synthetic-ticket-123456&ticket=another-ticket-12345'])
async def test_ticket_dependency_removes_query_before_handshake_logging(query):
    from app.api.routes.websocket import _ticket_from_query
    from fastapi import WebSocketException
    scope = {'type': 'websocket', 'path': '/ws/chat', 'query_string': query, 'headers': []}
    socket = WebSocket(scope, AsyncMock(), AsyncMock())
    try:
        await _ticket_from_query(socket)
    except WebSocketException:
        assert query.count(b'ticket=') == 2
    assert scope['query_string'] == b''
    assert socket.query_params.get('v') in ('bad', '1', None)


@pytest.mark.asyncio
async def test_periodic_registry_blackhole_has_bounded_failure(monkeypatch):
    from app.api.routes import websocket
    monkeypatch.setattr(ws_session, 'SESSION_CHECK_INTERVAL_SECONDS', 0)
    monkeypatch.setattr(ws_session, 'IO_TIMEOUT_SECONDS', .02)
    socket = AsyncMock()
    async def blocked(_):
        await asyncio.sleep(10)
    monkeypatch.setattr(websocket.manager, 'heartbeat', blocked)
    task = asyncio.create_task(websocket._periodic_authorization(socket, 'synthetic'))
    done, pending = await asyncio.wait([task], timeout=.5)
    if pending:
        task.cancel()
        await asyncio.gather(task, return_exceptions=True)
    assert done, 'Registry I/O must not disable future authorization indefinitely'
    with pytest.raises(TimeoutError):
        task.result()
