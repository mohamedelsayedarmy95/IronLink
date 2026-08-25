"""Smart Keyword Alert — server-side keyword store and alert fanout.

The audit (docs/SMART_KEYWORD_ALERT_AUDIT.md) found this path broken in four
independent ways at once, every one of which was invisible because the code
swallowed its own exceptions. These tests pin each one down by behaviour where
behaviour is observable, and structurally where the defect is one of wiring.
"""
from __future__ import annotations

import ast
import inspect
import json
import pathlib

import pytest

from tests.fakes import FakeRedis


@pytest.fixture
def fake_redis(monkeypatch) -> FakeRedis:
    """Swap the shared client the module binds at import time."""
    import app.redis as keyword_store

    fake = FakeRedis()
    monkeypatch.setattr(keyword_store, "redis_sessions", fake)
    return fake


# ── The await/sync mismatch that made every endpoint return 500 ──────────────

def test_every_store_function_is_awaitable() -> None:
    """The routes await these. They were declared ``def``, so ``await`` was
    applied to a ``set`` and a ``bool`` and raised TypeError on every call."""
    import app.redis as keyword_store
    import app.ocr as ocr

    for fn in (
        keyword_store.get_user_keywords,
        keyword_store.set_user_keywords,
        keyword_store.add_user_keywords,
        keyword_store.remove_user_keywords,
        keyword_store.publish_ocr_alert,
        keyword_store.claim_alert,
        ocr.load_user_keywords,
    ):
        assert inspect.iscoroutinefunction(fn), f"{fn.__name__} must be async"


def test_store_builds_no_redis_client_of_its_own() -> None:
    """The old module constructed ``redis.Redis(host="redis", port=6379)`` — a
    docker-compose service name that cannot resolve on Render, where the
    connection comes from REDIS_URL. Nothing here may build a client."""
    source = pathlib.Path("app/redis.py").read_text(encoding="utf-8")
    tree = ast.parse(source)

    code = "\n".join(
        line for line in source.splitlines() if not line.strip().startswith(("*", "#"))
    )
    assert 'host="redis"' not in code and "host='redis'" not in code

    imports = {
        alias.name
        for node in ast.walk(tree)
        if isinstance(node, ast.Import)
        for alias in node.names
    }
    assert "redis" not in imports, "must use app.core.redis, not its own client"


def test_publisher_and_subscriber_share_one_client() -> None:
    """Publishing on db 0 while ws_manager subscribes on REDIS_DB_SESSIONS
    meant an alert could never reach the socket that was listening for it."""
    from app.services import ws_manager

    publisher = pathlib.Path("app/redis.py").read_text(encoding="utf-8")
    subscriber = inspect.getsource(ws_manager)

    assert "from app.core.redis import redis_sessions" in publisher
    assert "redis_sessions" in subscriber


# ── Keyword set semantics ────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_adding_a_keyword_keeps_the_others(fake_redis: FakeRedis) -> None:
    """The client sends one keyword at a time. Against the old replace-only
    endpoint, adding the second keyword deleted the first."""
    from app.redis import add_user_keywords, get_user_keywords

    await add_user_keywords("u1", {"contract"})
    await add_user_keywords("u1", {"invoice"})

    assert await get_user_keywords("u1") == {"contract", "invoice"}


@pytest.mark.asyncio
async def test_removing_one_keyword_keeps_the_others(fake_redis: FakeRedis) -> None:
    """DELETE used to clear the whole set and ignore the keyword named in the
    body, so removing one entry silently destroyed the rest."""
    from app.redis import add_user_keywords, get_user_keywords, remove_user_keywords

    await add_user_keywords("u1", {"contract", "invoice", "urgent"})
    await remove_user_keywords("u1", {"invoice"})

    assert await get_user_keywords("u1") == {"contract", "urgent"}


@pytest.mark.asyncio
async def test_replace_is_still_available(fake_redis: FakeRedis) -> None:
    from app.redis import add_user_keywords, get_user_keywords, set_user_keywords

    await add_user_keywords("u1", {"old"})
    await set_user_keywords("u1", {"new"})

    assert await get_user_keywords("u1") == {"new"}


@pytest.mark.asyncio
async def test_keywords_are_scoped_per_user(fake_redis: FakeRedis) -> None:
    from app.redis import add_user_keywords, get_user_keywords

    await add_user_keywords("u1", {"mine"})
    await add_user_keywords("u2", {"theirs"})

    assert await get_user_keywords("u1") == {"mine"}
    assert await get_user_keywords("u2") == {"theirs"}


@pytest.mark.asyncio
async def test_read_failure_costs_alerts_not_the_upload(monkeypatch) -> None:
    """A Redis outage during an upload must not fail the upload itself."""
    import app.redis as keyword_store

    class Broken:
        async def smembers(self, key):
            raise ConnectionError("redis down")

    monkeypatch.setattr(keyword_store, "redis_sessions", Broken())
    assert await keyword_store.get_user_keywords("u1") == set()


# ── Duplicate suppression ────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_only_the_first_claim_on_a_document_succeeds(fake_redis: FakeRedis) -> None:
    """``set_alert_flag`` wrote a key no code path ever read, so the duplicate
    suppression it implied did not exist. SET NX makes the claim real."""
    from app.redis import claim_alert

    assert await claim_alert("file-1") is True
    assert await claim_alert("file-1") is False
    assert await claim_alert("file-2") is True


@pytest.mark.asyncio
async def test_claim_fails_open_when_redis_is_unreachable(monkeypatch) -> None:
    """Losing Redis should cost duplicate suppression, not every alert."""
    import app.redis as keyword_store

    class Broken:
        async def set(self, *a, **k):
            raise ConnectionError("redis down")

    monkeypatch.setattr(keyword_store, "redis_sessions", Broken())
    assert await keyword_store.claim_alert("file-1") is True


def test_the_claim_gates_the_notification() -> None:
    """Claiming after notifying would suppress nothing. Read structurally
    because the ordering, not the outcome, is the property under test."""
    from app.api.routes import media

    source = inspect.getsource(media._process_ocr)
    claim = source.index("claim_alert")
    publish = source.index("publish_ocr_alert(")
    push = source.index("send_ocr_push")
    assert claim < publish < push


# ── Alert payload ────────────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_alert_is_published_where_the_socket_listens(fake_redis: FakeRedis) -> None:
    from app.redis import ALERT_CHANNEL, publish_ocr_alert

    await publish_ocr_alert("file-1", "u1", "contract")

    assert len(fake_redis.published) == 1
    channel, raw = fake_redis.published[0]
    assert channel == ALERT_CHANNEL
    assert json.loads(raw) == {
        "file_id": "file-1",
        "user_id": "u1",
        "keyword": "contract",
    }


# ── The legacy path stays off ────────────────────────────────────────────────

def test_server_side_ocr_is_disabled_by_default() -> None:
    """Encryption is the default for every chat, so this path is dead on the
    live product. Turning it on means the server reads user attachments."""
    from app.config import settings

    assert settings.SERVER_SIDE_OCR_ENABLED is False


def test_upload_completion_respects_the_flag() -> None:
    from app.api.routes import media

    source = inspect.getsource(media.upload_complete)
    assert "settings.SERVER_SIDE_OCR_ENABLED" in source
    # …without weakening the encryption guard it sits beside.
    assert "not encrypted" in source
