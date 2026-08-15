from __future__ import annotations

import re
from datetime import datetime
from uuid import UUID

from pydantic import BaseModel, ConfigDict, Field, field_validator

_PHONE_RE = re.compile(r"^\+[1-9]\d{7,14}$")   # E.164


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


class WsTicketOut(BaseModel):
    ticket: str
    expires_in: int
    ws_url: str


class ErrorOut(BaseModel):
    detail: str
