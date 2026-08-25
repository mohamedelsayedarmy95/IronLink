"""Retention limits, enforced.

`audit_logs` and `user_sessions` grew without bound. A limit that is written
down and not enforced exists only in the document, which is the failure this
audit cycle keeps finding.

This is also the only code in the repository that deletes data nobody asked it
to delete, so most of these tests are about restraint rather than about
capability: what it must not touch, and what it must not do when misconfigured.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

import pytest
from sqlalchemy import select

from tests.conftest import requires_db

from app.config import settings
from app.models import AuditLog, User, UserSession
from app.models.user import UserStatus
from app.services.retention_worker import RetentionWorker


def _worker(db) -> RetentionWorker:
    """A worker that sweeps inside the test's own transaction.

    The worker opens its own session in production, which is right there and
    wrong here: a separate connection cannot see rows this test has not
    committed to the real database, so every "the old row was deleted"
    assertion would have passed because there was nothing there to delete.
    """

    class _Bound:
        async def __aenter__(self):
            return db

        async def __aexit__(self, *_exc):
            return False

    return RetentionWorker(session_factory=_Bound)


pytestmark = requires_db

NOW = datetime(2026, 8, 18, 12, 0, tzinfo=timezone.utc)


async def _person(db) -> User:
    user = User(
        phone_number=f"+2010{uuid.uuid4().int % 100000000:08d}",
        full_name="Someone",
        status=UserStatus.ACTIVE,
        hashed_military_id="not-a-hash",
        hashed_password="not-a-hash",
    )
    db.add(user)
    await db.flush()
    return user


async def _session(db, user_id, *, age_days: int, revoked: bool) -> uuid.UUID:
    row = UserSession(
        user_id=user_id,
        refresh_token_hash=uuid.uuid4().hex,
        ip_address="203.0.113.7",
        expires_at=NOW + timedelta(days=7),
        revoked_at=NOW - timedelta(days=age_days) if revoked else None,
    )
    db.add(row)
    await db.flush()
    # updated_at has a server default, so it is set explicitly to place the row
    # on the intended side of the cutoff without waiting months.
    row.updated_at = NOW - timedelta(days=age_days)
    await db.flush()
    return row.id


class TestAuditLogs:
    @pytest.mark.asyncio
    async def test_an_old_entry_is_removed(self, db, monkeypatch) -> None:
        monkeypatch.setattr(settings, "AUDIT_LOG_RETENTION_DAYS", 365)
        entry = AuditLog(action="test.old", success=True)
        db.add(entry)
        await db.flush()
        entry.created_at = NOW - timedelta(days=400)
        await db.commit()

        await _worker(db).sweep_once(now=NOW)
        db.expire_all()

        assert await db.scalar(
            select(AuditLog).where(AuditLog.action == "test.old")
        ) is None

    @pytest.mark.asyncio
    async def test_a_recent_entry_is_kept(self, db, monkeypatch) -> None:
        monkeypatch.setattr(settings, "AUDIT_LOG_RETENTION_DAYS", 365)
        entry = AuditLog(action="test.recent", success=True)
        db.add(entry)
        await db.flush()
        entry.created_at = NOW - timedelta(days=30)
        await db.commit()

        await _worker(db).sweep_once(now=NOW)
        db.expire_all()

        assert await db.scalar(
            select(AuditLog).where(AuditLog.action == "test.recent")
        ) is not None

    @pytest.mark.asyncio
    async def test_an_entry_one_day_inside_the_window_is_kept(
        self, db, monkeypatch
    ) -> None:
        # Off-by-one on a cutoff deletes a day of records that should have been
        # kept, and nothing anywhere would report it.
        monkeypatch.setattr(settings, "AUDIT_LOG_RETENTION_DAYS", 365)
        entry = AuditLog(action="test.boundary", success=True)
        db.add(entry)
        await db.flush()
        entry.created_at = NOW - timedelta(days=364)
        await db.commit()

        await _worker(db).sweep_once(now=NOW)
        db.expire_all()

        assert await db.scalar(
            select(AuditLog).where(AuditLog.action == "test.boundary")
        ) is not None


class TestSessions:
    @pytest.mark.asyncio
    async def test_a_live_session_is_never_touched(self, db, monkeypatch) -> None:
        """The property that matters most here.

        Deleting a live session signs somebody out. The filter is on
        revoked_at/expires_at, and the index the sweep uses is partial on
        revoked rows, so the query cannot even see a session someone is
        holding — but the guarantee is worth asserting rather than inferring
        from a WHERE clause.
        """
        monkeypatch.setattr(settings, "SESSION_RETENTION_DAYS", 90)
        user = await _person(db)
        # Old enough to be swept on age alone, and still live.
        session_id = await _session(db, user.id, age_days=400, revoked=False)
        await db.commit()

        await _worker(db).sweep_once(now=NOW)
        db.expire_all()

        assert await db.get(UserSession, session_id) is not None

    @pytest.mark.asyncio
    async def test_an_old_revoked_session_is_removed(self, db, monkeypatch) -> None:
        monkeypatch.setattr(settings, "SESSION_RETENTION_DAYS", 90)
        user = await _person(db)
        session_id = await _session(db, user.id, age_days=120, revoked=True)
        await db.commit()

        await _worker(db).sweep_once(now=NOW)
        db.expire_all()

        assert await db.get(UserSession, session_id) is None

    @pytest.mark.asyncio
    async def test_a_recently_revoked_session_is_kept(self, db, monkeypatch) -> None:
        # Recent history is what makes "this is a new device" mean anything.
        monkeypatch.setattr(settings, "SESSION_RETENTION_DAYS", 90)
        user = await _person(db)
        session_id = await _session(db, user.id, age_days=10, revoked=True)
        await db.commit()

        await _worker(db).sweep_once(now=NOW)
        db.expire_all()

        assert await db.get(UserSession, session_id) is not None


class TestMisconfiguration:
    @pytest.mark.asyncio
    async def test_zero_disables_the_sweep_rather_than_deleting_everything(
        self, db, monkeypatch
    ) -> None:
        """The failure mode a naive cutoff would have.

        `now - timedelta(days=0)` is now, so a sweep that did not check for
        zero would delete every record in the table the moment somebody set the
        window to zero meaning "off".
        """
        monkeypatch.setattr(settings, "AUDIT_LOG_RETENTION_DAYS", 0)
        monkeypatch.setattr(settings, "SESSION_RETENTION_DAYS", 0)

        entry = AuditLog(action="test.zero", success=True)
        db.add(entry)
        await db.flush()
        entry.created_at = NOW - timedelta(days=9999)
        await db.commit()

        result = await _worker(db).sweep_once(now=NOW)
        db.expire_all()

        assert result == {"audit_logs": 0, "user_sessions": 0}
        assert await db.scalar(
            select(AuditLog).where(AuditLog.action == "test.zero")
        ) is not None

    @pytest.mark.asyncio
    async def test_a_negative_window_is_also_off(self, db, monkeypatch) -> None:
        monkeypatch.setattr(settings, "AUDIT_LOG_RETENTION_DAYS", -1)
        entry = AuditLog(action="test.negative", success=True)
        db.add(entry)
        await db.flush()
        entry.created_at = NOW - timedelta(days=9999)
        await db.commit()

        await _worker(db).sweep_once(now=NOW)
        db.expire_all()

        assert await db.scalar(
            select(AuditLog).where(AuditLog.action == "test.negative")
        ) is not None

    @pytest.mark.asyncio
    async def test_a_sweep_with_nothing_to_do_reports_zero(
        self, db, monkeypatch
    ) -> None:
        monkeypatch.setattr(settings, "AUDIT_LOG_RETENTION_DAYS", 365)
        monkeypatch.setattr(settings, "SESSION_RETENTION_DAYS", 90)

        assert await _worker(db).sweep_once(now=NOW) == {
            "audit_logs": 0,
            "user_sessions": 0,
        }
