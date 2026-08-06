from __future__ import annotations

import asyncio
from datetime import datetime, timezone

import structlog
from sqlalchemy import select

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
                if wiped:
                    logger.info("self_destruct_sweep", wiped=wiped)
            except Exception as exc:  # worker must never die silently
                logger.error("self_destruct_sweep_failed", error=str(exc))
            await asyncio.sleep(SWEEP_INTERVAL_SECONDS)

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
                            settings.MINIO_BUCKET_ATTACHMENTS, msg.media_object_key
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
