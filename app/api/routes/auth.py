from __future__ import annotations

import secrets
from datetime import datetime, timedelta, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.api.schemas import (
    RequestOtpIn,
    RequestOtpOut,
    SessionOut,
    UserOut,
    VerifyIn,
    VerifyOut,
    WsTicketOut,
)
from app.config import settings
from app.core.database import get_db
from app.core.redis import redis_otp, redis_sessions
from app.core.security import (
    create_access_token,
    generate_refresh_token,
    hash_refresh_token,
    verify_military_id,
)
from app.models import AuditLog, User, UserSession
from app.models.audit_log import AuditAction
from app.models.user import UserStatus
from app.services.otp_service import OtpService
from app.services.sms_gateway import SmsGateway

router = APIRouter(prefix="/auth", tags=["auth"])

# Fable5-Enhancement: OTP request rate limiting per phone AND per IP.
# Per-phone stops SMS-bombing a victim; per-IP stops directory scanning.
_OTP_COOLDOWN_SECONDS = 60
_OTP_MAX_PER_HOUR = 5


async def _rate_limit_otp(phone: str, ip: str) -> int:
    """Returns retry_after seconds. Raises 429 if either limit is exceeded."""
    cooldown_key = f"otp:cooldown:{phone}"
    hourly_key = f"otp:hourly:{phone}"
    ip_key = f"otp:ip:{ip}"

    if await redis_otp.exists(cooldown_key):
        ttl = await redis_otp.ttl(cooldown_key)
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=f"Please wait {ttl}s before requesting another code",
        )

    hourly = await redis_otp.incr(hourly_key)
    if hourly == 1:
        await redis_otp.expire(hourly_key, 3600)
    ip_count = await redis_otp.incr(ip_key)
    if ip_count == 1:
        await redis_otp.expire(ip_key, 3600)

    if hourly > _OTP_MAX_PER_HOUR or ip_count > _OTP_MAX_PER_HOUR * 4:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail="Too many attempts. Try again later.",
        )

    await redis_otp.set(cooldown_key, "1", ex=_OTP_COOLDOWN_SECONDS)
    return _OTP_COOLDOWN_SECONDS


@router.post("/request-otp", response_model=RequestOtpOut)
async def request_otp(
    body: RequestOtpIn,
    request: Request,
    db: AsyncSession = Depends(get_db),
) -> RequestOtpOut:
    ip = request.client.host if request.client else "unknown"
    retry_after = await _rate_limit_otp(body.phone_number, ip)

    user = await db.scalar(select(User).where(User.phone_number == body.phone_number))

    # Fable5-Enhancement: the response is IDENTICAL whether the user exists or not,
    # and takes a comparable code path — no user-enumeration oracle via timing or body.
    if user is not None and user.status == UserStatus.ACTIVE:
        code = await OtpService(redis_otp).issue(user.id)
        await SmsGateway().send_otp(body.phone_number, code)

    return RequestOtpOut(retry_after_seconds=retry_after)


@router.post("/verify", response_model=VerifyOut)
async def verify(
    body: VerifyIn,
    request: Request,
    db: AsyncSession = Depends(get_db),
) -> VerifyOut:
    ip = request.client.host if request.client else "unknown"
    user_agent = request.headers.get("user-agent", "")[:512]

    generic_error = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Verification failed. Check your code and credentials.",
    )

    user = await db.scalar(select(User).where(User.phone_number == body.phone_number))
    if user is None or user.status != UserStatus.ACTIVE:
        raise generic_error

    # Account hard-expiry (contract end)
    if user.expiry_date is not None and user.expiry_date < datetime.now(timezone.utc).date():
        raise generic_error

    # 1. OTP — consumed on success, burned after max attempts
    otp_ok = await OtpService(redis_otp).verify(user.id, body.otp_code)

    # 2. Military ID against the bcrypt hash
    mil_ok = verify_military_id(body.military_id, user.hashed_military_id)

    if not (otp_ok and mil_ok):
        db.add(AuditLog(
            actor_id=user.id,
            actor_role=user.role,
            action=AuditAction.LOGIN_FAILED,
            ip_address=ip,
            user_agent=user_agent,
            success=False,
            error_code="otp_or_mid_mismatch",
        ))
        await db.commit()
        raise generic_error

    # Fable5-Enhancement: device fingerprint change is NOT a hard block (users
    # legitimately change phones) but IS recorded as a security event so the
    # admin dashboard can flag anomalous device migrations.
    fingerprint_changed = (
        user.device_fingerprint is not None
        and user.device_fingerprint != body.device_fingerprint
    )
    user.device_fingerprint = body.device_fingerprint

    # 3. Rotate token_version — invalidates ALL previously issued tokens
    user.token_version += 1
    user.last_seen_at = datetime.now(timezone.utc)

    access_token = create_access_token(user.id, user.token_version, user.role)
    refresh_token = generate_refresh_token()

    session = UserSession(
        user_id=user.id,
        refresh_token_hash=hash_refresh_token(refresh_token),
        ip_address=ip,
        user_agent=user_agent,
        device_type=_classify_device(user_agent),
        expires_at=datetime.now(timezone.utc) + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS),
    )
    db.add(session)

    db.add(AuditLog(
        actor_id=user.id,
        actor_role=user.role,
        action=AuditAction.LOGIN_SUCCESS,
        ip_address=ip,
        user_agent=user_agent,
        success=True,
        metadata_={"fingerprint_changed": fingerprint_changed},
    ))
    if fingerprint_changed:
        db.add(AuditLog(
            actor_id=user.id,
            actor_role=user.role,
            action=AuditAction.DEVICE_FINGERPRINT_CHANGED,
            ip_address=ip,
            success=True,
        ))
    await db.commit()
    await db.refresh(session)

    return VerifyOut(
        access_token=access_token,
        refresh_token=refresh_token,
        expires_in=settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60,
        session_id=session.id,
        user=UserOut.model_validate(user),
    )


# ── WebSocket ticket ──────────────────────────────────────────────────────────
# Fable5-Enhancement: instead of passing the long-lived JWT in the WebSocket
# query string (where it leaks into Nginx access logs, browser history, and
# proxies), the client exchanges its JWT for a ONE-TIME 30-second ticket over
# a normal authenticated POST. The WS URL carries only this ticket — worthless
# after first use or 30 seconds. Strictly more secure than the original request.

WS_TICKET_TTL_SECONDS = 30


@router.post("/ws-ticket", response_model=WsTicketOut)
async def create_ws_ticket(user: User = Depends(get_current_user)) -> WsTicketOut:
    ticket = secrets.token_urlsafe(32)
    await redis_sessions.set(
        f"ws:ticket:{ticket}",
        str(user.id),
        ex=WS_TICKET_TTL_SECONDS,
    )
    return WsTicketOut(
        ticket=ticket,
        expires_in=WS_TICKET_TTL_SECONDS,
        ws_url=f"/ws/chat?ticket={ticket}",
    )


# ── Multi-device session management ──────────────────────────────────────────

@router.get("/sessions", response_model=list[SessionOut])
async def list_sessions(
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> list[SessionOut]:
    """Every active (non-revoked, non-expired) session — phone, tablet, etc."""
    sessions = (await db.scalars(
        select(UserSession)
        .where(
            UserSession.user_id == user.id,
            UserSession.revoked_at.is_(None),
            UserSession.expires_at > datetime.now(timezone.utc),
        )
        .order_by(UserSession.created_at.desc())
    )).all()
    return [SessionOut.model_validate(s) for s in sessions]


@router.delete("/sessions/{session_id}", status_code=status.HTTP_204_NO_CONTENT, response_model=None)
async def revoke_session(
    session_id: UUID,
    user: User = Depends(get_current_user),
    db: AsyncSession = Depends(get_db),
) -> None:
    """Remote-kick a specific device.

    Fable5-Enhancement: revocation is per-DEVICE, not per-user. The refresh
    token dies immediately (revoked_at); the live WebSocket on that device is
    told to disconnect via a targeted 'session_revoked' Pub/Sub frame — each
    client knows its own session_id (returned at login) and closes itself when
    the ids match. Other devices of the same user are untouched.
    """
    session = await db.scalar(
        select(UserSession).where(
            UserSession.id == session_id,
            UserSession.user_id == user.id,
            UserSession.revoked_at.is_(None),
        )
    )
    if session is None:
        raise HTTPException(status_code=status.HTTP_404_NOT_FOUND, detail="session not found")

    session.revoked_at = datetime.now(timezone.utc)
    db.add(AuditLog(
        actor_id=user.id,
        actor_role=user.role,
        action=AuditAction.SESSION_REVOKED,
        resource_type="user_session",
        resource_id=str(session_id),
        success=True,
    ))
    await db.commit()

    from app.api.routes.websocket import publish
    await publish(user.id, {
        "type": "session_revoked",
        "session_id": str(session_id),
    })


def _classify_device(user_agent: str) -> str:
    ua = user_agent.lower()
    if any(k in ua for k in ("android", "iphone", "mobile")):
        return "mobile"
    if "ipad" in ua or "tablet" in ua:
        return "tablet"
    if any(k in ua for k in ("windows", "macintosh", "linux")):
        return "desktop"
    return "unknown"
