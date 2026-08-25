"""Who has agreed that a conversation may be sent to the AI provider.

The AI features are the one place in this product where message plaintext
leaves the device and reaches a third party. Everything here exists to make
that impossible without every affected person's agreement, and to make the
refusal explain itself rather than looking like a bug.
"""
from __future__ import annotations

from datetime import datetime, timezone
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import AiConsent, AiScopeType, GroupMember, User


class AiConsentMissing(Exception):
    """Not everyone whose words would be transmitted has agreed.

    Carries who is still missing so the interface can say "waiting for
    Sara" rather than a bare refusal — the difference between something the
    user can act on and something that looks broken.
    """

    def __init__(self, missing: list[str], total: int) -> None:
        super().__init__("consent missing")
        self.missing = missing
        self.total = total


async def _active(
    db: AsyncSession, user_id: UUID, scope_type: str, scope_id: UUID
) -> AiConsent | None:
    return await db.scalar(
        select(AiConsent).where(
            AiConsent.user_id == user_id,
            AiConsent.scope_type == scope_type,
            AiConsent.scope_id == scope_id,
            AiConsent.revoked_at.is_(None),
        )
    )


async def has_consent(
    db: AsyncSession, *, user_id: UUID, scope_type: str, scope_id: UUID
) -> bool:
    return await _active(db, user_id, scope_type, scope_id) is not None


async def grant(
    db: AsyncSession, *, user_id: UUID, scope_type: str, scope_id: UUID
) -> AiConsent:
    """Records one person's half of the agreement.

    Re-granting after a withdrawal creates a new row rather than clearing
    the old one's revoked_at, so the periods of exposure stay distinct.
    """
    existing = await _active(db, user_id, scope_type, scope_id)
    if existing is not None:
        return existing

    consent = AiConsent(
        user_id=user_id,
        scope_type=scope_type,
        scope_id=scope_id,
        granted_at=datetime.now(timezone.utc),
    )
    db.add(consent)
    await db.commit()
    await db.refresh(consent)
    return consent


async def revoke(
    db: AsyncSession, *, user_id: UUID, scope_type: str, scope_id: UUID
) -> bool:
    """Withdraws it. Returns False if there was nothing to withdraw.

    Stamps revoked_at rather than deleting: withdrawal stops future
    transmission, it cannot un-send what already went, and the record is
    what keeps that honest.
    """
    consent = await _active(db, user_id, scope_type, scope_id)
    if consent is None:
        return False
    consent.revoked_at = datetime.now(timezone.utc)
    await db.commit()
    return True


async def require_direct(
    db: AsyncSession, *, user_id: UUID, peer_id: UUID
) -> None:
    """Both sides of a one-to-one conversation must have agreed.

    A summary contains the other person's words. Letting one side enable it
    alone would mean sending someone else's messages to a third party on
    their behalf — the disclosure the encryption exists to prevent, performed
    from inside the conversation.

    Note the scope is stored from each side's own point of view: this user's
    row names the peer, the peer's row names this user. There is no shared
    conversation id to key on, and inventing one would need a migration for
    every existing message.
    """
    missing: list[str] = []

    if not await has_consent(
        db, user_id=user_id, scope_type=AiScopeType.DIRECT, scope_id=peer_id
    ):
        missing.append(str(user_id))

    if not await has_consent(
        db, user_id=peer_id, scope_type=AiScopeType.DIRECT, scope_id=user_id
    ):
        missing.append(str(peer_id))

    if missing:
        raise AiConsentMissing(missing=missing, total=2)


async def require_group(db: AsyncSession, *, group_id: UUID) -> None:
    """Every current member must have agreed.

    Strict on purpose. A group summary contains everyone's words, so anyone
    who has not agreed would be having their messages sent onward by other
    people's choice. The practical effect is that group AI is rarely
    available, which is the honest consequence rather than a flaw to design
    around.
    """
    member_ids = list(
        (
            await db.scalars(
                select(GroupMember.user_id).where(
                    GroupMember.group_id == group_id
                )
            )
        ).all()
    )
    if not member_ids:
        raise AiConsentMissing(missing=[], total=0)

    consented = set(
        (
            await db.scalars(
                select(AiConsent.user_id).where(
                    AiConsent.scope_type == AiScopeType.GROUP,
                    AiConsent.scope_id == group_id,
                    AiConsent.revoked_at.is_(None),
                    AiConsent.user_id.in_(member_ids),
                )
            )
        ).all()
    )

    missing = [str(m) for m in member_ids if m not in consented]
    if missing:
        raise AiConsentMissing(missing=missing, total=len(member_ids))


async def missing_names(db: AsyncSession, user_ids: list[str]) -> list[str]:
    """Turns the ids in an AiConsentMissing into names for the interface."""
    if not user_ids:
        return []
    rows = await db.scalars(
        select(User.full_name).where(User.id.in_([UUID(u) for u in user_ids]))
    )
    return list(rows.all())
