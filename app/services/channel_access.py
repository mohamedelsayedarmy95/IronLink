"""SQL authorization shared by channel discovery, reads and attached media."""
import asyncio
from uuid import UUID

from fastapi import HTTPException, status
from sqlalchemy import and_, exists, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.sql.elements import ColumnElement
from minio.error import S3Error
from urllib3.exceptions import HTTPError

from app.config import settings
from app.models.channel import Channel, ChannelMediaKey, ChannelPost, ChannelSubscription, ChannelType
from app.services.storage_service import StorageNotConfigured, StorageService

_storage = StorageService()


def channel_visible_to(user_id: UUID) -> ColumnElement[bool]:
    active_subscription = exists(select(ChannelSubscription.id).where(
        ChannelSubscription.channel_id == Channel.id,
        ChannelSubscription.user_id == user_id,
        ChannelSubscription.is_active.is_(True),
    )).correlate(Channel)
    return or_(Channel.channel_type == ChannelType.PUBLIC,
               Channel.owner_id == user_id, active_subscription)


def post_visible_to(user_id: UUID) -> ColumnElement[bool]:
    # A delayed scheduler must not publish a flagged row just because its due
    # time passed. Also protect future timestamps even if the flag is absent.
    return or_(Channel.owner_id == user_id, and_(
        ChannelPost.is_scheduled.is_(False),
        or_(ChannelPost.scheduled_at.is_(None),
            ChannelPost.scheduled_at <= func.statement_timestamp()),
    ))


async def accessible_channel(
    db: AsyncSession, channel_id: UUID, user_id: UUID, *, lock: bool = False,
) -> Channel:
    query = select(Channel).where(Channel.id == channel_id, channel_visible_to(user_id))
    if lock:
        # All membership mutations and visibility changes serialize on this
        # existing row. Refresh ORM state after waiting for a concurrent writer.
        query = query.with_for_update().execution_options(populate_existing=True)
    channel = await db.scalar(query)
    if channel is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, 'Channel not found')
    return channel


async def bind_channel_media(db: AsyncSession, media_key: str, channel_id: UUID, user_id: UUID) -> None:
    existing = await db.scalar(select(ChannelMediaKey).where(ChannelMediaKey.media_key == media_key))
    if existing is not None:
        if existing.channel_id != channel_id:
            raise HTTPException(status.HTTP_404_NOT_FOUND, 'Media not found')
        return
    # Knowing an unbound key is not ownership. Only metadata written by the
    # authenticated upload-completion route can authorize its first attachment.
    try:
        owner = await asyncio.wait_for(asyncio.to_thread(
            _storage.object_owner, settings.S3_BUCKET_ATTACHMENTS, media_key), timeout=5)
    except (StorageNotConfigured, S3Error, HTTPError, OSError) as exc:
        raise HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, 'Media ownership unavailable') from exc
    if owner != str(user_id):
        raise HTTPException(status.HTTP_404_NOT_FOUND, 'Media not found')
    # The unique key serializes competing first references. A foreign post
    # cannot broaden OR restrict another channel's attachment policy.
    await db.execute(insert(ChannelMediaKey).values(media_key=media_key, channel_id=channel_id)
                     .on_conflict_do_nothing(index_elements=['media_key']))
    scope = await db.scalar(select(ChannelMediaKey.channel_id).where(
        ChannelMediaKey.media_key == media_key))
    if scope != channel_id:
        raise HTTPException(status.HTTP_404_NOT_FOUND, 'Media not found')


async def require_channel_media_access(db: AsyncSession, media_key: str, user_id: UUID) -> None:
    permitted_post = exists(select(ChannelPost.id).join(
        Channel, Channel.id == ChannelPost.channel_id,
    ).where(
        ChannelPost.media_key == ChannelMediaKey.media_key,
        ChannelPost.channel_id == ChannelMediaKey.channel_id,
        channel_visible_to(user_id), post_visible_to(user_id),
    )).correlate(ChannelMediaKey)
    # A NULL/deleted channel or an unpublished-only binding has no permitted
    # post. Unbound non-channel uploads retain the existing media contract.
    denied = await db.scalar(select(exists(select(ChannelMediaKey.id).where(
        ChannelMediaKey.media_key == media_key, ~permitted_post,
    ))))
    if denied:
        raise HTTPException(status.HTTP_404_NOT_FOUND, 'Media not found')
