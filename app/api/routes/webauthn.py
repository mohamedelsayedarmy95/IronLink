from __future__ import annotations

from datetime import datetime, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession
from webauthn.helpers import bytes_to_base64url

from app.api.deps import get_current_user
from app.api.routes.auth import _issue_login
from app.api.schemas import (
    VerifyOut,
    WebAuthnAuthenticateCompleteIn,
    WebAuthnCredentialOut,
    WebAuthnOptionsOut,
    WebAuthnRegisterCompleteIn,
)
from app.core.database import get_db
from app.core.redis import redis_otp
from app.models import AuditLog, User, WebAuthnCredential
from app.models.audit_log import AuditAction
from app.models.user import UserStatus
from app.services.webauthn_service import (
    AuthenticationResult,
    WebAuthnDuplicateCredential,
    WebAuthnError,
    WebAuthnService,
)

router = APIRouter(prefix="/auth/webauthn", tags=["webauthn"])

_AUTHENTICATION_FAILED = HTTPException(
    status_code=status.HTTP_401_UNAUTHORIZED,
    detail="Authentication failed.",
)
_REGISTRATION_FAILED = HTTPException(
    status_code=status.HTTP_401_UNAUTHORIZED,
    detail="Registration failed. Start again.",
)


def _client_context(request: Request) -> tuple[str, str]:
    ip = request.client.host if request.client else "unknown"
    user_agent = request.headers.get("user-agent", "")[:512]
    return ip, user_agent


def _audit(
    db: AsyncSession,
    *,
    user: User,
    action: AuditAction,
    request: Request,
    success: bool,
    error_code: str | None = None,
    resource_id: str | None = None,
    metadata: dict | None = None,
) -> None:
    ip, user_agent = _client_context(request)
    payload = {"method": "webauthn"}
    if metadata:
        payload.update(metadata)
    db.add(
        AuditLog(
            actor_id=user.id,
            actor_role=user.role,
            action=action,
            resource_type="webauthn_credential",
            resource_id=resource_id,
            ip_address=ip,
            user_agent=user_agent,
            success=success,
            error_code=error_code[:50] if error_code else None,
            metadata_=payload,
        )
    )


def _credential_out(row: WebAuthnCredential) -> WebAuthnCredentialOut:
    return WebAuthnCredentialOut(
        id=row.id,
        credential_id=bytes_to_base64url(row.credential_id),
        nickname=row.nickname,
        aaguid=row.aaguid,
        credential_type=row.credential_type,
        sign_count=row.sign_count,
        transports=list(row.transports or []),
        user_verified=bool(row.user_verified),
        backup_eligible=bool(row.backup_eligible),
        backup_state=bool(row.backup_state),
        created_at=row.created_at,
        last_used_at=row.last_used_at,
    )


def _record_authentication(result: AuthenticationResult) -> None:
    """Apply the verified counter and backup state after status checks pass."""
    row = result.credential
    row.sign_count = result.new_sign_count
    row.last_used_at = datetime.now(timezone.utc)
    row.user_verified = result.user_verified
    row.backup_eligible = result.backup_eligible
    row.backup_state = result.backup_state


@router.post("/register/begin", response_model=WebAuthnOptionsOut)
async def begin_webauthn_registration(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> WebAuthnOptionsOut:
    """Start enrolling a hardware key for the signed-in account.

    Authentication is required because this binds a new credential to the
    caller. The ceremony is bound to the caller's id server-side, so a
    challenge issued to one account cannot be completed by another.
    """
    service = WebAuthnService(redis_otp, db)
    ceremony = await service.begin_registration(user)
    return WebAuthnOptionsOut(
        ceremony_id=ceremony.ceremony_id,
        expires_in=ceremony.expires_in,
        options=ceremony.options,
    )


@router.post(
    "/register/complete",
    response_model=WebAuthnCredentialOut,
    status_code=status.HTTP_201_CREATED,
)
async def complete_webauthn_registration(
    body: WebAuthnRegisterCompleteIn,
    request: Request,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> WebAuthnCredentialOut:
    """Verify the attestation and store the public credential.

    The challenge is consumed before verification, so a failed attempt cannot
    be retried with a different attestation against the same ceremony. The
    client must start a fresh ceremony after any failure.
    """
    service = WebAuthnService(redis_otp, db)
    try:
        row = await service.finish_registration(
            user,
            body.ceremony_id,
            body.credential,
            body.nickname,
        )
        _audit(
            db,
            user=user,
            action=AuditAction.WEBAUTHN_REGISTERED,
            request=request,
            success=True,
            resource_id=str(row.id),
        )
        await db.commit()
    except WebAuthnDuplicateCredential as exc:
        await db.rollback()
        _audit(
            db,
            user=user,
            action=AuditAction.WEBAUTHN_REGISTRATION_FAILED,
            request=request,
            success=False,
            error_code=exc.reason,
            resource_id=(
                str(exc.credential.id)
                if exc.credential is not None and exc.credential.id is not None
                else None
            ),
        )
        await db.commit()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This security key is already registered.",
        )
    except IntegrityError:
        # A concurrent registration can pass the SELECT and lose the unique
        # constraint race. The database is the final arbiter; report the same
        # conflict rather than a 500.
        await db.rollback()
        _audit(
            db,
            user=user,
            action=AuditAction.WEBAUTHN_REGISTRATION_FAILED,
            request=request,
            success=False,
            error_code="credential_already_registered",
        )
        await db.commit()
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This security key is already registered.",
        )
    except WebAuthnError as exc:
        await db.rollback()
        _audit(
            db,
            user=user,
            action=AuditAction.WEBAUTHN_REGISTRATION_FAILED,
            request=request,
            success=False,
            error_code=exc.reason,
            resource_id=(
                str(exc.credential.id)
                if exc.credential is not None and exc.credential.id is not None
                else None
            ),
        )
        await db.commit()
        raise _REGISTRATION_FAILED

    return _credential_out(row)


@router.post("/authenticate/begin", response_model=WebAuthnOptionsOut)
async def begin_webauthn_authentication(
    db: AsyncSession = Depends(get_db),
) -> WebAuthnOptionsOut:
    """Start a usernameless login ceremony.

    No account identifier is accepted or returned. The options deliberately
    carry an empty `allowCredentials` list, so this endpoint cannot be used to
    discover whether a phone number has a registered hardware key.
    """
    service = WebAuthnService(redis_otp, db)
    ceremony = await service.begin_authentication()
    return WebAuthnOptionsOut(
        ceremony_id=ceremony.ceremony_id,
        expires_in=ceremony.expires_in,
        options=ceremony.options,
    )


@router.post("/authenticate/complete", response_model=VerifyOut)
async def complete_webauthn_authentication(
    body: WebAuthnAuthenticateCompleteIn,
    request: Request,
    db: AsyncSession = Depends(get_db),
) -> VerifyOut:
    """Verify a discoverable-credential assertion and open a session.

    Every failure — expired challenge, unknown credential, wrong user handle,
    bad signature, counter regression, suspended account — returns the same
    401. Only the signed assertion identifies the account; the request never
    carries a phone number or user id.
    """
    service = WebAuthnService(redis_otp, db)
    try:
        result = await service.finish_authentication(
            body.ceremony_id, body.credential
        )
    except WebAuthnError as exc:
        if exc.user is not None:
            _audit(
                db,
                user=exc.user,
                action=AuditAction.LOGIN_FAILED,
                request=request,
                success=False,
                error_code=exc.reason,
                metadata={"auth_method": "webauthn"},
                resource_id=(
                    str(exc.credential.id)
                    if exc.credential is not None
                    and exc.credential.id is not None
                    else None
                ),
            )
            await db.commit()
        raise _AUTHENTICATION_FAILED

    user = result.user
    expired = (
        user.expiry_date is not None
        and user.expiry_date < datetime.now(timezone.utc).date()
    )
    if user.status != UserStatus.ACTIVE or expired:
        _audit(
            db,
            user=user,
            action=AuditAction.LOGIN_FAILED,
            request=request,
            success=False,
            error_code="inactive_or_expired",
            metadata={"auth_method": "webauthn"},
            resource_id=str(result.credential.id),
        )
        await db.commit()
        raise _AUTHENTICATION_FAILED

    _record_authentication(result)
    ip, user_agent = _client_context(request)
    return await _issue_login(
        db,
        user,
        body.device_fingerprint,
        ip,
        user_agent,
        auth_method="webauthn",
    )


@router.get("/credentials", response_model=list[WebAuthnCredentialOut])
async def list_webauthn_credentials(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[WebAuthnCredentialOut]:
    """List the caller's registered keys, newest first."""
    service = WebAuthnService(redis_otp, db)
    rows = await service.list_credentials(user)
    return [_credential_out(row) for row in rows]


@router.delete(
    "/credentials/{credential_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    response_model=None,
)
async def delete_webauthn_credential(
    credential_id: UUID,
    request: Request,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> None:
    """Remove one of the caller's keys. Another registered key may remain."""
    service = WebAuthnService(redis_otp, db)
    try:
        row = await service.remove_credential(user, credential_id)
    except WebAuthnError:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Security key not found.",
        )

    _audit(
        db,
        user=user,
        action=AuditAction.WEBAUTHN_CREDENTIAL_REMOVED,
        request=request,
        success=True,
        resource_id=str(row.id),
    )
    await db.commit()
    return None
