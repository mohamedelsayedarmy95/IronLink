"""Read the current OTP for a phone number — DEVELOPMENT ONLY.

The SMS gateway deliberately never logs OTP codes (not even in dev), so this
script exists to make on-device testing practical without weakening that rule.
It refuses to run unless ENV=development.

Usage:
    docker compose exec api python -m scripts.dev_get_otp +201000000001
"""
from __future__ import annotations

import asyncio
import sys

from sqlalchemy import select

from app.config import settings
from app.core.database import AsyncSessionLocal
from app.core.redis import redis_otp
from app.models import User


async def main(phone: str) -> int:
    if settings.ENV != "development":
        print("REFUSED: this script only runs when ENV=development")
        return 2

    async with AsyncSessionLocal() as db:
        user = await db.scalar(select(User).where(User.phone_number == phone))
        if user is None:
            print(f"No user with phone {phone}")
            return 1

    code = await redis_otp.get(f"otp:{user.id}")
    if code is None:
        print(f"No active OTP for {phone} — request one first "
              f"(POST /api/v1/auth/request-otp), codes expire after "
              f"{settings.OTP_TTL_SECONDS}s")
        return 1

    print(f"\n  {phone}  ->  OTP: {code}\n")
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(__doc__)
        raise SystemExit(2)
    raise SystemExit(asyncio.run(main(sys.argv[1])))
