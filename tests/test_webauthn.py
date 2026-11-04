"""WebAuthn hardware-key tests.

The security property is not "an options endpoint exists". It is that a
credential can only be enrolled by the authenticated account it belongs to, a
challenge can only be used once, an assertion must verify against the stored
public key, and a suspended account cannot turn a valid assertion into a
session.

The authenticator below is a real one in miniature: an EC P-256 key signs a
WebAuthn authenticator-data blob, wrapped in the same CBOR attestation object a
browser produces. The `webauthn` library verifies it in full. No test mocks the
verifier, so a future change that stops passing the challenge, origin, RP id,
public key, or counter through to it will fail here.
"""
from __future__ import annotations

import hashlib
import inspect
import json
import uuid
from datetime import date, datetime, timedelta, timezone
from pathlib import Path
from types import SimpleNamespace
from typing import Any

import cbor2
import pytest
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import ec
from fastapi import FastAPI
from fastapi.testclient import TestClient
from pydantic import ValidationError
from sqlalchemy import ForeignKeyConstraint, LargeBinary, UniqueConstraint
from webauthn.helpers import base64url_to_bytes, bytes_to_base64url

from app.api.deps import get_current_user
from app.api.routes import webauthn as webauthn_routes
from app.api.routes.auth import _issue_login
from app.api.schemas import (
    UserOut,
    VerifyOut,
    WebAuthnAuthenticateCompleteIn,
    WebAuthnCredentialOut,
    WebAuthnRegisterCompleteIn,
)
from app.config import settings
from app.core.database import get_db
from app.models import AuditLog, Base, User, WebAuthnCredential
from app.models.audit_log import AuditAction
from app.models.user import UserRole, UserStatus
from app.services.webauthn_service import (
    WebAuthnDuplicateCredential,
    WebAuthnError,
    WebAuthnService,
)
from tests.fakes import FakeRedis

_API = f"{settings.API_PREFIX}/auth/webauthn"


# ── A small, real authenticator ──────────────────────────────────────────────


def _b64(value: bytes) -> str:
    return bytes_to_base64url(value)


def _make_key() -> tuple[ec.EllipticCurvePrivateKey, bytes]:
    key = ec.generate_private_key(ec.SECP256R1())
    numbers = key.public_key().public_numbers()
    cose = cbor2.dumps(
        {
            1: 2,  # kty: EC2
            3: -7,  # alg: ES256
            -1: 1,  # crv: P-256
            -2: numbers.x.to_bytes(32, "big"),
            -3: numbers.y.to_bytes(32, "big"),
        }
    )
    return key, cose


def _client_data(*, kind: str, challenge: str, origin: str) -> bytes:
    return json.dumps(
        {
            "type": kind,
            "challenge": challenge,
            "origin": origin,
            "crossOrigin": False,
        },
        separators=(",", ":"),
    ).encode("utf-8")


def _registration_credential(
    challenge: str,
    credential_id: bytes,
    *,
    origin: str | None = None,
) -> tuple[dict[str, Any], ec.EllipticCurvePrivateKey, bytes]:
    key, cose = _make_key()
    rp_id = settings.WEBAUTHN_RP_ID
    origin = origin or settings.WEBAUTHN_ORIGIN
    auth_data = (
        hashlib.sha256(rp_id.encode("utf-8")).digest()
        # UP | UV | AT. A real security key sets all three when it verifies
        # the user at registration.
        + bytes([0x45])
        + (0).to_bytes(4, "big")
        + b"\x00" * 16  # AAGUID
        + len(credential_id).to_bytes(2, "big")
        + credential_id
        + cose
    )
    attestation_object = cbor2.dumps(
        {"fmt": "none", "attStmt": {}, "authData": auth_data}
    )
    client_data = _client_data(
        kind="webauthn.create",
        challenge=challenge,
        origin=origin,
    )
    credential = {
        "id": _b64(credential_id),
        "rawId": _b64(credential_id),
        "type": "public-key",
        "response": {
            "clientDataJSON": _b64(client_data),
            "attestationObject": _b64(attestation_object),
            "transports": ["usb"],
        },
    }
    return credential, key, cose


def _authentication_credential(
    challenge: str,
    credential_id: bytes,
    key: ec.EllipticCurvePrivateKey,
    user_handle: bytes,
    *,
    sign_count: int = 1,
    origin: str | None = None,
) -> dict[str, Any]:
    origin = origin or settings.WEBAUTHN_ORIGIN
    auth_data = (
        hashlib.sha256(settings.WEBAUTHN_RP_ID.encode("utf-8")).digest()
        + bytes([0x05])  # UP | UV
        + sign_count.to_bytes(4, "big")
    )
    client_data = _client_data(
        kind="webauthn.get",
        challenge=challenge,
        origin=origin,
    )
    signature = key.sign(
        auth_data + hashlib.sha256(client_data).digest(),
        ec.ECDSA(hashes.SHA256()),
    )
    return {
        "id": _b64(credential_id),
        "rawId": _b64(credential_id),
        "type": "public-key",
        "response": {
            "clientDataJSON": _b64(client_data),
            "authenticatorData": _b64(auth_data),
            "signature": _b64(signature),
            "userHandle": _b64(user_handle),
        },
    }


# ── Minimal async database fake ──────────────────────────────────────────────


class _Rows:
    def __init__(self, rows: list[Any]) -> None:
        self._rows = rows

    def all(self) -> list[Any]:
        return list(self._rows)


class FakeSession:
    """Returns queued scalar results and records writes.

    The service queries in a fixed order, so one queue per query shape is
    enough. This is deliberately not an SQL engine: the tests below are about
    the security decisions around the queries, not about SQLAlchemy.
    """

    def __init__(
        self,
        *,
        scalar_results: list[Any] | None = None,
        scalars_results: list[list[Any]] | None = None,
    ) -> None:
        self.scalar_results = list(scalar_results or [])
        self.scalars_results = list(scalars_results or [])
        self.added: list[Any] = []
        self.deleted: list[Any] = []
        self.refreshed: list[Any] = []
        self.commits = 0
        self.rollbacks = 0
        self.flushes = 0

    async def scalar(self, _stmt):
        return self.scalar_results.pop(0) if self.scalar_results else None

    async def scalars(self, _stmt):
        rows = self.scalars_results.pop(0) if self.scalars_results else []
        return _Rows(rows)

    def add(self, obj: Any) -> None:
        self.added.append(obj)

    async def flush(self) -> None:
        self.flushes += 1
        now = datetime.now(timezone.utc)
        for obj in self.added:
            if getattr(obj, "id", None) is None:
                obj.id = uuid.uuid4()
            if hasattr(obj, "created_at") and getattr(obj, "created_at", None) is None:
                obj.created_at = now
            if hasattr(obj, "updated_at") and getattr(obj, "updated_at", None) is None:
                obj.updated_at = now

    async def refresh(self, obj: Any) -> None:
        self.refreshed.append(obj)

    async def commit(self) -> None:
        self.commits += 1

    async def rollback(self) -> None:
        self.rollbacks += 1

    async def delete(self, obj: Any) -> None:
        self.deleted.append(obj)


def _user(
    *,
    status: str = UserStatus.ACTIVE,
    expiry_date: date | None = None,
) -> User:
    return User(
        id=uuid.uuid4(),
        phone_number="+201001234567",
        full_name="Test Soldier",
        username=None,
        hashed_military_id="hashed-mid",
        hashed_password="hashed-password",
        status=status,
        role=UserRole.SOLDIER,
        token_version=1,
        expiry_date=expiry_date,
    )


def _credential_row(
    user: User,
    *,
    credential_id: bytes = b"credential-1",
    public_key: bytes = b"public-key",
    sign_count: int = 0,
) -> WebAuthnCredential:
    now = datetime.now(timezone.utc)
    return WebAuthnCredential(
        id=uuid.uuid4(),
        user_id=user.id,
        credential_id=credential_id,
        public_key=public_key,
        sign_count=sign_count,
        transports=["usb"],
        aaguid="00000000-0000-0000-0000-000000000000",
        credential_type="public-key",
        user_verified=True,
        backup_eligible=False,
        backup_state=False,
        nickname="Field key",
        created_at=now,
        updated_at=now,
    )


def _service(db: FakeSession, redis: FakeRedis | None = None) -> WebAuthnService:
    return WebAuthnService(redis or FakeRedis(), db)


# ── Registration options and ceremony lifecycle ─────────────────────────────


async def test_registration_requests_a_resident_cross_platform_key() -> None:
    user = _user()
    db = FakeSession(scalars_results=[[]])
    service = _service(db)

    ceremony = await service.begin_registration(user)

    options = ceremony.options
    selection = options["authenticatorSelection"]
    expected_uv = (
        "required" if settings.WEBAUTHN_REQUIRE_USER_VERIFICATION else "preferred"
    )
    assert options["rp"]["id"] == settings.WEBAUTHN_RP_ID
    assert options["user"]["id"] == _b64(user.id.bytes)
    assert selection["authenticatorAttachment"] == "cross-platform"
    assert selection["residentKey"] == "required"
    assert selection["requireResidentKey"] is True
    assert selection["userVerification"] == expected_uv
    assert options["attestation"] == "none"
    assert options["excludeCredentials"] == []
    assert ceremony.expires_in == settings.WEBAUTHN_CHALLENGE_TTL_SECONDS


async def test_registration_options_exclude_already_registered_keys() -> None:
    user = _user()
    existing = _credential_row(user, credential_id=b"already-there")
    db = FakeSession(scalars_results=[[existing]])
    service = _service(db)

    ceremony = await service.begin_registration(user)

    assert ceremony.options["excludeCredentials"] == [
        {"type": "public-key", "id": _b64(b"already-there")}
    ]


async def test_registration_round_trip_verifies_and_stores_public_material() -> None:
    user = _user()
    db = FakeSession(scalars_results=[[]], scalar_results=[None])
    redis = FakeRedis()
    service = _service(db, redis)
    credential_id = b"round-trip-credential"

    ceremony = await service.begin_registration(user)
    credential, _key, cose = _registration_credential(
        ceremony.options["challenge"], credential_id
    )
    row = await service.finish_registration(
        user, ceremony.ceremony_id, credential, "  Field   Key  "
    )

    assert row.user_id == user.id
    assert row.credential_id == credential_id
    assert row.public_key == cose
    assert row.sign_count == 0
    assert row.transports == ["usb"]
    assert row.nickname == "Field Key"
    assert row.credential_type == "public-key"
    assert row.user_verified is True
    assert row.backup_eligible is False
    assert row.backup_state is False
    assert row.aaguid == "00000000-0000-0000-0000-000000000000"
    assert row in db.added
    # The attempt consumed the challenge; a second completion has nothing to
    # consume even before it reaches the verifier.
    with pytest.raises(WebAuthnError) as exc:
        await service.finish_registration(
            user, ceremony.ceremony_id, credential
        )
    assert exc.value.reason == "challenge_expired"


async def test_registration_challenge_cannot_be_completed_by_another_user() -> None:
    user = _user()
    attacker = _user()
    db = FakeSession(scalars_results=[[]], scalar_results=[None])
    service = _service(db)
    ceremony = await service.begin_registration(user)
    credential, _key, _cose = _registration_credential(
        ceremony.options["challenge"], b"bound-credential"
    )

    with pytest.raises(WebAuthnError) as exc:
        await service.finish_registration(
            attacker, ceremony.ceremony_id, credential
        )

    assert exc.value.reason == "registration_user_mismatch"
    assert exc.value.user is attacker


async def test_registration_rejects_a_duplicate_credential() -> None:
    user = _user()
    existing = _credential_row(user, credential_id=b"duplicate")
    db = FakeSession(scalars_results=[[]], scalar_results=[existing])
    service = _service(db)
    ceremony = await service.begin_registration(user)
    credential, _key, _cose = _registration_credential(
        ceremony.options["challenge"], b"duplicate"
    )

    with pytest.raises(WebAuthnDuplicateCredential) as exc:
        await service.finish_registration(
            user, ceremony.ceremony_id, credential
        )

    assert exc.value.reason == "credential_already_registered"
    assert exc.value.credential is existing


async def test_registration_rejects_a_wrong_origin() -> None:
    user = _user()
    db = FakeSession(scalars_results=[[]], scalar_results=[None])
    service = _service(db)
    ceremony = await service.begin_registration(user)
    credential, _key, _cose = _registration_credential(
        ceremony.options["challenge"],
        b"wrong-origin",
        origin="https://evil.example",
    )

    with pytest.raises(WebAuthnError) as exc:
        await service.finish_registration(
            user, ceremony.ceremony_id, credential
        )

    assert exc.value.reason == "registration_verification_failed"


async def test_a_tampered_challenge_store_is_rejected() -> None:
    user = _user()
    db = FakeSession(scalars_results=[[]])
    redis = FakeRedis()
    service = _service(db, redis)
    ceremony = await service.begin_registration(user)
    redis.store[f"webauthn:register:{ceremony.ceremony_id}"] = "not-json"

    with pytest.raises(WebAuthnError) as exc:
        await service.finish_registration(
            user, ceremony.ceremony_id, {"id": "x", "response": {}}
        )

    assert exc.value.reason == "challenge_invalid"


# ── Authentication ceremony ─────────────────────────────────────────────────


async def test_authentication_options_are_usernameless() -> None:
    db = FakeSession()
    service = _service(db)

    ceremony = await service.begin_authentication()

    options = ceremony.options
    expected_uv = (
        "required" if settings.WEBAUTHN_REQUIRE_USER_VERIFICATION else "preferred"
    )
    assert options["allowCredentials"] == []
    assert "user" not in options
    assert options["rpId"] == settings.WEBAUTHN_RP_ID
    assert options["userVerification"] == expected_uv
    assert ceremony.ceremony_id
    assert ceremony.expires_in == settings.WEBAUTHN_CHALLENGE_TTL_SECONDS


async def test_authentication_round_trip_verifies_a_real_signature() -> None:
    user = _user()
    key, cose = _make_key()
    credential_id = b"auth-credential"
    row = _credential_row(
        user, credential_id=credential_id, public_key=cose, sign_count=0
    )
    db = FakeSession(scalar_results=[row, user])
    service = _service(db)

    ceremony = await service.begin_authentication()
    credential = _authentication_credential(
        ceremony.options["challenge"],
        credential_id,
        key,
        user.id.bytes,
        sign_count=1,
    )
    result = await service.finish_authentication(
        ceremony.ceremony_id, credential
    )

    assert result.user is user
    assert result.credential is row
    assert result.new_sign_count == 1
    assert result.user_verified is True
    assert result.backup_eligible is False
    assert result.backup_state is False
    # The service verifies but does not advance the counter; the route does
    # that only after account-status checks pass.
    assert row.sign_count == 0


async def test_authentication_challenge_is_one_time() -> None:
    user = _user()
    key, cose = _make_key()
    credential_id = b"one-time-auth"
    row = _credential_row(
        user, credential_id=credential_id, public_key=cose, sign_count=0
    )
    db = FakeSession(scalar_results=[row, user])
    service = _service(db)
    ceremony = await service.begin_authentication()
    credential = _authentication_credential(
        ceremony.options["challenge"], credential_id, key, user.id.bytes
    )

    await service.finish_authentication(ceremony.ceremony_id, credential)

    with pytest.raises(WebAuthnError) as exc:
        await service.finish_authentication(ceremony.ceremony_id, credential)
    assert exc.value.reason == "challenge_expired"


async def test_authentication_rejects_a_credential_for_a_different_user_handle() -> None:
    user = _user()
    other = _user()
    key, cose = _make_key()
    credential_id = b"wrong-user-handle"
    row = _credential_row(
        user, credential_id=credential_id, public_key=cose
    )
    db = FakeSession(scalar_results=[row, user])
    service = _service(db)
    ceremony = await service.begin_authentication()
    credential = _authentication_credential(
        ceremony.options["challenge"], credential_id, key, other.id.bytes
    )

    with pytest.raises(WebAuthnError) as exc:
        await service.finish_authentication(ceremony.ceremony_id, credential)

    assert exc.value.reason == "user_handle_mismatch"
    assert exc.value.user is user
    assert exc.value.credential is row


async def test_authentication_rejects_a_bad_signature() -> None:
    user = _user()
    key, cose = _make_key()
    credential_id = b"bad-signature"
    row = _credential_row(
        user, credential_id=credential_id, public_key=cose
    )
    db = FakeSession(scalar_results=[row, user])
    service = _service(db)
    ceremony = await service.begin_authentication()
    credential = _authentication_credential(
        ceremony.options["challenge"], credential_id, key, user.id.bytes
    )
    signature = bytearray(base64url_to_bytes(credential["response"]["signature"]))
    signature[-1] ^= 0x01
    credential["response"]["signature"] = _b64(bytes(signature))

    with pytest.raises(WebAuthnError) as exc:
        await service.finish_authentication(ceremony.ceremony_id, credential)

    assert exc.value.reason == "authentication_verification_failed"
    assert exc.value.user is user
    assert exc.value.credential is row


async def test_authentication_rejects_a_sign_count_regression() -> None:
    user = _user()
    key, cose = _make_key()
    credential_id = b"counter-clone"
    row = _credential_row(
        user, credential_id=credential_id, public_key=cose, sign_count=5
    )
    db = FakeSession(scalar_results=[row, user])
    service = _service(db)
    ceremony = await service.begin_authentication()
    # Same counter as stored: the library treats this as a clone signal when
    # either side has reported a non-zero value.
    credential = _authentication_credential(
        ceremony.options["challenge"],
        credential_id,
        key,
        user.id.bytes,
        sign_count=5,
    )

    with pytest.raises(WebAuthnError) as exc:
        await service.finish_authentication(ceremony.ceremony_id, credential)

    assert exc.value.reason == "authentication_verification_failed"


async def test_authentication_rejects_an_unknown_credential() -> None:
    key, _cose = _make_key()
    user = _user()
    db = FakeSession(scalar_results=[None])
    service = _service(db)
    ceremony = await service.begin_authentication()
    credential = _authentication_credential(
        ceremony.options["challenge"], b"not-registered", key, user.id.bytes
    )

    with pytest.raises(WebAuthnError) as exc:
        await service.finish_authentication(ceremony.ceremony_id, credential)

    assert exc.value.reason == "unknown_credential"
    assert exc.value.user is None


async def test_authentication_rejects_malformed_client_json() -> None:
    db = FakeSession()
    service = _service(db)
    ceremony = await service.begin_authentication()

    with pytest.raises(WebAuthnError) as exc:
        await service.finish_authentication(
            ceremony.ceremony_id, {"id": "missing-response"}
        )

    assert exc.value.reason == "malformed_credential"


async def test_authentication_rejects_a_challenge_from_the_other_ceremony_type() -> None:
    user = _user()
    key, cose = _make_key()
    credential_id = b"ceremony-confusion"
    row = _credential_row(
        user, credential_id=credential_id, public_key=cose
    )
    db = FakeSession(scalar_results=[row, user])
    service = _service(db)
    registration = await service.begin_registration(user)
    credential = _authentication_credential(
        registration.options["challenge"], credential_id, key, user.id.bytes
    )

    with pytest.raises(WebAuthnError) as exc:
        await service.finish_authentication(
            registration.ceremony_id, credential
        )

    assert exc.value.reason == "challenge_expired"


# ── Request schemas ─────────────────────────────────────────────────────────


def test_registration_schema_requires_a_nested_credential() -> None:
    with pytest.raises(ValidationError):
        WebAuthnRegisterCompleteIn(
            ceremony_id="x" * 32,
            credential={"id": "x", "rawId": "x", "type": "public-key"},
        )


def test_registration_schema_bounds_the_credential_payload() -> None:
    with pytest.raises(ValidationError):
        WebAuthnRegisterCompleteIn(
            ceremony_id="x" * 32,
            credential={
                "id": "x",
                "rawId": "x",
                "type": "public-key",
                "response": {"blob": "x" * 70000},
            },
        )


def test_registration_schema_cleans_nickname_and_rejects_short_ceremony() -> None:
    body = WebAuthnRegisterCompleteIn(
        ceremony_id="x" * 32,
        credential={
            "id": "x",
            "rawId": "x",
            "type": "public-key",
            "response": {},
        },
        nickname="  Field   Key  ",
    )
    assert body.nickname == "Field Key"

    with pytest.raises(ValidationError):
        WebAuthnRegisterCompleteIn(
            ceremony_id="short",
            credential={
                "id": "x",
                "rawId": "x",
                "type": "public-key",
                "response": {},
            },
        )


def test_authentication_schema_requires_a_device_fingerprint() -> None:
    with pytest.raises(ValidationError):
        WebAuthnAuthenticateCompleteIn(
            ceremony_id="x" * 32,
            credential={
                "id": "x",
                "rawId": "x",
                "type": "public-key",
                "response": {},
            },
            device_fingerprint="short",
        )


def test_credential_response_contains_no_key_material() -> None:
    fields = set(WebAuthnCredentialOut.model_fields)
    assert "public_key" not in fields
    assert "private_key" not in fields
    assert {"credential_id", "sign_count", "last_used_at"} <= fields


# ── HTTP routes ─────────────────────────────────────────────────────────────


@pytest.fixture
def route_client(monkeypatch):
    redis = FakeRedis()
    monkeypatch.setattr(webauthn_routes, "redis_otp", redis)
    db = FakeSession()
    current_user = [_user()]
    app = FastAPI()
    app.include_router(webauthn_routes.router, prefix=settings.API_PREFIX)

    async def _override_db():
        yield db

    app.dependency_overrides[get_db] = _override_db
    app.dependency_overrides[get_current_user] = lambda: current_user[0]

    with TestClient(app) as client:
        yield SimpleNamespace(
            client=client,
            db=db,
            redis=redis,
            user=current_user[0],
            current_user=current_user,
        )


def _fake_issue_login(calls: list[dict[str, Any]]):
    async def _issue(db, user, fingerprint, ip, user_agent, auth_method="otp"):
        calls.append(
            {
                "db": db,
                "user": user,
                "fingerprint": fingerprint,
                "ip": ip,
                "user_agent": user_agent,
                "auth_method": auth_method,
            }
        )
        return VerifyOut(
            access_token="access-token",
            refresh_token="refresh-token",
            expires_in=3600,
            session_id=uuid.uuid4(),
            user=UserOut(
                id=user.id,
                full_name=user.full_name,
                username=user.username,
                role=user.role,
                avatar_url=None,
            ),
        )

    return _issue


def test_webauthn_routes_are_registered() -> None:
    from app.main import app

    paths = app.openapi()["paths"]
    for path in (
        f"{_API}/register/begin",
        f"{_API}/register/complete",
        f"{_API}/authenticate/begin",
        f"{_API}/authenticate/complete",
        f"{_API}/credentials",
        f"{_API}/credentials/{{credential_id}}",
    ):
        assert path in paths


def test_registration_route_enrolls_a_key(route_client) -> None:
    begin = route_client.client.post(f"{_API}/register/begin")
    assert begin.status_code == 200
    options = begin.json()
    credential, _key, cose = _registration_credential(
        options["options"]["challenge"], b"route-credential"
    )
    route_client.db.scalar_results.append(None)

    response = route_client.client.post(
        f"{_API}/register/complete",
        json={
            "ceremony_id": options["ceremony_id"],
            "credential": credential,
            "nickname": "  Route   Key ",
        },
    )

    assert response.status_code == 201, response.text
    body = response.json()
    assert body["credential_id"] == _b64(b"route-credential")
    assert body["nickname"] == "Route Key"
    assert body["sign_count"] == 0
    rows = [
        row for row in route_client.db.added if isinstance(row, WebAuthnCredential)
    ]
    assert len(rows) == 1
    assert rows[0].public_key == cose
    assert any(
        isinstance(row, AuditLog)
        and row.action == AuditAction.WEBAUTHN_REGISTERED
        for row in route_client.db.added
    )


def test_registration_route_rejects_a_duplicate_key(route_client) -> None:
    begin = route_client.client.post(f"{_API}/register/begin")
    assert begin.status_code == 200
    options = begin.json()
    credential, _key, _cose = _registration_credential(
        options["options"]["challenge"], b"already-registered"
    )
    existing = _credential_row(
        route_client.user, credential_id=b"already-registered"
    )
    route_client.db.scalar_results.append(existing)

    response = route_client.client.post(
        f"{_API}/register/complete",
        json={
            "ceremony_id": options["ceremony_id"],
            "credential": credential,
        },
    )

    assert response.status_code == 409
    assert route_client.db.rollbacks >= 1
    assert any(
        isinstance(row, AuditLog)
        and row.action == AuditAction.WEBAUTHN_REGISTRATION_FAILED
        for row in route_client.db.added
    )


def test_registration_route_rejects_another_users_ceremony(route_client) -> None:
    begin = route_client.client.post(f"{_API}/register/begin")
    assert begin.status_code == 200
    options = begin.json()
    credential, _key, _cose = _registration_credential(
        options["options"]["challenge"], b"stolen-ceremony"
    )
    route_client.current_user[0] = _user()

    response = route_client.client.post(
        f"{_API}/register/complete",
        json={
            "ceremony_id": options["ceremony_id"],
            "credential": credential,
        },
    )

    assert response.status_code == 401
    assert response.json()["detail"] == "Registration failed. Start again."


def test_authentication_begin_cannot_enumerate_accounts(route_client) -> None:
    response = route_client.client.post(f"{_API}/authenticate/begin")

    assert response.status_code == 200
    body = response.json()
    assert body["options"]["allowCredentials"] == []
    assert "user" not in body["options"]
    assert body["options"]["challenge"]


def test_authentication_route_issues_the_existing_session_shape(
    route_client, monkeypatch
) -> None:
    user = route_client.user
    key, cose = _make_key()
    credential_id = b"route-auth"
    row = _credential_row(
        user, credential_id=credential_id, public_key=cose, sign_count=0
    )
    calls: list[dict[str, Any]] = []
    monkeypatch.setattr(
        webauthn_routes, "_issue_login", _fake_issue_login(calls)
    )

    begin = route_client.client.post(f"{_API}/authenticate/begin")
    assert begin.status_code == 200
    options = begin.json()
    credential = _authentication_credential(
        options["options"]["challenge"],
        credential_id,
        key,
        user.id.bytes,
        sign_count=1,
    )
    route_client.db.scalar_results.extend([row, user])

    response = route_client.client.post(
        f"{_API}/authenticate/complete",
        json={
            "ceremony_id": options["ceremony_id"],
            "credential": credential,
            "device_fingerprint": "a" * 32,
        },
    )

    assert response.status_code == 200, response.text
    assert response.json()["access_token"] == "access-token"
    assert row.sign_count == 1
    assert row.last_used_at is not None
    assert len(calls) == 1
    assert calls[0]["user"] is user
    assert calls[0]["fingerprint"] == "a" * 32
    assert calls[0]["auth_method"] == "webauthn"


def test_authentication_route_rejects_a_suspended_account(
    route_client, monkeypatch
) -> None:
    user = _user(status=UserStatus.SUSPENDED)
    route_client.current_user[0] = user
    key, cose = _make_key()
    credential_id = b"suspended-auth"
    row = _credential_row(
        user, credential_id=credential_id, public_key=cose
    )
    calls: list[dict[str, Any]] = []
    monkeypatch.setattr(
        webauthn_routes, "_issue_login", _fake_issue_login(calls)
    )

    begin = route_client.client.post(f"{_API}/authenticate/begin")
    options = begin.json()
    credential = _authentication_credential(
        options["options"]["challenge"], credential_id, key, user.id.bytes
    )
    route_client.db.scalar_results.extend([row, user])

    response = route_client.client.post(
        f"{_API}/authenticate/complete",
        json={
            "ceremony_id": options["ceremony_id"],
            "credential": credential,
            "device_fingerprint": "b" * 32,
        },
    )

    assert response.status_code == 401
    assert response.json()["detail"] == "Authentication failed."
    assert calls == []
    assert row.sign_count == 0
    assert any(
        isinstance(entry, AuditLog)
        and entry.action == AuditAction.LOGIN_FAILED
        and entry.error_code == "inactive_or_expired"
        for entry in route_client.db.added
    )


def test_authentication_route_rejects_a_bad_assertion(
    route_client, monkeypatch
) -> None:
    user = route_client.user
    key, cose = _make_key()
    credential_id = b"route-bad-signature"
    row = _credential_row(
        user, credential_id=credential_id, public_key=cose
    )
    calls: list[dict[str, Any]] = []
    monkeypatch.setattr(
        webauthn_routes, "_issue_login", _fake_issue_login(calls)
    )

    begin = route_client.client.post(f"{_API}/authenticate/begin")
    options = begin.json()
    credential = _authentication_credential(
        options["options"]["challenge"], credential_id, key, user.id.bytes
    )
    signature = bytearray(base64url_to_bytes(credential["response"]["signature"]))
    signature[0] ^= 0x01
    credential["response"]["signature"] = _b64(bytes(signature))
    route_client.db.scalar_results.extend([row, user])

    response = route_client.client.post(
        f"{_API}/authenticate/complete",
        json={
            "ceremony_id": options["ceremony_id"],
            "credential": credential,
            "device_fingerprint": "c" * 32,
        },
    )

    assert response.status_code == 401
    assert calls == []
    assert row.sign_count == 0


def test_authentication_route_rejects_a_replayed_ceremony(
    route_client, monkeypatch
) -> None:
    user = route_client.user
    key, cose = _make_key()
    credential_id = b"route-replay"
    row = _credential_row(
        user, credential_id=credential_id, public_key=cose
    )
    calls: list[dict[str, Any]] = []
    monkeypatch.setattr(
        webauthn_routes, "_issue_login", _fake_issue_login(calls)
    )

    begin = route_client.client.post(f"{_API}/authenticate/begin")
    options = begin.json()
    credential = _authentication_credential(
        options["options"]["challenge"], credential_id, key, user.id.bytes
    )
    payload = {
        "ceremony_id": options["ceremony_id"],
        "credential": credential,
        "device_fingerprint": "d" * 32,
    }
    route_client.db.scalar_results.extend([row, user])
    first = route_client.client.post(
        f"{_API}/authenticate/complete", json=payload
    )
    second = route_client.client.post(
        f"{_API}/authenticate/complete", json=payload
    )

    assert first.status_code == 200
    assert second.status_code == 401
    assert len(calls) == 1


def test_credential_listing_and_removal_are_scoped_to_the_caller(
    route_client,
) -> None:
    row = _credential_row(route_client.user)
    route_client.db.scalars_results.append([row])

    listing = route_client.client.get(f"{_API}/credentials")
    assert listing.status_code == 200
    assert listing.json()[0]["credential_id"] == _b64(b"credential-1")

    route_client.db.scalar_results.append(row)
    removed = route_client.client.delete(
        f"{_API}/credentials/{row.id}"
    )
    assert removed.status_code == 204
    assert route_client.db.deleted == [row]
    assert any(
        isinstance(entry, AuditLog)
        and entry.action == AuditAction.WEBAUTHN_CREDENTIAL_REMOVED
        for entry in route_client.db.added
    )

    route_client.db.scalar_results.append(None)
    missing = route_client.client.delete(
        f"{_API}/credentials/{row.id}"
    )
    assert missing.status_code == 404


# ── Schema, model, migration, and integration invariants ────────────────────


def test_no_private_key_material_is_stored() -> None:
    table = Base.metadata.tables["webauthn_credentials"]
    assert not any("private" in column.name.lower() for column in table.columns)
    assert "public_key" in table.columns
    assert isinstance(table.c.public_key.type, LargeBinary)
    assert isinstance(table.c.credential_id.type, LargeBinary)
    assert table.c.credential_id.unique is True


def test_credential_ids_are_globally_unique_and_user_deletion_cascades() -> None:
    table = Base.metadata.tables["webauthn_credentials"]
    unique_columns = {
        tuple(column.name for column in constraint.columns)
        for constraint in table.constraints
        if isinstance(constraint, UniqueConstraint)
    }
    assert ("credential_id",) in unique_columns

    foreign_keys = [
        fk
        for constraint in table.constraints
        if isinstance(constraint, ForeignKeyConstraint)
        for fk in constraint.elements
    ]
    user_fk = next(fk for fk in foreign_keys if fk.parent.name == "user_id")
    assert user_fk.ondelete == "CASCADE"


def test_user_relationship_deletes_keys_with_the_account() -> None:
    cascade = User.webauthn_credentials.property.cascade
    assert "delete" in cascade
    assert "delete-orphan" in cascade


def test_migration_adds_the_credential_table_and_its_constraints() -> None:
    source = Path(
        "alembic/versions/0013_webauthn_credentials.py"
    ).read_text(encoding="utf-8")
    assert 'revision: str = "0013_webauthn_credentials"' in source
    assert 'down_revision: str | None = "0012_retention_limits"' in source
    assert 'op.create_table(\n        "webauthn_credentials"' in source
    assert "uq_webauthn_credentials_credential_id" in source
    assert 'ondelete="CASCADE"' in source
    assert "ix_webauthn_credentials_user_created" in source


def test_webauthn_dependency_is_pinned() -> None:
    requirements = Path("requirements.txt").read_text(encoding="utf-8")
    assert "webauthn==3.0.1" in requirements
    # webauthn 3.x requires cryptography >= 49; the old 43 pin would make a
    # clean Docker build fail before the app ever starts.
    assert "cryptography==50.0.2" in requirements


def test_successful_login_audit_records_the_authentication_method() -> None:
    source = inspect.getsource(_issue_login)
    assert "auth_method" in source
    assert '"auth_method": auth_method' in source
