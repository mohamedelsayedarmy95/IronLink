from __future__ import annotations

import json
import re
from datetime import datetime
from typing import Any
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

_PHONE_RE = re.compile(r"^\+[1-9]\d{7,14}$")   # E.164
_MAX_WEBAUTHN_CREDENTIAL_BYTES = 64 * 1024


class RequestOtpIn(BaseModel):
    phone_number: str = Field(..., examples=["+201001234567"])

    @field_validator("phone_number")
    @classmethod
    def _valid_phone(cls, v: str) -> str:
        v = v.strip().replace(" ", "")
        if not _PHONE_RE.match(v):
            raise ValueError("phone_number must be E.164, e.g. +201001234567")
        return v


class RequestOtpOut(BaseModel):
    # Fable5-Enhancement: identical response whether the phone exists or not —
    # prevents user-enumeration attacks against a military user directory.
    detail: str = "If this number is registered, a code has been sent."
    retry_after_seconds: int


class VerifyIn(BaseModel):
    phone_number: str
    otp_code: str = Field(..., min_length=6, max_length=6, pattern=r"^\d{6}$")
    military_id: str = Field(..., min_length=4, max_length=40)
    device_fingerprint: str = Field(..., min_length=16, max_length=128)

    @field_validator("phone_number")
    @classmethod
    def _valid_phone(cls, v: str) -> str:
        v = v.strip().replace(" ", "")
        if not _PHONE_RE.match(v):
            raise ValueError("invalid phone number")
        return v


class DeleteAccountIn(BaseModel):
    """A fresh phone-verification token for `DELETE /auth/me`.

    Deletion is the one irreversible action in the product, and a bearer token
    is exactly what someone holding a borrowed or stolen phone already has. So
    the caller has to prove they can receive an SMS on the number right now,
    not merely that they were signed in at some point.
    """

    id_token: str


class FirebaseVerifyIn(BaseModel):
    # phone_number is deliberately NOT taken from the client — it's read out of
    # the verified Firebase ID token server-side, so a caller can't claim a
    # number they don't control.
    id_token: str = Field(..., min_length=20)
    military_id: str = Field(..., min_length=4, max_length=40)
    device_fingerprint: str = Field(..., min_length=16, max_length=128)


class FirebaseRegisterIn(BaseModel):
    """Self-registration with a real phone number.

    Like FirebaseVerifyIn, the number is read out of the verified ID token
    rather than taken from the client — someone registering must control the
    number they are registering.

    The military ID is SET here rather than checked. It becomes this account's
    second factor for every later login, so it is a credential the user
    chooses once, not proof of anything on its own. Whether a self-registered
    account may use the system immediately is a policy decision — see
    SELF_REGISTRATION_AUTO_APPROVE.
    """

    id_token: str = Field(..., min_length=20)
    full_name: str = Field(..., min_length=2, max_length=120)
    military_id: str = Field(..., min_length=4, max_length=40)
    device_fingerprint: str = Field(..., min_length=16, max_length=128)

    @field_validator("full_name")
    @classmethod
    def _clean_name(cls, v: str) -> str:
        v = " ".join(v.split())
        if not v:
            raise ValueError("full_name must not be blank")
        return v


def _validate_webauthn_credential(value: dict[str, Any]) -> dict[str, Any]:
    """Bound the opaque WebAuthn payload before it reaches the verifier.

    The nested shape is defined by the browser, not by us, so the individual
    fields are validated by the WebAuthn library. What this layer adds is a
    hard size ceiling and the handful of top-level keys the library requires,
    which stops a caller using the endpoint as an arbitrary JSON store.
    """
    try:
        encoded = json.dumps(value, separators=(",", ":"))
    except (TypeError, ValueError) as exc:
        raise ValueError("credential must be a JSON object") from exc
    if len(encoded.encode("utf-8")) > _MAX_WEBAUTHN_CREDENTIAL_BYTES:
        raise ValueError("credential payload is too large")
    if not isinstance(value.get("response"), dict):
        raise ValueError("credential.response must be an object")
    for key in ("id", "rawId", "type"):
        if not isinstance(value.get(key), str) or not value[key]:
            raise ValueError(f"credential.{key} is required")
    return value


class WebAuthnOptionsOut(BaseModel):
    """A ceremony id plus the browser's PublicKeyCredential options.

    `ceremony_id` is returned separately because the browser's options object
    does not carry one. The client sends it back with the credential so the
    server can find and atomically consume the matching Redis challenge.
    """

    ceremony_id: str
    expires_in: int
    options: dict[str, Any]


class WebAuthnRegisterCompleteIn(BaseModel):
    ceremony_id: str = Field(..., min_length=16, max_length=128)
    credential: dict[str, Any]
    nickname: str | None = Field(default=None, max_length=100)

    @field_validator("credential")
    @classmethod
    def _valid_credential(cls, v: dict[str, Any]) -> dict[str, Any]:
        return _validate_webauthn_credential(v)

    @field_validator("nickname")
    @classmethod
    def _clean_nickname(cls, v: str | None) -> str | None:
        if v is None:
            return None
        cleaned = " ".join(v.split())
        return cleaned or None


class WebAuthnAuthenticateCompleteIn(BaseModel):
    ceremony_id: str = Field(..., min_length=16, max_length=128)
    credential: dict[str, Any]
    device_fingerprint: str = Field(..., min_length=16, max_length=128)

    @field_validator("credential")
    @classmethod
    def _valid_credential(cls, v: dict[str, Any]) -> dict[str, Any]:
        return _validate_webauthn_credential(v)


class WebAuthnCredentialOut(BaseModel):
    """Public metadata for one registered key. No key material is returned."""

    id: UUID
    credential_id: str
    nickname: str | None = None
    aaguid: str | None = None
    credential_type: str
    sign_count: int
    transports: list[str] = Field(default_factory=list)
    user_verified: bool
    backup_eligible: bool
    backup_state: bool
    created_at: datetime
    last_used_at: datetime | None = None


class UserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    full_name: str
    username: str | None
    role: str
    avatar_url: str | None = None   # pre-signed URL, resolved at response time


class VerifyOut(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int                 # seconds
    session_id: UUID                # this device's session — used for remote-kick UX
    user: UserOut


class RefreshIn(BaseModel):
    refresh_token: str = Field(..., min_length=20, max_length=512)


class RefreshOut(BaseModel):
    """A fresh access token, and the refresh token that replaces the one used.

    The refresh token is rotated on every exchange, so the caller must store
    the new one — the old is dead the moment this returns.
    """

    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int


class RegisterOut(BaseModel):
    """Either a session, or a plain statement that approval is pending.

    Handing back a token that does not work yet would be worse than saying so.
    """

    approved: bool
    session: VerifyOut | None = None


class SessionOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    device_type: str | None
    device_name: str | None
    ip_address: str
    geo_city: str | None
    created_at: datetime
    last_active_at: datetime | None
    is_current: bool = False


class SecurityEventOut(BaseModel):
    """One security-relevant thing that happened to this account.

    Deliberately narrow. It carries an action code, a time, and the coarse
    context of where it happened — never message content, never a resource the
    event touched, and never another user's identity. IronShield's promise is
    that it reports on the account without exposing what the account contains.
    """

    model_config = ConfigDict(from_attributes=True)

    action: str
    created_at: datetime
    ip_address: str | None
    device_type: str | None
    success: bool

    #: True when this event involved a device the account had not seen before.
    #: Derived server-side from the audit metadata rather than guessed at by
    #: the client, which has no way to know what "before" was.
    new_device: bool = False


class WsTicketOut(BaseModel):
    ticket: str
    expires_in: int
    ws_url: str


class ErrorOut(BaseModel):
    detail: str
