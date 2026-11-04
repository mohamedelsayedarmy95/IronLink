"""Tests for the E2EE public key directory.

These guard a security boundary, not a feature. The implementation this
replaced stored Signal private keys and session state server-side and threw
away the client's uploaded public key in favour of a server-generated mock —
a server holding private keys can read every message, so "E2EE" was a label
with nothing behind it.

The tests below are therefore written to fail loudly if anyone reintroduces
private-key storage, weakens pre-key single-use, or drops the client-side
signature verification contract.
"""
from __future__ import annotations

import base64

import pytest
from pydantic import ValidationError


def _b64(n: int = 33) -> str:
    return base64.b64encode(bytes(range(n % 251 or 1)) * (n // 250 + 1))[:44].decode()


# ── The core invariant: no private key material anywhere ───────────────────────

def test_no_private_key_columns_in_schema() -> None:
    """The key tables must be incapable of holding a private key.

    This is deliberately a schema assertion rather than a behavioural one: the
    guarantee should hold because there is nowhere to put a private key, not
    because the current handlers happen not to write one.
    """
    from app.models import OneTimePreKey, UserKeyBundle

    for model in (UserKeyBundle, OneTimePreKey):
        for column in model.__table__.columns:
            name = column.name.lower()
            assert "private" not in name, (
                f"{model.__tablename__}.{column.name} looks like private key "
                f"material — private keys must never reach the server"
            )
            assert "secret" not in name, (
                f"{model.__tablename__}.{column.name} looks like secret material"
            )


def test_upload_schema_rejects_private_key_fields() -> None:
    """A client cannot smuggle a private key in via an extra field."""
    from app.api.routes.keys import KeyBundleUpload

    payload = {
        "registration_id": 1,
        "identity_key": _b64(),
        "signed_prekey_id": 1,
        "signed_prekey_public": _b64(),
        "signed_prekey_signature": _b64(64),
        "identity_private_key": _b64(),  # must not be persisted
    }
    bundle = KeyBundleUpload(**payload)
    assert not hasattr(bundle, "identity_private_key")


def test_encryption_service_is_gone() -> None:
    """The server must not carry code that encrypts or decrypts messages.

    Its presence was what made private-key storage look reasonable.
    """
    import importlib

    with pytest.raises(ModuleNotFoundError):
        importlib.import_module("app.services.encryption_service")


# ── Route contract ─────────────────────────────────────────────────────────────

@pytest.mark.parametrize(
    "path,method",
    [
        ("/api/v1/keys/bundle", "post"),
        ("/api/v1/keys/prekeys", "post"),
        ("/api/v1/keys/prekeys/count", "get"),
        ("/api/v1/keys/bundle/{user_id}", "get"),
    ],
)
def test_key_route_registered(path: str, method: str) -> None:
    from app.main import app

    paths = app.openapi()["paths"]
    assert path in paths, f"{path} is not registered"
    assert method in paths[path], f"{path} must accept {method.upper()}"


def test_fetched_bundle_exposes_only_public_material() -> None:
    from app.api.routes.keys import PreKeyBundleOut

    fields = set(PreKeyBundleOut.model_fields)
    assert fields == {
        "user_id",
        "registration_id",
        "identity_key",
        "signed_prekey_id",
        "signed_prekey_public",
        "signed_prekey_signature",
        "one_time_prekey_id",
        "one_time_prekey",
    }


def test_bundle_tolerates_exhausted_prekeys() -> None:
    """one_time_prekey must be optional.

    Pre-keys run out when a user has been offline. libsignal can still open a
    session without one; refusing to return a bundle would make the peer
    unreachable instead, which is a worse failure than the slightly weaker
    forward secrecy on the first message.
    """
    from app.api.routes.keys import PreKeyBundleOut

    assert PreKeyBundleOut.model_fields["one_time_prekey"].default is None
    assert PreKeyBundleOut.model_fields["one_time_prekey_id"].default is None


# ── Input validation ───────────────────────────────────────────────────────────

def test_rejects_non_base64_key() -> None:
    from app.api.routes.keys import KeyBundleUpload

    with pytest.raises(ValidationError):
        KeyBundleUpload(
            registration_id=1,
            identity_key="not valid base64!!",
            signed_prekey_id=1,
            signed_prekey_public=_b64(),
            signed_prekey_signature=_b64(64),
        )


def test_rejects_oversized_key() -> None:
    """Bounds the directory against being used as free storage."""
    from app.api.routes.keys import KeyBundleUpload

    with pytest.raises(ValidationError):
        KeyBundleUpload(
            registration_id=1,
            identity_key=base64.b64encode(b"x" * 4096).decode(),
            signed_prekey_id=1,
            signed_prekey_public=_b64(),
            signed_prekey_signature=_b64(64),
        )


def test_rejects_duplicate_prekey_ids() -> None:
    """Duplicate ids would make single-use consumption ambiguous."""
    from app.api.routes.keys import PreKeysUpload

    with pytest.raises(ValidationError):
        PreKeysUpload(
            one_time_prekeys=[
                {"key_id": 7, "public_key": _b64()},
                {"key_id": 7, "public_key": _b64()},
            ]
        )


def test_prekey_upload_is_bounded() -> None:
    from app.api.routes.keys import _MAX_PREKEYS_PER_UPLOAD, PreKeysUpload

    with pytest.raises(ValidationError):
        PreKeysUpload(
            one_time_prekeys=[
                {"key_id": i, "public_key": _b64()}
                for i in range(_MAX_PREKEYS_PER_UPLOAD + 1)
            ]
        )


# ── Single-use consumption ─────────────────────────────────────────────────────

def test_prekey_claim_is_a_delete_not_a_flag() -> None:
    """Handing the same one-time pre-key to two senders breaks forward secrecy.

    The claim is implemented as DELETE ... RETURNING precisely so that two
    concurrent fetches cannot both win. A SELECT-then-DELETE, or a soft
    `consumed_at` flag set after reading, would reintroduce the race — so this
    asserts on the mechanism, which is the part that is easy to "simplify" into
    a bug later.
    """
    import inspect

    from app.api.routes.keys import fetch_key_bundle

    source = inspect.getsource(fetch_key_bundle)
    assert "delete(OneTimePreKey)" in source, "pre-key claim must delete the row"
    assert "returning(" in source, "claim must use RETURNING to detect the winner"
    assert "skip_locked" in source, "concurrent claims must not block on each other"


def test_one_time_prekey_has_no_soft_consume_column() -> None:
    from app.models import OneTimePreKey

    names = {c.name for c in OneTimePreKey.__table__.columns}
    assert "consumed_at" not in names, (
        "single-use pre-keys are deleted on claim; a soft flag invites the "
        "double-hand-out race this design avoids"
    )
