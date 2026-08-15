from __future__ import annotations

from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, ConfigDict, Field, field_validator
from sqlalchemy import delete, exists, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.core.database import get_db
from app.models import (
    ContactRelation,
    ContentReport,
    Message,
    ReportReason,
    ReportStatus,
    User,
    UserBlock,
)

router = APIRouter(tags=["moderation"])

#: Bound on the reporter-supplied evidence. Large enough for any real message,
#: small enough that the report table cannot be used as free storage.
MAX_SNAPSHOT_CHARS = 4_000


# ── Enforcement, used by the message path ────────────────────────────────────

async def blocked_between(
    db: AsyncSession, a: UUID, b: UUID
) -> bool:
    """Whether either user has blocked the other.

    Deliberately symmetric at the point of enforcement even though the block
    itself is directional: if A blocked B, then B must not be able to message
    A either. Checking only one direction would let the blocked party keep
    talking to someone who asked not to hear from them.
    """
    return bool(await db.scalar(
        select(
            exists().where(
                or_(
                    (UserBlock.blocker_id == a) & (UserBlock.blocked_id == b),
                    (UserBlock.blocker_id == b) & (UserBlock.blocked_id == a),
                )
            )
        )
    ))


async def assert_not_blocked(db: AsyncSession, sender: UUID, recipient: UUID) -> None:
    """Refuse a send between blocked parties.

    The error deliberately does not say a block exists. Telling a sender they
    have been blocked converts a quiet boundary into a confrontation, which is
    the thing blocking is meant to prevent.
    """
    if await blocked_between(db, sender, recipient):
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            "This message could not be delivered.",
        )


# ── Schemas ───────────────────────────────────────────────────────────────────

class BlockIn(BaseModel):
    reason: str | None = Field(default=None, max_length=500)


class BlockedUserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    user_id: UUID
    full_name: str
    username: str | None
    blocked_at: datetime


class ReportIn(BaseModel):
    reported_user_id: UUID
    reason: str
    message_id: UUID | None = None
    details: str | None = Field(default=None, max_length=2_000)
    content_snapshot: str | None = Field(default=None, max_length=MAX_SNAPSHOT_CHARS)

    @field_validator("reason")
    @classmethod
    def _known(cls, v: str) -> str:
        if v not in {r.value for r in ReportReason}:
            raise ValueError("unknown report reason")
        return v


class ReportOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    reported_user_id: UUID
    message_id: UUID | None
    reason: str
    status: str
    created_at: datetime


# ── Blocking ──────────────────────────────────────────────────────────────────

@router.post(
    "/users/{user_id}/block",
    status_code=status.HTTP_204_NO_CONTENT,
    response_model=None,
)
async def block_user(
    user_id: UUID,
    body: BlockIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> None:
    if user_id == user.id:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY, "You cannot block yourself"
        )

    target = await db.scalar(select(User).where(User.id == user_id))
    if target is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "user not found")

    existing = await db.scalar(
        select(UserBlock).where(
            UserBlock.blocker_id == user.id,
            UserBlock.blocked_id == user_id,
        )
    )
    if existing is None:
        db.add(UserBlock(
            blocker_id=user.id, blocked_id=user_id, reason=body.reason
        ))

    # Blocking also severs contact discovery in both directions. Leaving the
    # link would keep the blocked user surfacing in "people you know", which
    # is the opposite of what was asked for.
    await db.execute(
        delete(ContactRelation).where(
            or_(
                (ContactRelation.owner_id == user.id)
                & (ContactRelation.contact_user_id == user_id),
                (ContactRelation.owner_id == user_id)
                & (ContactRelation.contact_user_id == user.id),
            )
        )
    )
    await db.commit()


@router.delete(
    "/users/{user_id}/block",
    status_code=status.HTTP_204_NO_CONTENT,
    response_model=None,
)
async def unblock_user(
    user_id: UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> None:
    result = await db.execute(
        delete(UserBlock).where(
            UserBlock.blocker_id == user.id,
            UserBlock.blocked_id == user_id,
        )
    )
    if result.rowcount == 0:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "that user is not blocked")
    await db.commit()


@router.get("/users/blocked", response_model=list[BlockedUserOut])
async def blocked_users(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[BlockedUserOut]:
    """The people this user has blocked.

    Only their own list — there is no endpoint that reveals who has blocked
    you, because knowing that is exactly what a block withholds.
    """
    rows = (await db.execute(
        select(User, UserBlock.created_at)
        .join(UserBlock, UserBlock.blocked_id == User.id)
        .where(UserBlock.blocker_id == user.id)
        .order_by(UserBlock.created_at.desc())
    )).all()

    return [
        BlockedUserOut(
            user_id=u.id,
            full_name=u.full_name,
            username=u.username,
            blocked_at=blocked_at,
        )
        for u, blocked_at in rows
    ]


@router.get("/users/{user_id}/block-status")
async def block_status(
    user_id: UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, bool]:
    """Whether *this* user has blocked the other.

    Reports only their own action. Whether the other party has blocked them
    is not disclosed, so the response cannot be used to probe for it.
    """
    blocked = await db.scalar(
        select(exists().where(
            (UserBlock.blocker_id == user.id) & (UserBlock.blocked_id == user_id)
        ))
    )
    return {"blocked": bool(blocked)}


# ── Reporting ─────────────────────────────────────────────────────────────────

@router.post(
    "/reports",
    response_model=ReportOut,
    status_code=status.HTTP_201_CREATED,
)
async def submit_report(
    body: ReportIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> ReportOut:
    if body.reported_user_id == user.id:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY, "You cannot report yourself"
        )

    target = await db.scalar(select(User).where(User.id == body.reported_user_id))
    if target is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "user not found")

    if body.message_id is not None:
        message = await db.scalar(
            select(Message).where(Message.id == body.message_id)
        )
        if message is None:
            raise HTTPException(status.HTTP_404_NOT_FOUND, "message not found")
        # Without this, anyone could attach an arbitrary message id to a
        # report and pull unrelated conversations into moderation review.
        if message.sender_id != body.reported_user_id:
            raise HTTPException(
                status.HTTP_422_UNPROCESSABLE_ENTITY,
                "that message was not sent by the reported user",
            )

        duplicate = await db.scalar(
            select(exists().where(
                (ContentReport.reporter_id == user.id)
                & (ContentReport.message_id == body.message_id)
            ))
        )
        if duplicate:
            raise HTTPException(
                status.HTTP_409_CONFLICT,
                "You have already reported this message.",
            )

    report = ContentReport(
        reporter_id=user.id,
        reported_user_id=body.reported_user_id,
        message_id=body.message_id,
        reason=body.reason,
        details=body.details,
        # Supplied by the reporter, not read from the message: the server
        # cannot decrypt content_ciphertext, and this is the only way the
        # evidence survives the sender deleting it.
        content_snapshot=body.content_snapshot,
    )
    db.add(report)
    await db.commit()
    await db.refresh(report)
    return ReportOut.model_validate(report)


@router.get("/reports/mine", response_model=list[ReportOut])
async def my_reports(
    limit: int = Query(default=50, ge=1, le=100),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[ReportOut]:
    """Reports this user filed, so submitting one is not a dead end."""
    rows = (await db.scalars(
        select(ContentReport)
        .where(ContentReport.reporter_id == user.id)
        .order_by(ContentReport.created_at.desc())
        .limit(limit)
    )).all()
    return [ReportOut.model_validate(r) for r in rows]
