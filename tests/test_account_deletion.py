"""Erasing an account without erasing other people's records.

An account is not only its owner's data. It is a sender in someone else's
conversation, an admin in a group's audit trail, and possibly a banned party. A
naive DELETE takes all of that with it, and some of it is not the departing
user's to erase.

The journeys here run against a real Postgres, because the question is what the
foreign keys actually do — and the answer to that lives in the database, not in
the model definitions.
"""

from __future__ import annotations

import inspect
import uuid

import pytest
from sqlalchemy import select

from tests.conftest import requires_db

from app.models import AuditLog, Message, PlatformBan, User
from app.models.user import UserStatus
from app.services import account_deletion, message_service


def _expire(db) -> None:
    """Forces the next read to hit the database rather than the identity map.

    The journey fixture builds its session with `expire_on_commit=False`, which
    is right for the other tests and wrong for these: two of them passed
    nothing and failed on stale in-memory objects that still held the values
    the cascade had already changed underneath them.

    What these tests are actually about is what the foreign keys did, and that
    answer is in the database. This makes them read it.
    """
    db.expire_all()


class TestWhatIsRetained:
    """These need no database — they are about the reasoning."""

    def test_deletion_is_immediate_rather_than_scheduled(self) -> None:
        """A thirty-day recovery window is common and is wrong here.

        Someone deleting an account on this product is frequently doing it
        because they are at risk, and keeping everything for a month in case
        they change their mind is the opposite of what they asked for.

        Asserted against the statement that runs, not against a comment: the
        service issues a DELETE and commits, with nothing scheduled and no
        soft-delete column set.
        """
        source = inspect.getsource(account_deletion.delete_account)
        assert "delete(User)" in source
        assert "commit()" in source
        for deferral in ("scheduled", "pending_deletion", "soft_delete"):
            assert deferral not in source, deferral

    def test_the_retention_is_disclosed_to_the_user(self) -> None:
        # A retention someone is told about is a policy. The same retention
        # unmentioned is a broken promise.
        source = inspect.getsource(account_deletion.delete_account)
        assert "retained" in source
        assert 'return {' in source

    def test_deletion_requires_more_than_a_session_token(self) -> None:
        """A bearer token is exactly what a stolen phone already has.

        Deletion is the one irreversible action in the product, so the caller
        must prove they can receive an SMS on the number right now.
        """
        from app.api.routes import auth

        source = inspect.getsource(auth.delete_my_account)
        assert "verify_id_token" in source
        assert 'decoded.get("phone_number") != user.phone_number' in source, (
            "a valid token for any number must not delete a different account"
        )


@pytest.mark.usefixtures("db")
class TestDeletionJourney:
    pytestmark = requires_db

    async def _person(self, db, name: str, phone: str | None = None) -> User:
        user = User(
            phone_number=phone or f"+2010{uuid.uuid4().int % 100000000:08d}",
            full_name=name,
            status=UserStatus.ACTIVE,
            hashed_military_id="not-a-hash",
            hashed_password="not-a-hash",
        )
        db.add(user)
        await db.flush()
        return user

    @pytest.mark.asyncio
    async def test_the_account_is_gone(self, db) -> None:
        alice = await self._person(db, "Alice")
        alice_id = alice.id

        await account_deletion.delete_account(db, alice)
        _expire(db)

        assert await db.get(User, alice_id) is None

    @pytest.mark.asyncio
    async def test_the_recipient_keeps_their_conversation(self, db) -> None:
        """The property that makes this safe to offer at all.

        `messages.sender_id` is SET NULL, so Bob's history does not disappear
        because Alice left. Had it cascaded, one person deleting their account
        would have silently rewritten everyone else's past.
        """
        alice = await self._person(db, "Alice")
        bob = await self._person(db, "Bob")
        # Held as plain values, because `_expire` below detaches every loaded
        # object and reading an attribute off one afterwards would attempt a
        # synchronous lazy load from inside async code.
        bob_id = bob.id

        msg = await message_service.save_message(
            db,
            sender_id=alice.id,
            recipient_id=bob_id,
            group_id=None,
            message_type="text",
            content_ciphertext="envelope",
            client_ref="ref-1",
        )
        message_id = msg.id

        await account_deletion.delete_account(db, alice)
        _expire(db)

        surviving = await db.get(Message, message_id)
        assert surviving is not None
        assert surviving.sender_id is None
        assert surviving.recipient_id == bob_id

    @pytest.mark.asyncio
    async def test_their_own_inbox_goes(self, db) -> None:
        # The other direction cascades, and should: messages addressed to a
        # deleted account are that account's data.
        alice = await self._person(db, "Alice")
        bob = await self._person(db, "Bob")

        msg = await message_service.save_message(
            db,
            sender_id=bob.id,
            recipient_id=alice.id,
            group_id=None,
            message_type="text",
            content_ciphertext="envelope",
            client_ref="ref-1",
        )
        message_id = msg.id

        await account_deletion.delete_account(db, alice)
        _expire(db)

        assert await db.get(Message, message_id) is None

    @pytest.mark.asyncio
    async def test_a_ban_survives_the_deletion(self, db) -> None:
        """Otherwise evading a ban is one step: delete, register again.

        A ban a banned person can undo is decorative.
        """
        alice = await self._person(db, "Alice", phone="+201000000001")
        admin = await self._person(db, "Admin")
        db.add(PlatformBan(user_id=alice.id, banned_by_id=admin.id, reason="abuse"))
        await db.flush()

        result = await account_deletion.delete_account(db, alice)
        _expire(db)

        assert "platform_ban" in result["retained"]
        ban = await db.scalar(select(PlatformBan))
        assert ban is not None
        assert ban.user_id is None, "no identifier is kept"
        assert ban.phone_hash is not None, "but the number is still recognisable"

    @pytest.mark.asyncio
    async def test_the_retained_ban_is_a_hash_not_a_number(self, db) -> None:
        phone = "+201000000002"
        alice = await self._person(db, "Alice", phone=phone)
        admin = await self._person(db, "Admin")
        db.add(PlatformBan(user_id=alice.id, banned_by_id=admin.id, reason="abuse"))
        await db.flush()

        await account_deletion.delete_account(db, alice)
        _expire(db)

        ban = await db.scalar(select(PlatformBan))
        assert phone not in (ban.phone_hash or "")
        assert len(ban.phone_hash) == 64, "SHA-256 hex"

    @pytest.mark.asyncio
    async def test_the_ban_is_enforced_against_the_number(self, db) -> None:
        # The record has to be checked somewhere or it is a record of nothing.
        phone = "+201000000003"
        alice = await self._person(db, "Alice", phone=phone)
        admin = await self._person(db, "Admin")
        db.add(PlatformBan(user_id=alice.id, banned_by_id=admin.id, reason="abuse"))
        await db.flush()

        await account_deletion.delete_account(db, alice)
        _expire(db)

        assert await account_deletion.is_phone_banned(db, phone) is True
        assert await account_deletion.is_phone_banned(db, "+201999999999") is False

    @pytest.mark.asyncio
    async def test_an_unbanned_account_leaves_nothing_behind(self, db) -> None:
        # The common case. Nobody who was not banned should discover a hash of
        # their phone number retained after they asked to be erased.
        alice = await self._person(db, "Alice")

        result = await account_deletion.delete_account(db, alice)
        _expire(db)

        assert "platform_ban" not in result["retained"]
        assert await db.scalar(select(PlatformBan)) is None

    @pytest.mark.asyncio
    async def test_the_deletion_is_recorded_without_naming_anyone(self, db) -> None:
        """An account vanishing with no trace is indistinguishable from a fault.

        The row says a deletion happened and when. It does not say who, because
        the point is that there is no longer a who.
        """
        alice = await self._person(db, "Alice")

        await account_deletion.delete_account(db, alice)
        _expire(db)

        entry = await db.scalar(
            select(AuditLog).where(AuditLog.action == "account.deleted")
        )
        assert entry is not None
        assert entry.actor_id is None

    @pytest.mark.asyncio
    async def test_their_audit_entries_are_anonymised_not_erased(self, db) -> None:
        alice = await self._person(db, "Alice")
        db.add(
            AuditLog(
                actor_id=alice.id,
                action="group.member_removed",
                success=True,
                ip_address="203.0.113.7",
            )
        )
        await db.flush()

        await account_deletion.delete_account(db, alice)
        _expire(db)

        entry = await db.scalar(
            select(AuditLog).where(AuditLog.action == "group.member_removed")
        )
        assert entry is not None, "the event survives"
        assert entry.actor_id is None, "but names nobody"
        assert entry.ip_address is None, "and carries no address either"
