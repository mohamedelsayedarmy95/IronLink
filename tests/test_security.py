from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

import pytest
from jose import jwt

from app.config import settings
from app.core.security import (
    compute_device_fingerprint,
    constant_time_compare,
    create_access_token,
    decode_access_token,
    generate_otp,
    generate_refresh_token,
    hash_military_id,
    hash_password,
    hash_refresh_token,
    verify_military_id,
    verify_password,
)


class TestPasswordHashing:
    def test_hash_and_verify_roundtrip(self):
        hashed = hash_password("Str0ng!Passw0rd")
        assert hashed != "Str0ng!Passw0rd"
        assert verify_password("Str0ng!Passw0rd", hashed)

    def test_wrong_password_rejected(self):
        hashed = hash_password("correct")
        assert not verify_password("incorrect", hashed)

    def test_same_password_different_hashes(self):
        # bcrypt salting — two hashes of the same input must differ
        assert hash_password("same") != hash_password("same")


class TestMilitaryId:
    def test_roundtrip(self):
        hashed = hash_military_id("MIL-123456")
        assert verify_military_id("MIL-123456", hashed)
        assert not verify_military_id("MIL-654321", hashed)

    def test_whitespace_normalized(self):
        hashed = hash_military_id("  MIL-123456  ")
        assert verify_military_id("MIL-123456", hashed)

    def test_plaintext_never_in_hash(self):
        hashed = hash_military_id("MIL-999888")
        assert "999888" not in hashed


class TestRefreshTokens:
    def test_token_entropy(self):
        tokens = {generate_refresh_token() for _ in range(100)}
        assert len(tokens) == 100  # no collisions

    def test_hash_deterministic(self):
        token = generate_refresh_token()
        assert hash_refresh_token(token) == hash_refresh_token(token)

    def test_hash_not_reversible_format(self):
        token = generate_refresh_token()
        hashed = hash_refresh_token(token)
        assert token not in hashed
        assert len(hashed) == 64  # SHA-256 hex


class TestAccessTokens:
    def test_create_and_decode(self):
        user_id = uuid.uuid4()
        token = create_access_token(user_id, token_version=3, role="officer")
        payload = decode_access_token(token)
        assert payload is not None
        assert payload["sub"] == str(user_id)
        assert payload["ver"] == 3
        assert payload["role"] == "officer"

    def test_tampered_token_rejected(self):
        token = create_access_token(uuid.uuid4(), token_version=1, role="soldier")
        tampered = token[:-4] + "XXXX"
        assert decode_access_token(tampered) is None

    def test_expired_token_rejected(self):
        # Forge an already-expired token with the real key
        expired = jwt.encode(
            {
                "sub": str(uuid.uuid4()),
                "ver": 1,
                "exp": datetime.now(timezone.utc) - timedelta(minutes=1),
            },
            settings.SECRET_KEY,
            algorithm=settings.TOKEN_ALGORITHM,
        )
        assert decode_access_token(expired) is None

    def test_wrong_key_rejected(self):
        forged = jwt.encode(
            {"sub": str(uuid.uuid4()), "ver": 1},
            "attacker_key",
            algorithm=settings.TOKEN_ALGORITHM,
        )
        assert decode_access_token(forged) is None


class TestDeviceFingerprint:
    def test_deterministic(self):
        fp1 = compute_device_fingerprint("Mozilla/5.0", "Android14", "1080x2400")
        fp2 = compute_device_fingerprint("Mozilla/5.0", "Android14", "1080x2400")
        assert fp1 == fp2

    def test_different_device_different_fingerprint(self):
        fp1 = compute_device_fingerprint("Mozilla/5.0", "Android14", "1080x2400")
        fp2 = compute_device_fingerprint("Mozilla/5.0", "Android13", "1080x2400")
        assert fp1 != fp2


class TestOtp:
    def test_length_and_charset(self):
        for _ in range(50):
            code = generate_otp()
            assert len(code) == 6
            assert code.isdigit()

    def test_constant_time_compare(self):
        assert constant_time_compare("123456", "123456")
        assert not constant_time_compare("123456", "123457")
