"""Focused regression coverage for the H-04A-R messaging integrity fixes.

Two behaviours are asserted here, both against the real schema:

* The idempotency contract the client now depends on: one reference is one
  stored message, a retransmission returns that row, and two references leave
  two rows.
* The typing broadcast that raised ``NameError: select is not defined``. The
  test calls it directly, so a missing import fails here rather than in
  production; it also pins routing to the other participants only.

Run with ``TEST_DATABASE_URL`` pointing at a disposable Postgres database.
"""

from __future__ import annotations

import json
import uuid
from datetime import datetime, timezone

import pytest
from sqlalchemy import func, select

from tests.conftest import requires_db

from app.models import Group, GroupMember, Message, User
from app.models.user import UserStatus
from app.services import message_service
from app.services.group_message_service import save_group_message
from app.services.ws_manager import ConnectionManager

pytestmark = requires_db


async def _person(db, name: str) -> User:
    user = User(
        phone_number=f"+2010{uuid.uuid4().int % 100000000:08d}",
        full_name=name,
        status=UserStatus.ACTIVE,
        # Not credentials. These columns are NOT NULL and the journey needs a
        # row; nothing here authenticates.
        hashed_military_id="not-a-hash",
        hashed_password="not-a-hash",
    )
    db.add(user)
    await db.flush()
    return user


async def _group(db, members: list[User]) -> Group:
    group = Group(name=f"Synthetic {uuid.uuid4()}")
    db.add(group)
    await db.flush()
    now = datetime.now(timezone.utc)
    for index, member in enumerate(members):
        db.add(
            GroupMember(
                group_id=group.id,
                user_id=member.id,
                role="owner" if index == 0 else "member",
                joined_at=now,
            )
        )
    await db.flush()
    return group


class _RecordingRedis:
    def __init__(self) -> None:
        self.published: list[tuple[str, dict]] = []

    async def publish(self, channel: str, payload: str) -> None:
        self.published.append((channel, json.loads(payload)))


class _SessionScope:
    def __init__(self, session) -> None:
        self._session = session

    async def __aenter__(self):
        return self._session

    async def __aexit__(self, *exc_info) -> bool:
        # The fixture owns the transaction and rolls it back; this scope must
        # not close a session it did not open.
        return False


class _SessionFactory:
    def __init__(self, session) -> None:
        self._session = session

    def __call__(self) -> _SessionScope:
        return _SessionScope(self._session)


class TestIdempotency:
    @pytest.mark.asyncio
    async def test_a_retransmission_returns_the_stored_message(self, db) -> None:
        alice = await _person(db, "Alice")
        bob = await _person(db, "Bob")

        first = await message_service.save_message(
            db,
            sender_id=alice.id,
            recipient_id=bob.id,
            group_id=None,
            message_type="text",
            content_ciphertext="envelope-1",
            client_ref="ref_same",
        )
        second = await message_service.save_message(
            db,
            sender_id=alice.id,
            recipient_id=bob.id,
            group_id=None,
            message_type="text",
            content_ciphertext="envelope-1",
            client_ref="ref_same",
        )

        assert second.id == first.id
        rows = await db.scalar(
            select(func.count())
            .select_from(Message)
            .where(
                Message.sender_id == alice.id,
                Message.client_ref == "ref_same",
            )
        )
        assert rows == 1, "a retransmission must not create a second row"

    @pytest.mark.asyncio
    async def test_distinct_references_persist_as_distinct_messages(self, db) -> None:
        alice = await _person(db, "Alice")
        bob = await _person(db, "Bob")

        first = await message_service.save_message(
            db,
            sender_id=alice.id,
            recipient_id=bob.id,
            group_id=None,
            message_type="text",
            content_ciphertext="envelope-1",
            client_ref="ref_one",
        )
        second = await message_service.save_message(
            db,
            sender_id=alice.id,
            recipient_id=bob.id,
            group_id=None,
            message_type="text",
            content_ciphertext="envelope-2",
            client_ref="ref_two",
        )

        assert second.id != first.id
        rows = await db.scalar(
            select(func.count())
            .select_from(Message)
            .where(
                Message.sender_id == alice.id,
                Message.client_ref.in_(["ref_one", "ref_two"]),
            )
        )
        assert rows == 2

    @pytest.mark.asyncio
    async def test_group_retransmission_returns_the_stored_message(self, db) -> None:
        alice = await _person(db, "Alice")
        bob = await _person(db, "Bob")
        group = await _group(db, [alice, bob])

        first = await save_group_message(
            db,
            group_id=group.id,
            sender_id=alice.id,
            message_type="text",
            content_ciphertext="group-envelope",
            client_ref="gref_same",
        )
        second = await save_group_message(
            db,
            group_id=group.id,
            sender_id=alice.id,
            message_type="text",
            content_ciphertext="group-envelope",
            client_ref="gref_same",
        )

        assert second.id == first.id


class TestTypingBroadcast:
    @pytest.mark.asyncio
    async def test_direct_typing_reaches_only_the_other_participant(
        self, db, monkeypatch
    ) -> None:
        alice = await _person(db, "Alice")
        bob = await _person(db, "Bob")
        await message_service.save_message(
            db,
            sender_id=alice.id,
            recipient_id=bob.id,
            group_id=None,
            message_type="text",
            content_ciphertext="envelope-1",
            client_ref="typing-direct",
        )

        redis = _RecordingRedis()
        manager = ConnectionManager(redis)
        monkeypatch.setattr(
            "app.core.database.AsyncSessionLocal", _SessionFactory(db)
        )

        # This call is the regression: without the import it raises NameError.
        await manager.broadcast_typing(bob.id, alice.id, True)

        assert [channel for channel, _ in redis.published] == [
            f"chan:user:{bob.id}"
        ]
        assert redis.published[0][1] == {
            "type": "typing_start",
            "from": str(alice.id),
        }

    @pytest.mark.asyncio
    async def test_group_typing_skips_the_sender_and_non_members(
        self, db, monkeypatch
    ) -> None:
        alice = await _person(db, "Alice")
        bob = await _person(db, "Bob")
        carol = await _person(db, "Carol")
        outsider = await _person(db, "Outsider")
        group = await _group(db, [alice, bob, carol])

        redis = _RecordingRedis()
        manager = ConnectionManager(redis)
        monkeypatch.setattr(
            "app.core.database.AsyncSessionLocal", _SessionFactory(db)
        )

        await manager.broadcast_typing(group.id, alice.id, False)

        channels = {channel for channel, _ in redis.published}
        assert channels == {
            f"chan:user:{bob.id}",
            f"chan:user:{carol.id}",
        }
        assert f"chan:user:{alice.id}" not in channels
        assert f"chan:user:{outsider.id}" not in channels
        assert all(
            payload == {"type": "typing_stop", "from": str(alice.id)}
            for _, payload in redis.published
        )

    @pytest.mark.asyncio
    async def test_typing_without_a_conversation_discloses_nothing(
        self, db, monkeypatch
    ) -> None:
        alice = await _person(db, "Alice")
        stranger = await _person(db, "Stranger")

        redis = _RecordingRedis()
        manager = ConnectionManager(redis)
        monkeypatch.setattr(
            "app.core.database.AsyncSessionLocal", _SessionFactory(db)
        )

        await manager.broadcast_typing(stranger.id, alice.id, True)

        assert redis.published == []
