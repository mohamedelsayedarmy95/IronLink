"""A deletion the user performed and the system did not complete.

`unsend_message` used to null `media_object_key` and stop there. The encrypted
attachment stayed in object storage — and nulling the key was the part that
made it permanent, because nothing knew the object's name any more, so no sweep
could ever find it. A user who pressed "delete for everyone" left a body behind
that would outlive their account, and the bucket grew by one orphan per
retraction.

The body is encrypted, so this was never a plaintext exposure. It was worse in
a quieter way: the product told the user the message was gone, and one part of
it was not, with no mechanism anywhere that would ever notice.
"""

from __future__ import annotations

from datetime import datetime, timezone
from uuid import uuid4

import pytest

from app.services import message_service
from app.services.self_destruct_worker import SelfDestructWorker


class _Message:
    """Enough of a Message to exercise the retraction path."""

    def __init__(self, *, key: str | None) -> None:
        self.id = uuid4()
        self.sender_id = uuid4()
        self.created_at = datetime.now(timezone.utc)
        self.content_ciphertext = "envelope"
        self.media_object_key = key
        self.media_mime_type = "application/octet-stream"
        self.deleted_for_everyone = False
        self.deleted_at = None


class _Db:
    def __init__(self, message: _Message) -> None:
        self._message = message
        self.committed = False

    async def scalar(self, _statement: object) -> _Message:
        return self._message

    async def commit(self) -> None:
        self.committed = True


class _Storage:
    """Records deletes, and can be told to fail like unreachable storage."""

    def __init__(self, *, fails: bool = False) -> None:
        self.deleted: list[str] = []
        self._fails = fails

    def delete_object(self, _bucket: str, key: str) -> None:
        if self._fails:
            raise RuntimeError("object storage unreachable")
        self.deleted.append(key)


@pytest.fixture()
def storage(monkeypatch: pytest.MonkeyPatch) -> _Storage:
    fake = _Storage()
    monkeypatch.setattr(
        "app.services.storage_service.StorageService", lambda: fake
    )
    return fake


class TestRetractionRemovesTheBody:
    @pytest.mark.asyncio
    async def test_the_object_is_deleted(
        self, storage: _Storage, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        msg = _Message(key="attachments/abc123")
        db = _Db(msg)

        await message_service.unsend_message(db, msg.id, msg.sender_id)

        assert storage.deleted == ["attachments/abc123"], (
            "the encrypted body must leave the bucket, not just the pointer"
        )

    @pytest.mark.asyncio
    async def test_the_pointer_is_cleared_only_after_the_object_is_gone(
        self, storage: _Storage
    ) -> None:
        msg = _Message(key="attachments/abc123")
        await message_service.unsend_message(_Db(msg), msg.id, msg.sender_id)

        assert msg.media_object_key is None

    @pytest.mark.asyncio
    async def test_the_ciphertext_goes_too(self, storage: _Storage) -> None:
        msg = _Message(key=None)
        await message_service.unsend_message(_Db(msg), msg.id, msg.sender_id)

        assert msg.content_ciphertext is None
        assert msg.deleted_for_everyone is True


class TestStorageBeingDownDoesNotLoseTheDeletion:
    """The case that produced the orphan in the first place."""

    @pytest.mark.asyncio
    async def test_the_retraction_still_succeeds(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        # A user pressing "delete for everyone" must not be told it failed
        # because a bucket is briefly unreachable. The message is gone for both
        # parties either way.
        monkeypatch.setattr(
            "app.services.storage_service.StorageService",
            lambda: _Storage(fails=True),
        )
        msg = _Message(key="attachments/abc123")

        await message_service.unsend_message(_Db(msg), msg.id, msg.sender_id)

        assert msg.deleted_for_everyone is True
        assert msg.content_ciphertext is None

    @pytest.mark.asyncio
    async def test_but_the_key_is_kept_so_the_body_can_still_be_found(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """The whole fix, in one assertion.

        Clearing the key on a failed delete is what made the old orphan
        unreachable. Keeping it means the sweeper has something to find.
        """
        monkeypatch.setattr(
            "app.services.storage_service.StorageService",
            lambda: _Storage(fails=True),
        )
        msg = _Message(key="attachments/abc123")

        await message_service.unsend_message(_Db(msg), msg.id, msg.sender_id)

        assert msg.media_object_key == "attachments/abc123"


class _ScalarResult:
    def __init__(self, values: list[_Message]) -> None:
        self._values = values

    def all(self) -> list[_Message]:
        return self._values


class _SweepDb:
    def __init__(self, stranded: list[_Message]) -> None:
        self._stranded = stranded
        self.committed = False

    async def scalars(self, _statement: object) -> _ScalarResult:
        return _ScalarResult(self._stranded)

    async def commit(self) -> None:
        self.committed = True

    async def __aenter__(self) -> _SweepDb:
        return self

    async def __aexit__(self, *_: object) -> None:
        return None


class TestTheSweeperFinishesTheJob:
    @pytest.mark.asyncio
    async def test_a_stranded_body_is_deleted_on_the_next_pass(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        stranded = _Message(key="attachments/left-behind")
        stranded.deleted_for_everyone = True

        monkeypatch.setattr(
            "app.services.self_destruct_worker.AsyncSessionLocal",
            lambda: _SweepDb([stranded]),
        )
        worker = SelfDestructWorker()
        storage = _Storage()
        worker._storage = storage  # noqa: SLF001

        outstanding = await worker.reap_orphans()

        assert storage.deleted == ["attachments/left-behind"]
        assert stranded.media_object_key is None
        assert outstanding == 0

    @pytest.mark.asyncio
    async def test_a_body_it_still_cannot_delete_is_reported_not_forgotten(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        # The gauge is the point. A number that does not come back to zero
        # means somebody's deletion has not actually happened, and that is a
        # privacy failure rather than a storage one.
        stranded = _Message(key="attachments/still-stuck")
        stranded.deleted_for_everyone = True

        monkeypatch.setattr(
            "app.services.self_destruct_worker.AsyncSessionLocal",
            lambda: _SweepDb([stranded]),
        )
        worker = SelfDestructWorker()
        worker._storage = _Storage(fails=True)  # noqa: SLF001

        outstanding = await worker.reap_orphans()

        assert outstanding == 1
        assert stranded.media_object_key == "attachments/still-stuck", (
            "keeping the key is what lets the next pass try again"
        )

    @pytest.mark.asyncio
    async def test_nothing_stranded_is_a_quiet_pass(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        db = _SweepDb([])
        monkeypatch.setattr(
            "app.services.self_destruct_worker.AsyncSessionLocal", lambda: db
        )
        worker = SelfDestructWorker()
        worker._storage = _Storage()  # noqa: SLF001

        assert await worker.reap_orphans() == 0
        assert db.committed is False, "no write when there is nothing to do"
