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
    # Only legitimate for an end-to-end encrypted body, where the real type is
    # inside the envelope and the server is meant to learn nothing beyond the
    # length. The media route rejects it on any upload not marked encrypted,
    # so it cannot be used to smuggle a disallowed type past the check.
    "application/octet-stream": ".bin",
}

#: What an encrypted attachment declares itself as. Its real type travels
#: inside the end-to-end encrypted envelope instead.
ENCRYPTED_MIME_TYPE = "application/octet-stream"

MAX_UPLOAD_BYTES = 50 * 1024 * 1024  # matches nginx client_max_body_size


class StorageNotConfigured(RuntimeError):
    """Raised when a storage operation is attempted with no S3 credentials.

    Surfaced as 503 by the media routes rather than 500: the request is valid,
    the capability is simply not provisioned yet.
    """


class StorageService:
    """S3-compatible object storage, enforcing short-lived pre-signed URLs and
    MIME allow-listing.

    Backend-agnostic: the same code drives Cloudflare R2 in production and the
    local MinIO container in development, since both speak S3. The `minio`
    package is simply the S3 client here — it is not tied to a MinIO server,
    and using it avoids pulling boto3 (~15 MB) onto a 512 MB instance.

    All object access goes through pre-signed URLs that expire in
    S3_PRESIGN_EXPIRY_SECONDS (15 min) — no bucket is ever public. R2 buckets
    default to private, which is what this relies on: do NOT attach a public
    r2.dev domain to these buckets, or the expiry stops meaning anything.
    """

    def __init__(self) -> None:
        # Built lazily. This class is instantiated at import time in media.py
        # and self_destruct_worker.py, so constructing a client here would make
        # missing storage credentials an import-time crash — taking down auth,
        # chat, and every other route with it.
        self._client_instance: Minio | None = None

    @property
    def _client(self) -> Minio:
        if not settings.storage_configured:
            raise StorageNotConfigured(
                "Object storage is not configured — set S3_ENDPOINT, "
                "S3_ACCESS_KEY_ID and S3_SECRET_ACCESS_KEY. Media upload and "
                "download are unavailable until then; the rest of the API works."
            )
        if self._client_instance is None:
            self._client_instance = Minio(
                settings.S3_ENDPOINT,
                access_key=settings.S3_ACCESS_KEY_ID,
                secret_key=settings.S3_SECRET_ACCESS_KEY,
                secure=settings.S3_SECURE,
                # None lets the client resolve the region itself (MinIO); R2
                # needs the literal "auto" folded into the SigV4 scope.
                region=settings.S3_REGION or None,
            )
        return self._client_instance

    def ensure_buckets(self) -> None:
        """Idempotent bucket bootstrap — for local development only.

        Not called at startup. On R2 the API token is normally scoped to
        existing buckets and lacks CreateBucket, so invoking this in production
        raises AccessDenied; create the buckets in the Cloudflare dashboard.
        """
        for bucket in (settings.S3_BUCKET_AVATARS, settings.S3_BUCKET_ATTACHMENTS):
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
            expires=timedelta(seconds=settings.S3_PRESIGN_EXPIRY_SECONDS),
        )
        return object_key, url

    def presign_download(self, bucket: str, object_key: str) -> str:
        return self._client.presigned_get_object(
            bucket,
            object_key,
            expires=timedelta(seconds=settings.S3_PRESIGN_EXPIRY_SECONDS),
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
            settings.S3_BUCKET_ATTACHMENTS,
            f"staging/{upload_id}/{index}",
            io.BytesIO(data),
            length=len(data),
            content_type="application/octet-stream",
        )

    def assemble_staging(self, upload_id: str, total_chunks: int) -> bytes:
        parts: list[bytes] = []
        for i in range(total_chunks):
            resp = self._client.get_object(
                settings.S3_BUCKET_ATTACHMENTS, f"staging/{upload_id}/{i}"
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
                settings.S3_BUCKET_ATTACHMENTS, f"staging/{upload_id}/{i}"
            )

    def delete_object(self, bucket: str, object_key: str) -> None:
        """Used by the self-destruct cleanup worker for media messages."""
        try:
            self._client.remove_object(bucket, object_key)
        except S3Error as exc:
            if exc.code != "NoSuchKey":
                raise
