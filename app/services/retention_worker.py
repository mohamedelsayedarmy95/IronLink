"""Enforcing retention limits.

The standard requires retention limits defined per data type *and enforced*.
`audit_logs` and `user_sessions` had neither: both grew without bound, and both
hold data that `docs/DATA_CLASSIFICATION.md` classifies as identifying — actor
ids in one, IP addresses and user agents in the other.

A limit that is written down and not enforced is a limit that exists only in the
document, which is the failure this whole audit cycle keeps finding.

WHY THE WINDOWS ARE WHAT THEY ARE

Neither number is arbitrary, and neither is a guess dressed as a standard.

**Audit logs: 365 days.** Long enough to cover a full annual security review and
an incident investigation that begins months after the event, which is the usual
case — breaches are typically discovered long after they happen. Short enough
that the record of who did what is not permanent.

**Sessions: 90 days**, and only rows that are already revoked or expired. The
reason to keep any is that "this is a new device" can only be said relative to
the devices seen before; three months is enough history to make that judgement.
Beyond it, the row is not security signal, it is a location and IP trail.

A LIST OF THINGS A DESTRUCTIVE BACKGROUND JOB MUST GET RIGHT

This is the only code in the repository that deletes data nobody asked it to
delete, so it is built to be timid:

  It never touches a live session. The filter is on `revoked_at`/`expires_at`,
  and the index it uses is partial on revoked rows, so the query cannot even
  see a session somebody is holding.

  It deletes in bounded batches. A single unbounded DELETE over a large table
  takes a lock long enough to matter, and a bug in it is unbounded too.

  It reports what it removed. `ironlink_retention_deleted_total` makes a
  sudden spike visible; a sweeper that quietly deleted ten times its usual
  volume would otherwise be invisible until somebody went looking for a row.

  It is disabled by setting a window to zero, which is checked explicitly
  rather than falling through to "delete everything older than now".
"""

from __future__ import annotations

import asyncio
from datetime import datetime, timedelta, timezone

import structlog
from sqlalchemy import delete, or_, select

from app.config import settings
from app.core import observability
from app.core.database import AsyncSessionLocal
from app.models import AuditLog, UserSession

logger = structlog.get_logger("retention")

#: Daily. The windows are measured in months, so a faster cadence would only
#: add load, and a slower one would let a table drift meaningfully past its
#: limit between passes.
SWEEP_INTERVAL_SECONDS = 24 * 60 * 60

#: Rows per statement. Bounded so one pass cannot hold a lock long enough to be
#: felt, and so a bug cannot delete an entire table in a single transaction.
BATCH_SIZE = 1000

#: Passes per run, so a large backlog drains over several days rather than in
#: one very long transaction on the first night this ships.
MAX_BATCHES = 20


class RetentionWorker:
    """Deletes records that have outlived their stated retention."""

    def __init__(self, session_factory=None) -> None:
        self._task: asyncio.Task | None = None
        # Injectable so a test can hand in its own transaction-bound session.
        # Without this the worker opens a separate connection, which cannot see
        # a test's uncommitted rows — and every "the old row was deleted" test
        # would pass because there was nothing there to delete.
        self._session_factory = session_factory or AsyncSessionLocal

    def start(self) -> None:
        self._task = asyncio.create_task(self._run(), name="retention-worker")

    async def stop(self) -> None:
        if self._task is not None:
            self._task.cancel()
            try:
                await self._task
            except asyncio.CancelledError:
                pass

    async def _run(self) -> None:
        while True:
            try:
                await self.sweep_once()
            except Exception as exc:  # worker must never die silently
                observability.retention_failures.inc()
                logger.error("retention_sweep_failed", error=str(exc))
            await asyncio.sleep(SWEEP_INTERVAL_SECONDS)

    async def sweep_once(self, now: datetime | None = None) -> dict[str, int]:
        """One pass. Returns what was deleted, by table.

        `now` is injectable so the tests can place a row on either side of a
        boundary without waiting a year.
        """
        at = (now or datetime.now(timezone.utc)).astimezone(timezone.utc)

        deleted = {
            "audit_logs": await self._sweep_audit_logs(at),
            "user_sessions": await self._sweep_sessions(at),
        }
        if any(deleted.values()):
            logger.info("retention_sweep", **deleted)
        return deleted

    async def _sweep_audit_logs(self, at: datetime) -> int:
        days = settings.AUDIT_LOG_RETENTION_DAYS
        if days <= 0:
            # Explicitly "retention disabled", not "delete everything older
            # than right now", which is what a naive cutoff would compute.
            return 0

        cutoff = at - timedelta(days=days)
        return await self._delete_in_batches(
            lambda: select(AuditLog.id)
            .where(AuditLog.created_at < cutoff)
            .order_by(AuditLog.created_at)
            .limit(BATCH_SIZE),
            lambda ids: delete(AuditLog).where(AuditLog.id.in_(ids)),
            table="audit_logs",
        )

    async def _sweep_sessions(self, at: datetime) -> int:
        days = settings.SESSION_RETENTION_DAYS
        if days <= 0:
            return 0

        cutoff = at - timedelta(days=days)
        return await self._delete_in_batches(
            # A live session is one that is neither revoked nor past its expiry.
            # Both halves are required: a revoked session may not have expired,
            # and an expired one may never have been revoked.
            lambda: select(UserSession.id)
            .where(
                or_(
                    UserSession.revoked_at.is_not(None),
                    UserSession.expires_at < at,
                ),
                UserSession.updated_at < cutoff,
            )
            .order_by(UserSession.updated_at)
            .limit(BATCH_SIZE),
            lambda ids: delete(UserSession).where(UserSession.id.in_(ids)),
            table="user_sessions",
        )

    async def _delete_in_batches(self, select_ids, delete_by_ids, *, table: str) -> int:
        """Selects then deletes, in bounded batches, committing each one.

        Two statements rather than `DELETE ... WHERE ... LIMIT`, which Postgres
        does not support. Committing per batch means an interruption leaves the
        work done so far rather than rolling back an hour of it.
        """
        total = 0
        for _ in range(MAX_BATCHES):
            async with self._session_factory() as db:
                ids = (await db.scalars(select_ids())).all()
                if not ids:
                    break
                await db.execute(delete_by_ids(ids))
                await db.commit()

            total += len(ids)
            observability.retention_deleted.labels(table=table).inc(len(ids))
            if len(ids) < BATCH_SIZE:
                break
        return total
