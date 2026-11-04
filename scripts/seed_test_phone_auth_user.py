"""One-off: seed the users matching Firebase's phone-auth test numbers, so the
real Firebase Phone Auth flow can be exercised end-to-end against production
with two signed-in accounts on one phone (see docs/DEVICE_TEST_2026-08-18.md
and the -PtestInstance=true side-by-side build).

Idempotent: safe to re-run. Existing rows are updated in place, not duplicated.

Not part of the app's normal seed set — delete after testing.
"""
from __future__ import annotations

import asyncio

from sqlalchemy import select

from app.core.database import AsyncSessionLocal
from app.core.security import hash_military_id, hash_password
from app.models import User
from app.models.user import UserRole, UserStatus

# Both numbers must also exist under Firebase Console → Authentication →
# Sign-in method → Phone → "Phone numbers for testing", with verification
# code 123456 — see docs/FIREBASE_SETUP_PROMPT.md Task 1. A number seeded
# here but missing there (or the reverse) fails at whichever half is missing,
# collapsed to the same generic 401 by design (see app/api/routes/auth.py,
# verify_firebase) — which is exactly the gap this script closes.
TEST_ACCOUNTS = [
    {"phone": "+201099695779", "military_id": "TEST1234", "username": "fbauth_test"},
    {"phone": "+201128108020", "military_id": "TEST5678", "username": "fbauth_test2"},
]


async def _seed_one(db, phone: str, military_id: str, username: str) -> None:
    user = await db.scalar(select(User).where(User.phone_number == phone))
    if user is None:
        user = User(
            phone_number=phone,
            hashed_password=hash_password("unused-firebase-auth-only"),
        )
        db.add(user)

    user.full_name = f"Firebase Phone Auth Test User ({phone[-4:]})"
    user.username = username
    user.status = UserStatus.ACTIVE
    user.role = UserRole.SOLDIER
    user.hashed_military_id = hash_military_id(military_id)


async def main() -> None:
    async with AsyncSessionLocal() as db:
        for account in TEST_ACCOUNTS:
            await _seed_one(db, account["phone"], account["military_id"], account["username"])
        await db.commit()

    for account in TEST_ACCOUNTS:
        print(f"Seeded {account['phone']} with military ID {account['military_id']}")


if __name__ == "__main__":
    asyncio.run(main())
