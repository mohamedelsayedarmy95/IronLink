"""Comprehensive tests for the Self-Destruct Messages feature.

This test suite covers:
1. Direct messages read before and after expiry
2. Expired messages hidden from history/lists immediately
3. Redis outage (test that the DB wipe still commits even if publish fails)
4. Audit metadata `had_media` being correctly set to true when media existed
5. Multi-message sweeps
"""

from __future__ import annotations

import inspect
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from uuid import uuid4

import pytest

from app.models import AuditLog, Message
from app.models.message import MessageStatus, MessageType
from app.services import group_message_service, message_service
from app.services.message_service import visible_message_clause
from app.services.self_destruct_worker import SelfDestructWorker


# ── Test Doubles ──────────────────────────────────────────────────────────────

class _Message:
    """Minimal Message stand-in for unit-testing the worker logic."""

    def __init__(
        self,
        *,
        is_self_destruct: bool = True,
        destruct_after_seconds: int | None = 60,
        destruct_at: datetime | None = None,
        is_destructed: bool = False,
        media_object_key: str | None = None,
        sender_id: uuid4 | None = None,
        recipient_id: uuid4 | None = None,
        group_id: uuid4 | None = None,
    ) -> None:
        self.id = uuid4()
        self.sender_id = sender_id or uuid4()
        self.recipient_id = recipient_id
        self.group_id = group_id
        self.content_ciphertext = "encrypted-content"
        self.message_type = MessageType.TEXT.value
        self.status = MessageStatus.SENT
        self.is_self_destruct = is_self_destruct
        self.destruct_after_seconds = destruct_after_seconds
        self.destruct_at = destruct_at
        self.is_destructed = is_destructed
        self.media_object_key = media_object_key
        self.media_mime_type = "image/png" if media_object_key else None
        self.media_size_bytes = 1234 if media_object_key else None
        self.deleted_at = None
        self.created_at = datetime.now(timezone.utc)
        self.deleted_for_everyone = False
        self.is_edited = False
        self.edit_count = 0
        self.is_secret = False
        self.read_at = None
        self.delivered_at = None
        self.client_ref = None


class _ScalarResult:
    def __init__(self, values: list[object]) -> None:
        self._values = values

    def all(self) -> list[object]:
        return self._values


class _MockDb:
    """Async context manager that mimics AsyncSessionLocal for the worker."""

    def __init__(
        self,
        messages: list[_Message],
        *,
        group_member_ids: set[object] | None = None,
    ) -> None:
        self._messages = messages
        self.group_member_ids = group_member_ids or set()
        self.committed = False
        self.added: list[AuditLog] = []

    async def scalars(self, statement: object) -> _ScalarResult:
        # The worker asks for group members as well as expired messages. The
        # fake distinguishes them by the table in the statement, so a group
        # message can fan its unsend frame out to every member in the test.
        if "group_members" in str(statement):
            return _ScalarResult(list(self.group_member_ids))

        now = datetime.now(timezone.utc)
        expired = [
            m
            for m in self._messages
            if not m.is_destructed
            and m.destruct_at is not None
            and m.destruct_at <= now
        ]
        # Extract limit from the SQLAlchemy statement if present
        limit = getattr(statement, "_limit", None)
        if limit is not None:
            expired = expired[:limit]
        return _ScalarResult(expired)

    def add(self, obj: AuditLog) -> None:
        self.added.append(obj)

    async def commit(self) -> None:
        self.committed = True

    async def __aenter__(self) -> _MockDb:
        return self

    async def __aexit__(self, *_: object) -> None:
        pass


class _Storage:
    """Fake storage that can be made to fail."""

    def __init__(self, *, fails: bool = False) -> None:
        self.deleted: list[str] = []
        self._fails = fails

    def delete_object(self, _bucket: str, key: str) -> None:
        if self._fails:
            raise RuntimeError("object storage unreachable")
        self.deleted.append(key)


class _ServiceDb:
    """Small session double for save_message / mark_read / group saves."""

    def __init__(self, *scalar_results: object) -> None:
        self._scalar_results = list(scalar_results)
        self.added: list[object] = []
        self.commits = 0
        self.refreshed: list[object] = []

    async def scalar(self, _statement: object) -> object | None:
        if not self._scalar_results:
            return None
        return self._scalar_results.pop(0)

    async def commit(self) -> None:
        self.commits += 1

    def add(self, obj: object) -> None:
        self.added.append(obj)

    async def refresh(self, obj: object) -> None:
        self.refreshed.append(obj)


# ── Tests ─────────────────────────────────────────────────────────────────────


class TestMessageExpiryBeforeAndAfter:
    """Tests for direct messages read before and after expiry."""

    @pytest.mark.asyncio
    async def test_message_read_before_expiry_is_visible(self) -> None:
        """A message before its destruct_at should be returned by visible_message_clause."""
        msg = _Message(
            destruct_at=datetime.now(timezone.utc) + timedelta(minutes=5),
            is_destructed=False,
        )
        from app.services.message_service import is_expired

        assert not is_expired(msg), "Message before expiry should not be expired"

    @pytest.mark.asyncio
    async def test_message_read_after_expiry_is_hidden(self) -> None:
        """A message past its destruct_at should be considered expired."""
        msg = _Message(
            destruct_at=datetime.now(timezone.utc) - timedelta(minutes=5),
            is_destructed=False,
        )
        from app.services.message_service import is_expired

        assert is_expired(msg), "Message past expiry should be expired"

    @pytest.mark.asyncio
    async def test_message_already_destructed_is_expired(self) -> None:
        """A message with is_destructed=True should be expired regardless of destruct_at."""
        msg = _Message(
            destruct_at=datetime.now(timezone.utc) + timedelta(days=1),
            is_destructed=True,
        )
        from app.services.message_service import is_expired

        assert is_expired(msg), "Already destructed message should be expired"

    @pytest.mark.asyncio
    async def test_message_without_destruct_at_never_expires(self) -> None:
        """A message without destruct_at should never be expired."""
        msg = _Message(
            is_self_destruct=False,
            destruct_at=None,
            is_destructed=False,
        )
        from app.services.message_service import is_expired

        assert not is_expired(msg), "Message without destruct_at should not expire"


class TestExpiredMessagesHiddenFromHistory:
    """Tests that expired messages are hidden from history/lists immediately."""

    def test_visible_message_clause_excludes_expired(self) -> None:
        """The visible_message_clause should filter out messages past destruct_at."""
        clause = visible_message_clause(now=datetime.now(timezone.utc))
        assert clause is not None
        compiled = str(clause.compile(compile_kwargs={"literal_binds": True}))
        assert "is_destructed" in compiled
        assert "destruct_at" in compiled
class TestRedisOutageDbWipeCommits:
    """Tests that DB wipe commits even when Redis publish fails."""

    @pytest.mark.asyncio
    async def test_db_commits_even_when_redis_publish_fails(self, monkeypatch: pytest.MonkeyPatch) -> None:
        """The DB transaction should commit even if Redis publish raises an exception."""
        msg = _Message(
            destruct_at=datetime.now(timezone.utc) - timedelta(minutes=1),
            media_object_key="attachments/test-key",
            sender_id=uuid4(),
            recipient_id=uuid4(),
        )
        mock_db = _MockDb([msg])
        storage = _Storage()

        def mock_session_factory():
            return mock_db

        monkeypatch.setattr(
            "app.services.self_destruct_worker.AsyncSessionLocal",
            mock_session_factory,
        )

        async def failing_publish(_user_id, _event):
            raise ConnectionError("Redis unavailable")

        monkeypatch.setattr(
            "app.api.routes.websocket.publish",
            failing_publish,
        )

        worker = SelfDestructWorker()
        worker._storage = storage  # noqa: SLF001
        wiped = await worker.sweep_once()

        assert wiped == 1
        assert mock_db.committed
        assert msg.is_destructed
        assert msg.content_ciphertext is None
        assert msg.media_object_key is None
        assert storage.deleted == ["attachments/test-key"]
        assert len(mock_db.added) == 1
class TestAuditMetadataHadMedia:
    """Tests that audit metadata 'had_media' is correctly set."""

    @pytest.mark.asyncio
    async def test_audit_log_had_media_true_when_media_existed(self, monkeypatch: pytest.MonkeyPatch) -> None:
        """Audit log should have had_media=true when message had media."""
        msg = _Message(
            destruct_at=datetime.now(timezone.utc) - timedelta(minutes=1),
            media_object_key="attachments/test-image.png",
            sender_id=uuid4(),
            recipient_id=uuid4(),
        )
        mock_db = _MockDb([msg])
        storage = _Storage()

        def mock_session_factory():
            return mock_db

        monkeypatch.setattr(
            "app.services.self_destruct_worker.AsyncSessionLocal",
            mock_session_factory,
        )

        async def mock_publish(_user_id, _event):
            return 1

        monkeypatch.setattr(
            "app.api.routes.websocket.publish",
            mock_publish,
        )

        worker = SelfDestructWorker()
        worker._storage = storage  # noqa: SLF001
        await worker.sweep_once()

        assert len(mock_db.added) == 1
        audit_log = mock_db.added[0]
        assert audit_log.action == "message.self_destructed"
        assert audit_log.metadata_ is not None
        assert audit_log.metadata_.get("had_media") is True

    @pytest.mark.asyncio
    async def test_audit_log_had_media_false_when_no_media(self, monkeypatch: pytest.MonkeyPatch) -> None:
        """Audit log should have had_media=false when message had no media."""
        msg = _Message(
            destruct_at=datetime.now(timezone.utc) - timedelta(minutes=1),
            media_object_key=None,
            sender_id=uuid4(),
            recipient_id=uuid4(),
        )
        mock_db = _MockDb([msg])
        storage = _Storage()

        def mock_session_factory():
            return mock_db

        monkeypatch.setattr(
            "app.services.self_destruct_worker.AsyncSessionLocal",
            mock_session_factory,
        )

        async def mock_publish(_user_id, _event):
            return 1

        monkeypatch.setattr(
            "app.api.routes.websocket.publish",
            mock_publish,
        )

        worker = SelfDestructWorker()
        worker._storage = storage  # noqa: SLF001
        await worker.sweep_once()

        assert len(mock_db.added) == 1
        audit_log = mock_db.added[0]
        assert audit_log.metadata_.get("had_media") is False

    @pytest.mark.asyncio
    async def test_audit_log_had_media_true_for_group_messages(self, monkeypatch: pytest.MonkeyPatch) -> None:
        """Audit log should have had_media=true for group messages with media."""
        msg = _Message(
            destruct_at=datetime.now(timezone.utc) - timedelta(minutes=1),
            media_object_key="attachments/group-image.jpg",
            sender_id=uuid4(),
            group_id=uuid4(),
            recipient_id=None,
        )
        mock_db = _MockDb([msg])
        storage = _Storage()

        def mock_session_factory():
            return mock_db

        monkeypatch.setattr(
            "app.services.self_destruct_worker.AsyncSessionLocal",
            mock_session_factory,
        )

        async def mock_publish(_user_id, _event):
            return 1

        monkeypatch.setattr(
            "app.api.routes.websocket.publish",
            mock_publish,
        )

        worker = SelfDestructWorker()
        worker._storage = storage  # noqa: SLF001
        await worker.sweep_once()

        assert len(mock_db.added) == 1
        audit_log = mock_db.added[0]
        assert audit_log.metadata_.get("had_media") is True
class TestMultiMessageSweeps:
    """Tests for multi-message batch sweeps."""

    @pytest.mark.asyncio
    async def test_sweep_handles_multiple_expired_messages(self, monkeypatch: pytest.MonkeyPatch) -> None:
        """A single sweep should wipe multiple expired messages."""
        msg1 = _Message(
            destruct_at=datetime.now(timezone.utc) - timedelta(minutes=2),
            media_object_key="attachments/msg1.png",
            sender_id=uuid4(),
            recipient_id=uuid4(),
        )
        msg2 = _Message(
            destruct_at=datetime.now(timezone.utc) - timedelta(minutes=1),
            media_object_key="attachments/msg2.png",
            sender_id=uuid4(),
            recipient_id=uuid4(),
        )
        msg3 = _Message(
            destruct_at=datetime.now(timezone.utc) - timedelta(minutes=3),
            media_object_key=None,
            sender_id=uuid4(),
            recipient_id=uuid4(),
        )
        mock_db = _MockDb([msg1, msg2, msg3])
        storage = _Storage()

        def mock_session_factory():
            return mock_db

        monkeypatch.setattr(
            "app.services.self_destruct_worker.AsyncSessionLocal",
            mock_session_factory,
        )

        async def mock_publish(_user_id, _event):
            return 1

        monkeypatch.setattr(
            "app.api.routes.websocket.publish",
            mock_publish,
        )

        worker = SelfDestructWorker()
        worker._storage = storage  # noqa: SLF001
        wiped = await worker.sweep_once()

        assert wiped == 3
        assert mock_db.committed
        assert all(m.is_destructed for m in [msg1, msg2, msg3])
        assert len(storage.deleted) == 2
        assert len(mock_db.added) == 3

    @pytest.mark.asyncio
    async def test_sweep_respects_batch_size(self, monkeypatch: pytest.MonkeyPatch) -> None:
        """Sweep should respect BATCH_SIZE limit."""
        messages = [
            _Message(
                destruct_at=datetime.now(timezone.utc) - timedelta(minutes=i + 1),
                sender_id=uuid4(),
                recipient_id=uuid4(),
            )
            for i in range(550)
        ]
        mock_db = _MockDb(messages)
        storage = _Storage()

        def mock_session_factory():
            return mock_db

        monkeypatch.setattr(
            "app.services.self_destruct_worker.AsyncSessionLocal",
            mock_session_factory,
        )

        async def mock_publish(_user_id, _event):
            return 1

        monkeypatch.setattr(
            "app.api.routes.websocket.publish",
            mock_publish,
        )

        worker = SelfDestructWorker()
        worker._storage = storage  # noqa: SLF001
        wiped = await worker.sweep_once()

        assert wiped == 500

    @pytest.mark.asyncio
    async def test_sweep_skips_already_destructed(self, monkeypatch: pytest.MonkeyPatch) -> None:
        """Sweep should skip messages already marked as destructed."""
        msg1 = _Message(
            destruct_at=datetime.now(timezone.utc) - timedelta(minutes=1),
            is_destructed=True,
            sender_id=uuid4(),
            recipient_id=uuid4(),
        )
        msg2 = _Message(
            destruct_at=datetime.now(timezone.utc) - timedelta(minutes=1),
            is_destructed=False,
            sender_id=uuid4(),
            recipient_id=uuid4(),
        )
        mock_db = _MockDb([msg1, msg2])
        storage = _Storage()

        def mock_session_factory():
            return mock_db

        monkeypatch.setattr(
            "app.services.self_destruct_worker.AsyncSessionLocal",
            mock_session_factory,
        )

        async def mock_publish(_user_id, _event):
            return 1

        monkeypatch.setattr(
            "app.api.routes.websocket.publish",
            mock_publish,
        )

        worker = SelfDestructWorker()
        worker._storage = storage  # noqa: SLF001
        wiped = await worker.sweep_once()

        assert wiped == 1
        assert msg2.is_destructed
class TestSelfDestructWorkerEdgeCases:
    """Additional edge case tests for the self-destruct worker."""

    @pytest.mark.asyncio
    async def test_minio_delete_failure_keeps_message_for_next_sweep(self, monkeypatch: pytest.MonkeyPatch) -> None:
        """If MinIO delete fails, the message should not be wiped and should be retried."""
        msg = _Message(
            destruct_at=datetime.now(timezone.utc) - timedelta(minutes=1),
            media_object_key="attachments/should-fail.png",
            sender_id=uuid4(),
            recipient_id=uuid4(),
        )
        mock_db = _MockDb([msg])
        storage = _Storage(fails=True)

        def mock_session_factory():
            return mock_db

        monkeypatch.setattr(
            "app.services.self_destruct_worker.AsyncSessionLocal",
            mock_session_factory,
        )

        async def mock_publish(_user_id, _event):
            return 1

        monkeypatch.setattr(
            "app.api.routes.websocket.publish",
            mock_publish,
        )

        worker = SelfDestructWorker()
        worker._storage = storage  # noqa: SLF001
        wiped = await worker.sweep_once()

        assert wiped == 0
        assert not mock_db.committed
        assert not msg.is_destructed
        assert msg.content_ciphertext == "encrypted-content"
        assert msg.media_object_key == "attachments/should-fail.png"
        assert len(mock_db.added) == 0

    @pytest.mark.asyncio
    async def test_non_self_destruct_messages_not_wiped(self, monkeypatch: pytest.MonkeyPatch) -> None:
        """Messages without destruct_at should not be wiped by the worker."""
        msg = _Message(
            is_self_destruct=False,
            destruct_at=None,
            is_destructed=False,
            sender_id=uuid4(),
            recipient_id=uuid4(),
        )
        mock_db = _MockDb([msg])
        storage = _Storage()

        def mock_session_factory():
            return mock_db

        monkeypatch.setattr(
            "app.services.self_destruct_worker.AsyncSessionLocal",
            mock_session_factory,
        )

        async def mock_publish(_user_id, _event):
            return 1

        monkeypatch.setattr(
            "app.api.routes.websocket.publish",
            mock_publish,
        )

        worker = SelfDestructWorker()
        worker._storage = storage  # noqa: SLF001
        wiped = await worker.sweep_once()

        assert wiped == 0
        assert not mock_db.committed
        assert not msg.is_destructed

    @pytest.mark.asyncio
    async def test_publish_called_for_both_sender_and_recipient(self, monkeypatch: pytest.MonkeyPatch) -> None:
        """Publish should be called for both sender and recipient of DM."""
        sender_id = uuid4()
        recipient_id = uuid4()
        msg = _Message(
            destruct_at=datetime.now(timezone.utc) - timedelta(minutes=1),
            sender_id=sender_id,
            recipient_id=recipient_id,
        )
        mock_db = _MockDb([msg])
        storage = _Storage()

        published_events: list[tuple] = []

        def mock_session_factory():
            return mock_db

        monkeypatch.setattr(
            "app.services.self_destruct_worker.AsyncSessionLocal",
            mock_session_factory,
        )

        async def mock_publish(user_id, event):
            published_events.append((user_id, event))
            return 1

        monkeypatch.setattr(
            "app.api.routes.websocket.publish",
            mock_publish,
        )

        worker = SelfDestructWorker()
        worker._storage = storage  # noqa: SLF001
        await worker.sweep_once()

        assert len(published_events) == 2
        user_ids = {str(e[0]) for e in published_events}
        assert str(sender_id) in user_ids
        assert str(recipient_id) in user_ids
        for _, event in published_events:
            assert event["type"] == "unsend"
            assert event["message_id"] == str(msg.id)

    @pytest.mark.asyncio
    async def test_publish_called_for_every_group_member(self, monkeypatch: pytest.MonkeyPatch) -> None:
        """A group message's unsend frame must reach every member, not only the sender.

        Group messages have no recipient_id, so the old sender-only path left
        every other member with the message on screen until their next history
        fetch. The database still enforced expiry; the realtime cleanup did not.
        """
        sender_id = uuid4()
        member_a = uuid4()
        member_b = uuid4()
        group_id = uuid4()
        msg = _Message(
            destruct_at=datetime.now(timezone.utc) - timedelta(minutes=1),
            sender_id=sender_id,
            group_id=group_id,
            recipient_id=None,
        )
        mock_db = _MockDb(
            [msg], group_member_ids={sender_id, member_a, member_b}
        )
        storage = _Storage()

        published_events: list[tuple] = []

        def mock_session_factory():
            return mock_db

        monkeypatch.setattr(
            "app.services.self_destruct_worker.AsyncSessionLocal",
            mock_session_factory,
        )

        async def mock_publish(user_id, event):
            published_events.append((user_id, event))
            return 1

        monkeypatch.setattr(
            "app.api.routes.websocket.publish",
            mock_publish,
        )

        worker = SelfDestructWorker()
        worker._storage = storage  # noqa: SLF001
        await worker.sweep_once()

        assert len(published_events) == 3
        user_ids = {str(e[0]) for e in published_events}
        assert user_ids == {str(sender_id), str(member_a), str(member_b)}
        assert all(e[1]["type"] == "unsend" for e in published_events)
        assert all(e[1]["message_id"] == str(msg.id) for e in published_events)

    @pytest.mark.asyncio
    async def test_empty_sweep_does_nothing(self, monkeypatch: pytest.MonkeyPatch) -> None:
        """A sweep with no expired messages should do nothing."""
        mock_db = _MockDb([])
        storage = _Storage()

        def mock_session_factory():
            return mock_db

        monkeypatch.setattr(
            "app.services.self_destruct_worker.AsyncSessionLocal",
            mock_session_factory,
        )

        publish_called = False

        async def mock_publish(_user_id, _event):
            nonlocal publish_called
            publish_called = True
            return 1

        monkeypatch.setattr(
            "app.api.routes.websocket.publish",
            mock_publish,
        )

        worker = SelfDestructWorker()
        worker._storage = storage  # noqa: SLF001
        wiped = await worker.sweep_once()

        assert wiped == 0
        assert not mock_db.committed
        assert not publish_called
        assert len(mock_db.added) == 0

class TestDirectMessageTimer:
    """The direct-message timer is burn-after-reading, not send-time."""

    @pytest.mark.asyncio
    async def test_sending_a_self_destruct_dm_does_not_start_the_timer(self) -> None:
        db = _ServiceDb()
        msg = await message_service.save_message(
            db,
            sender_id=uuid4(),
            recipient_id=uuid4(),
            group_id=None,
            message_type="text",
            content_ciphertext="envelope",
            destruct_after_seconds=60,
        )

        assert msg.is_self_destruct is True
        assert msg.destruct_after_seconds == 60
        assert msg.destruct_at is None, (
            "a direct message must remain unexpired until it is first read"
        )

    @pytest.mark.asyncio
    async def test_first_read_starts_the_timer(self) -> None:
        msg = _Message(destruct_at=None, recipient_id=uuid4())
        db = _ServiceDb(msg)

        returned = await message_service.mark_read(db, msg.id, msg.recipient_id)

        assert returned is msg
        assert msg.status == MessageStatus.READ
        assert msg.read_at is not None
        assert msg.destruct_at == msg.read_at + timedelta(seconds=60)

    @pytest.mark.asyncio
    async def test_a_second_read_does_not_extend_the_timer(self) -> None:
        msg = _Message(destruct_at=None, recipient_id=uuid4())
        msg.status = MessageStatus.READ
        msg.read_at = datetime.now(timezone.utc) - timedelta(seconds=30)
        msg.destruct_at = msg.read_at + timedelta(seconds=60)
        original_destruct_at = msg.destruct_at
        db = _ServiceDb(msg)

        returned = await message_service.mark_read(db, msg.id, msg.recipient_id)

        assert returned is msg
        assert msg.destruct_at == original_destruct_at
        assert db.commits == 0, "an already-read message needs no write"

    @pytest.mark.asyncio
    async def test_a_legacy_read_row_without_a_timer_still_gets_one(self) -> None:
        # A row written before the timer fix can be READ with destruct_at NULL.
        msg = _Message(destruct_at=None, recipient_id=uuid4())
        msg.status = MessageStatus.READ
        msg.read_at = datetime.now(timezone.utc) - timedelta(minutes=5)
        db = _ServiceDb(msg)

        returned = await message_service.mark_read(db, msg.id, msg.recipient_id)

        assert returned is msg
        assert msg.destruct_at == msg.read_at + timedelta(seconds=60)

    @pytest.mark.asyncio
    async def test_reading_after_expiry_returns_nothing_and_does_not_revive_it(self) -> None:
        expired_at = datetime.now(timezone.utc) - timedelta(seconds=1)
        msg = _Message(destruct_at=expired_at, recipient_id=uuid4())
        db = _ServiceDb(msg)

        returned = await message_service.mark_read(db, msg.id, msg.recipient_id)

        assert returned is None
        assert msg.destruct_at == expired_at
        assert msg.status == MessageStatus.SENT
        assert msg.read_at is None
        assert db.commits == 0

    @pytest.mark.asyncio
    async def test_reading_an_already_destructed_message_returns_nothing(self) -> None:
        msg = _Message(
            destruct_at=datetime.now(timezone.utc) + timedelta(days=1),
            is_destructed=True,
            recipient_id=uuid4(),
        )
        db = _ServiceDb(msg)

        assert await message_service.mark_read(
            db, msg.id, msg.recipient_id
        ) is None
        assert db.commits == 0

    @pytest.mark.asyncio
    async def test_the_expiry_boundary_is_inclusive(self) -> None:
        now = datetime.now(timezone.utc)
        msg = _Message(destruct_at=now)

        assert message_service.is_expired(msg, now=now) is True

    def test_naive_timestamps_are_treated_as_utc(self) -> None:
        naive = datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(seconds=1)
        msg = _Message(destruct_at=naive)

        assert message_service.is_expired(msg) is True

    @pytest.mark.parametrize("bad_ttl", [0, -1, 604_801, True, "60", 60.5])
    def test_invalid_durations_are_rejected(self, bad_ttl: object) -> None:
        with pytest.raises(message_service.InvalidDestructTTL):
            message_service.validate_destruct_after_seconds(bad_ttl)  # type: ignore[arg-type]

    def test_the_maximum_duration_is_allowed(self) -> None:
        assert message_service.validate_destruct_after_seconds(604_800) == 604_800


class TestGroupTimer:
    """Groups have one row and many readers, so their timer starts at send."""

    async def _save(self, *, default: int | None, explicit: int | None):
        member = SimpleNamespace(role="member")
        group = SimpleNamespace(
            only_admins_can_post=False,
            disappearing_messages_seconds=default,
        )
        db = _ServiceDb(member, group)
        msg = await group_message_service.save_group_message(
            db,
            group_id=uuid4(),
            sender_id=uuid4(),
            message_type="text",
            content_ciphertext="group-envelope",
            destruct_after_seconds=explicit,
        )
        return msg, db

    @pytest.mark.asyncio
    async def test_group_default_starts_at_send_time(self) -> None:
        before = datetime.now(timezone.utc)
        msg, _ = await self._save(default=30, explicit=None)
        after = datetime.now(timezone.utc)

        assert msg.destruct_after_seconds == 30
        assert msg.destruct_at is not None
        assert before + timedelta(seconds=30) <= msg.destruct_at
        assert msg.destruct_at <= after + timedelta(seconds=30)

    @pytest.mark.asyncio
    async def test_explicit_ttl_overrides_the_group_default(self) -> None:
        msg, _ = await self._save(default=30, explicit=120)

        assert msg.destruct_after_seconds == 120
        assert msg.destruct_at is not None

    @pytest.mark.asyncio
    async def test_invalid_group_default_is_rejected(self) -> None:
        with pytest.raises(message_service.InvalidDestructTTL):
            await self._save(default=0, explicit=None)


class TestReadPathsUseTheVisibilityRule:
    """Expiry has to be applied by readers, not deferred to the sweeper."""

    @pytest.mark.asyncio
    async def test_group_history_query_excludes_expired_rows(self) -> None:
        member = SimpleNamespace(joined_at=datetime.now(timezone.utc) - timedelta(days=1))
        db = _ServiceDb(member)
        captured: list[str] = []

        async def fake_scalars(statement):
            captured.append(str(statement))
            return _ScalarResult([])

        db.scalars = fake_scalars  # type: ignore[attr-defined]

        await group_message_service.history(
            db, group_id=uuid4(), user_id=uuid4()
        )

        assert captured
        assert "destruct_at" in captured[0]
        assert "is_destructed" in captured[0]

    @pytest.mark.asyncio
    async def test_direct_history_route_excludes_expired_rows(self) -> None:
        from app.api.routes.chats import message_history

        caller = SimpleNamespace(id=uuid4())
        peer = SimpleNamespace(id=uuid4())
        db = _ServiceDb(peer)
        captured: list[str] = []

        async def fake_scalars(statement):
            captured.append(str(statement))
            return _ScalarResult([])

        db.scalars = fake_scalars  # type: ignore[attr-defined]

        await message_history(
            peer_id=peer.id,
            before=None,
            limit=50,
            user=caller,
            db=db,
        )

        assert captured
        assert "destruct_at" in captured[0]
        assert "is_destructed" in captured[0]


class TestWebSocketContract:
    """The client sends read/delivered; the server must understand both spellings."""

    def test_read_and_delivered_aliases_are_accepted(self) -> None:
        from app.api.routes import websocket

        source = inspect.getsource(websocket._handle_frame)
        assert '"message_delivered", "delivered"' in source
        assert '"message_read", "read"' in source

    def test_websocket_rejects_invalid_destruct_ttl(self) -> None:
        from app.api.routes import websocket

        source = inspect.getsource(websocket._handle_frame)
        assert source.count("InvalidDestructTTL") == 2

    def test_realtime_frames_carry_the_destruct_metadata(self) -> None:
        from app.api.routes import websocket

        source = inspect.getsource(websocket._handle_frame)
        assert source.count('"destruct_after": msg.destruct_after_seconds') == 2
        assert source.count('"destruct_at": msg.destruct_at.isoformat()') == 2


class TestWorkerCommitOrdering:
    @pytest.mark.asyncio
    async def test_commit_happens_before_any_notification(self, monkeypatch: pytest.MonkeyPatch) -> None:
        msg = _Message(
            destruct_at=datetime.now(timezone.utc) - timedelta(minutes=1),
            sender_id=uuid4(),
            recipient_id=uuid4(),
        )
        mock_db = _MockDb([msg])
        timeline: list[str] = []
        original_commit = mock_db.commit

        async def timed_commit():
            timeline.append("commit")
            await original_commit()

        mock_db.commit = timed_commit  # type: ignore[method-assign]

        def mock_session_factory():
            return mock_db

        monkeypatch.setattr(
            "app.services.self_destruct_worker.AsyncSessionLocal",
            mock_session_factory,
        )

        async def mock_publish(_user_id, _event):
            timeline.append("publish")

        monkeypatch.setattr(
            "app.api.routes.websocket.publish",
            mock_publish,
        )

        worker = SelfDestructWorker()
        worker._storage = _Storage()  # noqa: SLF001
        await worker.sweep_once()

        assert timeline[0] == "commit"
        assert timeline.count("publish") == 2

    @pytest.mark.asyncio
    async def test_one_failed_notification_does_not_skip_the_rest(self, monkeypatch: pytest.MonkeyPatch) -> None:
        sender_id = uuid4()
        recipient_id = uuid4()
        msg = _Message(
            destruct_at=datetime.now(timezone.utc) - timedelta(minutes=1),
            sender_id=sender_id,
            recipient_id=recipient_id,
        )
        mock_db = _MockDb([msg])

        def mock_session_factory():
            return mock_db

        monkeypatch.setattr(
            "app.services.self_destruct_worker.AsyncSessionLocal",
            mock_session_factory,
        )

        delivered: list[object] = []

        async def flaky_publish(user_id, _event):
            if user_id == recipient_id:
                raise ConnectionError("Redis unavailable")
            delivered.append(user_id)

        monkeypatch.setattr(
            "app.api.routes.websocket.publish",
            flaky_publish,
        )

        worker = SelfDestructWorker()
        worker._storage = _Storage()  # noqa: SLF001
        wiped = await worker.sweep_once()

        assert wiped == 1
        assert mock_db.committed is True
        assert delivered == [sender_id], (
            "the other recipient must still receive the unsend frame"
        )

    @pytest.mark.asyncio
    async def test_storage_failure_produces_no_unsend_notification(self, monkeypatch: pytest.MonkeyPatch) -> None:
        msg = _Message(
            destruct_at=datetime.now(timezone.utc) - timedelta(minutes=1),
            media_object_key="attachments/stuck.png",
        )
        mock_db = _MockDb([msg])
        published = False

        def mock_session_factory():
            return mock_db

        monkeypatch.setattr(
            "app.services.self_destruct_worker.AsyncSessionLocal",
            mock_session_factory,
        )

        async def mock_publish(_user_id, _event):
            nonlocal published
            published = True

        monkeypatch.setattr(
            "app.api.routes.websocket.publish",
            mock_publish,
        )

        worker = SelfDestructWorker()
        worker._storage = _Storage(fails=True)  # noqa: SLF001
        wiped = await worker.sweep_once()

        assert wiped == 0
        assert published is False
        assert msg.is_destructed is False

    @pytest.mark.asyncio
    async def test_media_pointer_metadata_is_wiped_with_the_body(self, monkeypatch: pytest.MonkeyPatch) -> None:
        msg = _Message(
            destruct_at=datetime.now(timezone.utc) - timedelta(minutes=1),
            media_object_key="attachments/image.png",
        )
        mock_db = _MockDb([msg])

        def mock_session_factory():
            return mock_db

        monkeypatch.setattr(
            "app.services.self_destruct_worker.AsyncSessionLocal",
            mock_session_factory,
        )

        async def mock_publish(_user_id, _event):
            return None

        monkeypatch.setattr(
            "app.api.routes.websocket.publish",
            mock_publish,
        )

        worker = SelfDestructWorker()
        worker._storage = _Storage()  # noqa: SLF001
        await worker.sweep_once()

        assert msg.media_mime_type is None
        assert msg.media_size_bytes is None
