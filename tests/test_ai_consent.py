"""Tests for the consent gate on the AI features.

These endpoints are the only place message plaintext leaves the device and
reaches a third party. Everything else in this product is built so the server
cannot read messages; here the client decrypts and posts them, and the server
forwards them to Hugging Face.

So the tests that matter are about what is refused.
"""
from __future__ import annotations

import inspect

import pytest


def _source(fn) -> str:
    return inspect.getsource(fn)


AI_ENDPOINTS = [
    "summarize_conversation",
    "generate_smart_replies",
    "translate_message",
    "moderate_message",
]


# ── Every endpoint is gated ──────────────────────────────────────────────────

@pytest.mark.parametrize("name", AI_ENDPOINTS)
def test_every_ai_endpoint_requires_consent(name: str) -> None:
    """Missing one leaves an open path to the provider, and it would be the
    one nobody thinks about."""
    from app.api.routes import ai

    fn = getattr(ai, name)
    assert "_require_consent" in _source(fn), f"{name} is not gated"


@pytest.mark.parametrize("name", AI_ENDPOINTS)
def test_the_gate_runs_before_the_provider_call(name: str) -> None:
    """Checking after the call would still have sent the text."""
    from app.api.routes import ai

    source = _source(getattr(ai, name))
    gate = source.index("_require_consent")
    call = source.index("ai_service.")
    assert gate < call, f"{name} calls the provider before checking consent"


def test_enforcement_is_server_side() -> None:
    """A client-side check is a suggestion. The point is that a modified
    build cannot post someone else's messages to a third party."""
    from app.api.routes.ai import _require_consent

    source = _source(_require_consent)
    assert "ai_consent_service" in source
    assert "HTTP_403_FORBIDDEN" in source


# ── Both parties, not just the requester ─────────────────────────────────────

def test_a_direct_conversation_needs_both_people() -> None:
    """A summary is made of both people's words. One side agreeing would mean
    sending the other's messages to a third party on their behalf."""
    from app.services.ai_consent_service import require_direct

    source = _source(require_direct)
    # Checked from each side's own scope: this user's row names the peer and
    # the peer's row names this user.
    assert "user_id=user_id, scope_type=AiScopeType.DIRECT, scope_id=peer_id" in source
    assert "user_id=peer_id, scope_type=AiScopeType.DIRECT, scope_id=user_id" in source


def test_a_group_needs_every_member() -> None:
    from app.services.ai_consent_service import require_group

    source = _source(require_group)
    assert "GroupMember.group_id == group_id" in source
    assert "missing" in source


def test_an_empty_group_is_refused_rather_than_allowed() -> None:
    """A membership query returning nothing must not read as 'nobody
    objects'."""
    from app.services.ai_consent_service import require_group

    source = _source(require_group)
    assert "if not member_ids:" in source
    index = source.index("if not member_ids:")
    assert "raise AiConsentMissing" in source[index:index + 200]


def test_the_refusal_names_who_is_missing() -> None:
    """'Waiting for Sara' is something the user can act on; a bare refusal
    looks like a bug."""
    from app.api.routes.ai import _require_consent

    source = _source(_require_consent)
    assert "waiting_on" in source
    assert "missing_names" in source


# ── Consent is per conversation, and withdrawable ────────────────────────────

def test_consent_is_scoped_not_a_profile_setting() -> None:
    """What is disclosed is a conversation. Agreeing that one chat may be
    summarised says nothing about another."""
    from app.models import AiConsent

    assert "scope_type" in AiConsent.__table__.columns
    assert "scope_id" in AiConsent.__table__.columns


def test_withdrawal_stamps_rather_than_deletes() -> None:
    """Withdrawing stops future transmission but cannot un-send what already
    went. The dates are what keep that answerable."""
    from app.services.ai_consent_service import revoke

    source = _source(revoke)
    assert "revoked_at" in source
    assert "db.delete" not in source


def test_only_live_consent_counts() -> None:
    from app.services.ai_consent_service import _active

    assert "revoked_at.is_(None)" in _source(_active)


def test_re_granting_after_withdrawal_is_possible() -> None:
    """A plain unique constraint would make the first withdrawal permanent.
    The index is partial so a withdrawn row does not block a new one."""
    from pathlib import Path

    migration = Path("alembic/versions/0007_ai_consent.py").read_text(
        encoding="utf-8"
    )
    index = migration.index("uq_ai_consent_scope")
    window = migration[index:index + 400]
    assert "revoked_at IS NULL" in window
    assert "unique=True" in window


# ── The server must be able to tell whose consent applies ────────────────────

@pytest.mark.parametrize("schema", ["TranslateIn", "ModerateIn", "SmartRepliesIn"])
def test_ai_requests_carry_the_conversation(schema: str) -> None:
    """These used to take a bare string, so there was no way to know whose
    consent applied — and therefore nothing to enforce."""
    from app.api.routes import ai

    fields = getattr(ai, schema).model_fields
    assert "peer_id" in fields
    assert "group_id" in fields


def test_exactly_one_scope_is_required() -> None:
    """Both, or neither, would leave it ambiguous whose consent to check."""
    from app.api.routes.ai import _require_consent

    assert "(peer_id is None) == (group_id is None)" in _source(_require_consent)


# ── A global off switch ──────────────────────────────────────────────────────

def test_the_features_can_be_disabled_entirely() -> None:
    """A deployment that would rather not offer the choice at all."""
    from app.api.routes.ai import _require_consent
    from app.config import settings

    assert hasattr(settings, "AI_FEATURES_ENABLED")
    assert "AI_FEATURES_ENABLED" in _source(_require_consent)


def test_the_kill_switch_is_checked_before_consent() -> None:
    """Otherwise a disabled deployment still runs the consent lookups."""
    from app.api.routes.ai import _require_consent

    source = _source(_require_consent)
    assert source.index("AI_FEATURES_ENABLED") < source.index("require_group")


# ── Reporting is deliberately NOT gated ──────────────────────────────────────

def test_reporting_a_message_does_not_need_consent() -> None:
    """Someone sending abuse does not get to veto being reported. The report
    flow goes to a human moderator, not to the AI provider — a different
    thing entirely from the toxicity classifier."""
    from app.api.routes.moderation import submit_report

    source = _source(submit_report)
    assert "consent" not in source.lower()


# ── Route contract ───────────────────────────────────────────────────────────

@pytest.mark.parametrize(
    "path,method",
    [
        ("/api/v1/ai/consent", "get"),
        ("/api/v1/ai/consent", "put"),
    ],
)
def test_consent_routes_registered(path: str, method: str) -> None:
    from app.main import app

    paths = app.openapi()["paths"]
    assert path in paths
    assert method in paths[path]


# ── The client stops volunteering content ────────────────────────────────────

def test_the_client_no_longer_summarises_automatically() -> None:
    """It used to fire whenever more than 20 messages were unread — sending
    the conversation to a third party on merely opening a chat."""
    from pathlib import Path

    bloc = Path("frontend/lib/features/chat/bloc/chat_bloc.dart")
    if not bloc.exists():
        pytest.skip("frontend not present")

    source = bloc.read_text(encoding="utf-8")
    assert "unreadCount > 20" not in source
    assert "add(ChatFetchSummaryStarted())" not in source


def test_the_client_sends_the_conversation_id() -> None:
    """Without it the server cannot tell whose consent applies."""
    from pathlib import Path

    bloc = Path("frontend/lib/features/chat/bloc/chat_bloc.dart")
    if not bloc.exists():
        pytest.skip("frontend not present")

    source = bloc.read_text(encoding="utf-8")
    # translate, moderate and smart-replies each carry it.
    assert source.count("'peer_id': peerId") >= 3


# ── Integration checklist ────────────────────────────────────────────────────
#
# Needs live Postgres:
#   * a summary with one side consenting returns 403 naming the other
#   * with both consenting it reaches the provider
#   * withdrawing one side makes the next call 403 again
#   * a group with one silent member refuses
#   * re-granting after a withdrawal succeeds and leaves two rows
