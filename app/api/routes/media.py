from __future__ import annotations

import io
import json
import logging
import secrets
import tempfile
import os
from datetime import timedelta

from fastapi import APIRouter, Depends, HTTPException, Request, status, BackgroundTasks
from pydantic import BaseModel, Field

from app.api.deps import get_current_user
from app.config import settings
from app.core.redis import redis_sessions
from app.models import User
from app.services.storage_service import (
    ALLOWED_MIME_TYPES,
    MAX_UPLOAD_BYTES,
    StorageNotConfigured,
    StorageService,
)
from app.ocr import extract_text, load_user_keywords, contains_keywords, normalize_text
from app.redis import publish_ocr_alert, set_alert_flag
from app.services import push_service

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/media", tags=["media"])


def _storage_unavailable(exc: StorageNotConfigured) -> HTTPException:
    """503, not 500 — the request is well-formed, the backend is unprovisioned."""
    return HTTPException(status.HTTP_503_SERVICE_UNAVAILABLE, str(exc))

CHUNK_SIZE = 5 * 1024 * 1024          # 5 MiB per chunk
UPLOAD_STATE_TTL = 24 * 3600          # incomplete uploads survive 24h for resume
PRESIGN_VIEW_TTL = 300                # 5-minute view links, per spec

_storage = StorageService()


# ── Schemas ────────────────────────────────────────────────────────────────────

class UploadInitIn(BaseModel):
    filename: str = Field(..., max_length=255)
    mime_type: str
    total_size: int = Field(..., gt=0, le=MAX_UPLOAD_BYTES)


class UploadInitOut(BaseModel):
    upload_id: str
    chunk_size: int
    total_chunks: int
    received_chunks: list[int] = []


class UploadStatusOut(BaseModel):
    upload_id: str
    total_chunks: int
    received_chunks: list[int]
    missing_chunks: list[int]
    complete: bool


class UploadCompleteOut(BaseModel):
    media_key: str
    mime_type: str
    size_bytes: int
    thumbnail_key: str | None = None


class PresignedOut(BaseModel):
    url: str
    expires_in: int


# ── State helpers (Redis) ──────────────────────────────────────────────────────

def _state_key(upload_id: str) -> str:
    return f"upload:{upload_id}"


def _chunks_key(upload_id: str) -> str:
    return f"upload:chunks:{upload_id}"


async def _load_state(upload_id: str, user_id: str) -> dict:
    raw = await redis_sessions.get(_state_key(upload_id))
    if raw is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "upload not found or expired")
    state = json.loads(raw)
    if state["user_id"] != user_id:
        # Same 404 as unknown id — no oracle for other users' upload ids
        raise HTTPException(status.HTTP_404_NOT_FOUND, "upload not found or expired")
    return state


# ── Endpoints ──────────────────────────────────────────────────────────────────

@router.post("/upload/init", response_model=UploadInitOut)
async def upload_init(
    body: UploadInitIn,
    user: User = Depends(get_current_user),
) -> UploadInitOut:
    """Start (or implicitly resume — see GET status) a chunked upload.

    Fable5-Enhancement: chunks go STRAIGHT into MinIO as staged objects
    (staging/{upload_id}/{n}) instead of API-server local disk. Any replica can
    accept any chunk — resumable uploads work behind a load balancer with zero
    sticky-session configuration, and a crashed API pod loses nothing.
    """
    if body.mime_type not in ALLOWED_MIME_TYPES:
        raise HTTPException(
            status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
            f"MIME type not allowed: {body.mime_type}",
        )

    upload_id = secrets.token_urlsafe(24)
    total_chunks = (body.total_size + CHUNK_SIZE - 1) // CHUNK_SIZE

    await redis_sessions.set(
        _state_key(upload_id),
        json.dumps({
            "user_id": str(user.id),
            "filename": body.filename,
            "mime_type": body.mime_type,
            "total_size": body.total_size,
            "total_chunks": total_chunks,
        }),
        ex=UPLOAD_STATE_TTL,
    )
    return UploadInitOut(
        upload_id=upload_id, chunk_size=CHUNK_SIZE, total_chunks=total_chunks
    )


@router.put("/upload/{upload_id}/chunk/{chunk_index}", status_code=status.HTTP_204_NO_CONTENT)
async def upload_chunk(
    upload_id: str,
    chunk_index: int,
    request: Request,
    user: User = Depends(get_current_user),
) -> None:
    state = await _load_state(upload_id, str(user.id))
    if not 0 <= chunk_index < state["total_chunks"]:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "chunk index out of range")

    data = await request.body()
    if len(data) > CHUNK_SIZE:
        raise HTTPException(status.HTTP_413_REQUEST_ENTITY_TOO_LARGE, "chunk too large")
    if not data:
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "empty chunk")

    try:
        _storage.put_staging_chunk(upload_id, chunk_index, data)
    except StorageNotConfigured as exc:
        raise _storage_unavailable(exc) from exc
    await redis_sessions.sadd(_chunks_key(upload_id), str(chunk_index))
    await redis_sessions.expire(_chunks_key(upload_id), UPLOAD_STATE_TTL)


@router.get("/upload/{upload_id}", response_model=UploadStatusOut)
async def upload_status(
    upload_id: str,
    user: User = Depends(get_current_user),
) -> UploadStatusOut:
    """Resume point: the client asks which chunks the server already has."""
    state = await _load_state(upload_id, str(user.id))
    received = sorted(
        int(i) for i in await redis_sessions.smembers(_chunks_key(upload_id))
    )
    missing = [i for i in range(state["total_chunks"]) if i not in set(received)]
    return UploadStatusOut(
        upload_id=upload_id,
        total_chunks=state["total_chunks"],
        received_chunks=received,
        missing_chunks=missing,
        complete=not missing,
    )


@router.post("/upload/{upload_id}/complete", response_model=UploadCompleteOut)
async def upload_complete(
    upload_id: str,
    user: User = Depends(get_current_user),
    background_tasks: BackgroundTasks = None,
) -> UploadCompleteOut:
    state = await _load_state(upload_id, str(user.id))
    received = {
        int(i) for i in await redis_sessions.smembers(_chunks_key(upload_id))
    }
    missing = [i for i in range(state["total_chunks"]) if i not in received]
    if missing:
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            f"upload incomplete — missing chunks: {missing[:20]}",
        )

    try:
        assembled = _storage.assemble_staging(upload_id, state["total_chunks"])
    except StorageNotConfigured as exc:
        raise _storage_unavailable(exc) from exc
    if len(assembled) != state["total_size"]:
        _storage.delete_staging(upload_id, state["total_chunks"])
        raise HTTPException(status.HTTP_400_BAD_REQUEST, "size mismatch — re-upload")

    mime = state["mime_type"]
    thumbnail_key: str | None = None

    if mime.startswith("image/"):
        assembled, thumb = _process_image(assembled, mime)
        if thumb is not None:
            thumbnail_key = _storage.put_object(
                settings.S3_BUCKET_ATTACHMENTS, thumb, "image/jpeg", suffix="_thumb.jpg"
            )
    elif mime.startswith("video/"):
        # Fable5-Enhancement: video thumbnailing needs ffmpeg, which does not
        # belong inside the API container (CPU spikes would starve the event
        # loop). Production path: a dedicated thumbnailer worker container
        # consuming a Redis queue. Until then videos ship without thumbnails
        # rather than blocking the upload.
        thumbnail_key = None

    media_key = _storage.put_object(
        settings.S3_BUCKET_ATTACHMENTS, assembled, mime,
        suffix=_ext_for(mime),
    )
    _storage.delete_staging(upload_id, state["total_chunks"])
    await redis_sessions.delete(_state_key(upload_id), _chunks_key(upload_id))

    # Schedule OCR processing in the background (non-blocking)
    if background_tasks is not None:
        background_tasks.add_task(
            _process_ocr,
            file_bytes=assembled,
            mime_type=mime,
            user_id=state["user_id"],
            media_key=media_key,
        )

    return UploadCompleteOut(
        media_key=media_key,
        mime_type=mime,
        size_bytes=len(assembled),
        thumbnail_key=thumbnail_key,
    )


@router.get("/{media_key}/url", response_model=PresignedOut)
async def presigned_view_url(
    media_key: str,
    user: User = Depends(get_current_user),
) -> PresignedOut:
    """5-minute pre-signed view link, generated fresh on each open."""
    try:
        url = _storage.presign_download_ttl(
            settings.S3_BUCKET_ATTACHMENTS, media_key, PRESIGN_VIEW_TTL
        )
    except StorageNotConfigured as exc:
        raise _storage_unavailable(exc) from exc
    return PresignedOut(url=url, expires_in=PRESIGN_VIEW_TTL)


# ── Image processing ────────────────────────────────────────────────────────────

def _process_image(data: bytes, mime: str) -> tuple[bytes, bytes | None]:
    """Recompress large images + build a thumbnail.

    Quality 85 JPEG / effort-6 WebP is visually lossless for print at the
    resolutions phones produce; anything already small passes through untouched.
    """
    try:
        from PIL import Image
    except ImportError:
        return data, None   # Pillow not installed — store original, no thumb

    try:
        img = Image.open(io.BytesIO(data))
        img.load()
    except Exception:
        return data, None

    out = data
    if len(data) > 512 * 1024:  # only recompress when it actually pays off
        buf = io.BytesIO()
        rgb = img.convert("RGB") if img.mode not in ("RGB", "L") else img
        rgb.save(buf, format="JPEG", quality=85, optimize=True)
        if buf.tell() < len(data):
            out = buf.getvalue()

    thumb_img = img.copy()
    thumb_img.thumbnail((320, 320))
    tbuf = io.BytesIO()
    thumb_img.convert("RGB").save(tbuf, format="JPEG", quality=70)
    return out, tbuf.getvalue()


def _ext_for(mime: str) -> str:
    return ALLOWED_MIME_TYPES.get(mime, "")


# ── OCR background task ─────────────────────────────────────────────────────────

async def _process_ocr(
    file_bytes: bytes,
    mime_type: str,
    user_id: str,
    media_key: str,
) -> None:
    """
    Background task to run OCR on an uploaded file and trigger alerts if keywords match.
    """
    # Write to a temporary file
    ext = _ext_for(mime_type)
    if not ext:
        # Fallback extension based on MIME type
        if mime_type == 'text/plain':
            ext = '.txt'
        elif mime_type == 'text/csv':
            ext = '.csv'
        elif mime_type.startswith('image/'):
            ext = '.bin'  # Pillow/Tesseract can handle raw bytes without extension? we'll use .bin
        else:
            ext = '.bin'
    try:
        with tempfile.NamedTemporaryFile(delete=False, suffix=ext) as tmp:
            tmp.write(file_bytes)
            temp_path = tmp.name
    except Exception as e:
        logger.error(f"Failed to create temp file for OCR: {e}")
        return

    try:
        # Extract text
        text = extract_text(temp_path, mime_type)
        if not text:
            return

        # Load user keywords
        keywords = load_user_keywords(user_id)
        if not keywords:
            return

        # Check for keyword match and get the matched keyword
        normalized = normalize_text(text)
        matched_kw = None
        for kw in keywords:
            if kw in normalized:
                matched_kw = kw
                break

        if matched_kw:
            # Publish alert (live WS ticker) and set flag
            publish_ocr_alert(media_key, user_id, matched_kw)
            set_alert_flag(media_key)
            # FCM fallback for backgrounded/killed apps not on the live WS
            await push_service.send_ocr_push(user_id, media_key, matched_kw)
    except Exception as e:
        logger.error(f"OCR background task failed for file {media_key}: {e}")
    finally:
        # Clean up temp file
        if os.path.exists(temp_path):
            try:
                os.unlink(temp_path)
            except Exception:
                pass