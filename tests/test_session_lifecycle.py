"""Tests for session-bound authentication and token refresh.

Three defects shared one root cause: the access token was validated only
against User.token_version, and UserSession played no part in authenticating
a request. That meant remote-kick did nothing to requests, signing in on a
second device kicked the first, and there was no way to renew a token at all.
"""
from __future__ import annotations

import inspect

import pytest


def _source(fn) -> str:
    return inspect.getsource(fn)


# ── Session binding ──────────────────────────────────────────────────────────

def test_a_request_is_authenticated_against_its_session() -> None:
    """Revoking a session must stop the device immediately. Before this, the
    kicked device kept working until its token expired on its own."""
    from app.api.deps import get_current_user

    source = _source(get_current_user)
    assert "UserSession" in source
    assert "UserSession.revoked_at.is_(None)" in source


def test_an_expired_session_is_rejected() -> None:
    from app.api.deps import get_current_user

    assert "UserSession.expires_at >" in _source(get_current_user)


def test_the_session_must_belong_to_the_token_holder() -> None:
    """Otherwise anyone could quote someone else's live session id."""
    from app.api.deps import get_current_user

    assert "UserSession.user_id == user.id" in _source(get_current_user)


def test_a_token_without_a_session_claim_is_refused() -> None:
    """Accepting them 'for compatibility' would reopen the hole for as long
    as any old token lived."""
    from app.api.deps import get_current_user

    source = _source(get_current_user)
    assert 'UUID(payload["sid"])' in source
    # The missing-claim path raises rather than falling through.
    assert "except (KeyError, ValueError, TypeError):" in source


def test_the_account_wide_lever_still_exists() -> None:
    """token_version stays as the way to invalidate everything at once for a
    compromised account. Session binding narrows revocation, it does not
    replace it."""
    from app.api.deps import get_current_user

    assert "token_version != user.token_version" in _source(get_current_user)


# ── Signing in no longer kicks your other devices ────────────────────────────

def test_login_does_not_bump_token_version() -> None:
    """It used to, which invalidated every other device on each sign-in —
    directly contradicting this file's own remote-kick design, where other
    devices of the same user are untouched."""
    from app.api.routes.auth import _issue_login

    assert "token_version += 1" not in _source(_issue_login)


def test_the_session_exists_before_the_token_is_minted() -> None:
    """The token carries the session id, so the row has to be flushed first."""
    from app.api.routes.auth import _issue_login

    source = _source(_issue_login)
    assert source.index("db.flush()") < source.index("create_access_token")


# ── Refresh ──────────────────────────────────────────────────────────────────

def test_a_refresh_endpoint_exists() -> None:
    """There was none. Access tokens live an hour, so every user was signed
    out after sixty minutes and had to redo SMS verification — while the
    refresh token was generated, stored on both sides, and never used."""
    from app.main import app

    paths = app.openapi()["paths"]
    assert "/api/v1/auth/refresh" in paths
    assert "post" in paths["/api/v1/auth/refresh"]


def test_refresh_rotates_the_token() -> None:
    """A refresh token that survives its own use is a long-lived credential;
    rotation makes a stolen one usable at most once."""
    from app.api.routes.auth import refresh_access_token

    source = _source(refresh_access_token)
    assert "generate_refresh_token()" in source
    assert "session.refresh_token_hash = hash_refresh_token(new_refresh)" in source


def test_refresh_keeps_the_hash_it_replaced() -> None:
    """Rotation alone cannot tell theft from a retry: the old token simply
    matches nothing. Keeping the previous hash is what makes a replay
    visible."""
    from app.api.routes.auth import refresh_access_token

    assert "session.previous_refresh_token_hash = session.refresh_token_hash" \
        in _source(refresh_access_token)


def test_replaying_a_used_refresh_token_revokes_the_session() -> None:
    """Either a thief or the real device is replaying it and there is no way
    to tell which, so the session dies. One re-login is a smaller harm than
    an attacker holding a renewable foothold."""
    from app.api.routes.auth import refresh_access_token

    source = _source(refresh_access_token)
    assert "previous_refresh_token_hash == token_hash" in source
    assert "refresh_token_reuse" in source
    assert "replayed.revoked_at = now" in source


def test_a_revoked_or_expired_session_cannot_refresh() -> None:
    from app.api.routes.auth import refresh_access_token

    source = _source(refresh_access_token)
    assert "session.revoked_at is not None or expires_at <= now" in source


def test_refresh_refuses_a_non_active_user() -> None:
    """A suspended account must not be able to renew its way back in."""
    from app.api.routes.auth import refresh_access_token

    assert "user.status != UserStatus.ACTIVE" in _source(refresh_access_token)


def test_refresh_slides_the_expiry() -> None:
    """A device in daily use should not be signed out on the seventh day."""
    from app.api.routes.auth import refresh_access_token

    assert "session.expires_at = now + timedelta" in _source(refresh_access_token)


def test_the_new_access_token_is_bound_to_the_same_session() -> None:
    """Minting one against a new session would leave the old row orphaned and
    make revocation miss."""
    from app.api.routes.auth import refresh_access_token

    assert "user.token_version, user.role, session.id" in _source(
        refresh_access_token
    )


def test_refresh_failures_are_indistinguishable() -> None:
    """Unknown, expired, revoked and replayed all return the same thing, so
    the endpoint cannot be used to probe which tokens exist."""
    from app.api.routes.auth import refresh_access_token

    source = _source(refresh_access_token)
    # One error object, raised on every failure path — unknown token,
    # revoked session, expired session, replayed token, inactive user.
    assert source.count("HTTPException(") == 1
    assert source.count("raise invalid") == 3
    # And nothing leaks a more specific reason to the caller.
    assert "detail=" not in source.split("invalid = HTTPException(")[1].split(")")[1]


# ── Migration ────────────────────────────────────────────────────────────────

def test_migration_adds_the_reuse_column() -> None:
    from pathlib import Path

    migration = Path(
        "alembic/versions/0008_session_bound_tokens.py"
    ).read_text(encoding="utf-8")
    assert "previous_refresh_token_hash" in migration
    # The replay path must stay cheap — it is what an attacker hits.
    assert "ix_user_sessions_previous_refresh" in migration


# ── Integration checklist ────────────────────────────────────────────────────
#
# Needs live Postgres:
#   * refresh returns a working token, and the old refresh token then fails
#   * replaying the old one revokes the session and the access token dies
#   * revoking a session makes that device's next request 401 immediately
#   * signing in on a second device leaves the first working
#   * a token minted before this change (no sid) is refused
