from __future__ import annotations

import pytest
from pydantic import ValidationError

from app.api.schemas import RequestOtpIn, VerifyIn


class TestPhoneValidation:
    def test_valid_e164(self):
        assert RequestOtpIn(phone_number="+201001234567").phone_number == "+201001234567"

    def test_spaces_stripped(self):
        assert RequestOtpIn(phone_number=" +20 100 123 4567 ").phone_number == "+201001234567"

    @pytest.mark.parametrize("bad", [
        "01001234567",        # missing +
        "+0123456789",        # leading zero after +
        "+2",                 # too short
        "+2010012345678901",  # too long
        "abc",
        "+20100123456a",
    ])
    def test_invalid_rejected(self, bad: str):
        with pytest.raises(ValidationError):
            RequestOtpIn(phone_number=bad)


class TestVerifyValidation:
    def _base(self, **overrides):
        data = {
            "phone_number": "+201001234567",
            "otp_code": "123456",
            "military_id": "MIL-4457",
            "device_fingerprint": "a" * 32,
        }
        data.update(overrides)
        return data

    def test_valid_payload(self):
        v = VerifyIn(**self._base())
        assert v.otp_code == "123456"

    @pytest.mark.parametrize("bad_otp", ["12345", "1234567", "12345a", "abcdef", ""])
    def test_bad_otp_rejected(self, bad_otp: str):
        with pytest.raises(ValidationError):
            VerifyIn(**self._base(otp_code=bad_otp))

    def test_short_fingerprint_rejected(self):
        with pytest.raises(ValidationError):
            VerifyIn(**self._base(device_fingerprint="short"))

    def test_short_military_id_rejected(self):
        with pytest.raises(ValidationError):
            VerifyIn(**self._base(military_id="123"))
