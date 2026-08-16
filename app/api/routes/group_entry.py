from __future__ import annotations

from datetime import datetime, timezone
from typing import Any
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, ConfigDict, Field, field_validator
from sqlalchemy import delete, func, select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from app.api.deps import get_current_user
from app.core.database import get_db
from app.models import (
    Group,
    GroupAuditAction,
    GroupAuditLog,
    GroupBan,
    GroupJoinMode,
    GroupJoinRequest,
    GroupMember,
    GroupRole,
    JoinRequestStatus,
    PlatformBan,
    User,
    VerificationForm,
    VerificationFormField,
)
from app.models.group import GROUP_ROLE_RANK
from app.services import group_message_service
from app.services.form_validation import (
    FormValidationError,
    expiry_for,
    validate_answers,
    validate_field_definition,
)

router = APIRouter(prefix="/groups", tags=["group-entry"])

#: Cap on a single bulk action. Beyond this the spec calls for background
#: processing; until that exists, refusing is safer than a request that times
#: out halfway through and leaves the caller unsure what was applied.
MAX_BULK_SIZE = 200


# ── Schemas ───────────────────────────────────────────────────────────────────

class FormFieldIn(BaseModel):
    field_type: str
    label: str = Field(..., min_length=1, max_length=500)
    placeholder: str | None = Field(default=None, max_length=500)
    helper_text: str | None = Field(default=None, max_length=1000)
    is_required: bool = True
    validation_rules: dict[str, Any] | None = None
    options: dict[str, Any] | None = None
    icon: str | None = Field(default=None, max_length=50)


class FormFieldOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    field_type: str
    label: str
    placeholder: str | None
    helper_text: str | None
    is_required: bool
    validation_rules: dict[str, Any] | None
    options: dict[str, Any] | None
    icon: str | None
    order_index: int


class FormIn(BaseModel):
    name: str = Field(..., min_length=1, max_length=255)
    description: str | None = Field(default=None, max_length=2000)
    is_template: bool = False
    fields: list[FormFieldIn] = Field(default_factory=list)

    @field_validator("fields")
    @classmethod
    def _bounded(cls, v: list[FormFieldIn]) -> list[FormFieldIn]:
        # A form long enough to be abusive is also one nobody completes.
        if len(v) > 100:
            raise ValueError("a form may have at most 100 fields")
        return v


class FormOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    name: str
    description: str | None
    is_template: bool
    fields: list[FormFieldOut] = Field(default_factory=list)


class JoinModeIn(BaseModel):
    join_mode: str
    verification_form_id: UUID | None = None
    request_expiry_days: int = Field(default=14, ge=0, le=365)
    allow_rejoin: bool = False

    @field_validator("join_mode")
    @classmethod
    def _known(cls, v: str) -> str:
        if v not in {m.value for m in GroupJoinMode}:
            raise ValueError("unknown join mode")
        return v


class SubmitRequestIn(BaseModel):
    answers: dict[str, Any] = Field(default_factory=dict)
    message: str | None = Field(default=None, max_length=300)


class RequestOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    group_id: UUID
    user_id: UUID
    status: str
    answers: dict[str, Any] | None
    message: str | None
    admin_notes: str | None
    rejection_reason: str | None
    expires_at: datetime | None
    created_at: datetime


class DecisionIn(BaseModel):
    reason: str | None = Field(default=None, max_length=1000)
    notes: str | None = Field(default=None, max_length=1000)


class BulkDecisionIn(BaseModel):
    request_ids: list[UUID] | None = Field(
        default=None,
        description="Specific requests to act on; omit to act on all pending",
    )
    reason: str | None = Field(default=None, max_length=1000)


class BulkResultOut(BaseModel):
    succeeded: int
    failed: int
    total: int


class BanIn(BaseModel):
    reason: str | None = Field(default=None, max_length=1000)
    is_permanent: bool = True
    expires_at: datetime | None = None

    @field_validator("expires_at")
    @classmethod
    def _future(cls, v: datetime | None) -> datetime | None:
        if v is not None and v <= datetime.now(timezone.utc):
            raise ValueError("expiry must be in the future")
        return v


class BannedUserOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    user_id: UUID
    banned_by_id: UUID
    reason: str | None
    is_permanent: bool
    expires_at: datetime | None
    created_at: datetime


class AuditEntryOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: UUID
    action: str
    performed_by_id: UUID
    target_user_id: UUID | None
    details: dict[str, Any] | None
    created_at: datetime


# ── Helpers ───────────────────────────────────────────────────────────────────

async def _membership(
    db: AsyncSession, group_id: UUID, user_id: UUID
) -> GroupMember | None:
    return await db.scalar(
        select(GroupMember).where(
            GroupMember.group_id == group_id,
            GroupMember.user_id == user_id,
        )
    )


async def _require_rank(
    db: AsyncSession, group_id: UUID, user_id: UUID, minimum: GroupRole
) -> GroupMember:
    member = await _membership(db, group_id, user_id)
    if member is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "group not found")
    if GROUP_ROLE_RANK.get(member.role, 0) < GROUP_ROLE_RANK[minimum]:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            "You don't have permission to perform this action.",
        )
    return member


async def _get_group(db: AsyncSession, group_id: UUID) -> Group:
    group = await db.scalar(select(Group).where(Group.id == group_id))
    if group is None or group.is_archived:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "group not found")
    return group


def _log(
    db: AsyncSession,
    *,
    group_id: UUID,
    action: GroupAuditAction,
    performed_by: UUID,
    target: UUID | None = None,
    details: dict[str, Any] | None = None,
) -> None:
    db.add(GroupAuditLog(
        group_id=group_id,
        action=action.value,
        performed_by_id=performed_by,
        target_user_id=target,
        details=details,
    ))


async def _assert_not_banned(
    db: AsyncSession, group_id: UUID, user_id: UUID
) -> None:
    """Block a banned user before any request is created.

    Platform bans are checked first: their message is deliberately broader,
    and telling a platform-banned user only about this one group would be
    misleading about why they cannot proceed.
    """
    platform = await db.scalar(
        select(PlatformBan).where(PlatformBan.user_id == user_id)
    )
    if platform is not None:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN,
            "Your account has been restricted from joining groups on IronLink. "
            "Contact support for more information.",
        )

    ban = await db.scalar(
        select(GroupBan).where(
            GroupBan.group_id == group_id,
            GroupBan.user_id == user_id,
        )
    )
    if ban is None:
        return
    # A time-limited ban that has lapsed is cleared rather than enforced, so
    # the user isn't blocked by a row nobody remembered to remove.
    if not ban.is_permanent and ban.expires_at is not None:
        if ban.expires_at <= datetime.now(timezone.utc):
            await db.delete(ban)
            await db.flush()
            return
    raise HTTPException(
        status.HTTP_403_FORBIDDEN,
        "You've been removed from this group and can't request to rejoin.",
    )


async def _load_form(db: AsyncSession, form_id: UUID) -> VerificationForm:
    form = await db.scalar(
        select(VerificationForm)
        .options(selectinload(VerificationForm.fields))
        .where(VerificationForm.id == form_id)
    )
    if form is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "form not found")
    return form


def _expire_if_due(req: GroupJoinRequest) -> bool:
    """Flip a lapsed request to EXPIRED. Returns whether it changed.

    Evaluated on read rather than by a scheduler: without a job runner in
    Phase 1, a request whose window has passed must not still be approvable
    just because nothing swept it.
    """
    if req.status != JoinRequestStatus.PENDING:
        return False
    if req.expires_at is None or req.expires_at > datetime.now(timezone.utc):
        return False
    req.status = JoinRequestStatus.EXPIRED
    return True


# ── Verification forms (admin) ────────────────────────────────────────────────

@router.post(
    "/{group_id}/forms",
    response_model=FormOut,
    status_code=status.HTTP_201_CREATED,
)
async def create_form(
    group_id: UUID,
    body: FormIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> FormOut:
    """Create a verification form. Admin only — moderators cannot author forms."""
    await _require_rank(db, group_id, user.id, GroupRole.ADMIN)
    await _get_group(db, group_id)

    for index, field in enumerate(body.fields):
        try:
            validate_field_definition(
                field.field_type, field.options, field.validation_rules
            )
        except ValueError as exc:
            raise HTTPException(
                status.HTTP_422_UNPROCESSABLE_ENTITY,
                f"field {index + 1}: {exc}",
            ) from None

    form = VerificationForm(
        name=body.name,
        description=body.description,
        is_template=body.is_template,
        created_by_id=user.id,
    )
    db.add(form)
    await db.flush()

    for index, field in enumerate(body.fields):
        db.add(VerificationFormField(
            form_id=form.id,
            field_type=field.field_type,
            label=field.label,
            placeholder=field.placeholder,
            helper_text=field.helper_text,
            is_required=field.is_required,
            validation_rules=field.validation_rules,
            options=field.options,
            icon=field.icon,
            order_index=index,
        ))

    _log(
        db,
        group_id=group_id,
        action=GroupAuditAction.UPDATE_FORM,
        performed_by=user.id,
        details={"form_id": str(form.id), "name": form.name, "created": True},
    )
    await db.commit()
    return FormOut.model_validate(await _load_form(db, form.id))


@router.get("/{group_id}/forms/active", response_model=FormOut | None)
async def active_form(
    group_id: UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> FormOut | None:
    """The form a prospective member must complete.

    Readable by any authenticated user: they need the questions before they
    can answer them, and a form's field labels are not member-only content.
    """
    group = await _get_group(db, group_id)
    if group.verification_form_id is None:
        return None
    return FormOut.model_validate(await _load_form(db, group.verification_form_id))


@router.put("/{group_id}/join-mode", response_model=None, status_code=status.HTTP_204_NO_CONTENT)
async def set_join_mode(
    group_id: UUID,
    body: JoinModeIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> None:
    await _require_rank(db, group_id, user.id, GroupRole.ADMIN)
    group = await _get_group(db, group_id)

    if body.verification_form_id is not None:
        await _load_form(db, body.verification_form_id)

    previous = group.join_mode
    group.join_mode = body.join_mode
    group.verification_form_id = body.verification_form_id
    group.request_expiry_days = body.request_expiry_days
    group.allow_rejoin = body.allow_rejoin
    # Keep the legacy boolean truthful for clients still reading it.
    group.join_approval_required = body.join_mode == GroupJoinMode.REQUEST_APPROVAL

    _log(
        db,
        group_id=group_id,
        action=GroupAuditAction.CHANGE_JOIN_MODE,
        performed_by=user.id,
        details={"old_mode": previous, "new_mode": body.join_mode},
    )
    await db.commit()


# ── Requesting entry (user) ───────────────────────────────────────────────────

@router.post(
    "/{group_id}/entry-request",
    response_model=RequestOut,
    status_code=status.HTTP_201_CREATED,
)
async def submit_request(
    group_id: UUID,
    body: SubmitRequestIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> RequestOut:
    group = await _get_group(db, group_id)
    await _assert_not_banned(db, group_id, user.id)

    if await _membership(db, group_id, user.id) is not None:
        raise HTTPException(
            status.HTTP_409_CONFLICT, "You are already a member of this group"
        )

    if group.join_mode == GroupJoinMode.INVITE_ONLY:
        raise HTTPException(
            status.HTTP_403_FORBIDDEN, "This group can only be joined by invite"
        )

    existing = await db.scalar(
        select(GroupJoinRequest).where(
            GroupJoinRequest.group_id == group_id,
            GroupJoinRequest.user_id == user.id,
        )
    )
    if existing is not None:
        _expire_if_due(existing)
        if existing.status == JoinRequestStatus.PENDING:
            raise HTTPException(
                status.HTTP_409_CONFLICT,
                "You already have a pending request. Please wait for admin approval.",
            )
        if existing.status == JoinRequestStatus.REJECTED and not group.allow_rejoin:
            raise HTTPException(
                status.HTTP_403_FORBIDDEN,
                "Your request was not approved and this group does not accept "
                "new requests.",
            )

    # Open groups admit immediately; the row is still written so the join is
    # visible in history rather than appearing from nowhere.
    if group.join_mode == GroupJoinMode.OPEN:
        db.add(GroupMember(
            group_id=group_id,
            user_id=user.id,
            role=GroupRole.MEMBER,
            joined_at=datetime.now(timezone.utc),
        ))
        # Same reason as the approval path: without this no existing member
        # mints a new sender key, so nobody distributes one to the arrival
        # and they see an unreadable group.
        await group_message_service.bump_epoch(db, group_id)

    cleaned: dict[str, Any] = {}
    if group.join_mode == GroupJoinMode.REQUEST_APPROVAL and group.verification_form_id:
        form = await _load_form(db, group.verification_form_id)
        try:
            cleaned = validate_answers(form.fields, body.answers)
        except FormValidationError as exc:
            raise HTTPException(
                status.HTTP_422_UNPROCESSABLE_ENTITY,
                detail={"field_errors": exc.errors},
            ) from None

    req = existing or GroupJoinRequest(group_id=group_id, user_id=user.id)
    req.message = body.message
    req.answers = cleaned
    # Snapshot the form so editing the group's active form later cannot change
    # what this request was asked.
    req.form_id = group.verification_form_id
    req.admin_notes = None
    req.rejection_reason = None
    req.decided_by_id = None
    req.decided_at = None

    if group.join_mode == GroupJoinMode.OPEN:
        req.status = JoinRequestStatus.APPROVED
        req.expires_at = None
    else:
        req.status = JoinRequestStatus.PENDING
        req.expires_at = expiry_for(group.request_expiry_days)

    if existing is None:
        db.add(req)
    await db.commit()
    await db.refresh(req)
    return RequestOut.model_validate(req)


@router.get("/{group_id}/entry-request/me", response_model=RequestOut | None)
async def my_request(
    group_id: UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> RequestOut | None:
    req = await db.scalar(
        select(GroupJoinRequest).where(
            GroupJoinRequest.group_id == group_id,
            GroupJoinRequest.user_id == user.id,
        )
    )
    if req is None:
        return None
    if _expire_if_due(req):
        await db.commit()
        await db.refresh(req)
    return RequestOut.model_validate(req)


@router.delete(
    "/{group_id}/entry-request/me",
    status_code=status.HTTP_204_NO_CONTENT,
    response_model=None,
)
async def cancel_request(
    group_id: UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> None:
    """Withdraw one's own pending request.

    Deleted rather than marked cancelled: a withdrawn request carries no
    decision to audit, and keeping it would block a fresh attempt through the
    one-request-per-group constraint.
    """
    result = await db.execute(
        delete(GroupJoinRequest).where(
            GroupJoinRequest.group_id == group_id,
            GroupJoinRequest.user_id == user.id,
            GroupJoinRequest.status.in_([
                JoinRequestStatus.PENDING,
                JoinRequestStatus.MORE_INFO_NEEDED,
            ]),
        )
    )
    if result.rowcount == 0:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "no active request")
    await db.commit()


# ── Reviewing requests (admin / moderator) ────────────────────────────────────

@router.get("/{group_id}/entry-requests", response_model=list[RequestOut])
async def list_requests(
    group_id: UUID,
    request_status: str = Query(
        default=JoinRequestStatus.PENDING.value, alias="status"
    ),
    limit: int = Query(default=50, ge=1, le=200),
    offset: int = Query(default=0, ge=0),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[RequestOut]:
    await _require_rank(db, group_id, user.id, GroupRole.MODERATOR)

    if request_status not in {s.value for s in JoinRequestStatus}:
        raise HTTPException(status.HTTP_422_UNPROCESSABLE_ENTITY, "unknown status")

    rows = list((await db.scalars(
        select(GroupJoinRequest)
        .where(GroupJoinRequest.group_id == group_id)
        .order_by(GroupJoinRequest.created_at.desc())
        .limit(limit)
        .offset(offset)
    )).all())

    # Lapsed requests are settled before filtering, so a request past its
    # window never appears in the Pending tab as if it were still actionable.
    if any(_expire_if_due(r) for r in rows):
        await db.commit()

    return [
        RequestOut.model_validate(r) for r in rows if r.status == request_status
    ]


async def _apply_decision(
    db: AsyncSession,
    *,
    req: GroupJoinRequest,
    approve: bool,
    actor: User,
    reason: str | None,
) -> None:
    req.status = (
        JoinRequestStatus.APPROVED if approve else JoinRequestStatus.REJECTED
    )
    req.decided_by_id = actor.id
    req.decided_at = datetime.now(timezone.utc)
    if not approve:
        req.rejection_reason = reason

    if approve:
        already = await _membership(db, req.group_id, req.user_id)
        if already is None:
            db.add(GroupMember(
                group_id=req.group_id,
                user_id=req.user_id,
                role=GroupRole.MEMBER,
                joined_at=datetime.now(timezone.utc),
            ))
            # Every path that adds a member has to move the epoch, and this
            # one is the product's main way in — yet it was the one that did
            # not. Without it no existing member is told to mint a new sender
            # key, so nobody distributes one to the arrival and they sit in
            # the group unable to read a single message, with nothing
            # anywhere reporting a problem.
            #
            # Bumped only when a membership is actually created: re-approving
            # someone already inside changes nothing about who holds keys,
            # and a needless rotation makes every member re-distribute.
            await group_message_service.bump_epoch(db, req.group_id)


@router.post("/{group_id}/entry-requests/{request_id}/approve", response_model=RequestOut)
async def approve_request(
    group_id: UUID,
    request_id: UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> RequestOut:
    await _require_rank(db, group_id, user.id, GroupRole.MODERATOR)
    req = await _actionable_request(db, group_id, request_id)

    await _apply_decision(db, req=req, approve=True, actor=user, reason=None)
    _log(
        db,
        group_id=group_id,
        action=GroupAuditAction.APPROVE_REQUEST,
        performed_by=user.id,
        target=req.user_id,
    )
    await db.commit()
    await db.refresh(req)
    return RequestOut.model_validate(req)


@router.post("/{group_id}/entry-requests/{request_id}/reject", response_model=RequestOut)
async def reject_request(
    group_id: UUID,
    request_id: UUID,
    body: DecisionIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> RequestOut:
    await _require_rank(db, group_id, user.id, GroupRole.MODERATOR)
    req = await _actionable_request(db, group_id, request_id)

    await _apply_decision(db, req=req, approve=False, actor=user, reason=body.reason)
    _log(
        db,
        group_id=group_id,
        action=GroupAuditAction.REJECT_REQUEST,
        performed_by=user.id,
        target=req.user_id,
        details={"reason": body.reason} if body.reason else None,
    )
    await db.commit()
    await db.refresh(req)
    return RequestOut.model_validate(req)


@router.post(
    "/{group_id}/entry-requests/{request_id}/request-info",
    response_model=RequestOut,
)
async def request_more_info(
    group_id: UUID,
    request_id: UUID,
    body: DecisionIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> RequestOut:
    await _require_rank(db, group_id, user.id, GroupRole.MODERATOR)
    req = await _actionable_request(db, group_id, request_id)

    if not body.notes:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            "Say what additional information is needed.",
        )

    req.status = JoinRequestStatus.MORE_INFO_NEEDED
    req.admin_notes = body.notes
    _log(
        db,
        group_id=group_id,
        action=GroupAuditAction.REQUEST_MORE_INFO,
        performed_by=user.id,
        target=req.user_id,
        details={"notes": body.notes},
    )
    await db.commit()
    await db.refresh(req)
    return RequestOut.model_validate(req)


async def _actionable_request(
    db: AsyncSession, group_id: UUID, request_id: UUID
) -> GroupJoinRequest:
    req = await db.scalar(
        select(GroupJoinRequest)
        .where(
            GroupJoinRequest.id == request_id,
            GroupJoinRequest.group_id == group_id,
        )
        # Locked for the transaction. Two moderators reviewing the same queue
        # and acting at the same moment would otherwise both read it as
        # pending and both approve: the unique index on (group_id, user_id)
        # turns the second insert into an integrity error, so one of them
        # gets a 500 for doing nothing wrong. With the lock the second waits
        # and then sees the decided status, which is the 409 below.
        .with_for_update()
    )
    if req is None:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "request not found")

    if _expire_if_due(req):
        await db.commit()
    if not req.is_actionable():
        # Includes the expired case: approving after the window closed would
        # defeat the purpose of having one.
        raise HTTPException(
            status.HTTP_409_CONFLICT,
            f"This request is {req.status} and can no longer be acted on.",
        )
    return req


# ── Bulk actions ──────────────────────────────────────────────────────────────

@router.post("/{group_id}/entry-requests/bulk-approve", response_model=BulkResultOut)
async def bulk_approve(
    group_id: UUID,
    body: BulkDecisionIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> BulkResultOut:
    return await _bulk(db, group_id, body, user, approve=True)


@router.post("/{group_id}/entry-requests/bulk-reject", response_model=BulkResultOut)
async def bulk_reject(
    group_id: UUID,
    body: BulkDecisionIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> BulkResultOut:
    return await _bulk(db, group_id, body, user, approve=False)


async def _bulk(
    db: AsyncSession,
    group_id: UUID,
    body: BulkDecisionIn,
    user: User,
    *,
    approve: bool,
) -> BulkResultOut:
    # Bulk power is admin-only: it is the action least likely to be reviewed
    # per-item and the most damaging to get wrong.
    await _require_rank(db, group_id, user.id, GroupRole.ADMIN)

    query = select(GroupJoinRequest).where(
        GroupJoinRequest.group_id == group_id,
        GroupJoinRequest.status.in_([
            JoinRequestStatus.PENDING,
            JoinRequestStatus.MORE_INFO_NEEDED,
        ]),
    )
    if body.request_ids:
        if len(body.request_ids) > MAX_BULK_SIZE:
            raise HTTPException(
                status.HTTP_422_UNPROCESSABLE_ENTITY,
                f"at most {MAX_BULK_SIZE} requests per bulk action",
            )
        query = query.where(GroupJoinRequest.id.in_(body.request_ids))

    # Locked for the transaction so two admins acting at once cannot both
    # approve the same request and insert duplicate memberships.
    rows = list((await db.scalars(
        query.limit(MAX_BULK_SIZE).with_for_update(skip_locked=True)
    )).all())

    settled = [r for r in rows if not _expire_if_due(r)]

    for req in settled:
        await _apply_decision(
            db, req=req, approve=approve, actor=user, reason=body.reason
        )

    _log(
        db,
        group_id=group_id,
        action=(
            GroupAuditAction.BULK_APPROVE if approve
            else GroupAuditAction.BULK_REJECT
        ),
        performed_by=user.id,
        details={"count": len(settled), "reason": body.reason},
    )
    await db.commit()

    return BulkResultOut(
        succeeded=len(settled),
        failed=len(rows) - len(settled),
        total=len(rows),
    )


# ── Bans ──────────────────────────────────────────────────────────────────────

@router.post(
    "/{group_id}/bans/{user_id}",
    response_model=BannedUserOut,
    status_code=status.HTTP_201_CREATED,
)
async def ban_from_group(
    group_id: UUID,
    user_id: UUID,
    body: BanIn,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> BannedUserOut:
    """Ban a user from this group.

    Admin-only rather than delegable: a moderator who can ban can permanently
    exclude anyone from a group they do not own.
    """
    await _require_rank(db, group_id, user.id, GroupRole.ADMIN)
    await _get_group(db, group_id)

    if user_id == user.id:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_ENTITY, "You cannot ban yourself"
        )

    target = await _membership(db, group_id, user_id)
    if target is not None and GROUP_ROLE_RANK.get(target.role, 0) >= GROUP_ROLE_RANK[
        GroupRole.ADMIN
    ]:
        # Otherwise any admin could unilaterally remove a peer or the owner.
        raise HTTPException(
            status.HTTP_403_FORBIDDEN, "You cannot ban another admin"
        )

    existing = await db.scalar(
        select(GroupBan).where(
            GroupBan.group_id == group_id, GroupBan.user_id == user_id
        )
    )
    ban = existing or GroupBan(group_id=group_id, user_id=user_id)
    ban.banned_by_id = user.id
    ban.reason = body.reason
    ban.is_permanent = body.is_permanent
    ban.expires_at = None if body.is_permanent else body.expires_at
    if existing is None:
        db.add(ban)

    # A ban also removes an existing membership; leaving them inside a group
    # they are barred from rejoining would be incoherent.
    if target is not None:
        await db.delete(target)
        # The membership row is not what keeps them out of the conversation —
        # the sender keys they already hold decrypt every future message
        # until each remaining sender mints a new one. Bumping the epoch is
        # what actually ends their access; without it a ban only removes the
        # name from the member list.
        await group_message_service.bump_epoch(db, group_id)

    # Any live request is closed too, so an admin cannot later approve someone
    # who is banned.
    await db.execute(
        delete(GroupJoinRequest).where(
            GroupJoinRequest.group_id == group_id,
            GroupJoinRequest.user_id == user_id,
        )
    )

    _log(
        db,
        group_id=group_id,
        action=GroupAuditAction.BAN_MEMBER,
        performed_by=user.id,
        target=user_id,
        details={"reason": body.reason, "permanent": body.is_permanent},
    )
    await db.commit()
    await db.refresh(ban)
    return BannedUserOut.model_validate(ban)


@router.delete(
    "/{group_id}/bans/{user_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    response_model=None,
)
async def unban_from_group(
    group_id: UUID,
    user_id: UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> None:
    """Lift a group ban.

    The user is deliberately not notified: telling someone they may reapply
    re-opens contact they may not want, so they simply find the option
    available next time they look.
    """
    await _require_rank(db, group_id, user.id, GroupRole.ADMIN)

    result = await db.execute(
        delete(GroupBan).where(
            GroupBan.group_id == group_id, GroupBan.user_id == user_id
        )
    )
    if result.rowcount == 0:
        raise HTTPException(status.HTTP_404_NOT_FOUND, "user is not banned")

    _log(
        db,
        group_id=group_id,
        action=GroupAuditAction.UNBAN_MEMBER,
        performed_by=user.id,
        target=user_id,
    )
    await db.commit()


@router.get("/{group_id}/bans", response_model=list[BannedUserOut])
async def list_bans(
    group_id: UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[BannedUserOut]:
    await _require_rank(db, group_id, user.id, GroupRole.ADMIN)
    rows = (await db.scalars(
        select(GroupBan)
        .where(GroupBan.group_id == group_id)
        .order_by(GroupBan.created_at.desc())
    )).all()
    return [BannedUserOut.model_validate(r) for r in rows]


# ── Audit log ─────────────────────────────────────────────────────────────────

@router.get("/{group_id}/audit-log", response_model=list[AuditEntryOut])
async def audit_log(
    group_id: UUID,
    action: str | None = Query(default=None),
    limit: int = Query(default=25, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[AuditEntryOut]:
    await _require_rank(db, group_id, user.id, GroupRole.ADMIN)

    query = select(GroupAuditLog).where(GroupAuditLog.group_id == group_id)
    if action:
        query = query.where(GroupAuditLog.action == action)

    rows = (await db.scalars(
        query.order_by(GroupAuditLog.created_at.desc()).limit(limit).offset(offset)
    )).all()
    return [AuditEntryOut.model_validate(r) for r in rows]


@router.get("/{group_id}/entry-requests/counts")
async def request_counts(
    group_id: UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> dict[str, int]:
    """Tab badge counts, in one query rather than one call per status."""
    await _require_rank(db, group_id, user.id, GroupRole.MODERATOR)

    rows = (await db.execute(
        select(GroupJoinRequest.status, func.count())
        .where(GroupJoinRequest.group_id == group_id)
        .group_by(GroupJoinRequest.status)
    )).all()
    counts = {s.value: 0 for s in JoinRequestStatus}
    for value, count in rows:
        counts[value] = count
    return counts
