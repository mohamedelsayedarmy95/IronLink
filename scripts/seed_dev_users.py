"""Seed two test users for device testing.

Usage (inside the api container):
    docker compose exec api python -m scripts.seed_dev_users

Creates:
    +201000000001  "الرائد أحمد سالم"    military ID: MIL-1001
    +201000000002  "النقيب خالد منصور"   military ID: MIL-1002

Both are ACTIVE. Log in with the phone + the OTP printed by the API logs
(development SMS gateway) + the military ID above.

Idempotent: re-running updates the existing rows instead of duplicating.
"""
from __future__ import annotations

import asyncio

from sqlalchemy import select

from app.core.database import AsyncSessionLocal
from app.core.security import hash_military_id
from app.models import User
from app.models.user import UserRole, UserStatus

SEED_USERS = [
    {
        "phone_number": "+201000000001",
        "full_name": "الرائد أحمد سالم",
        "username": "ahmed",
        "military_id": "MIL-1001",
        "department": "العمليات",
        "role": UserRole.OFFICER,
    },
    {
        "phone_number": "+201000000002",
        "full_name": "النقيب خالد منصور",
        "username": "khaled",
        "military_id": "MIL-1002",
        "department": "العمليات",
        "role": UserRole.OFFICER,
    },
    {
        "phone_number": "+201000000009",
        "full_name": "المشرف العام",
        "username": "ops_admin",
        "military_id": "MIL-0000",
        "department": "القيادة",
        "role": UserRole.SUPERADMIN,
    },
]


async def main() -> None:
    async with AsyncSessionLocal() as db:
        for spec in SEED_USERS:
            user = await db.scalar(
                select(User).where(User.phone_number == spec["phone_number"])
            )
            if user is None:
                user = User(phone_number=spec["phone_number"])
                db.add(user)

            user.full_name = spec["full_name"]
            user.username = spec["username"]
            user.department = spec["department"]
            user.role = spec["role"]
            user.status = UserStatus.ACTIVE
            user.hashed_military_id = hash_military_id(spec["military_id"])

            print(f"  seeded {spec['phone_number']}  {spec['full_name']}  "
                  f"(military id: {spec['military_id']}, role: {spec['role']})")

        await db.commit()

    print("\nDone. Log in with phone + OTP (see API logs) + military ID.")


if __name__ == "__main__":
    asyncio.run(main())
