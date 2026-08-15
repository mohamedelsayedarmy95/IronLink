from __future__ import annotations

import asyncio
import json
from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Query, WebSocket, WebSocketDisconnect, status
from sqlalchemy import select

from app.core.database import AsyncSessionLocal
from app.core.redis import redis_pubsub, redis_sessions
from app.models import User
from app.services import group_message_service, message_service, push_service
from app.services.message_service import UnsendDenied
from app.services.ws_manager import ConnectionManager

router = APIRouter(tags=["websocket"])

manager = ConnectionManager(redis_sessions)


BROADCAST_CHANNEL = "chan:broadcast"


def user_channel(user_id: UUID | str) -> str:
    return f"chan:user:{user_id}"


async def publish(user_id: UUID | str, payload: dict) -> None:
    await redis_pubsub.publish(user_channel(user_id), json.dumps(payload, default=str))


async def publish_broadcast(payload: dict) -> None:
    """Admin urgent broadcast — one publish, every connected device receives it."""
    await redis_pubsub.publish(BROADCAST_CHANNEL, json.dumps(payload, default=str))


# Fable5-Enhancement: every connection runs a private Redis Pub/Sub listener on
# the user's channel. This is what makes the engine horizontally scalable: the
# sender's API replica publishes once; whichever replica holds the recipient's
# socket relays it. Multi-device comes free — every device of the user is
# subscribed to the same channel and receives the frame simultaneously.
async def _relay_loop(websocket: WebSocket, user_id: UUID, connection_id: str) -> None:
    pubsub = redis_pubsub.pubsub()
    await pubsub.subscribe(user_channel(user_id), BROADCAST_CHANNEL)
    try:
        async for item in pubsub.listen():
            if item["type"] != "message":
                continue
            frame = json.loads(item["data"])
            # Targeted force-disconnect for remote device kick
            if frame.get("type") == "session_revoked":
                await websocket.send_json(frame)
                continue
            await websocket.send_json(frame)
    except Exception:
        pass
    finally:
        await pubsub.unsubscribe(user_channel(user_id))
        await pubsub.aclose()


@router.websocket("/ws/chat")
async def chat_socket(
    websocket: WebSocket,
    ticket: str = Query(..., min_length=16, max_length=64),
) -> None:
    # One-time ticket auth (see auth.py — JWT never travels in the query string)
    user_id_raw = await redis_sessions.getdel(f"ws:ticket:{ticket}")
    if user_id_raw is None:
        await websocket.close(code=status.WS_1008_POLICY_VIOLATION)
        return

    user_id = UUID(user_id_raw)
    await websocket.accept()
    connection_id = await manager.register(user_id, websocket)
    relay_task = asyncio.create_task(_relay_loop(websocket, user_id, connection_id))

    try:
        await websocket.send_json({
            "type": "welcome",
            "connection_id": connection_id,
            "online_users": await manager.online_count(),
            "server_time": datetime.now(timezone.utc).isoformat(),
        })

        while True:
            raw = await websocket.receive_text()
            try:
                frame = json.loads(raw)
            except json.JSONDecodeError:
                await websocket.send_json({"type": "error", "detail": "invalid JSON frame"})
                continue
            await _handle_frame(websocket, user_id, connection_id, frame)

    except WebSocketDisconnect:
        pass
    finally:
        relay_task.cancel()
        await manager.unregister(user_id, connection_id)


async def _handle_frame(
    websocket: WebSocket, user_id: UUID, connection_id: str, frame: dict
) -> None:
    frame_type = frame.get("type")

    # ── Heartbeat / presence ──────────────────────────────────────────────────
    if frame_type == "ping":
        await manager.heartbeat(connection_id)
        await websocket.send_json({"type": "pong"})
        return

    if frame_type == "presence":
        await websocket.send_json({
            "type": "presence",
            "online_users": await manager.online_count(),
        })
        return

    # ── Typing indicators (ephemeral — never persisted) ───────────────────────
    if frame_type in ("typing_start", "typing_stop"):
        to = _uuid_or_none(frame.get("to"))
        if to is None:
            return
        await publish(to, {
            "type": frame_type,
            "from": str(user_id),
        })
        return

    # ── Outbound content messages ─────────────────────────────────────────────
    if frame_type in ("text", "image", "file"):
        to = _uuid_or_none(frame.get("to"))
        if to is None:
            await websocket.send_json({"type": "error", "detail": "missing/invalid 'to'"})
            return

        async with AsyncSessionLocal() as db:
            try:
                msg = await message_service.save_message(
                    db,
                    sender_id=user_id,
                    recipient_id=to,
                    group_id=None,
                    message_type=frame_type,
                    content_ciphertext=frame.get("content"),
                    media_object_key=frame.get("media_key"),
                    media_mime_type=frame.get("media_mime"),
                    destruct_after_seconds=frame.get("destruct_after"),
                )
            except message_service.BlockedDelivery:
                # Reported as an undeliverable message rather than as a block.
                # Saying "you are blocked" would tell the sender something the
                # recipient chose not to disclose, and turns a quiet boundary
                # into a confrontation.
                await websocket.send_json({
                    "type": "error",
                    "detail": "This message could not be delivered.",
                })
                return
            # Offline recipient → FCM push with sender name + short preview.
            # Checked while the session is open so we read fcm_token in one trip.
            recipient_offline = not await manager.is_online(to)
            if recipient_offline:
                recipient = await db.scalar(select(User).where(User.id == to))
                sender = await db.scalar(select(User).where(User.id == user_id))
                if recipient is not None and recipient.fcm_token and sender is not None:
                    preview = (
                        frame.get("content") or f"[{frame_type}]"
                    )
                    await push_service.send_message_push(
                        recipient.fcm_token,
                        sender_name=sender.full_name,
                        preview=preview,
                        peer_id=str(user_id),
                    )

        # 1. Ack the sender: server timestamp + canonical id replaces client_ref
        await websocket.send_json({
            "type": "ack",
            "client_ref": frame.get("client_ref"),
            "message_id": str(msg.id),
            "created_at": msg.created_at.isoformat(),
        })

        # 2. Fan out to every one of the recipient's devices via Pub/Sub
        await publish(to, {
            "type": "message",
            "message_id": str(msg.id),
            "message_type": frame_type,
            "from": str(user_id),
            "content": frame.get("content"),
            "media_key": frame.get("media_key"),
            "media_mime": frame.get("media_mime"),
            "created_at": msg.created_at.isoformat(),
        })
        return

    # ── Group messages ────────────────────────────────────────────────────────
    if frame_type in ("group_text", "group_image", "group_file", "group_voice"):
        group_id = _uuid_or_none(frame.get("group"))
        if group_id is None:
            await websocket.send_json(
                {"type": "error", "detail": "missing/invalid 'group'"}
            )
            return

        async with AsyncSessionLocal() as db:
            try:
                msg = await group_message_service.save_group_message(
                    db,
                    group_id=group_id,
                    sender_id=user_id,
                    message_type=frame_type.removeprefix("group_"),
                    content_ciphertext=frame.get("content"),
                    media_object_key=frame.get("media_key"),
                    media_mime_type=frame.get("media_mime"),
                    destruct_after_seconds=frame.get("destruct_after"),
                )
            except group_message_service.NotAMember:
                await websocket.send_json(
                    {"type": "error", "detail": "not a member of that group"}
                )
                return
            except group_message_service.PostingNotAllowed:
                await websocket.send_json(
                    {"type": "error", "detail": "only admins can post here"}
                )
                return

            recipients = await group_message_service.member_ids(db, group_id)

        await websocket.send_json({
            "type": "ack",
            "client_ref": frame.get("client_ref"),
            "message_id": str(msg.id),
            "created_at": msg.created_at.isoformat(),
        })

        # One publish per member. The ciphertext is identical for all of
        # them — a sender key is encrypted once, not per recipient, which is
        # the whole reason groups do not cost O(members) encryptions.
        event = {
            "type": "group_message",
            "group": str(group_id),
            "message_id": str(msg.id),
            "message_type": msg.message_type,
            "from": str(user_id),
            "content": frame.get("content"),
            "media_key": frame.get("media_key"),
            "media_mime": frame.get("media_mime"),
            "created_at": msg.created_at.isoformat(),
        }
        for member_id in recipients:
            if member_id == user_id:
                continue  # the sender already has it
            await publish(member_id, event)
        return

    # ── Sender-key distribution ───────────────────────────────────────────────
    #
    # Key material, pairwise encrypted by the sender for one member. Persisted
    # so a member who is offline still receives it, and excluded from history
    # so it never surfaces as a message.
    if frame_type == "skdm":
        to = _uuid_or_none(frame.get("to"))
        group_id = _uuid_or_none(frame.get("group"))
        if to is None or group_id is None:
            await websocket.send_json(
                {"type": "error", "detail": "skdm needs 'to' and 'group'"}
            )
            return

        async with AsyncSessionLocal() as db:
            try:
                await group_message_service.assert_member(db, group_id, user_id)
                # The recipient has to be a member too, or this becomes a way
                # to push arbitrary payloads at any user.
                await group_message_service.assert_member(db, group_id, to)
            except group_message_service.NotAMember:
                await websocket.send_json(
                    {"type": "error", "detail": "not a member of that group"}
                )
                return

            msg = await message_service.save_message(
                db,
                sender_id=user_id,
                recipient_id=to,
                group_id=None,
                message_type=group_message_service.SKDM_MESSAGE_TYPE,
                content_ciphertext=frame.get("content"),
                # See save_message: a block must not withhold the key to
                # messages that are delivered regardless.
                enforce_blocks=False,
            )

        await publish(to, {
            "type": "skdm",
            "group": str(group_id),
            "from": str(user_id),
            "content": frame.get("content"),
            "message_id": str(msg.id),
            "created_at": msg.created_at.isoformat(),
        })
        await websocket.send_json({
            "type": "ack",
            "client_ref": frame.get("client_ref"),
            "message_id": str(msg.id),
            "created_at": msg.created_at.isoformat(),
        })
        return

    # ── Delivery / read receipts ──────────────────────────────────────────────
    if frame_type in ("message_delivered", "message_read"):
        message_id = _uuid_or_none(frame.get("message_id"))
        if message_id is None:
            return
        async with AsyncSessionLocal() as db:
            if frame_type == "message_delivered":
                msg = await message_service.mark_delivered(db, message_id, user_id)
            else:
                msg = await message_service.mark_read(db, message_id, user_id)
        if msg is not None and msg.sender_id is not None:
            await publish(msg.sender_id, {
                "type": "receipt",
                "message_id": str(message_id),
                "status": "read" if frame_type == "message_read" else "delivered",
            })
        return

    # ── Unsend (delete for everyone, 5-minute window) ─────────────────────────
    if frame_type == "unsend":
        message_id = _uuid_or_none(frame.get("message_id"))
        if message_id is None:
            return
        async with AsyncSessionLocal() as db:
            try:
                msg = await message_service.unsend_message(db, message_id, user_id)
            except UnsendDenied as e:
                await websocket.send_json({"type": "error", "detail": str(e)})
                return
        event = {"type": "unsend", "message_id": str(message_id)}
        # Both parties (all devices of each) drop the message locally
        if msg.recipient_id is not None:
            await publish(msg.recipient_id, event)
        await publish(user_id, event)
        return

    await websocket.send_json({
        "type": "error",
        "detail": f"unsupported frame type: {frame_type}",
    })


def _uuid_or_none(value: object) -> UUID | None:
    try:
        return UUID(str(value))
    except (ValueError, TypeError):
        return None
