from __future__ import annotations

import base64
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Path, status
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import get_db
from app.models import OneTimePreKey, User, UserKeyBundle

router = APIRouter(tags=["keys"])

# A Curve25519 public key is 32 bytes; libsignal prefixes a 1-byte type tag,
# so 33 bytes on the wire. Signatures are 64 bytes. Bounding these stops a
# client from using the key directory as free storage, and rejects obviously
# malformed material early.
_MAX_KEY_BYTES = 64
_MAX_SIG_BYTES = 128
_MAX_PREKEYS_PER_UPLOAD = 100
_MAX_PREKEYS_STORED = 500


def _validate_b64(value: str, *, max_bytes: int, field: str) -> str:
    try:
        raw = base64.b64decode(value, validate=True)
    except Exception:
        raise ValueError(f"{field} must be valid base64")
    if not raw:
        raise ValueError(f"{field} must not be empty")
    if len(raw) > max_bytes:
        raise ValueError(f"{field} exceeds {max_bytes} bytes")
    return value


class OneTimePreKeyIn(BaseModel):
    key_id: int = Field(..., ge=0, le=0xFFFFFF)
    public_key: str

    @field_validator("public_key")
    @classmethod
    def _check(cls, v: str) -> str:
        return _validate_b64(v, max_bytes=_MAX_KEY_BYTES, field="public_key")


class KeyBundleUpload(BaseModel):
    """Published once per install, and on signed-pre-key rotation.

    Only public material. If a field name here ever suggests a private key,
    something has gone wrong — see the contract on models/device_key.py.
    """

    registration_id: int = Field(..., ge=0, le=0x3FFF)
    identity_key: str
    signed_prekey_id: int = Field(..., ge=0, le=0xFFFFFF)
    signed_prekey_public: str
    signed_prekey_signature: str
    one_time_prekeys: list[OneTimePreKeyIn] = Field(default_factory=list)

    @field_validator("identity_key", "signed_prekey_public")
    @classmethod
    def _check_key(cls, v: str) -> str:
        return _validate_b64(v, max_bytes=_MAX_KEY_BYTES, field="key")

    @field_validator("signed_prekey_signature")
    @classmethod
    def _check_sig(cls, v: str) -> str:
        return _validate_b64(v, max_bytes=_MAX_SIG_BYTES, field="signature")

    @field_validator("one_time_prekeys")
    @classmethod
    def _check_prekeys(cls, v: list[OneTimePreKeyIn]) -> list[OneTimePreKeyIn]:
        if len(v) > _MAX_PREKEYS_PER_UPLOAD:
            raise ValueError(f"at most {_MAX_PREKEYS_PER_UPLOAD} pre-keys per request")
        if len({k.key_id for k in v}) != len(v):
            raise ValueError("duplicate key_id in one_time_prekeys")
        return v


class PreKeysUpload(BaseModel):
    one_time_prekeys: list[OneTimePreKeyIn]

    @field_validator("one_time_prekeys")
    @classmethod
    def _check(cls, v: list[OneTimePreKeyIn]) -> list[OneTimePreKeyIn]:
        if not v:
            raise ValueError("one_time_prekeys must not be empty")
        if len(v) > _MAX_PREKEYS_PER_UPLOAD:
            raise ValueError(f"at most {_MAX_PREKEYS_PER_UPLOAD} pre-keys per request")
        if len({k.key_id for k in v}) != len(v):
            raise ValueError("duplicate key_id in one_time_prekeys")
        return v


class PreKeyBundleOut(BaseModel):
    """What a sender needs to open a session (X3DH).

    one_time_prekey may be null: pre-keys run out if the owner has been offline
    and has not replenished. libsignal handles a bundle without one — the
    session is still secure, with slightly weaker forward secrecy for the very
    first message. Failing the send instead would be worse.
    """

    user_id: UUID
    registration_id: int
    identity_key: str
    signed_prekey_id: int
    signed_prekey_public: str
    signed_prekey_signature: str
    one_time_prekey_id: int | None = None
    one_time_prekey: str | None = None


class PreKeyCountOut(BaseModel):
    remaining: int


@router.post("/keys/bundle", status_code=status.HTTP_204_NO_CONTENT, response_model=None)
async def publish_key_bundle(
    body: KeyBundleUpload,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> None:
    """Publish (or replace) this user's public key bundle.

    Replacing the identity key is a legitimate operation (reinstall, key reset)
    but it invalidates every existing session, so stale one-time pre-keys signed
    under the old identity are dropped in the same transaction.
    """
    existing = await db.scalar(
        select(UserKeyBundle).where(UserKeyBundle.user_id == current_user.id)
    )

    identity_changed = existing is not None and existing.identity_key != body.identity_key

    if existing is None:
        existing = UserKeyBundle(user_id=current_user.id)
        db.add(existing)

    existing.registration_id = body.registration_id
    existing.identity_key = body.identity_key
    existing.signed_prekey_id = body.signed_prekey_id
    existing.signed_prekey_public = body.signed_prekey_public
    existing.signed_prekey_signature = body.signed_prekey_signature

    if identity_changed:
        await db.execute(
            delete(OneTimePreKey).where(OneTimePreKey.user_id == current_user.id)
        )

    for pk in body.one_time_prekeys:
        db.add(
            OneTimePreKey(
                user_id=current_user.id,
                key_id=pk.key_id,
                public_key=pk.public_key,
            )
        )

    await db.commit()


@router.post("/keys/prekeys", status_code=status.HTTP_204_NO_CONTENT, response_model=None)
async def replenish_prekeys(
    body: PreKeysUpload,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> None:
    """Top up one-time pre-keys. The client calls this when its count runs low."""
    bundle = await db.scalar(
        select(UserKeyBundle).where(UserKeyBundle.user_id == current_user.id)
    )
    if bundle is None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="publish a key bundle before uploading pre-keys",
        )

    current = await db.scalar(
        select(func.count())
        .select_from(OneTimePreKey)
        .where(OneTimePreKey.user_id == current_user.id)
    ) or 0
    if current + len(body.one_time_prekeys) > _MAX_PREKEYS_STORED:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"pre-key store full (max {_MAX_PREKEYS_STORED})",
        )

    existing_ids = set(
        (
            await db.scalars(
                select(OneTimePreKey.key_id).where(
                    OneTimePreKey.user_id == current_user.id
                )
            )
        ).all()
    )
    for pk in body.one_time_prekeys:
        # Silently skipping a replayed key_id is safer than erroring: a client
        # retrying after a dropped response must not be pushed into a state
        # where it can never replenish.
        if pk.key_id in existing_ids:
            continue
        db.add(
            OneTimePreKey(
                user_id=current_user.id,
                key_id=pk.key_id,
                public_key=pk.public_key,
            )
        )

    await db.commit()


@router.get("/keys/prekeys/count", response_model=PreKeyCountOut)
async def my_prekey_count(
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> PreKeyCountOut:
    remaining = await db.scalar(
        select(func.count())
        .select_from(OneTimePreKey)
        .where(OneTimePreKey.user_id == current_user.id)
    ) or 0
    return PreKeyCountOut(remaining=remaining)


@router.get("/keys/bundle/{user_id}", response_model=PreKeyBundleOut)
async def fetch_key_bundle(
    user_id: UUID = Path(...),
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> PreKeyBundleOut:
    """Fetch a peer's bundle to open a session, consuming one one-time pre-key.

    The caller MUST verify signed_prekey_signature against identity_key before
    using this bundle. libsignal's processPreKeyBundle does that automatically;
    a hand-rolled client that skips it is trusting the server not to perform a
    man-in-the-middle attack, which is exactly the trust E2EE exists to remove.
    """
    bundle = await db.scalar(
        select(UserKeyBundle).where(UserKeyBundle.user_id == user_id)
    )
    if bundle is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="user has not published encryption keys",
        )

    # Claim one pre-key atomically. Two senders racing here must not receive the
    # same key, so the delete itself is the claim — RETURNING tells us whether
    # this request won. A plain SELECT-then-DELETE would hand the same pre-key
    # to both under concurrency.
    claimed = (
        await db.execute(
            delete(OneTimePreKey)
            .where(
                OneTimePreKey.id.in_(
                    select(OneTimePreKey.id)
                    .where(OneTimePreKey.user_id == user_id)
                    .order_by(OneTimePreKey.id)
                    .limit(1)
                    .with_for_update(skip_locked=True)
                )
            )
            .returning(OneTimePreKey.key_id, OneTimePreKey.public_key)
        )
    ).first()
    await db.commit()

    return PreKeyBundleOut(
        user_id=user_id,
        registration_id=bundle.registration_id,
        identity_key=bundle.identity_key,
        signed_prekey_id=bundle.signed_prekey_id,
        signed_prekey_public=bundle.signed_prekey_public,
        signed_prekey_signature=bundle.signed_prekey_signature,
        one_time_prekey_id=claimed[0] if claimed else None,
        one_time_prekey=claimed[1] if claimed else None,
    )
