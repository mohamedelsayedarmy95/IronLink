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
