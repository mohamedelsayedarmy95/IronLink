"""The journeys a person actually takes, against a real database.

The engineering standard asks for end-to-end coverage of send, receive,
offline, reconnect and delete. Nothing here had it, and the reason is visible
in the rest of the suite: every other test runs against fakes, and there was no
database to run a journey against.

A fake cannot answer the question a journey asks. Does a message survive being
sent, stored, delivered, retracted, and read back — through the real schema,
with the real constraints, in the real order? Each of those steps is covered
somewhere in isolation. None of them was ever covered together, and the bugs
that live between two correct steps are the ones no unit test sees.

These are skipped without `TEST_DATABASE_URL`. CI provides one.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

import pytest

from tests.conftest import requires_db

from app.models import Message, User
from app.models.message import MessageStatus
from app.models.user import UserStatus
from app.services import message_service

pytestmark = requires_db


async def _person(db, name: str) -> User:
    user = User(
        phone_number=f"+2010{uuid.uuid4().int % 100000000:08d}",
        full_name=name,
        status=UserStatus.ACTIVE,
        # Not real hashes and not real credentials. Nothing here authenticates;
        # these columns are NOT NULL and the journeys need a row to exist.
        hashed_military_id="not-a-hash",
        hashed_password="not-a-hash",
    )
    db.add(user)
    await db.flush()
    return user


class TestSendAndReceive:
    @pytest.mark.asyncio
    async def test_a_message_survives_the_round_trip(self, db) -> None:
        alice = await _person(db, "Alice")
        bob = await _person(db, "Bob")

        msg = await message_service.save_message(
            db,
            sender_id=alice.id,
            recipient_id=bob.id,
            message_type="text",
            content_ciphertext="envelope-1",
            client_ref="ref-1",
        )

        assert msg.id is not None
        assert msg.sender_id == alice.id
        assert msg.recipient_id == bob.id
        assert msg.status == MessageStatus.SENT

    @pytest.mark.asyncio
    async def test_the_server_stores_ciphertext_and_nothing_else(self, db) -> None:
        # The premise of the product, asserted against the real column rather
        # than against a comment.
        alice = await _person(db, "Alice")
        bob = await _person(db, "Bob")

        msg = await message_service.save_message(
            db,
            sender_id=alice.id,
            recipient_id=bob.id,
            message_type="text",
            content_ciphertext="envelope-1",
            client_ref="ref-1",
        )

        stored = await db.get(Message, msg.id)
        assert stored.content_ciphertext == "envelope-1"
        # There is no plaintext column to leak into. If one is ever added, this
        # is where it shows up.
        assert not hasattr(stored, "content_plaintext")


class TestReconnect:
    """The case the client's outbox exists for."""

    @pytest.mark.asyncio
    async def test_a_resend_after_a_dropped_socket_is_not_a_second_message(
        self, db
    ) -> None:
        """The journey: send, lose the connection before the ack, send again.

        The client cannot tell whether the server stored the first attempt, so
        it re-sends — which is correct behaviour and would produce a duplicate
        without idempotency. The recipient would see the same sentence twice.
        """
        alice = await _person(db, "Alice")
        bob = await _person(db, "Bob")

        first = await message_service.save_message(
            db,
            sender_id=alice.id,
            recipient_id=bob.id,
            message_type="text",
            content_ciphertext="envelope-1",
            client_ref="ref-same",
        )
        second = await message_service.save_message(
            db,
            sender_id=alice.id,
            recipient_id=bob.id,
            message_type="text",
            content_ciphertext="envelope-1",
            client_ref="ref-same",
        )

        assert first.id == second.id, "the resend must return the original"

    @pytest.mark.asyncio
    async def test_two_people_can_independently_generate_the_same_reference(
        self, db
    ) -> None:
        # Client refs are generated per device and look like "ref_3". The
        # uniqueness is per sender for exactly this reason; a global constraint
        # would make one person's message silently collapse into another's.
        alice = await _person(db, "Alice")
        bob = await _person(db, "Bob")
        carol = await _person(db, "Carol")

        from_alice = await message_service.save_message(
            db,
            sender_id=alice.id,
            recipient_id=carol.id,
            message_type="text",
            content_ciphertext="from alice",
            client_ref="ref_3",
        )
        from_bob = await message_service.save_message(
            db,
            sender_id=bob.id,
            recipient_id=carol.id,
            message_type="text",
            content_ciphertext="from bob",
            client_ref="ref_3",
        )

        assert from_alice.id != from_bob.id


class TestRetraction:
    @pytest.mark.asyncio
    async def test_deleting_for_everyone_removes_the_content(self, db) -> None:
        alice = await _person(db, "Alice")
        bob = await _person(db, "Bob")

        msg = await message_service.save_message(
            db,
            sender_id=alice.id,
            recipient_id=bob.id,
            message_type="text",
            content_ciphertext="something regretted",
            client_ref="ref-1",
        )

        await message_service.unsend_message(db, msg.id, alice.id)

        stored = await db.get(Message, msg.id)
        assert stored.content_ciphertext is None
        assert stored.deleted_for_everyone is True

    @pytest.mark.asyncio
    async def test_a_tombstone_remains(self, db) -> None:
        """Content gone, evidence kept.

        The row is not hard-deleted, deliberately: an audit trail has to be
        able to show that a message existed and was retracted, by whom, and
        when. A journey test is where that policy is worth asserting, because
        it is the kind of thing a later "clean up deleted rows" change would
        quietly undo.
        """
        alice = await _person(db, "Alice")
        bob = await _person(db, "Bob")

        msg = await message_service.save_message(
            db,
            sender_id=alice.id,
            recipient_id=bob.id,
            message_type="text",
            content_ciphertext="something regretted",
            client_ref="ref-1",
        )
        await message_service.unsend_message(db, msg.id, alice.id)

        stored = await db.get(Message, msg.id)
        assert stored is not None
        assert stored.sender_id == alice.id
        assert stored.deleted_at is not None

    @pytest.mark.asyncio
    async def test_only_the_sender_may_retract(self, db) -> None:
        alice = await _person(db, "Alice")
        bob = await _person(db, "Bob")

        msg = await message_service.save_message(
            db,
            sender_id=alice.id,
            recipient_id=bob.id,
            message_type="text",
            content_ciphertext="envelope-1",
            client_ref="ref-1",
        )

        with pytest.raises(message_service.UnsendDenied):
            await message_service.unsend_message(db, msg.id, bob.id)

    @pytest.mark.asyncio
    async def test_the_window_closes(self, db) -> None:
        alice = await _person(db, "Alice")
        bob = await _person(db, "Bob")

        msg = await message_service.save_message(
            db,
            sender_id=alice.id,
            recipient_id=bob.id,
            message_type="text",
            content_ciphertext="envelope-1",
            client_ref="ref-1",
        )
        # Aged past the window rather than waiting five minutes.
        msg.created_at = datetime.now(timezone.utc) - timedelta(minutes=10)
        await db.flush()

        with pytest.raises(message_service.UnsendDenied):
            await message_service.unsend_message(db, msg.id, alice.id)


class TestBlocking:
    @pytest.mark.asyncio
    async def test_a_blocked_sender_cannot_deliver(self, db) -> None:
        from app.models import UserBlock

        alice = await _person(db, "Alice")
        bob = await _person(db, "Bob")
        db.add(UserBlock(blocker_id=bob.id, blocked_id=alice.id))
        await db.flush()

        with pytest.raises(message_service.BlockedDelivery):
            await message_service.save_message(
                db,
                sender_id=alice.id,
                recipient_id=bob.id,
                message_type="text",
                content_ciphertext="envelope-1",
                client_ref="ref-1",
            )

    @pytest.mark.asyncio
    async def test_blocking_is_directional(self, db) -> None:
        # Bob blocking Alice must not stop Bob messaging Alice. Getting this
        # backwards would silently mute the person who did the blocking.
        from app.models import UserBlock

        alice = await _person(db, "Alice")
        bob = await _person(db, "Bob")
        db.add(UserBlock(blocker_id=bob.id, blocked_id=alice.id))
        await db.flush()

        msg = await message_service.save_message(
            db,
            sender_id=bob.id,
            recipient_id=alice.id,
            message_type="text",
            content_ciphertext="envelope-1",
            client_ref="ref-1",
        )
        assert msg.id is not None
