from __future__ import annotations

import io
from datetime import timedelta
from uuid import uuid4

from minio import Minio
from minio.error import S3Error

from app.config import settings

# MIME allow-list — reject anything not explicitly permitted
ALLOWED_MIME_TYPES: dict[str, str] = {
    "image/jpeg": ".jpg",
    "image/png": ".png",
    "image/webp": ".webp",
    "video/mp4": ".mp4",
    "audio/ogg": ".ogg",
    "audio/mpeg": ".mp3",
    "application/pdf": ".pdf",
}

MAX_UPLOAD_BYTES = 50 * 1024 * 1024  # matches nginx client_max_body_size


class StorageService:
    """MinIO wrapper enforcing short-lived pre-signed URLs and MIME allow-listing.

    All object access goes through pre-signed URLs that expire in
    MINIO_PRESIGN_EXPIRY_SECONDS (15 min) — no bucket is ever public.
    """

    def __init__(self) -> None:
        self._client = Minio(
            settings.MINIO_ENDPOINT,
            access_key=settings.MINIO_ROOT_USER,
            secret_key=settings.MINIO_ROOT_PASSWORD,
            secure=settings.MINIO_SECURE,
        )

    def ensure_buckets(self) -> None:
        """Idempotent bucket bootstrap — called once at application startup."""
        for bucket in (settings.MINIO_BUCKET_AVATARS, settings.MINIO_BUCKET_ATTACHMENTS):
            if not self._client.bucket_exists(bucket):
                self._client.make_bucket(bucket)

    def presign_upload(self, bucket: str, mime_type: str) -> tuple[str, str]:
        """Returns (object_key, upload_url). Raises ValueError on disallowed MIME."""
        ext = ALLOWED_MIME_TYPES.get(mime_type)
        if ext is None:
            raise ValueError(f"MIME type not allowed: {mime_type}")
        object_key = f"{uuid4().hex}{ext}"
        url = self._client.presigned_put_object(
            bucket,
            object_key,
            expires=timedelta(seconds=settings.MINIO_PRESIGN_EXPIRY_SECONDS),
        )
        return object_key, url

    def presign_download(self, bucket: str, object_key: str) -> str:
        return self._client.presigned_get_object(
            bucket,
            object_key,
            expires=timedelta(seconds=settings.MINIO_PRESIGN_EXPIRY_SECONDS),
        )

    def presign_download_ttl(self, bucket: str, object_key: str, ttl_seconds: int) -> str:
        return self._client.presigned_get_object(
            bucket, object_key, expires=timedelta(seconds=ttl_seconds)
        )

    def put_object(
        self, bucket: str, data: bytes, mime_type: str, *, suffix: str = ""
    ) -> str:
        """Stores bytes under a random key; returns the key."""
        object_key = f"{uuid4().hex}{suffix}"
        self._client.put_object(
            bucket, object_key, io.BytesIO(data), length=len(data),
            content_type=mime_type,
        )
        return object_key

    # ── Chunked-upload staging (media.py) ─────────────────────────────────────
    # Staged chunks live in the attachments bucket under staging/{upload_id}/{n}
    # so any API replica can write or read them — no local disk involved.

    def put_staging_chunk(self, upload_id: str, index: int, data: bytes) -> None:
        self._client.put_object(
            settings.MINIO_BUCKET_ATTACHMENTS,
            f"staging/{upload_id}/{index}",
            io.BytesIO(data),
            length=len(data),
            content_type="application/octet-stream",
        )

    def assemble_staging(self, upload_id: str, total_chunks: int) -> bytes:
        parts: list[bytes] = []
        for i in range(total_chunks):
            resp = self._client.get_object(
                settings.MINIO_BUCKET_ATTACHMENTS, f"staging/{upload_id}/{i}"
            )
            try:
                parts.append(resp.read())
            finally:
                resp.close()
                resp.release_conn()
        return b"".join(parts)

    def delete_staging(self, upload_id: str, total_chunks: int) -> None:
        for i in range(total_chunks):
            self.delete_object(
                settings.MINIO_BUCKET_ATTACHMENTS, f"staging/{upload_id}/{i}"
            )

    def delete_object(self, bucket: str, object_key: str) -> None:
        """Used by the self-destruct cleanup worker for media messages."""
        try:
            self._client.remove_object(bucket, object_key)
        except S3Error as exc:
            if exc.code != "NoSuchKey":
                raise
