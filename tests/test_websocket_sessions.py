"""Real HTTP/WebSockets, two independent workers, real disposable PG16/Redis.

Run with python -m scripts.test_websocket_sessions. No production endpoint is
accepted and no SMS/Firebase/object-storage service is involved.
"""
from __future__ import annotations

import asyncio
from dataclasses import dataclass, field
from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import secrets
import socket
import subprocess
import sys
import time
import uuid

import httpx
import pytest
import redis
from sqlalchemy import create_engine, select, text, update, func
from sqlalchemy.orm import Session
import websockets
from websockets.exceptions import ConnectionClosed, InvalidHandshake

from app.core.database_config import postgres_url, sync_url
from app.core.security import create_access_token, hash_refresh_token
from app.models import Base, Message, User, UserSession
from app.core.redis import _url_with_db
from app.config import settings
from app.models.user import UserRole, UserStatus

pytestmark = pytest.mark.skipif(
    not os.environ.get('WS_TEST_REDIS_URL'),
    reason='Use python -m scripts.test_websocket_sessions for isolated PG16/Redis',
)
ROOT = Path(__file__).resolve().parents[1]


@dataclass(frozen=True)
class Device:
    user_id: uuid.UUID
    session_id: uuid.UUID
    access: str = field(repr=False)
    refresh: str = field(repr=False)


class World:
    def __init__(self, engine, redis_client, ports):
        self.engine = engine
        self.redis = redis_client
        self.ports = ports

    def device(self, user_id=None, role=UserRole.SOLDIER):
        with Session(self.engine, expire_on_commit=False) as db:
            if user_id is None:
                user = User(phone_number='test-' + secrets.token_hex(6),
                            full_name='Synthetic WebSocket user',
                            hashed_military_id='synthetic', hashed_password='synthetic',
                            status=UserStatus.ACTIVE, role=role)
                db.add(user)
                db.flush()
            else:
                user = db.get(User, user_id)
            refresh = secrets.token_urlsafe(32)
            session = UserSession(user_id=user.id, refresh_token_hash=hash_refresh_token(refresh),
                                  ip_address='127.0.0.1',
                                  expires_at=datetime.now(timezone.utc)+timedelta(days=1))
            db.add(session)
            db.commit()
            return Device(user.id, session.id,
                          create_access_token(user.id, user.token_version, user.role, session.id), refresh)

    async def request(self, device, method, path, *, worker=0, data=None):
        async with httpx.AsyncClient(trust_env=False) as client:
            return await client.request(method, f'http://127.0.0.1:{self.ports[worker]}/api/v1/auth{path}',
                                        headers={'Authorization': 'Bearer '+device.access}, json=data)

    async def ticket(self, device, worker=0):
        response = await self.request(device, 'POST', '/ws-ticket', worker=worker)
        assert response.status_code == 200
        return response.json()['ticket']

    def connect(self, ticket, worker=0):
        return websockets.connect(f'ws://127.0.0.1:{self.ports[worker]}/ws/chat?ticket={ticket}')

    def invalidate(self, device):
        with Session(self.engine) as db:
            db.execute(update(UserSession).where(UserSession.id == device.session_id)
                       .values(revoked_at=datetime.now(timezone.utc)))
            db.commit()

    async def open(self, device, worker=0):
        ws = await self.connect(await self.ticket(device, worker), worker)
        try:
            welcome = json.loads(await asyncio.wait_for(ws.recv(), 3))
            assert welcome['type'] == 'welcome'
        except BaseException:
            await ws.close()
            raise
        return ws, welcome

    def message_count(self, device):
        with Session(self.engine) as db:
            return db.scalar(select(func.count()).select_from(Message).where(Message.sender_id==device.user_id))


@pytest.fixture(scope='module')
def world(tmp_path_factory):
    value = os.environ.get('IRONLINK_TEST_ADMIN_URL')
    assert value, 'The disposable PG16 runner is required'
    admin = postgres_url(value)
    assert admin.host == '127.0.0.1' and admin.database == 'postgres'
    engine = create_engine(sync_url(postgres_url(os.environ['TEST_DATABASE_URL'])))
    with engine.connect() as db:
        assert db.scalar(text('SHOW cluster_name')).startswith('ironlink_m01a_')
    Base.metadata.create_all(engine)
    redis_url = os.environ['WS_TEST_REDIS_URL']
    assert redis_url.startswith('redis://127.0.0.1:')
    redis_client = redis.Redis.from_url(_url_with_db(redis_url, settings.REDIS_DB_SESSIONS), decode_responses=True)
    directory = tmp_path_factory.mktemp('ws-workers')
    harness = directory/'ws_test_app.py'
    harness.write_text('''import os
from fastapi import FastAPI
from app.api.routes import admin, auth, websocket
from app.services import ws_session
# One worker demonstrates periodic invalidation, the other disables the timer
# to prove action/delivery checks independently of notifications or polling.
ws_session.SESSION_CHECK_INTERVAL_SECONDS = float(os.environ['WS_TEST_INTERVAL'])
app = FastAPI()
app.include_router(auth.router, prefix="/api/v1")
app.include_router(admin.router, prefix="/api/v1")
app.include_router(websocket.router)
@app.get("/health")
def health():
    return {"ok": True}
''', encoding='utf-8')
    environment = os.environ.copy()
    for key in list(environment):
        if key.upper().startswith(('POSTGRES_', 'MIGRATION_')) or key.upper()=='DATABASE_URL':
            environment.pop(key)
    environment.update(DATABASE_URL=os.environ['TEST_DATABASE_URL'], REDIS_URL=redis_url,
                       ENV='development', PYTHONPATH=str(ROOT), PYTHONDONTWRITEBYTECODE='1')
    ports, processes, logs = [], [], []
    try:
        for worker in range(2):
            with socket.socket() as probe:
                probe.bind(('127.0.0.1', 0))
                port = probe.getsockname()[1]
            ports.append(port)
            log = (directory/f'worker-{worker}.log').open('w', encoding='utf-8')
            logs.append(log)
            process = subprocess.Popen([sys.executable, '-B', '-m', 'uvicorn', 'ws_test_app:app',
                                        '--host', '127.0.0.1', '--port', str(port),
                                        '--log-level', 'warning', '--no-access-log'],
                                       cwd=directory, env={**environment,'WS_TEST_INTERVAL':'0.1' if worker==0 else '3600'}, stdout=log, stderr=log)
            processes.append(process)
            deadline = time.monotonic()+30
            while True:
                assert process.poll() is None, 'Isolated WebSocket worker exited during startup'
                try:
                    if httpx.get(f'http://127.0.0.1:{port}/health', timeout=0.5, trust_env=False).status_code==200:
                        break
                except httpx.HTTPError:
                    pass
                assert time.monotonic()<deadline, 'Isolated worker did not become ready'
                time.sleep(0.1)
        yield World(engine, redis_client, ports)
    finally:
        for process in processes:
            process.terminate()
        for process in processes:
            process.wait(timeout=10)
        for log in logs:
            log.close()
        redis_client.close()
        engine.dispose()


@pytest.mark.asyncio
async def test_ticket_issued_before_revocation_cannot_connect(world):
    device = world.device()
    ticket = await world.ticket(device)
    world.invalidate(device)  # committed authority; intentionally no Pub/Sub
    with pytest.raises((InvalidHandshake, ConnectionClosed)):
        async with world.connect(ticket) as ws:
            await asyncio.wait_for(ws.recv(), 3)


@pytest.mark.asyncio
async def test_ticket_is_bound_to_validated_session_and_consumed_once(world):
    device = world.device()
    other = world.device(device.user_id)
    response = await world.request(device, 'POST', '/ws-ticket', data={'session_id':str(other.session_id)})
    assert response.status_code==200
    ticket=response.json()['ticket']
    value=json.loads(world.redis.get('ws:ticket:'+ticket))
    assert value=={'user_id':str(device.user_id),'session_id':str(device.session_id),'token_version':1}
    assert 0<world.redis.ttl('ws:ticket:'+ticket)<=30
    async with world.connect(ticket) as ws:
        assert json.loads(await ws.recv())['type']=='welcome'
        assert world.redis.get('ws:ticket:'+ticket) is None
    with pytest.raises((InvalidHandshake,ConnectionClosed)):
        async with world.connect(ticket) as ws:
            await asyncio.wait_for(ws.recv(),3)


@pytest.mark.asyncio
async def test_expired_ticket_cannot_connect(world):
    device=world.device()
    ticket=await world.ticket(device)
    world.redis.pexpire('ws:ticket:'+ticket,1)
    await asyncio.sleep(0.03)
    with pytest.raises((InvalidHandshake,ConnectionClosed)):
        async with world.connect(ticket) as ws:
            await asyncio.wait_for(ws.recv(),3)


@pytest.mark.asyncio
@pytest.mark.parametrize('invalid',['legacy','malformed','mismatched','missing','wrong_version','deleted'])
async def test_invalid_ticket_identity_is_rejected(world,invalid):
    device=world.device()
    other=world.device()
    ticket=await world.ticket(device)
    key='ws:ticket:'+ticket
    payload=json.loads(world.redis.get(key))
    if invalid=='legacy':
        world.redis.set(key,str(device.user_id),ex=30)
    elif invalid=='malformed':
        world.redis.set(key,'{"session_id":',ex=30)
    elif invalid=='deleted':
        with Session(world.engine) as db:
            db.query(UserSession).filter_by(id=device.session_id).delete()
            db.commit()
    else:
        if invalid=='mismatched':
            payload['session_id']=str(other.session_id)
        elif invalid=='missing':
            payload.pop('session_id')
        else:
            payload['token_version']=2
        world.redis.set(key,json.dumps(payload),ex=30)
    with pytest.raises((InvalidHandshake,ConnectionClosed)):
        async with world.connect(ticket) as ws:
            await asyncio.wait_for(ws.recv(),3)


@pytest.mark.asyncio
async def test_remote_revoke_closes_exact_session_across_workers_and_preserves_messages(world):
    a=world.device()
    b=world.device(a.user_id)
    c=world.device()
    sa,wa=await world.open(a,0)
    sb,wb=await world.open(b,1)
    same,_=await world.open(a,1)
    sc,_=await world.open(c,0)
    try:
        metadata=json.loads(world.redis.get('ws:conn:'+wa['connection_id']))
        othermeta=json.loads(world.redis.get('ws:conn:'+wb['connection_id']))
        assert metadata['session_id']==str(a.session_id) and metadata['user_id']==str(a.user_id)
        assert metadata['connection_id']==wa['connection_id']
        assert metadata['owner_id']!=othermeta['owner_id']
        assert 0<world.redis.ttl('ws:conn:'+wa['connection_id'])<=90
        await sa.send(json.dumps({'type':'text','to':str(c.user_id),'content':'before revoke','client_ref':str(uuid.uuid4())}))
        assert json.loads(await sa.recv())['type']=='ack'
        assert json.loads(await sc.recv())['type']=='message'
        response=await world.request(b,'DELETE','/sessions/'+str(a.session_id),worker=1)
        assert response.status_code==204
        # Both independent workers close this exact session. Neither client
        # cooperates with the notification, and the sibling session stays valid.
        await asyncio.wait_for(asyncio.gather(sa.wait_closed(),same.wait_closed()),3)
        assert sa.close_code==same.close_code==4421
        assert world.message_count(a)==1
        assert (await world.request(a,'POST','/ws-ticket')).status_code==401
        for socket_ in (sb,sc):
            await socket_.send('{"type":"ping"}')
            assert json.loads(await socket_.recv())['type']=='pong'
        await sb.send(json.dumps({'type':'text','to':str(c.user_id),'content':'valid sibling still sends','client_ref':str(uuid.uuid4())}))
        assert json.loads(await sb.recv())['type']=='ack'
        assert json.loads(await sc.recv())['type']=='message'
        await sc.send(json.dumps({'type':'text','to':str(b.user_id),'content':'valid reply','client_ref':str(uuid.uuid4())}))
        assert json.loads(await sc.recv())['type']=='ack'
        assert json.loads(await sb.recv())['type']=='message'
        deadline=time.monotonic()+3
        while world.redis.exists('ws:conn:'+wa['connection_id']) and time.monotonic()<deadline:
            await asyncio.sleep(0.02)
        assert not world.redis.exists('ws:conn:'+wa['connection_id'])
        assert world.redis.exists('ws:conn:'+wb['connection_id'])
    finally:
        await asyncio.gather(sa.close(),same.close(),sb.close(),sc.close())


@pytest.mark.asyncio
@pytest.mark.parametrize('raw',['{','[]','"a string"','42','null'])
async def test_malformed_frame_is_rejected_without_losing_valid_connection(world,raw):
    device=world.device()
    ws,_=await world.open(device,1)
    try:
        await ws.send(raw)
        assert json.loads(await asyncio.wait_for(ws.recv(),3))['type']=='error'
        await ws.send('{"type":"ping"}')
        assert json.loads(await asyncio.wait_for(ws.recv(),3))['type']=='pong'
    finally:
        await ws.close()


@pytest.mark.asyncio
@pytest.mark.parametrize('kind',['text','image','file','reaction','group_text','group_image','group_file','group_voice','skdm','typing_start','typing_stop','presence','read','delivered','unsend'])
async def test_missed_notification_cannot_authorize_any_action(world,kind):
    device=world.device()
    peer=world.device()
    ws,_=await world.open(device,1)  # no periodic timer during this test
    try:
        world.invalidate(device)
        await ws.send(json.dumps({'type':kind,'to':str(peer.user_id),'group':str(uuid.uuid4()),
                                  'target':str(uuid.uuid4()),'message_id':str(uuid.uuid4()),
                                  'content':'must never be accepted','client_ref':str(uuid.uuid4())}))
        await asyncio.wait_for(ws.wait_closed(),3)
        assert ws.close_code==4421
        assert world.message_count(device)==0
    finally:
        await ws.close()


@pytest.mark.asyncio
async def test_revoked_connection_does_not_receive_new_protected_delivery(world):
    device=world.device()
    ws,_=await world.open(device,1)
    try:
        world.invalidate(device)
        world.redis.publish('chan:user:'+str(device.user_id),json.dumps({'type':'message','content':'protected-after-revoke'}))
        received=[]
        with pytest.raises(ConnectionClosed):
            while True:
                received.append(json.loads(await asyncio.wait_for(ws.recv(),3)))
        assert not any(frame.get('content')=='protected-after-revoke' for frame in received)
        assert ws.close_code==4421
    finally:
        await ws.close()


@pytest.mark.asyncio
@pytest.mark.parametrize('mode',['expired','deleted','deactivated','pending','version','account_expired'])
async def test_idle_session_invalidation_is_enforced_without_notifications(world,mode):
    device=world.device()
    ws,_=await world.open(device,0)
    try:
        with Session(world.engine) as db:
            if mode=='expired':
                db.execute(update(UserSession).where(UserSession.id==device.session_id).values(expires_at=datetime.now(timezone.utc)-timedelta(seconds=1)))
            elif mode=='deleted':
                db.query(UserSession).filter_by(id=device.session_id).delete()
            elif mode=='version':
                db.execute(update(User).where(User.id==device.user_id).values(token_version=2))
            elif mode=='account_expired':
                db.execute(update(User).where(User.id==device.user_id).values(expiry_date=datetime.now(timezone.utc).date()-timedelta(days=1)))
            else:
                db.execute(update(User).where(User.id==device.user_id).values(status=mode))
            db.commit()
        await asyncio.wait_for(ws.wait_closed(),3)
        assert ws.close_code==4421
    finally:
        await ws.close()


@pytest.mark.asyncio
@pytest.mark.parametrize('operation',['logout','refresh_replay'])
async def test_logout_and_refresh_replay_close_existing_socket(world,operation):
    device=world.device()
    ws,_=await world.open(device,1)
    try:
        if operation=='logout':
            assert (await world.request(device,'POST','/logout')).status_code==204
        else:
            assert (await world.request(device,'POST','/refresh',data={'refresh_token':device.refresh})).status_code==200
            assert (await world.request(device,'POST','/refresh',data={'refresh_token':device.refresh})).status_code==401
        await asyncio.wait_for(ws.wait_closed(),3)
        assert ws.close_code==4421
    finally:
        await ws.close()


@pytest.mark.asyncio
async def test_client_cannot_publish_a_revocation_control_frame(world):
    device=world.device()
    other=world.device(device.user_id)
    ws,_=await world.open(device,1)
    peer=None
    try:
        peer,_=await world.open(other,0)
        await ws.send(json.dumps({'type':'session_revoked','session_id':str(other.session_id)}))
        assert json.loads(await ws.recv())['type']=='error'
        await peer.send('{"type":"ping"}')
        assert json.loads(await peer.recv())['type']=='pong'
    finally:
        await ws.close()
        if peer is not None:
            await peer.close()


@pytest.mark.asyncio
async def test_database_failure_fails_closed_without_accepting_message(world):
    device=world.device()
    peer=world.device()
    ws,_=await world.open(device,1)
    try:
        with world.engine.begin() as db:
            db.execute(text('ALTER TABLE user_sessions RENAME TO ws_test_unavailable_sessions'))
        await ws.send(json.dumps({'type':'text','to':str(peer.user_id),'content':'unavailable','client_ref':str(uuid.uuid4())}))
        await asyncio.wait_for(ws.wait_closed(),3)
        assert ws.close_code==1013
        assert world.message_count(device)==0
    finally:
        with world.engine.begin() as db:
            db.execute(text('ALTER TABLE ws_test_unavailable_sessions RENAME TO user_sessions'))
        await ws.close()


@pytest.mark.asyncio
async def test_redis_subscription_loss_closes_and_valid_session_reconnects(world):
    device=world.device()
    ws,_=await world.open(device,1)
    try:
        world.redis.execute_command('CLIENT','KILL','TYPE','PUBSUB')
        await asyncio.wait_for(ws.wait_closed(),3)
        assert ws.close_code==1013
    finally:
        await ws.close()
    replacement,_=await world.open(device,1)
    await replacement.close()


@pytest.mark.asyncio
async def test_operation_authorized_before_revoke_commit_may_finish(world):
    device=world.device()
    peer=world.device()
    ws,_=await world.open(device,1)
    try:
        with world.engine.connect() as db:
            transaction=db.begin()
            db.execute(update(UserSession).where(UserSession.id==device.session_id).values(revoked_at=datetime.now(timezone.utc)))
            # Another transaction sees the still-committed valid session. This
            # is a pre-revocation operation, even though a revoke is in flight.
            await ws.send(json.dumps({'type':'text','to':str(peer.user_id),'content':'authorized before commit','client_ref':str(uuid.uuid4())}))
            assert json.loads(await asyncio.wait_for(ws.recv(),3))['type']=='ack'
            transaction.commit()
        assert world.message_count(device)==1
        await ws.send(json.dumps({'type':'text','to':str(peer.user_id),'content':'after commit','client_ref':str(uuid.uuid4())}))
        await asyncio.wait_for(ws.wait_closed(),3)
        assert ws.close_code==4421 and world.message_count(device)==1
    finally:
        await ws.close()


@pytest.mark.asyncio
async def test_account_suspension_requires_new_authentication_after_reactivation(world):
    admin=world.device(role=UserRole.SUPERADMIN)
    device=world.device()
    async with httpx.AsyncClient(trust_env=False) as client:
        endpoint=f'http://127.0.0.1:{world.ports[1]}/api/v1/admin/users/{device.user_id}/status'
        headers={'Authorization':'Bearer '+admin.access}
        response=await client.post(endpoint,headers=headers,json={'action':'suspend','reason':'Synthetic security test'})
        assert response.status_code==200
        with Session(world.engine) as db:
            assert db.get(UserSession,device.session_id).revoked_at is not None
        response=await client.post(endpoint,headers=headers,json={'action':'activate','reason':'Synthetic security test'})
        assert response.status_code==200
    assert (await world.request(device,'POST','/refresh',data={'refresh_token':device.refresh})).status_code==401
    fresh=world.device(device.user_id)
    ws,_=await world.open(fresh,1)
    try:
        world.redis.publish('chan:user:'+str(device.user_id),'{"type":"account_suspended"}')
        await ws.send('{"type":"ping"}')
        assert json.loads(await asyncio.wait_for(ws.recv(),3))['type']=='pong'
    finally:
        await ws.close()
