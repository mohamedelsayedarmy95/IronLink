from __future__ import annotations

import asyncio
from datetime import datetime, timezone

import structlog
from sqlalchemy import select

from app.core import observability
from app.config import settings
from app.core.database import AsyncSessionLocal
from app.models import AuditLog, Message
from app.services.storage_service import StorageService

logger = structlog.get_logger("self_destruct")

SWEEP_INTERVAL_SECONDS = 60
BATCH_SIZE = 500


class SelfDestructWorker:
    """Background sweep: permanently wipes expired self-destruct messages.

    Every minute:
      1. SELECT messages where destruct_at <= now AND is_destructed = false
      2. Delete the media object from MinIO (if any)
      3. Wipe ciphertext + media pointers, set is_destructed = true
      4. Append an audit_logs row (content is gone; the event is provable)
      5. Publish an 'unsend' frame to both parties so ONLINE clients drop the
         message instantly; offline clients reconcile on next history fetch
         because destructed messages are excluded from history queries.

    And a second pass, reap_orphans, for attachment bodies whose message was
    retracted while object storage was unreachable. Those must not be left:
    a deletion the user performed and the system did not complete is a
    deletion that did not happen.
    """

    def __init__(self) -> None:
        self._task: asyncio.Task | None = None
        self._storage = StorageService()

    def start(self) -> None:
        self._task = asyncio.create_task(self._run(), name="self-destruct-worker")

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
                wiped = await self.sweep_once()
                # Second pass: bodies whose message was retracted but whose
                # object delete did not succeed at the time. Run every cycle,
                # because until it does the user's deletion is incomplete.
                orphans = await self.reap_orphans()
                observability.orphaned_attachments.set(orphans)
                # The gauge is the backlog: how many messages were already past
                # their expiry when the sweep ran. If it stops returning to
                # zero, the sweeper is not keeping up and messages are
                # outliving the lifetime their sender chose — which is a
                # privacy failure, not a slow background job.
                observability.self_destruct_overdue.set(wiped)
                if wiped:
                    observability.self_destruct_wiped.inc(wiped)
                    logger.info("self_destruct_sweep", wiped=wiped)
            except Exception as exc:  # worker must never die silently
                observability.self_destruct_failures.inc()
                logger.error("self_destruct_sweep_failed", error=str(exc))
            await asyncio.sleep(SWEEP_INTERVAL_SECONDS)

    async def reap_orphans(self) -> int:
        """Deletes attachment bodies left behind by a retraction.

        `unsend_message` attempts the object delete inline and clears the key
        only when it succeeds. When object storage is briefly unreachable it
        deliberately leaves the key in place rather than failing the user's
        retraction — the message is already deleted for both parties, and the
        body has to catch up.

        This is that catching up. Returns the number still outstanding after
        the pass, which is what the gauge reports: a number that does not
        return to zero means somebody's deletion has not actually happened.
        """
        outstanding = 0

        async with AsyncSessionLocal() as db:
            stranded = (await db.scalars(
                select(Message)
                .where(
                    Message.deleted_for_everyone.is_(True),
                    Message.media_object_key.isnot(None),
                )
                .limit(BATCH_SIZE)
            )).all()

            for msg in stranded:
                try:
                    self._storage.delete_object(
                        settings.S3_BUCKET_ATTACHMENTS, msg.media_object_key
                    )
                except Exception as exc:
                    outstanding += 1
                    logger.warning(
                        "orphan_delete_failed",
                        message_id=str(msg.id),
                        error=str(exc),
                    )
                    continue
                # Cleared only after the object is gone, so a failure here
                # leaves something for the next pass to find. Clearing it
                # first is exactly the bug this pass exists to clean up after.
                msg.media_object_key = None

            if stranded:
                await db.commit()

        return outstanding

    async def sweep_once(self) -> int:
        # Imported here to avoid a circular import (websocket → message_service
        # → … ). publish() is a leaf function with no route dependencies.
        from app.api.routes.websocket import publish

        now = datetime.now(timezone.utc)
        wiped = 0

        async with AsyncSessionLocal() as db:
            expired = (await db.scalars(
                select(Message)
                .where(
                    Message.is_destructed.is_(False),
                    Message.destruct_at.isnot(None),
                    Message.destruct_at <= now,
                )
                .limit(BATCH_SIZE)
            )).all()

            for msg in expired:
                if msg.media_object_key:
                    try:
                        self._storage.delete_object(
                            settings.S3_BUCKET_ATTACHMENTS, msg.media_object_key
                        )
                    except Exception as exc:
                        # Keep the message queued for the next sweep rather than
                        # leaving an orphaned file in MinIO.
                        logger.warning(
                            "minio_delete_failed",
                            message_id=str(msg.id),
                            error=str(exc),
                        )
                        continue

                msg.content_ciphertext = None
                msg.media_object_key = None
                msg.media_mime_type = None
                msg.is_destructed = True
                msg.deleted_at = now

                db.add(AuditLog(
                    actor_id=None,   # system event
                    action="message.self_destructed",
                    resource_type="message",
                    resource_id=str(msg.id),
                    success=True,
                    metadata_={"had_media": msg.media_object_key is not None},
                ))
                wiped += 1

                event = {"type": "unsend", "message_id": str(msg.id)}
                if msg.recipient_id is not None:
                    await publish(msg.recipient_id, event)
                if msg.sender_id is not None:
                    await publish(msg.sender_id, event)

            await db.commit()

        return wiped
