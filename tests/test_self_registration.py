"""Tests for self-registration with a real phone number.

Registration is the one endpoint that creates an account from outside, so
what it refuses matters more than what it accepts.
"""
from __future__ import annotations

import inspect

import pytest


def _source(fn) -> str:
    return inspect.getsource(fn)


# ── The number must be proved, never claimed ─────────────────────────────────

def test_the_phone_number_comes_from_the_verified_token() -> None:
    """Taking it from the request body would let anyone register any number,
    which is the whole attack this endpoint has to stop."""
    from app.api.routes.auth import register_firebase
    from app.api.schemas import FirebaseRegisterIn

    assert "phone_number" not in FirebaseRegisterIn.model_fields
    source = _source(register_firebase)
    assert 'decoded.get("phone_number")' in source
    assert "verify_id_token" in source


def test_a_token_without_a_phone_claim_is_rejected() -> None:
    """A Firebase token from a different sign-in method proves nothing about
    a phone number."""
    from app.api.routes.auth import register_firebase

    source = _source(register_firebase)
    assert "firebase_id_token_missing_phone" in source


def test_an_unverifiable_token_is_rejected() -> None:
    from app.api.routes.auth import register_firebase

    assert "firebase_id_token_rejected" in _source(register_firebase)


# ── What registration sets, and what it does not check ───────────────────────

def test_the_military_id_is_stored_hashed() -> None:
    from app.api.routes.auth import register_firebase

    source = _source(register_firebase)
    assert "hash_military_id(body.military_id)" in source
    # The raw value must never be persisted.
    assert "military_id=body.military_id" not in source


def test_the_password_hash_is_random_not_a_shared_constant() -> None:
    """This path never uses a password, but the column is NOT NULL. A shared
    constant would be a real credential if password login were switched on."""
    from app.api.routes.auth import register_firebase

    assert "hash_password(secrets.token_hex(32))" in _source(register_firebase)


def test_registering_an_existing_number_is_a_conflict_not_a_second_account() -> None:
    from app.api.routes.auth import register_firebase

    source = _source(register_firebase)
    assert "HTTP_409_CONFLICT" in source
    assert "already has an account" in source


# ── Admission policy ─────────────────────────────────────────────────────────

def test_registration_can_be_closed_entirely() -> None:
    from app.api.routes.auth import register_firebase

    source = _source(register_firebase)
    assert "SELF_REGISTRATION_ENABLED" in source
    assert "HTTP_403_FORBIDDEN" in source


def test_approval_policy_decides_the_status() -> None:
    from app.api.routes.auth import register_firebase

    source = _source(register_firebase)
    assert "SELF_REGISTRATION_AUTO_APPROVE" in source
    assert "UserStatus.ACTIVE if approved else UserStatus.PENDING" in source


def test_an_unapproved_registration_gets_no_session() -> None:
    """Handing back a token that does not work yet would be worse than
    saying plainly that approval is pending."""
    from app.api.routes.auth import register_firebase

    source = _source(register_firebase)
    assert "if not approved:" in source
    assert "return RegisterOut(approved=False)" in source


def test_pending_is_its_own_status_not_reused_from_suspended() -> None:
    """SUSPENDED is a decision about someone who was already in; PENDING is
    the absence of a decision. Conflating them would make 'approve' and
    'un-suspend' the same action."""
    from app.models.user import UserStatus

    assert UserStatus.PENDING.value == "pending"
    assert UserStatus.PENDING != UserStatus.SUSPENDED


def test_a_pending_account_cannot_log_in() -> None:
    from app.api.routes.auth import verify_firebase

    source = _source(verify_firebase)
    assert "UserStatus.PENDING" in source
    assert "waiting for approval" in source


def test_a_pending_account_is_told_why_rather_than_blaming_the_code() -> None:
    """They just proved they control the number, so 'check your code' would be
    false and would have them retrying the SMS forever."""
    from app.api.routes.auth import verify_firebase

    source = _source(verify_firebase)
    pending_index = source.index("UserStatus.PENDING")
    generic_index = source.index("if user is None or user.status != UserStatus.ACTIVE")
    # The specific check has to come first, or the generic one swallows it.
    assert pending_index < generic_index


def test_only_active_accounts_pass_the_login_check() -> None:
    """The new status must not have widened what counts as allowed."""
    from app.api.routes.auth import verify_firebase

    assert "user.status != UserStatus.ACTIVE" in _source(verify_firebase)


# ── Route contract ───────────────────────────────────────────────────────────

def test_route_registered() -> None:
    from app.main import app

    paths = app.openapi()["paths"]
    assert "/api/v1/auth/register-firebase" in paths
    assert "post" in paths["/api/v1/auth/register-firebase"]


def test_full_name_is_bounded_and_not_blank() -> None:
    from pydantic import ValidationError

    from app.api.schemas import FirebaseRegisterIn

    base = {
        "id_token": "x" * 30,
        "military_id": "ABCD1234",
        "device_fingerprint": "f" * 20,
    }
    with pytest.raises(ValidationError):
        FirebaseRegisterIn(**base, full_name="   ")
    with pytest.raises(ValidationError):
        FirebaseRegisterIn(**base, full_name="a" * 200)

    # Interior whitespace is collapsed rather than rejected.
    assert FirebaseRegisterIn(
        **base, full_name="  Ahmed   Hassan "
    ).full_name == "Ahmed Hassan"


# ── Integration checklist ────────────────────────────────────────────────────
#
# Needs live Postgres and a Firebase project:
#   * a real number registers, then logs in with the military ID it set
#   * the same number registering twice gets 409
#   * with AUTO_APPROVE off, registration returns approved=False and the
#     subsequent login returns 403 until an admin activates the account
#
# Firebase configuration is a prerequisite for any of the above with a real
# number — see HANDOVER: the Android app must be registered under its actual
# package with its signing SHA-1/SHA-256, or only test numbers work.
