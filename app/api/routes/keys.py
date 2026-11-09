from __future__ import annotations

import base64
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Path, status
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import delete, func, select, text
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import get_db
from app.models import (
    ConsumedOneTimePreKey,
    OneTimePreKey,
    User,
    UserKeyBundle,
)

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


async def _lock_key_directory(db: AsyncSession, user_id: UUID) -> None:
    """Serialize publication, replenishment and claims for one user.

    `pg_advisory_xact_lock` is held until the request's transaction commits or
    rolls back. Using one lock for all three operations is what orders a claim
    against a concurrent bundle retry: the retry cannot insert a key while the
    claim is between its DELETE and its tombstone INSERT.
    """
    await db.execute(
        text("SELECT pg_advisory_xact_lock(hashtextextended(:user_id, 0))"),
        {"user_id": str(user_id)},
    )


def _conflict(key_id: int) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_409_CONFLICT,
        detail=(
            f"one-time pre-key id {key_id} is already registered with "
            "different material"
        ),
    )


async def _active_prekeys(db: AsyncSession, user_id: UUID) -> dict[int, str]:
    rows = await db.execute(
        select(OneTimePreKey.key_id, OneTimePreKey.public_key).where(
            OneTimePreKey.user_id == user_id
        )
    )
    return {row.key_id: row.public_key for row in rows}


async def _consumed_prekeys(
    db: AsyncSession, user_id: UUID, identity_key: str
) -> dict[int, str]:
    rows = await db.execute(
        select(
            ConsumedOneTimePreKey.key_id,
            ConsumedOneTimePreKey.public_key,
        ).where(
            ConsumedOneTimePreKey.user_id == user_id,
            ConsumedOneTimePreKey.identity_key == identity_key,
        )
    )
    return {row.key_id: row.public_key for row in rows}


def _fresh_prekeys(
    uploaded: list[OneTimePreKeyIn],
    active: dict[int, str],
    consumed: dict[int, str],
) -> list[OneTimePreKeyIn]:
    """Return uploads that are neither active nor already consumed.

    Identical material is an idempotent retry. Different material under a
    reused key id is not a retry — it is either a client bug or an attempt to
    replace key material a peer may already trust — so it is rejected rather
    than silently overwritten.
    """
    fresh: list[OneTimePreKeyIn] = []
    for pk in uploaded:
        if pk.key_id in active:
            if active[pk.key_id] != pk.public_key:
                raise _conflict(pk.key_id)
            continue
        if pk.key_id in consumed:
            if consumed[pk.key_id] != pk.public_key:
                raise _conflict(pk.key_id)
            # Identical to a consumed key: never make it available again.
            continue
        fresh.append(pk)
    return fresh


@router.post("/keys/bundle", status_code=status.HTTP_204_NO_CONTENT, response_model=None)
async def publish_key_bundle(
    body: KeyBundleUpload,
    current_user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> None:
    """Publish (or replace) this user's public key bundle.

    Three cases are accepted:

    * First publication — install the advertised pre-keys.
    * Identity change — discard the old identity's active pre-keys and install
      the new identity's. Consumed-key tombstones are identity-scoped and stay.
    * Same identity — update the registration id and signed pre-key only.

    Pre-keys are deliberately never inserted in the same-identity case. A
    client retrying a bundle whose response was lost still sends the keys it
    uploaded originally; if some were consumed, re-inserting them would hand
    them out again. New pre-keys belong on POST /keys/prekeys, which is what
    the client already calls for replenishment.

    Identical material is idempotent; different material under a reused key id
    is a 409, never a silent overwrite or a blind ON CONFLICT DO NOTHING.
    """
    await _lock_key_directory(db, current_user.id)

    existing = await db.scalar(
        select(UserKeyBundle).where(UserKeyBundle.user_id == current_user.id)
    )
    first_publication = existing is None
    identity_changed = (
        existing is not None and existing.identity_key != body.identity_key
    )
    accepts_new_prekeys = first_publication or identity_changed

    if accepts_new_prekeys:
        # Any existing rows cannot belong to the identity being published:
        # either there was no bundle at all (orphans are unreachable) or the
        # identity is being replaced. They are deleted after validation below.
        active: dict[int, str] = {}
    else:
        active = await _active_prekeys(db, current_user.id)

    consumed = await _consumed_prekeys(db, current_user.id, body.identity_key)
    fresh = _fresh_prekeys(body.one_time_prekeys, active, consumed)

    if first_publication:
        await db.execute(
            delete(OneTimePreKey).where(OneTimePreKey.user_id == current_user.id)
        )
        existing = UserKeyBundle(user_id=current_user.id)
        db.add(existing)
    elif identity_changed:
        await db.execute(
            delete(OneTimePreKey).where(OneTimePreKey.user_id == current_user.id)
        )

    existing.registration_id = body.registration_id
    existing.identity_key = body.identity_key
    existing.signed_prekey_id = body.signed_prekey_id
    existing.signed_prekey_public = body.signed_prekey_public
    existing.signed_prekey_signature = body.signed_prekey_signature

    if accepts_new_prekeys:
        for pk in fresh:
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
    """Top up one-time pre-keys. The client calls this when its count runs low.

    Replaying a key id that is still active, or that was already consumed under
    this identity, is idempotent. Reusing an id for different material is a
    409. The advisory lock serializes this with publication and claims so two
    replenishments cannot both decide an id is free.
    """
    await _lock_key_directory(db, current_user.id)

    bundle = await db.scalar(
        select(UserKeyBundle).where(UserKeyBundle.user_id == current_user.id)
    )
    if bundle is None:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="publish a key bundle before uploading pre-keys",
        )

    active = await _active_prekeys(db, current_user.id)
    consumed = await _consumed_prekeys(db, current_user.id, bundle.identity_key)
    fresh = _fresh_prekeys(body.one_time_prekeys, active, consumed)

    if len(active) + len(fresh) > _MAX_PREKEYS_STORED:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail=f"pre-key store full (max {_MAX_PREKEYS_STORED})",
        )

    for pk in fresh:
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

    The claim deletes the row and records an identity-scoped tombstone in the
    same transaction. The tombstone is what makes a later bundle retry skip
    the key instead of re-advertising it. The advisory lock orders this claim
    against publication and replenishment for the same user.

    The caller MUST verify signed_prekey_signature against identity_key before
    using this bundle. libsignal's processPreKeyBundle does that automatically;
    a hand-rolled client that skips it is trusting the server not to perform a
    man-in-the-middle attack, which is exactly the trust E2EE exists to remove.
    """
    await _lock_key_directory(db, user_id)

    bundle = await db.scalar(
        select(UserKeyBundle).where(UserKeyBundle.user_id == user_id)
    )
    if bundle is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="user has not published encryption keys",
        )

    # Copy before the commit: expire_on_commit is disabled at runtime, but
    # keeping the response independent of ORM state is cheaper than relying on
    # that setting staying that way.
    identity_key = bundle.identity_key
    registration_id = bundle.registration_id
    signed_prekey_id = bundle.signed_prekey_id
    signed_prekey_public = bundle.signed_prekey_public
    signed_prekey_signature = bundle.signed_prekey_signature

    # Claim one pre-key atomically. Two senders racing here must not receive the
    # same key, so the delete itself is the claim — RETURNING tells us whether
    # this request won. A plain SELECT-then-DELETE would hand the same pre-key
    # to both under concurrency. `skip_locked` remains as a second guard even
    # though the advisory lock already serializes claims for this user.
    already_consumed = (
        select(ConsumedOneTimePreKey.id)
        .where(
            ConsumedOneTimePreKey.user_id == user_id,
            ConsumedOneTimePreKey.identity_key == identity_key,
            ConsumedOneTimePreKey.key_id == OneTimePreKey.key_id,
        )
        .exists()
    )
    claimed = (
        await db.execute(
            delete(OneTimePreKey)
            .where(
                OneTimePreKey.id.in_(
                    select(OneTimePreKey.id)
                    .where(
                        OneTimePreKey.user_id == user_id,
                        ~already_consumed,
                    )
                    .order_by(OneTimePreKey.id)
                    .limit(1)
                    .with_for_update(skip_locked=True)
                )
            )
            .returning(OneTimePreKey.key_id, OneTimePreKey.public_key)
        )
    ).first()

    claimed_key_id: int | None = None
    claimed_public_key: str | None = None
    if claimed is not None:
        # Record the tombstone before the key is returned. ON CONFLICT DO
        # NOTHING is deliberate: if a tombstone already exists, this row was a
        # resurrection and must not be handed out. It has been deleted above,
        # so a later claim can still serve a genuinely distinct key.
        recorded = (
            await db.execute(
                pg_insert(ConsumedOneTimePreKey)
                .values(
                    user_id=user_id,
                    identity_key=identity_key,
                    key_id=claimed[0],
                    public_key=claimed[1],
                )
                .on_conflict_do_nothing(
                    index_elements=["user_id", "identity_key", "key_id"]
                )
                .returning(ConsumedOneTimePreKey.key_id)
            )
        ).first()
        if recorded is not None:
            claimed_key_id = claimed[0]
            claimed_public_key = claimed[1]

    await db.commit()

    return PreKeyBundleOut(
        user_id=user_id,
        registration_id=registration_id,
        identity_key=identity_key,
        signed_prekey_id=signed_prekey_id,
        signed_prekey_public=signed_prekey_public,
        signed_prekey_signature=signed_prekey_signature,
        one_time_prekey_id=claimed_key_id,
        one_time_prekey=claimed_public_key,
    )
