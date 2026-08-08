"""One-off: seed a user matching the Firebase test phone number so the real
Firebase Phone Auth flow can be exercised end-to-end against production.

Not part of the app's normal seed set — delete after testing.
"""
from __future__ import annotations

import asyncio

from sqlalchemy import select

from app.core.database import AsyncSessionLocal
from app.core.security import hash_military_id, hash_password
from app.models import User
from app.models.user import UserRole, UserStatus

PHONE_NUMBER = "+201099695779"
MILITARY_ID = "TEST1234"


async def main() -> None:
    async with AsyncSessionLocal() as db:
        user = await db.scalar(select(User).where(User.phone_number == PHONE_NUMBER))
        if user is None:
            user = User(
                phone_number=PHONE_NUMBER,
                hashed_password=hash_password("unused-firebase-auth-only"),
            )
            db.add(user)

        user.full_name = "Firebase Phone Auth Test User"
        user.username = "fbauth_test"
        user.status = UserStatus.ACTIVE
        user.role = UserRole.SOLDIER
        user.hashed_military_id = hash_military_id(MILITARY_ID)

        await db.commit()

    print(f"Seeded {PHONE_NUMBER} with military ID {MILITARY_ID}")


if __name__ == "__main__":
    asyncio.run(main())
