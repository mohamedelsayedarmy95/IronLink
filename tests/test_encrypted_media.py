"""Tests for encrypted attachment uploads.

The completion path assumes readable content: it re-compresses images, builds
thumbnails, and runs OCR. Every one of those is wrong for ciphertext — the
first two corrupt the object, and the third reads the user's attachments,
which is the thing end-to-end encryption is supposed to make impossible.
"""
from __future__ import annotations

import inspect

import pytest


def _complete_source() -> str:
    from app.api.routes import media

    return inspect.getsource(media.upload_complete)


# ── What the server must not do to an encrypted body ─────────────────────────

def test_encrypted_uploads_skip_image_reprocessing() -> None:
    """Re-compression rewrites the bytes. On ciphertext that is unrecoverable
    — the recipient's authentication check fails and the file is lost."""
    source = _complete_source()

    # The image branch must be reachable only when not encrypted.
    assert "if encrypted:" in source
    assert 'elif mime.startswith("image/"):' in source


def test_encrypted_uploads_never_reach_ocr() -> None:
    """Running text extraction over someone's attachments is precisely what
    the encryption promises does not happen."""
    source = _complete_source()
    assert "background_tasks is not None and not encrypted" in source


def test_unknown_encrypted_state_is_treated_as_encrypted() -> None:
    """For an upload in flight across the deploy the state has no flag.
    Assuming plaintext would hand ciphertext to the image processor and to
    OCR, so the default has to fall the other way."""
    source = _complete_source()
    assert 'state.get("encrypted", mime == ENCRYPTED_MIME_TYPE)' in source


# ── The declared type and the flag must agree ────────────────────────────────

def test_encrypted_flag_and_mime_must_match() -> None:
    from app.api.routes.media import upload_init

    source = inspect.getsource(upload_init)
    assert "body.encrypted != (body.mime_type == ENCRYPTED_MIME_TYPE)" in source


def test_octet_stream_alone_cannot_bypass_the_type_allowlist() -> None:
    """Otherwise any client could declare octet-stream and upload a file type
    the allow-list exists to reject."""
    from app.api.routes.media import upload_init

    source = inspect.getsource(upload_init)
    # The mismatch check rejects octet-stream when encrypted is False.
    assert "only encrypted uploads may use it" in source


def test_encrypted_mime_type_is_allowed_for_storage() -> None:
    """The allow-list is also what decides the stored object's extension, so
    a type the route accepts but storage rejects would fail at completion."""
    from app.services.storage_service import ALLOWED_MIME_TYPES, ENCRYPTED_MIME_TYPE

    assert ENCRYPTED_MIME_TYPE in ALLOWED_MIME_TYPES
    assert ALLOWED_MIME_TYPES[ENCRYPTED_MIME_TYPE] == ".bin"


def test_the_flag_is_persisted_with_the_upload() -> None:
    """Init and complete are different requests, possibly on different
    replicas. If the flag were not stored, completion could not know."""
    from app.api.routes.media import upload_init

    assert '"encrypted": body.encrypted' in inspect.getsource(upload_init)


# ── What the server still learns ─────────────────────────────────────────────

def test_size_limit_still_applies_to_encrypted_uploads() -> None:
    """Encryption does not exempt an upload from the bounds — otherwise it
    would be the obvious way to push a 5 GB object into storage."""
    from app.api.routes.media import UploadInitIn
    from app.services.storage_service import MAX_UPLOAD_BYTES

    field = UploadInitIn.model_fields["total_size"]
    limits = [getattr(m, "le", None) for m in field.metadata]
    assert MAX_UPLOAD_BYTES in limits


def test_client_and_server_agree_on_the_encrypted_mime_type() -> None:
    """These are two constants in two languages. If they drift, every
    encrypted upload is rejected at init with a 400."""
    import re
    from pathlib import Path

    dart = Path("frontend/lib/core/media_service.dart")
    if not dart.exists():
        pytest.skip("frontend not present")

    from app.services.storage_service import ENCRYPTED_MIME_TYPE

    source = dart.read_text(encoding="utf-8")
    match = re.search(r"encryptedMimeType\s*=\s*'([^']+)'", source)
    assert match is not None, "client no longer declares an encrypted MIME type"
    assert match.group(1) == ENCRYPTED_MIME_TYPE


# ── Integration checklist ────────────────────────────────────────────────────
#
# Needs live storage and Redis:
#   * an encrypted upload round-trips byte for byte through assemble + put
#   * completion of an encrypted upload returns thumbnail_key = None
#   * no OCR alert is emitted for an encrypted upload
#   * init rejects encrypted=True with mime_type="image/jpeg" (400)
#   * init rejects encrypted=False with mime_type="application/octet-stream"
