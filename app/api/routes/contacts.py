from __future__ import annotations

from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, ConfigDict, Field, field_validator
from sqlalchemy import delete, func, select
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import get_db
from app.models import (
    ContactHash,
    ContactInvite,
    ContactRelation,
    ContactSyncState,
    DiscoverabilityLevel,
    User,
    UserPhoneIndex,
)
from app.services.contact_discovery import (
    MAX_CONTACTS_PER_SYNC,
    hash_phone,
    is_valid_hash,
    new_invite_token,
    normalize_phone,
)

router = APIRouter(prefix="/contacts", tags=["contacts"])


# ── Schemas ───────────────────────────────────────────────────────────────────

class SyncIn(BaseModel):
    """Hashes only.

    There is deliberately no field here that could carry a phone number, a
    name, or anything else from the address book — the endpoint is incapable
    of receiving one.
    """

    hashes: list[str] = Field(..., min_length=0, max_length=MAX_CONTACTS_PER_SYNC)
    replace: bool = Field(
        default=True,
        description="True wipes previously stored hashes; False merges "
                    "(incremental sync)",
    )

    @field_validator("hashes")
    @classmethod
    def _digests_only(cls, v: list[str]) -> list[str]:
        # Rejecting the whole batch rather than filtering: a client sending
        # non-digests is either broken or probing, and silently dropping the
        # bad entries would hide both.
        for h in v:
            if not is_valid_hash(h):
                raise ValueError(
                    "every entry must be a hex SHA-256 digest — raw phone "
                    "numbers must never be uploaded"
                )
        return v


class SyncOut(BaseModel):
    stored: int
    matched: int
    new_matches: int


class DiscoveredContactOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    user_id: UUID
    full_name: str
    username: str | None
    avatar_url: str | None = None
    is_new: bool = False


class InviteIn(BaseModel):
    """A number to invite.

    This is the one endpoint that accepts a raw number, because an invite has
    to be delivered to it. It is normalized, hashed, and discarded — never
    stored.
    """

    phone_number: str = Field(..., min_length=4, max_length=32)


class InviteOut(BaseModel):
    invite_token: str
    deep_link: str


class PrivacyIn(BaseModel):
    discoverability: str

    @field_validator("discoverability")
    @classmethod
    def _known(cls, v: str) -> str:
        if v not in {d.value for d in DiscoverabilityLevel}:
            raise ValueError("unknown discoverability level")
        return v


class SyncStateOut(BaseModel):
    sync_enabled: bool
    contact_count: int
    synced_at: datetime | None
    discoverability: str


# ── Helpers ───────────────────────────────────────────────────────────────────

async def _ensure_indexed(db: AsyncSession, user: User) -> UserPhoneIndex:
    """Make sure this user is findable by their own number.

    Called on every sync rather than only at registration so that accounts
    created before this feature existed become discoverable the first time
    their owner opens contacts, instead of being invisible forever.
    """
    row = await db.scalar(
        select(UserPhoneIndex).where(UserPhoneIndex.user_id == user.id)
    )
    if row is not None:
        return row

    normalized = normalize_phone(user.phone_number)
    if normalized is None:
        # The account's own number is unparseable; nothing to index. Not an
        # error for the caller — their sync still works, they are just not
        # discoverable until the number is corrected.
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            "your account's phone number could not be normalized",
        )

    row = UserPhoneIndex(
        user_id=user.id,
        phone_hash=hash_phone(normalized),
        allows_discovery=DiscoverabilityLevel.CONTACTS_OF_CONTACTS,
    )
    db.add(row)
    await db.flush()
    return row


async def _sync_state(db: AsyncSession, user_id: UUID) -> ContactSyncState:
    state = await db.scalar(
        select(ContactSyncState).where(ContactSyncState.user_id == user_id)
    )
    if state is None:
        state = ContactSyncState(user_id=user_id)
        db.add(state)
        await db.flush()
    return state


async def _mutual(db: AsyncSession, a: UUID, b: UUID) -> bool:
    """Whether b has a in their contacts — the reciprocal direction.

    Used for CONTACTS_OF_CONTACTS: being in someone's address book is not
    the same as them being in yours, and the narrower setting should mean
    the relationship actually goes both ways.
    """
    return await db.scalar(
        select(func.count())
        .select_from(ContactRelation)
        .where(
            ContactRelation.owner_id == b,
            ContactRelation.contact_user_id == a,
        )
    ) > 0


# ── Endpoints ─────────────────────────────────────────────────────────────────

@router.post("/sync", response_model=SyncOut)
async def sync_contacts(
    body: SyncIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> SyncOut:
    """Upload hashed contacts and get back how many are on IronLink.

    The device does the hashing; this never sees a phone number.
    """
    state = await _sync_state(db, user.id)
    if not state.sync_enabled:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            "contact sync is turned off for this account",
        )

    await _ensure_indexed(db, user)

    if body.replace:
        await db.execute(
            delete(ContactHash).where(ContactHash.owner_id == user.id)
        )

    unique = list(dict.fromkeys(body.hashes))
    if unique:
        # ON CONFLICT DO NOTHING so a re-sync of an overlapping book is a
        # no-op per row rather than a constraint violation for the batch.
        await db.execute(
            pg_insert(ContactHash)
            .values([{"owner_id": user.id, "phone_hash": h} for h in unique])
            .on_conflict_do_nothing(constraint="uq_contact_hash")
        )

    # Match against registered users who permit being found at all.
    candidates = (await db.execute(
        select(UserPhoneIndex.user_id, UserPhoneIndex.allows_discovery)
        .where(
            UserPhoneIndex.phone_hash.in_(unique),
            UserPhoneIndex.allows_discovery != DiscoverabilityLevel.NOBODY,
            UserPhoneIndex.user_id != user.id,
        )
    )).all() if unique else []

    new_matches = 0
    for contact_id, level in candidates:
        if level == DiscoverabilityLevel.CONTACTS_OF_CONTACTS:
            if not await _mutual(db, user.id, contact_id):
                continue
        result = await db.execute(
            pg_insert(ContactRelation)
            .values(owner_id=user.id, contact_user_id=contact_id, source="phone")
            .on_conflict_do_nothing(constraint="uq_contact_relation")
        )
        new_matches += result.rowcount or 0

    state.synced_at = datetime.now(timezone.utc)
    state.contact_count = len(unique)
    await db.commit()

    total = await db.scalar(
        select(func.count())
        .select_from(ContactRelation)
        .where(ContactRelation.owner_id == user.id)
    ) or 0

    return SyncOut(stored=len(unique), matched=total, new_matches=new_matches)


@router.get("/matches", response_model=list[DiscoveredContactOut])
async def matches(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[DiscoveredContactOut]:
    """Contacts of this user who are on IronLink."""
    rows = (await db.execute(
        select(User, ContactRelation.notified_at)
        .join(ContactRelation, ContactRelation.contact_user_id == User.id)
        .where(ContactRelation.owner_id == user.id)
        .order_by(User.full_name)
    )).all()

    return [
        DiscoveredContactOut(
            user_id=u.id,
            full_name=u.full_name,
            username=u.username,
            is_new=notified_at is None,
        )
        for u, notified_at in rows
    ]


@router.post("/matches/seen", status_code=status.HTTP_204_NO_CONTENT, response_model=None)
async def mark_matches_seen(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> None:
    """Stop flagging current matches as new.

    Separate from GET /matches so that merely fetching the list does not
    clear the badge — a screen that loads in the background would otherwise
    silently consume the notification.
    """
    await db.execute(
        ContactRelation.__table__.update()
        .where(
            ContactRelation.owner_id == user.id,
            ContactRelation.notified_at.is_(None),
        )
        .values(notified_at=datetime.now(timezone.utc))
    )
    await db.commit()


@router.post("/invite", response_model=InviteOut, status_code=status.HTTP_201_CREATED)
async def invite(
    body: InviteIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> InviteOut:
    normalized = normalize_phone(body.phone_number)
    if normalized is None:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY, "that is not a valid phone number"
        )

    phone_hash = hash_phone(normalized)

    existing = await db.scalar(
        select(ContactInvite).where(
            ContactInvite.inviter_id == user.id,
            ContactInvite.phone_hash == phone_hash,
        )
    )
    # Re-inviting reuses the token so a person who receives the link twice
    # does not end up with two competing invitations.
    if existing is not None:
        return InviteOut(
            invite_token=existing.invite_token,
            deep_link=f"https://ironlink.app/i/{existing.invite_token}",
        )

    token = new_invite_token()
    db.add(ContactInvite(
        inviter_id=user.id, phone_hash=phone_hash, invite_token=token
    ))
    await db.commit()
    # The raw number was used to compute the hash and is not persisted
    # anywhere in this handler.
    return InviteOut(
        invite_token=token, deep_link=f"https://ironlink.app/i/{token}"
    )


@router.get("/state", response_model=SyncStateOut)
async def sync_state(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> SyncStateOut:
    state = await _sync_state(db, user.id)
    index = await db.scalar(
        select(UserPhoneIndex).where(UserPhoneIndex.user_id == user.id)
    )
    await db.commit()
    return SyncStateOut(
        sync_enabled=state.sync_enabled,
        contact_count=state.contact_count,
        synced_at=state.synced_at,
        discoverability=(
            index.allows_discovery if index
            else DiscoverabilityLevel.CONTACTS_OF_CONTACTS.value
        ),
    )


@router.put("/privacy", status_code=status.HTTP_204_NO_CONTENT, response_model=None)
async def set_privacy(
    body: PrivacyIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> None:
    index = await _ensure_indexed(db, user)
    index.allows_discovery = body.discoverability
    await db.commit()


@router.delete("/delete-all", status_code=status.HTTP_204_NO_CONTENT, response_model=None)
async def delete_all(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> None:
    """Erase everything derived from this user's address book.

    Opting out has to actually remove the data, not just stop using it: the
    hashes, the resolved relations, and the index entry that made them
    discoverable all go. Invites are kept, since those were sent to other
    people and revoking them retroactively would break links already
    delivered.
    """
    await db.execute(delete(ContactHash).where(ContactHash.owner_id == user.id))
    await db.execute(
        delete(ContactRelation).where(ContactRelation.owner_id == user.id)
    )
    # Also drop links *other* people hold to this user, so opting out means
    # disappearing from their discovery lists too rather than only clearing
    # your own.
    await db.execute(
        delete(ContactRelation).where(ContactRelation.contact_user_id == user.id)
    )
    await db.execute(
        delete(UserPhoneIndex).where(UserPhoneIndex.user_id == user.id)
    )

    state = await _sync_state(db, user.id)
    state.sync_enabled = False
    state.synced_at = None
    state.contact_count = 0
    await db.commit()
