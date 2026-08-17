"""Push tokens belong to a device, not to an account.

`users.fcm_token` was a single column. The second device to sign in overwrote
the first one's token, so anyone with a phone and a tablet had exactly one of
them receiving notifications, decided by whichever had launched the app last —
and nothing anywhere reported it, because from the server's point of view the
send succeeded.
"""

from __future__ import annotations

import inspect
from pathlib import Path

import pytest

from app.services import push_service


class _FakeScalars:
    def __init__(self, values: list[str]) -> None:
        self._values = values

    def all(self) -> list[str]:
        return self._values


class _FakeDb:
    """Answers `scalars` with a fixed list and records what it was asked."""

    def __init__(self, tokens: list[str]) -> None:
        self._tokens = tokens
        self.statements: list[object] = []

    async def scalars(self, statement: object) -> _FakeScalars:
        self.statements.append(statement)
        return _FakeScalars(self._tokens)


class TestTokensForUser:
    @pytest.mark.asyncio
    async def test_returns_every_device(self) -> None:
        db = _FakeDb(["phone-token", "tablet-token"])
        tokens = await push_service.tokens_for_user(db, "user-1")
        assert tokens == ["phone-token", "tablet-token"]

    @pytest.mark.asyncio
    async def test_deduplicates(self) -> None:
        # Reinstalling can leave two live sessions holding the same token, and
        # sending twice shows one message as two notifications.
        db = _FakeDb(["same", "same", "other"])
        assert await push_service.tokens_for_user(db, "user-1") == ["same", "other"]

    @pytest.mark.asyncio
    async def test_preserves_order(self) -> None:
        # dict.fromkeys rather than set(), because a set would reorder and make
        # the delivery order depend on hash seeding.
        db = _FakeDb(["a", "b", "c"])
        assert await push_service.tokens_for_user(db, "user-1") == ["a", "b", "c"]

    @pytest.mark.asyncio
    async def test_excludes_revoked_and_expired_sessions(self) -> None:
        """The filter is on the query, so this asserts the query.

        A revoked device going on being told about new messages would make
        remote sign-out cosmetic — the session cannot be used, but the person
        holding the phone still sees who is messaging whom.
        """
        db = _FakeDb([])
        await push_service.tokens_for_user(db, "user-1")

        rendered = str(db.statements[0])
        assert "revoked_at IS NULL" in rendered
        assert "expires_at" in rendered
        assert "fcm_token IS NOT NULL" in rendered


class TestEveryPathFansOut:
    """Each of the three senders had its own copy of the bug."""

    def test_direct_messages(self) -> None:
        from app.api.routes import websocket as ws_route

        source = inspect.getsource(ws_route._handle_frame)
        assert "tokens_for_user" in source
        assert "recipient.fcm_token" not in source

    def test_admin_broadcasts(self) -> None:
        # The place it would have mattered most: an urgent broadcast reaching
        # only whichever device signed in most recently.
        from app.api.routes import admin

        source = inspect.getsource(admin)
        assert "tokens_for_user" in source
        assert "u.fcm_token for u in targets" not in source

    def test_document_wake_ups(self) -> None:
        # Keyword rules live on each device separately, so a wake-up that
        # reaches one device checks only that device's watchlist.
        source = inspect.getsource(push_service.send_ocr_push)
        assert "tokens_for_user" in source
        assert "select(User.fcm_token)" not in source


class TestRegistration:
    def test_writes_the_token_to_the_session(self) -> None:
        from app.api.routes import broadcasts

        source = inspect.getsource(broadcasts.register_fcm_token)
        assert "session.fcm_token = body.token" in source

    def test_still_writes_the_old_column_during_the_expand_phase(self) -> None:
        """Expand, not replace.

        Nothing reads `users.fcm_token` any more, but a rollback to the
        previous release would, and it must not find the column stale. The
        write goes away with the migration that drops the column, not before.
        """
        from app.api.routes import broadcasts

        source = inspect.getsource(broadcasts.register_fcm_token)
        assert "user.fcm_token = body.token" in source


class TestMigrationIsAdditive:
    def test_it_adds_and_drops_nothing(self) -> None:
        # A rollback of application code across this migration has to be safe,
        # which is the whole reason for expand-migrate-contract.
        #
        # Read as text rather than imported: alembic/versions is a script
        # directory, not a package, and `alembic` resolves to the library.
        source = (
            Path("alembic/versions/0010_per_session_fcm_token.py")
            .read_text(encoding="utf-8")
        )
        upgrade = source.split("def upgrade()")[1].split("def downgrade()")[0]
        assert "add_column" in upgrade
        assert "drop_column" not in upgrade
        assert "drop_table" not in upgrade


class TestDeadTokensAreForgotten:
    def test_there_is_a_way_to_clear_one(self) -> None:
        """Otherwise the token list only ever grows.

        An uninstalled app leaves its session behind, every message pays for a
        delivery attempt that cannot succeed, and the resulting failures are
        permanent noise in the metrics that would mask a real one.
        """
        assert hasattr(push_service, "forget_token")
        source = inspect.getsource(push_service.forget_token)
        assert "fcm_token=None" in source
