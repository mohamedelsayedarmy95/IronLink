from __future__ import annotations

import uuid

import pytest

from app.services.otp_service import OtpService


class FakePipeline:
    """Minimal Redis pipeline fake — records ops, executes against FakeRedis."""

    def __init__(self, redis: "FakeRedis") -> None:
        self._redis = redis
        self._ops: list = []

    def set(self, key, value, ex=None):
        self._ops.append(("set", key, value, ex))
        return self

    def delete(self, *keys):
        self._ops.append(("delete", *keys))
        return self

    async def execute(self):
        for op in self._ops:
            if op[0] == "set":
                await self._redis.set(op[1], op[2], ex=op[3])
            elif op[0] == "delete":
                await self._redis.delete(*op[1:])
        self._ops.clear()


class FakeRedis:
    """In-memory async Redis fake covering the OtpService surface."""

    def __init__(self) -> None:
        self.store: dict[str, str] = {}

    def pipeline(self):
        return FakePipeline(self)

    async def set(self, key, value, ex=None):
        self.store[key] = str(value)

    async def get(self, key):
        return self.store.get(key)

    async def delete(self, *keys):
        for k in keys:
            self.store.pop(k, None)

    async def incr(self, key):
        val = int(self.store.get(key, "0")) + 1
        self.store[key] = str(val)
        return val

    async def expire(self, key, seconds):
        return True


@pytest.fixture
def redis() -> FakeRedis:
    return FakeRedis()


@pytest.fixture
def otp_service(redis: FakeRedis) -> OtpService:
    return OtpService(redis)  # type: ignore[arg-type]


@pytest.mark.asyncio
async def test_issue_returns_6_digit_code(otp_service: OtpService):
    code = await otp_service.issue(uuid.uuid4())
    assert len(code) == 6
    assert code.isdigit()


@pytest.mark.asyncio
async def test_correct_code_verifies_once(otp_service: OtpService):
    user_id = uuid.uuid4()
    code = await otp_service.issue(user_id)
    assert await otp_service.verify(user_id, code) is True
    # Consumed — second attempt with same code fails
    assert await otp_service.verify(user_id, code) is False


@pytest.mark.asyncio
async def test_wrong_code_rejected(otp_service: OtpService):
    user_id = uuid.uuid4()
    await otp_service.issue(user_id)
    assert await otp_service.verify(user_id, "000000") is False


@pytest.mark.asyncio
async def test_brute_force_burns_the_code(otp_service: OtpService, redis: FakeRedis):
    user_id = uuid.uuid4()
    code = await otp_service.issue(user_id)

    # Exhaust max attempts with wrong codes
    for _ in range(5):
        await otp_service.verify(user_id, "999999")

    # 6th attempt exceeds OTP_MAX_ATTEMPTS → code deleted, even the REAL code fails
    assert await otp_service.verify(user_id, code) is False
    assert redis.store.get(f"otp:{user_id}") is None


@pytest.mark.asyncio
async def test_reissue_replaces_code_and_resets_attempts(otp_service: OtpService):
    user_id = uuid.uuid4()
    await otp_service.issue(user_id)
    await otp_service.verify(user_id, "111111")  # one failed attempt

    new_code = await otp_service.issue(user_id)
    assert await otp_service.verify(user_id, new_code) is True
