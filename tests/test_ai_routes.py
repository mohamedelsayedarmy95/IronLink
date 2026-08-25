"""Contract tests for the AI endpoints and Firebase credential loading.

The AI routes were written against a Flutter client that is already shipped, so
their field names are not free to change — a rename here is a silent runtime
break in the app, not a compile error anywhere. These tests freeze the contract
against frontend/lib/features/chat/bloc/chat_bloc.dart.
"""
from __future__ import annotations

import pytest


# ── Route registration ─────────────────────────────────────────────────────────

@pytest.mark.parametrize(
    "path",
    [
        "/api/v1/chats/{peer_id}/summary",
        "/api/v1/ai/smart-replies",
        "/api/v1/ai/translate",
        "/api/v1/ai/moderate",
    ],
)
def test_ai_route_registered(path: str) -> None:
    from app.main import app

    paths = app.openapi()["paths"]
    assert path in paths, f"{path} is not registered"
    assert "post" in paths[path], f"{path} must accept POST"


# ── Request / response field contract ──────────────────────────────────────────

CONTRACT = [
    # (path, request fields, response fields) — mirrors chat_bloc.dart exactly.
    #
    # peer_id/group_id were added when these endpoints were put behind
    # consent: without knowing which conversation the text came from, the
    # server cannot tell whose agreement applies, so there is nothing to
    # enforce. The client sends them — see test_ai_consent.py.
    #
    # The summary endpoint takes its peer_id from the URL, so its body is
    # unchanged.
    ("/api/v1/chats/{peer_id}/summary", {"messages"}, {"summary"}),
    (
        "/api/v1/ai/smart-replies",
        {"context", "num_replies", "peer_id", "group_id"},
        {"replies"},
    ),
    (
        "/api/v1/ai/translate",
        {"text", "target_lang", "peer_id", "group_id"},
        {"translation"},
    ),
    ("/api/v1/ai/moderate", {"text", "peer_id", "group_id"}, {"scores"}),
]


def _schema_for(spec: dict, ref: str) -> dict:
    return spec["components"]["schemas"][ref.rsplit("/", 1)[-1]]


@pytest.mark.parametrize("path,req_fields,res_fields", CONTRACT)
def test_field_names_match_the_shipped_client(
    path: str, req_fields: set[str], res_fields: set[str]
) -> None:
    from app.main import app

    spec = app.openapi()
    op = spec["paths"][path]["post"]

    req_ref = op["requestBody"]["content"]["application/json"]["schema"]["$ref"]
    got_req = set(_schema_for(spec, req_ref).get("properties", {}))
    assert got_req == req_fields, (
        f"{path} request fields drifted from the shipped app: "
        f"expected {sorted(req_fields)}, got {sorted(got_req)}"
    )

    res_ref = op["responses"]["200"]["content"]["application/json"]["schema"]["$ref"]
    got_res = set(_schema_for(spec, res_ref).get("properties", {}))
    assert got_res == res_fields, (
        f"{path} response fields drifted from the shipped app: "
        f"expected {sorted(res_fields)}, got {sorted(got_res)}"
    )


# ── Firebase credential loading ────────────────────────────────────────────────

def test_firebase_configured_accepts_either_source() -> None:
    from app.config import Settings

    # _env_file=None and explicit values keep this independent of the developer's
    # local .env — which does set FIREBASE_CREDENTIALS_FILE, and would otherwise
    # make this pass here and fail in CI.
    base = dict(
        _env_file=None,
        POSTGRES_PASSWORD="x",
        DB_ENCRYPTION_KEY="k" * 32,
        S3_SECRET_ACCESS_KEY="x",
    )

    neither = Settings(**base, FIREBASE_CREDENTIALS_FILE="", FIREBASE_CREDENTIALS_JSON="")
    assert not neither.firebase_configured

    file_only = Settings(**base, FIREBASE_CREDENTIALS_FILE="/tmp/sa.json", FIREBASE_CREDENTIALS_JSON="")
    assert file_only.firebase_configured

    json_only = Settings(
        **base,
        FIREBASE_CREDENTIALS_FILE="",
        FIREBASE_CREDENTIALS_JSON='{"type":"service_account"}',
    )
    assert json_only.firebase_configured


def test_malformed_firebase_json_disables_push_without_crashing(monkeypatch) -> None:
    """A truncated or shell-mangled paste must not take the process down.

    Push is a degradable feature; the rest of the API has to keep serving.
    """
    from app.config import settings
    from app.services import push_service

    monkeypatch.setattr(settings, "FIREBASE_CREDENTIALS_JSON", "{not valid json", raising=False)
    monkeypatch.setattr(settings, "FIREBASE_CREDENTIALS_FILE", "", raising=False)
    monkeypatch.setattr(push_service, "_initialized", False, raising=False)
    monkeypatch.setattr(push_service, "_available", False, raising=False)

    assert push_service._ensure_init() is False


# ── Graceful degradation ───────────────────────────────────────────────────────

@pytest.mark.asyncio
async def test_ai_degrades_when_redis_and_hf_are_both_unavailable() -> None:
    """Neither an unreachable cache nor a missing token may raise.

    The cache reads originally sat outside the try block guarding the Hugging
    Face call, so a Redis outage propagated ConnectionError straight out of the
    endpoint — a 500 for a feature that is supposed to fall back. Redis is not
    running in the test environment, which is exactly the condition to assert.
    """
    from app.services.ai_service import ai_service

    assert not ai_service.enabled, "test assumes HF_API_TOKEN is unset"

    assert await ai_service.generate_smart_replies("hello") == [
        "Thanks!",
        "Sounds good",
        "Let me know",
    ]
    # Translation falls back to the original text, never to empty.
    assert await ai_service.translate_message("hello", "arb_Arab") == "hello"
    # Empty dict means "no verdict", not "safe".
    assert await ai_service.moderate_message("hello") == {}
    # Short input is returned as-is rather than lost.
    assert await ai_service.summarize_messages(["a b c"]) == "a b c"


def test_push_disabled_when_nothing_configured(monkeypatch) -> None:
    from app.config import settings
    from app.services import push_service

    monkeypatch.setattr(settings, "FIREBASE_CREDENTIALS_JSON", "", raising=False)
    monkeypatch.setattr(settings, "FIREBASE_CREDENTIALS_FILE", "", raising=False)
    monkeypatch.setattr(push_service, "_initialized", False, raising=False)
    monkeypatch.setattr(push_service, "_available", False, raising=False)

    assert push_service._ensure_init() is False
