"""Real HTTP, JWT/session authentication and PostgreSQL channel ACL regressions."""
from __future__ import annotations

import asyncio
from datetime import datetime, timedelta, timezone
import os
from types import SimpleNamespace
from uuid import uuid4

import httpx
import pytest
import pytest_asyncio
from fastapi import FastAPI
from sqlalchemy import delete, event, func, select
from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine

from app.api.routes import channels, media
from app.core.database import get_db
from app.core.security import create_access_token
from app.models import User, UserSession
from app.models.channel import Channel, ChannelMediaKey, ChannelPost, ChannelSubscription
from app.services.storage_service import StorageNotConfigured, StorageService
from tests.conftest import requires_db

pytestmark = [requires_db, pytest.mark.asyncio]
_real_object_owner = StorageService.object_owner


@pytest_asyncio.fixture
async def world(db, monkeypatch):
    app = FastAPI()
    app.include_router(channels.router, prefix='/api/v1')
    app.include_router(media.router, prefix='/api/v1')

    async def database():
        yield db
        await db.flush()

    app.dependency_overrides[get_db] = database
    people = {}
    headers = {}
    for name in ('owner', 'member', 'outsider', 'former', 'unrelated'):
        user = User(phone_number='+' + str(uuid4().int)[:18], full_name=name,
                    hashed_military_id='synthetic', hashed_password='synthetic')
        db.add(user)
        await db.flush()
        session = UserSession(user_id=user.id, refresh_token_hash=uuid4().hex,
                              ip_address='127.0.0.1',
                              expires_at=datetime.now(timezone.utc) + timedelta(days=1))
        db.add(session)
        await db.flush()
        people[name] = user
        headers[name] = {'Authorization': 'Bearer ' + create_access_token(
            user.id, user.token_version, user.role, session.id)}
    private = Channel(name='private', channel_type='private', owner_id=people['owner'].id,
                      subscriber_count=1)
    public = Channel(name='public', channel_type='public', owner_id=people['unrelated'].id)
    other = Channel(name='other private', channel_type='private', owner_id=people['unrelated'].id)
    db.add_all([private, public, other])
    await db.flush()
    db.add_all([
        ChannelSubscription(channel_id=private.id, user_id=people['member'].id),
        ChannelSubscription(channel_id=private.id, user_id=people['former'].id, is_active=False),
    ])
    now = datetime.now(timezone.utc)
    posts = {}
    for name, ch, scheduled, when in [
        ('private', private, False, None), ('public', public, False, None),
        ('future', private, True, now + timedelta(days=1)),
        ('delayed', private, True, now - timedelta(days=1)),
        ('future_unflagged', private, False, now + timedelta(days=1)),
    ]:
        post = ChannelPost(channel_id=ch.id, author_id=ch.owner_id, content=name,
                           media_key=uuid4().hex, is_scheduled=scheduled, scheduled_at=when)
        db.add(post)
        await db.flush()
        posts[name] = post
        db.add(ChannelMediaKey(media_key=post.media_key, channel_id=ch.id))
    await db.flush()
    monkeypatch.setattr(media._storage, 'presign_download_ttl',
                        lambda *args: 'https://storage.invalid/synthetic')
    owned_media = {}
    monkeypatch.setattr(StorageService, 'object_owner',
                        lambda self, bucket, key: owned_media.get(key), raising=False)
    async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app),
                                 base_url='http://test') as client:
        yield dict(db=db, client=client, people=people, headers=headers, private=private,
                   public=public, other=other, posts=posts, owned_media=owned_media)


async def request(w, who, method, path, **kwargs):
    return await w['client'].request(method, '/api/v1' + path,
                                     headers=w['headers'].get(who, {}), **kwargs)


@pytest.mark.parametrize('who', ['outsider', 'former', 'unrelated'])
@pytest.mark.parametrize('surface', ['', '/posts'])
async def test_private_uuid_read_denied(world, who, surface):
    r = await request(world, who, 'GET', f"/channels/{world['private'].id}{surface}")
    assert r.status_code == 404, r.text


@pytest.mark.parametrize('who', ['outsider', 'former', 'unrelated'])
async def test_private_discovery_filtered(world, who):
    r = await request(world, who, 'GET', '/channels')
    assert r.status_code == 200
    ids = {c['id'] for c in r.json()}
    assert str(world['private'].id) not in ids
    assert str(world['public'].id) in ids


@pytest.mark.parametrize('who', ['outsider', 'former', 'unrelated'])
async def test_private_self_subscription_denied(world, who):
    r = await request(world, who, 'POST', f"/channels/{world['private'].id}/subscribe",
                      json={'user_id': str(world['people']['member'].id),
                            'is_active': True, 'owner_id': str(world['people']['owner'].id)})
    assert r.status_code == 404, r.text


@pytest.mark.parametrize('surface', ['', '/posts', '/analytics', '/subscribe'])
async def test_unauthenticated(world, surface):
    method = 'POST' if surface == '/subscribe' else 'GET'
    r = await request(world, None, method, f"/channels/{world['private'].id}{surface}", json={})
    assert r.status_code == 401


@pytest.mark.parametrize('who', ['owner', 'member'])
async def test_authorized_private_reads(world, who):
    ch = world['private']
    r = await request(world, who, 'GET', f'/channels/{ch.id}')
    assert r.status_code == 200
    assert r.json()['owner_id'] == str(world['people']['owner'].id)
    r = await request(world, who, 'GET', '/channels')
    assert str(ch.id) in {c['id'] for c in r.json()}
    r = await request(world, who, 'GET', f'/channels/{ch.id}/posts')
    assert 'private' in {p['content'] for p in r.json()}
    r = await request(world, who, 'GET', f"/media/{world['posts']['private'].media_key}/url")
    assert r.status_code == 200


@pytest.mark.parametrize('method,suffix,body', [
    ('PATCH', '', {'name': 'stolen'}), ('DELETE', '', None),
    ('POST', '/posts', {'content': 'stolen'}), ('GET', '/analytics', None),
])
@pytest.mark.parametrize('who,expected', [('member', 403), ('outsider', 404), ('former', 404)])
async def test_owner_boundaries(world, method, suffix, body, who, expected):
    r = await request(world, who, method, f"/channels/{world['private'].id}{suffix}", json=body)
    assert r.status_code == expected, r.text


async def test_owner_lifecycle_and_no_mass_assignment(world):
    r = await request(world, 'owner', 'POST', '/channels', json={
        'name': 'new', 'channel_type': 'private', 'owner_id': str(world['people']['outsider'].id),
        'is_verified': True})
    assert r.status_code == 201
    ch = r.json()['id']
    assert r.json()['owner_id'] == str(world['people']['owner'].id)
    assert r.json()['is_verified'] is False
    r = await request(world, 'owner', 'PATCH', f'/channels/{ch}', json={
        'name': 'edited', 'owner_id': str(world['people']['outsider'].id), 'is_verified': True})
    assert r.status_code == 200
    assert r.json()['name'] == 'edited'
    assert r.json()['is_verified'] is False
    r = await request(world, 'owner', 'POST', f'/channels/{ch}/posts', json={'content': 'broadcast'})
    assert r.status_code == 201
    assert r.json()['author_id'] == str(world['people']['owner'].id)
    assert (await request(world, 'owner', 'GET', f'/channels/{ch}/analytics')).status_code == 200
    assert (await request(world, 'owner', 'DELETE', f'/channels/{ch}')).status_code == 204
    assert (await request(world, 'owner', 'GET', f'/channels/{ch}')).status_code == 404


async def test_public_contract_and_repeated_subscription(world):
    ch = world['public'].id
    for suffix in ('', '/posts'):
        assert (await request(world, 'outsider', 'GET', f'/channels/{ch}{suffix}')).status_code == 200
    assert (await request(world, 'outsider', 'GET', f"/media/{world['posts']['public'].media_key}/url")).status_code == 200
    r = await request(world, 'outsider', 'POST', f'/channels/{ch}/subscribe', json={})
    assert r.status_code == 201
    assert r.json()['user_id'] == str(world['people']['outsider'].id)
    assert (await request(world, 'outsider', 'POST', f'/channels/{ch}/subscribe', json={})).status_code == 409
    assert (await request(world, 'outsider', 'DELETE', f'/channels/{ch}/subscribe')).status_code == 204
    assert (await request(world, 'outsider', 'POST', f'/channels/{ch}/subscribe', json={})).status_code == 201
    assert (await request(world, 'outsider', 'GET', f'/channels/{ch}')).json()['subscriber_count'] == 1


async def test_owner_grant_revoke_regrant_and_member_cannot_restore(world):
    ch = world['private'].id
    target = world['people']['outsider'].id
    path = f'/channels/{ch}/subscribers/{target}'
    r = await request(world, 'owner', 'PUT', path)
    assert r.status_code == 200, r.text
    first = r.json()['id']
    assert (await request(world, 'owner', 'PUT', path)).json()['id'] == first
    assert (await request(world, 'outsider', 'GET', f'/channels/{ch}/posts')).status_code == 200
    assert (await request(world, 'owner', 'GET', f'/channels/{ch}')).json()['subscriber_count'] == 2
    assert (await request(world, 'owner', 'DELETE', path)).status_code == 204
    assert (await request(world, 'owner', 'DELETE', path)).status_code == 204
    assert (await request(world, 'outsider', 'GET', f'/channels/{ch}/posts')).status_code == 404
    assert (await request(world, 'outsider', 'POST', f'/channels/{ch}/subscribe', json={})).status_code == 404
    assert (await request(world, 'owner', 'PUT', path)).json()['id'] == first
    assert (await request(world, 'outsider', 'DELETE', f'/channels/{ch}/subscribe')).status_code == 204
    assert (await request(world, 'outsider', 'POST', f'/channels/{ch}/subscribe', json={})).status_code == 404
    assert (await request(world, 'owner', 'GET', f'/channels/{ch}')).json()['subscriber_count'] == 1


@pytest.mark.parametrize('method', ['PUT', 'DELETE'])
@pytest.mark.parametrize('who,expected', [('member', 403), ('outsider', 404)])
async def test_only_owner_grants_and_revokes(world, method, who, expected):
    path = f"/channels/{world['private'].id}/subscribers/{world['people']['former'].id}"
    assert (await request(world, who, method, path)).status_code == expected


async def test_cross_channel_and_nonexistent_targets(world):
    path = f"/channels/{world['other'].id}/subscribers/{world['people']['outsider'].id}"
    assert (await request(world, 'owner', 'PUT', path)).status_code == 404
    assert (await request(world, 'owner', 'PUT', f"/channels/{world['private'].id}/subscribers/{uuid4()}")).status_code == 404
    assert (await request(world, 'member', 'GET', f'/channels/{uuid4()}')).status_code == 404


async def test_discovery_paginates_after_filtering_with_stable_ties(world):
    now = datetime.now(timezone.utc)
    for i in range(6):
        world['db'].add(Channel(name=str(i), owner_id=world['people']['owner'].id,
                                channel_type='private' if i % 2 else 'public', created_at=now))
    await world['db'].flush()
    all_rows = (await request(world, 'outsider', 'GET', '/channels')).json()
    pages = []
    for i in range(len(all_rows)):
        r = await request(world, 'outsider', 'GET', f'/channels?skip={i}&limit=1')
        assert len(r.json()) == 1
        pages += r.json()
    assert pages == all_rows
    assert all(c['channel_type'] == 'public' for c in pages)


async def test_owner_can_preview_and_published_transition(world):
    ch = world['private'].id
    r = await request(world, 'owner', 'GET', f'/channels/{ch}/posts')
    assert len(r.json()) == 4
    for name in ('future', 'delayed', 'future_unflagged'):
        assert (await request(world, 'owner', 'GET', f"/media/{world['posts'][name].media_key}/url")).status_code == 200
    world['posts']['delayed'].is_scheduled = False
    await world['db'].flush()
    r = await request(world, 'member', 'GET', f'/channels/{ch}/posts?limit=1')
    assert [p['content'] for p in r.json()] == ['delayed']
    r = await request(world, 'member', 'GET', f'/channels/{ch}/posts?skip=1&limit=1')
    assert [p['content'] for p in r.json()] == ['private']


async def test_duplicate_public_reference_cannot_launder_private_media(world):
    world['db'].add(ChannelPost(channel_id=world['public'].id,
                                author_id=world['people']['unrelated'].id, content='copy',
                                media_key=world['posts']['private'].media_key))
    await world['db'].flush()
    assert (await request(world, 'outsider', 'GET', f"/media/{world['posts']['private'].media_key}/url")).status_code == 404


async def test_revocation_changes_fresh_reads(world):
    ch = world['private'].id
    sub = await world['db'].scalar(select(ChannelSubscription).where(
        ChannelSubscription.channel_id == ch, ChannelSubscription.user_id == world['people']['member'].id))
    assert (await request(world, 'member', 'GET', f'/channels/{ch}')).status_code == 200
    sub.is_active = False
    await world['db'].flush()
    assert (await request(world, 'member', 'GET', f'/channels/{ch}')).status_code == 404
    assert (await request(world, 'member', 'GET', f"/media/{world['posts']['private'].media_key}/url")).status_code == 404


async def test_deleted_private_channel_media_cannot_be_reopened_by_key(world):
    key = world['posts']['private'].media_key
    assert (await request(world, 'owner', 'DELETE', f"/channels/{world['private'].id}")).status_code == 204
    # A retained object is still private even after its post's FK cascade.
    for who in ('outsider', 'former', 'member', 'owner'):
        assert (await request(world, who, 'GET', f'/media/{key}/url')).status_code == 404


async def test_foreign_media_reference_cannot_change_original_policy(world):
    key = world['posts']['public'].media_key
    r = await request(world, 'owner', 'POST', f"/channels/{world['private'].id}/posts",
                      json={'content': 'foreign key', 'media_key': key})
    assert r.status_code == 404
    assert (await request(world, 'outsider', 'GET', f'/media/{key}/url')).status_code == 200


async def test_api_media_scope_is_immutable_and_survives_deletion(world):
    key = uuid4().hex
    world['owned_media'][key] = str(world['people']['owner'].id)
    path = f"/channels/{world['private'].id}/posts"
    for _ in range(2):
        r = await request(world, 'owner', 'POST', path, json={'content': 'attachment', 'media_key': key})
        assert r.status_code == 201
    assert (await request(world, 'member', 'GET', f'/media/{key}/url')).status_code == 200
    assert (await request(world, 'outsider', 'GET', f'/media/{key}/url')).status_code == 404
    r = await request(world, 'unrelated', 'POST', f"/channels/{world['public'].id}/posts",
                      json={'content': 'copy', 'media_key': key})
    assert r.status_code == 404
    assert (await request(world, 'owner', 'DELETE', f"/channels/{world['private'].id}")).status_code == 204
    r = await request(world, 'unrelated', 'POST', f"/channels/{world['public'].id}/posts",
                      json={'content': 'copy after deletion', 'media_key': key})
    assert r.status_code == 404
    assert (await request(world, 'member', 'GET', f'/media/{key}/url')).status_code == 404


@pytest.mark.parametrize('known_uploader', [True, False])
async def test_first_media_binding_requires_authoritative_upload_owner(world, known_uploader):
    key = uuid4().hex
    if known_uploader:
        world['owned_media'][key] = str(world['people']['unrelated'].id)
    assert (await request(world, 'outsider', 'GET', f'/media/{key}/url')).status_code == 200
    r = await request(world, 'owner', 'POST', f"/channels/{world['private'].id}/posts",
                      json={'content': 'claim foreign/unattributed upload', 'media_key': key})
    assert r.status_code == 404
    assert (await request(world, 'outsider', 'GET', f'/media/{key}/url')).status_code == 200


async def test_actual_encrypted_upload_metadata_authorizes_first_binding(world, monkeypatch):
    from tests.fakes import FakeRedis

    class ObjectStore:
        def __init__(self):
            self.objects = {}

        def put_object(self, bucket, key, data, length, content_type, metadata=None):
            self.objects[key] = (data.read(), {
                'X-Amz-Meta-' + name: value for name, value in (metadata or {}).items()
            })

        def stat_object(self, bucket, key):
            return SimpleNamespace(metadata=self.objects[key][1])

    store = ObjectStore()
    monkeypatch.setattr(StorageService, '_client', property(lambda self: store))
    monkeypatch.setattr(StorageService, 'object_owner', _real_object_owner)
    monkeypatch.setattr(media, 'redis_sessions', FakeRedis())
    monkeypatch.setattr(media._storage, 'assemble_staging', lambda *args: b'abc')
    monkeypatch.setattr(media._storage, 'delete_staging', lambda *args: None)
    r = await request(world, 'owner', 'POST', '/media/upload/init', json={
        'filename': 'synthetic.bin', 'mime_type': 'application/octet-stream',
        'encrypted': True, 'total_size': 3,
        'owner_id': str(world['people']['unrelated'].id),
    })
    assert r.status_code == 200, r.text
    upload = r.json()['upload_id']
    assert (await request(world, 'owner', 'PUT', f'/media/upload/{upload}/chunk/0', content=b'abc')).status_code == 204
    r = await request(world, 'owner', 'POST', f'/media/upload/{upload}/complete')
    assert r.status_code == 200, r.text
    key = r.json()['media_key']
    assert store.objects[key][0] == b'abc'
    assert r.json()['thumbnail_key'] is None
    assert media._storage.object_owner('synthetic', key) == str(world['people']['owner'].id)
    r = await request(world, 'unrelated', 'POST', f"/channels/{world['public'].id}/posts",
                      json={'content': 'claim other upload', 'media_key': key})
    assert r.status_code == 404
    r = await request(world, 'owner', 'POST', f"/channels/{world['private'].id}/posts",
                      json={'content': 'authorized upload', 'media_key': key})
    assert r.status_code == 201, r.text
    assert (await request(world, 'member', 'GET', f'/media/{key}/url')).status_code == 200


async def test_storage_ownership_outage_fails_closed_without_binding(world, monkeypatch):
    key = uuid4().hex

    def unavailable(*args):
        raise StorageNotConfigured('synthetic outage')

    monkeypatch.setattr(StorageService, 'object_owner', unavailable)
    r = await request(world, 'owner', 'POST', f"/channels/{world['private'].id}/posts",
                      json={'content': 'unverified upload', 'media_key': key})
    assert r.status_code == 503
    assert await world['db'].scalar(select(ChannelMediaKey).where(ChannelMediaKey.media_key == key)) is None


@pytest.mark.parametrize('headers,expected', [
    ({'X-Amz-Meta-IronLink-Owner-Id': 'synthetic-owner'}, 'synthetic-owner'),
    ({'x-amz-meta-ironlink-owner-id': 'synthetic-owner'}, 'synthetic-owner'),
    ({}, None),
])
async def test_storage_provenance_header_is_case_insensitive_and_missing_is_unowned(monkeypatch, headers, expected):
    client = SimpleNamespace(stat_object=lambda *args: SimpleNamespace(metadata=headers))
    monkeypatch.setattr(StorageService, '_client', property(lambda self: client))
    assert StorageService().object_owner('synthetic', 'synthetic') == expected


@pytest.mark.parametrize('who', ['outsider', 'former', 'unrelated'])
async def test_private_media_key_denied(world, who):
    r = await request(world, who, 'GET', f"/media/{world['posts']['private'].media_key}/url")
    assert r.status_code == 404, r.text


@pytest.mark.parametrize('name', ['future', 'delayed', 'future_unflagged'])
async def test_unpublished_hidden_from_subscriber(world, name):
    r = await request(world, 'member', 'GET', f"/channels/{world['private'].id}/posts")
    assert r.status_code == 200
    assert name not in {p['content'] for p in r.json()}
    r = await request(world, 'member', 'GET', f"/media/{world['posts'][name].media_key}/url")
    assert r.status_code == 404, r.text


async def test_concurrent_subscription_mutations_are_serialized(db):
    """Independent HTTP transactions actually wait on one PostgreSQL row lock."""
    engine = create_async_engine(os.environ['TEST_DATABASE_URL'])
    sessions = async_sessionmaker(engine, expire_on_commit=False)
    app = FastAPI()
    app.include_router(channels.router, prefix='/api/v1')

    async def database():
        async with sessions() as session:
            try:
                yield session
                await session.commit()
            except BaseException:
                await session.rollback()
                raise

    app.dependency_overrides[get_db] = database
    ids = []
    tokens = []
    ch_id = None
    try:
        async with sessions() as seed:
            for name in ('concurrent owner', 'concurrent subscriber'):
                user = User(phone_number='+' + str(uuid4().int)[:18], full_name=name,
                            hashed_military_id='synthetic', hashed_password='synthetic')
                seed.add(user)
                await seed.flush()
                session = UserSession(user_id=user.id, refresh_token_hash=uuid4().hex,
                                      ip_address='127.0.0.1', expires_at=
                                      datetime.now(timezone.utc) + timedelta(days=1))
                seed.add(session)
                await seed.flush()
                ids.append(user.id)
                tokens.append({'Authorization': 'Bearer ' + create_access_token(
                    user.id, user.token_version, user.role, session.id)})
            ch = Channel(name='concurrent', owner_id=ids[0], channel_type='public')
            seed.add(ch)
            await seed.commit()
            ch_id = ch.id
        async with httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url='http://test') as client:
            async def req(who, method, suffix, **kwargs):
                return await client.request(method, f'/api/v1/channels/{ch_id}{suffix}',
                                             headers=tokens[who], **kwargs)

            async def race(left, right):
                ready = asyncio.Event()
                attempts = 0

                def on_query(conn, cursor, statement, parameters, context, executemany):
                    nonlocal attempts
                    if 'FOR UPDATE' in statement:
                        attempts += 1
                        if attempts == 2:
                            ready.set()

                async with sessions() as holder:
                    await holder.scalar(select(Channel).where(Channel.id == ch_id).with_for_update())
                    event.listen(engine.sync_engine, 'before_cursor_execute', on_query)
                    tasks = [asyncio.create_task(left()), asyncio.create_task(right())]
                    try:
                        await asyncio.wait_for(ready.wait(), 5)
                        assert not any(task.done() for task in tasks)
                        await holder.commit()
                        return await asyncio.wait_for(asyncio.gather(*tasks), 10)
                    finally:
                        event.remove(engine.sync_engine, 'before_cursor_execute', on_query)
                        for task in tasks:
                            if not task.done():
                                task.cancel()
                        await asyncio.gather(*tasks, return_exceptions=True)

            responses = await race(lambda: req(1, 'POST', '/subscribe', json={}),
                                   lambda: req(1, 'POST', '/subscribe', json={}))
            assert sorted(r.status_code for r in responses) == [201, 409]
            grant_path = f'/subscribers/{ids[1]}'
            assert (await req(0, 'DELETE', grant_path)).status_code == 204
            assert (await req(0, 'PATCH', '', json={'channel_type': 'private'})).status_code == 200
            responses = await race(lambda: req(0, 'PUT', grant_path), lambda: req(0, 'PUT', grant_path))
            assert [r.status_code for r in responses] == [200, 200]
            responses = await race(lambda: req(1, 'DELETE', '/subscribe'),
                                   lambda: req(0, 'DELETE', grant_path))
            assert responses[0].status_code in (204, 404)
            assert responses[1].status_code == 204
            assert (await req(1, 'GET', '/posts')).status_code == 404
            assert (await req(1, 'POST', '/subscribe', json={})).status_code == 404
        async with sessions() as check:
            assert await check.scalar(select(func.count()).select_from(ChannelSubscription).where(
                ChannelSubscription.channel_id == ch_id)) == 1
            sub = await check.scalar(select(ChannelSubscription).where(ChannelSubscription.channel_id == ch_id))
            assert sub.is_active is False
            assert (await check.get(Channel, ch_id)).subscriber_count == 0
    finally:
        async with sessions() as cleanup:
            if ch_id:
                await cleanup.execute(delete(Channel).where(Channel.id == ch_id))
            await cleanup.execute(delete(User).where(User.id.in_(ids)))
            await cleanup.commit()
        await engine.dispose()
