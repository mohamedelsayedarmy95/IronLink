from __future__ import annotations

import hashlib
import secrets
from datetime import datetime, timedelta, timezone
from typing import Any
from uuid import UUID

import bcrypt
from jose import JWTError, jwt

from app.config import settings

# bcrypt 12 rounds — balance between security and login latency at 500 concurrent.
# passlib is deliberately NOT used: it is unmaintained and incompatible with bcrypt >= 4.1.
_BCRYPT_ROUNDS = 12


def _bcrypt_input(value: str) -> bytes:
    """bcrypt hard-limits input to 72 bytes. Pre-hash with SHA-256 so arbitrarily
    long passphrases keep full entropy instead of being silently truncated."""
    return hashlib.sha256(value.encode("utf-8")).hexdigest().encode("ascii")


def hash_password(plain: str) -> str:
    return bcrypt.hashpw(
        _bcrypt_input(plain), bcrypt.gensalt(rounds=_BCRYPT_ROUNDS)
    ).decode("ascii")


def verify_password(plain: str, hashed: str) -> bool:
    try:
        return bcrypt.checkpw(_bcrypt_input(plain), hashed.encode("ascii"))
    except ValueError:
        return False


def hash_military_id(military_id: str) -> str:
    """Military service numbers are hashed with bcrypt like passwords —
    they are used for identity verification, never for lookup, so a
    non-deterministic salt is correct here."""
    return hash_password(military_id.strip())


def verify_military_id(military_id: str, hashed: str) -> bool:
    return verify_password(military_id.strip(), hashed)


# ── Refresh token handling ────────────────────────────────────────────────────

def generate_refresh_token() -> str:
    """256-bit URL-safe random token. Only its SHA-256 is stored server-side."""
    return secrets.token_urlsafe(32)


def hash_refresh_token(token: str) -> str:
    """SHA-256 (not bcrypt) — refresh tokens are already high-entropy random
    strings, so a fast deterministic hash is correct and allows indexed lookup."""
    return hashlib.sha256(token.encode()).hexdigest()


# ── JWT access tokens ─────────────────────────────────────────────────────────

def create_access_token(
    user_id: UUID,
    token_version: int,
    role: str,
    extra_claims: dict[str, Any] | None = None,
) -> str:
    """Access token embeds token_version at issue time. Verification compares
    against the user's current token_version — a single DB increment invalidates
    every outstanding token for that user (see User.token_version)."""
    now = datetime.now(timezone.utc)
    payload: dict[str, Any] = {
        "sub": str(user_id),
        "ver": token_version,
        "role": role,
        "iat": now,
        "exp": now + timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES),
        "jti": secrets.token_hex(8),
    }
    if extra_claims:
        payload.update(extra_claims)
    return jwt.encode(payload, settings.SECRET_KEY, algorithm=settings.TOKEN_ALGORITHM)


def decode_access_token(token: str) -> dict[str, Any] | None:
    """Returns the payload, or None for any invalid/expired token.
    Callers must additionally check payload['ver'] against User.token_version."""
    try:
        return jwt.decode(
            token, settings.SECRET_KEY, algorithms=[settings.TOKEN_ALGORITHM]
        )
    except JWTError:
        return None


# ── Device fingerprint ────────────────────────────────────────────────────────

def compute_device_fingerprint(user_agent: str, os_build: str, screen: str) -> str:
    """SHA-256 of stable device characteristics. Used for anomalous-login
    detection, never as a sole authentication factor."""
    raw = f"{user_agent}|{os_build}|{screen}"
    return hashlib.sha256(raw.encode()).hexdigest()


# ── OTP ───────────────────────────────────────────────────────────────────────

def generate_otp(digits: int = 6) -> str:
    """Cryptographically secure numeric OTP."""
    return "".join(str(secrets.randbelow(10)) for _ in range(digits))


def constant_time_compare(a: str, b: str) -> bool:
    return secrets.compare_digest(a.encode(), b.encode())
