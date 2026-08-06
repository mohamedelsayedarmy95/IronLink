from __future__ import annotations

from uuid import UUID

from redis.asyncio import Redis

from app.config import settings
from app.core.security import constant_time_compare, generate_otp


class OtpService:
    """OTP lifecycle backed entirely by Redis DB index 1 (REDIS_DB_OTP).

    Keys:
      otp:{user_id}          → the code (TTL = OTP_TTL_SECONDS)
      otp:attempts:{user_id} → failed attempt counter (same TTL)

    No OTP state ever touches PostgreSQL — Redis TTL is the single source of
    truth for expiry, and keys vanish automatically.
    """

    def __init__(self, redis: Redis) -> None:
        self._redis = redis

    @staticmethod
    def _code_key(user_id: UUID) -> str:
        return f"otp:{user_id}"

    @staticmethod
    def _attempts_key(user_id: UUID) -> str:
        return f"otp:attempts:{user_id}"

    async def issue(self, user_id: UUID) -> str:
        """Generates and stores a new OTP, replacing any outstanding one."""
        code = generate_otp()
        pipe = self._redis.pipeline()
        pipe.set(self._code_key(user_id), code, ex=settings.OTP_TTL_SECONDS)
        pipe.delete(self._attempts_key(user_id))
        await pipe.execute()
        return code

    async def verify(self, user_id: UUID, submitted: str) -> bool:
        """Constant-time verification with attempt limiting.

        The code is consumed on success AND on exceeding max attempts, so a
        brute-force attempt burns the OTP rather than leaving it live.
        """
        attempts_key = self._attempts_key(user_id)
        attempts = await self._redis.incr(attempts_key)
        if attempts == 1:
            await self._redis.expire(attempts_key, settings.OTP_TTL_SECONDS)

        if attempts > settings.OTP_MAX_ATTEMPTS:
            await self._redis.delete(self._code_key(user_id))
            return False

        stored = await self._redis.get(self._code_key(user_id))
        if stored is None:
            return False

        if constant_time_compare(stored, submitted):
            await self._redis.delete(self._code_key(user_id), attempts_key)
            return True
        return False
