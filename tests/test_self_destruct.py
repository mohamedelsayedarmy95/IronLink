"""Comprehensive tests for the Self-Destruct Messages feature.

This test suite covers:
1. Direct messages read before and after expiry
2. Expired messages hidden from history/lists immediately
3. Redis outage (test that the DB wipe still commits even if publish fails)
4. Audit metadata `had_media` being correctly set to true when media existed
5. Multi-message sweeps
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from uuid import uuid4

import pytest

from app.models import AuditLog, Message
from app.models.message import MessageStatus, MessageType
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
        self.deleted_at = None
        self.created_at = datetime.now(timezone.utc)
        self.deleted_for_everyone = False
        self.is_edited = False
        self.edit_count = 0
        self.is_secret = False


class _ScalarResult:
    def __init__(self, values: list[_Message]) -> None:
        self._values = values

    def all(self) -> list[_Message]:
        return self._values


class _MockDb:
    """Async context manager that mimics AsyncSessionLocal for the worker."""

    def __init__(self, messages: list[_Message]) -> None:
        self._messages = messages
        self.committed = False
        self.added: list[AuditLog] = []

    async def scalars(self, statement: object) -> _ScalarResult:
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
    async def test_publish_called_only_for_sender_in_group(self, monkeypatch: pytest.MonkeyPatch) -> None:
        """For group messages, publish should only go to sender."""
        sender_id = uuid4()
        group_id = uuid4()
        msg = _Message(
            destruct_at=datetime.now(timezone.utc) - timedelta(minutes=1),
            sender_id=sender_id,
            group_id=group_id,
            recipient_id=None,
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

        assert len(published_events) == 1
        assert str(published_events[0][0]) == str(sender_id)
        assert published_events[0][1]["type"] == "unsend"

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
