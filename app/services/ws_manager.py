from __future__ import annotations

import asyncio
import json
import logging
import secrets
from datetime import datetime, timezone
from uuid import UUID

from fastapi import WebSocket
from redis.asyncio import Redis

from app.core.redis import redis_sessions as redis_client

logger = logging.getLogger(__name__)


class ConnectionManager:
    """WebSocket connection registry — local sockets + Redis shared state.

    Redis keys (DB index 2 — REDIS_DB_SESSIONS):
      ws:conn:{connection_id}  → JSON {user_id, connected_at}   (TTL-refreshed)
      ws:user:{user_id}        → SET of connection_ids           (multi-device)
      ws:online                → SET of user_ids currently online

    The Redis layer is what makes this horizontally scalable: any API replica
    can answer "who is online" and target a specific device for disconnect,
    even for sockets it does not hold locally.
    """

    CONN_TTL_SECONDS = 90   # heartbeat refresh window

    def __init__(self, redis: Redis) -> None:
        self._redis = redis
        self._local: dict[str, WebSocket] = {}

    async def register(self, user_id: UUID, websocket: WebSocket) -> str:
        connection_id = secrets.token_hex(16)
        self._local[connection_id] = websocket

        pipe = self._redis.pipeline()
        pipe.set(
            f"ws:conn:{connection_id}",
            json.dumps({
                "user_id": str(user_id),
                "connected_at": datetime.now(timezone.utc).isoformat(),
            }),
            ex=self.CONN_TTL_SECONDS,
        )
        pipe.sadd(f"ws:user:{user_id}", connection_id)
        pipe.sadd("ws:online", str(user_id))
        await pipe.execute()
        return connection_id

    async def heartbeat(self, connection_id: str) -> None:
        await self._redis.expire(f"ws:conn:{connection_id}", self.CONN_TTL_SECONDS)

    async def unregister(self, user_id: UUID, connection_id: str) -> None:
        self._local.pop(connection_id, None)

        pipe = self._redis.pipeline()
        pipe.delete(f"ws:conn:{connection_id}")
        pipe.srem(f"ws:user:{user_id}", connection_id)
        await pipe.execute()

        # User goes offline only when their LAST device disconnects
        remaining = await self._redis.scard(f"ws:user:{user_id}")
        if remaining == 0:
            await self._redis.srem("ws:online", str(user_id))

    async def online_count(self) -> int:
        return await self._redis.scard("ws:online")

    async def is_online(self, user_id: UUID) -> bool:
        return bool(await self._redis.sismember("ws:online", str(user_id)))

    async def send_local(self, connection_id: str, payload: dict) -> bool:
        ws = self._local.get(connection_id)
        if ws is None:
            return False
        await ws.send_json(payload)
        return True

    async def listen_ocr_alerts(self) -> None:
        """Listen for OCR alerts on Redis channel and broadcast to user's WS connections."""
        pubsub = self._redis.pubsub()
        await pubsub.subscribe("ocr:alerts")
        try:
            async for message in pubsub.listen():
                if message["type"] != "message":
                    continue
                data = message["data"]
                try:
                    payload = json.loads(data)
                    file_id = payload.get("file_id")
                    user_id = payload.get("user_id")
                    keyword = payload.get("keyword")
                    if not (file_id and user_id and keyword):
                        continue
                    ws_payload = {"type": "ocr_alert", "file_id": file_id, "keyword": keyword}
                    conns = await self._redis.smembers(f"ws:user:{user_id}")
                    for conn_id in conns:
                        await self.send_local(conn_id, ws_payload)
                except Exception as e:
                    logger.error(f"Error processing OCR alert: {e}")
        finally:
            await pubsub.unsubscribe("ocr:alerts")
            await pubsub.aclose()

    async def broadcast_typing(self, chat_id: UUID, user_id: UUID, is_typing: bool) -> None:
        """Broadcast typing indicator to other participants in the chat."""
        from app.models import Group, GroupMember
        from app.core.database import AsyncSessionLocal

        async with AsyncSessionLocal() as db:
            # First, try as group ID
            group = await db.scalar(select(Group).where(Group.id == chat_id))
            participant_ids = []
            if group is not None:
                # Get all group members except current user
                result = await db.execute(
                    select(GroupMember.user_id).where(
                        GroupMember.group_id == chat_id,
                        GroupMember.user_id != user_id,
                    )
                )
                participant_ids = [row[0] for row in result]
            else:
                # treat as direct message with the other user
                other_user_id = chat_id
                # Verify that there is a direct message (or at least that a direct chat exists)
                from app.models import Message
                exists = await db.scalar(
                    select(Message.id).where(
                        ((Message.sender_id == user_id) & (Message.recipient_id == other_user_id)) |
                        ((Message.sender_id == other_user_id) & (Message.recipient_id == user_id)),
                        Message.group_id.is_(None),
                    ).limit(1)
                )
                if exists is None:
                    # No direct chat; nothing to broadcast
                    return
                participant_ids = [other_user_id]

            typing_payload = {
                "type": "typing_start" if is_typing else "typing_stop",
                "from": str(user_id),
            }
            import json
            for pid in participant_ids:
                await self._redis.publish(
                    f"chan:user:{pid}",
                    json.dumps(typing_payload),
                )

    async def broadcast_delivered(self, chat_id: UUID, message_id: UUID, sender_id: UUID) -> None:
        """Broadcast delivered event to the sender (as per spec)."""
        payload = {
            "type": "delivered",
            "message_id": str(message_id),
        }
        import json
        await self._redis.publish(
            f"chan:user:{sender_id}",
            json.dumps(payload),
        )

    async def broadcast_read(self, chat_id: UUID, message_id: UUID, reader_id: UUID) -> None:
        """Broadcast read event to group members (as per spec)."""
        from app.models import Group, GroupMember
        from app.core.database import AsyncSessionLocal

        async with AsyncSessionLocal() as db:
            group = await db.scalar(select(Group).where(Group.id == chat_id))
            participant_ids = []
            if group is not None:
                # Get all group members (including reader? we'll include all)
                result = await db.execute(
                    select(GroupMember.user_id).where(
                        GroupMember.group_id == chat_id,
                    )
                )
                participant_ids = [row[0] for row in result]
            else:
                # Direct chat: the other user is the only participant (the sender)
                # Find the other user
                from app.models import Message
                msg = await db.scalar(select(Message).where(Message.id == message_id))
                if msg is None:
                    return
                other_user_id = msg.sender_id if msg.recipient_id == reader_id else msg.recipient_id
                participant_ids = [other_user_id]

            payload = {
                "type": "read",
                "message_id": str(message_id),
            }
            import json
            for pid in participant_ids:
                await self._redis.publish(
                    f"chan:user:{pid}",
                    json.dumps(payload),
                )


# Global instance
connection_manager = ConnectionManager(redis_client)