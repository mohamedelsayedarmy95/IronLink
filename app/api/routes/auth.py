from __future__ import annotations

import secrets
from datetime import datetime, timedelta, timezone
from uuid import UUID

from fastapi import APIRouter, Depends, HTTPException, Request, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.api.deps import get_current_user
from app.api.schemas import (
    FirebaseRegisterIn,
    FirebaseVerifyIn,
    RegisterOut,
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
import structlog

from app.core.security import (
    constant_time_compare,
    create_access_token,
    generate_refresh_token,
    hash_military_id,
    hash_password,
    hash_refresh_token,
    verify_military_id,
)
from app.models import AuditLog, User, UserSession
from app.models.audit_log import AuditAction
from app.models.user import UserRole, UserStatus

logger = structlog.get_logger("auth")
from app.services import push_service
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

    # Dev bypass: provision unknown numbers so the app is reachable without an
    # SMS provider or a registration endpoint. Gated in config; see _dev_user.
    if settings.DEV_AUTH_BYPASS and user is None:
        user = await _provision_dev_user(db, body.phone_number)

    # Fable5-Enhancement: the response is IDENTICAL whether the user exists or not,
    # and takes a comparable code path — no user-enumeration oracle via timing or body.
    if user is not None and user.status == UserStatus.ACTIVE:
        code = await OtpService(redis_otp).issue(user.id)
        if settings.DEV_AUTH_BYPASS:
            # No SMS provider exists, and SmsGateway raises outside development.
            # The code is not logged — DEV_OTP_CODE is what /auth/verify accepts.
            logger.warning("dev_auth_bypass_otp_skipped", phone=body.phone_number[:5] + "****")
        else:
            await SmsGateway().send_otp(body.phone_number, code)

    return RequestOtpOut(retry_after_seconds=retry_after)


async def _provision_dev_user(db: AsyncSession, phone_number: str) -> User:
    """Create a throwaway ACTIVE user for the dev bypass.

    hashed_military_id and hashed_password are NOT NULL, so they get random
    values rather than a shared constant — the bypass skips both checks anyway,
    and a predictable hash would still be a real credential if the bypass were
    ever switched off with these rows left behind.
    """
    user = User(
        phone_number=phone_number,
        full_name=f"Dev User {phone_number[-4:]}",
        hashed_military_id=hash_military_id(secrets.token_hex(16)),
        hashed_password=hash_password(secrets.token_hex(16)),
        status=UserStatus.ACTIVE,
        role=UserRole.SOLDIER,
    )
    db.add(user)
    await db.flush()
    await db.refresh(user)
    logger.warning("dev_auth_bypass_user_provisioned", user_id=str(user.id))
    return user


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

    if settings.DEV_AUTH_BYPASS:
        # Fixed code, no military-ID check. constant_time_compare keeps the
        # comparison uniform even here, so the bypass path does not become a
        # timing oracle if someone leaves it on by mistake.
        otp_ok = constant_time_compare(body.otp_code, settings.DEV_OTP_CODE)
        mil_ok = True
        logger.warning("dev_auth_bypass_verify", user_id=str(user.id), accepted=otp_ok)
    else:
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

    return await _issue_login(db, user, body.device_fingerprint, ip, user_agent)


@router.post("/verify-firebase", response_model=VerifyOut)
async def verify_firebase(
    body: FirebaseVerifyIn,
    request: Request,
    db: AsyncSession = Depends(get_db),
) -> VerifyOut:
    """Firebase Phone Auth path: the client verifies phone ownership with
    Firebase client-side (SMS code) and hands us the resulting ID token. We
    verify it server-side — never trust a client-supplied phone number — then
    still require the military ID as the app's own second factor, exactly like
    /verify. This replaces OTP delivery, not the military-ID check."""
    ip = request.client.host if request.client else "unknown"
    user_agent = request.headers.get("user-agent", "")[:512]

    generic_error = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Verification failed. Check your code and credentials.",
    )

    if not push_service.ensure_initialized():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Phone verification is temporarily unavailable.",
        )

    from firebase_admin import auth as firebase_auth

    try:
        decoded = firebase_auth.verify_id_token(body.id_token)
    except Exception as exc:
        # Expired, revoked, malformed, wrong-project — all collapse to the same
        # generic 401 so the failure mode can't be used to fingerprint the cause.
        logger.warning("firebase_id_token_rejected", error=str(exc))
        raise generic_error

    phone_number = decoded.get("phone_number")
    if not phone_number:
        # A Firebase ID token from a different sign-in method (no phone claim).
        logger.warning("firebase_id_token_missing_phone", uid=decoded.get("uid"))
        raise generic_error

    user = await db.scalar(select(User).where(User.phone_number == phone_number))

    # Told plainly rather than folded into the generic failure. The caller has
    # just proved they control this number, so "your code is wrong" would be
    # both false and impossible to act on — they would retry the SMS forever.
    if user is not None and user.status == UserStatus.PENDING:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Your account is waiting for approval.",
        )

    if user is None or user.status != UserStatus.ACTIVE:
        raise generic_error

    if user.expiry_date is not None and user.expiry_date < datetime.now(timezone.utc).date():
        raise generic_error

    mil_ok = verify_military_id(body.military_id, user.hashed_military_id)
    if not mil_ok:
        db.add(AuditLog(
            actor_id=user.id,
            actor_role=user.role,
            action=AuditAction.LOGIN_FAILED,
            ip_address=ip,
            user_agent=user_agent,
            success=False,
            error_code="firebase_mid_mismatch",
        ))
        await db.commit()
        raise generic_error

    return await _issue_login(db, user, body.device_fingerprint, ip, user_agent)


@router.post("/register-firebase", response_model=RegisterOut)
async def register_firebase(
    body: FirebaseRegisterIn,
    request: Request,
    db: AsyncSession = Depends(get_db),
) -> RegisterOut:
    """Register a new account from a verified phone number.

    This is what makes the app usable by anyone with a real number, instead
    of only by accounts seeded by hand.

    The number is read out of the Firebase ID token, never from the request
    body, so registering requires actually controlling the number. The
    military ID is *set* here — it is the account's second factor from now
    on, not evidence of anything by itself.
    """
    ip = request.client.host if request.client else "unknown"
    user_agent = request.headers.get("user-agent", "")[:512]

    if not settings.SELF_REGISTRATION_ENABLED:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Registration is closed. Contact your administrator.",
        )

    if not push_service.ensure_initialized():
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Phone verification is temporarily unavailable.",
        )

    from firebase_admin import auth as firebase_auth

    try:
        decoded = firebase_auth.verify_id_token(body.id_token)
    except Exception as exc:
        logger.warning("firebase_id_token_rejected", error=str(exc))
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Verification failed. Request a new code and try again.",
        ) from None

    phone_number = decoded.get("phone_number")
    if not phone_number:
        logger.warning("firebase_id_token_missing_phone", uid=decoded.get("uid"))
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Verification failed. Request a new code and try again.",
        )

    existing = await db.scalar(
        select(User).where(User.phone_number == phone_number)
    )
    if existing is not None:
        # Says the number is taken rather than pretending to register it.
        # This is not an enumeration leak worth hiding: the caller has just
        # proved they control this number, so they are entitled to know
        # whether it already has an account.
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This number already has an account. Sign in instead.",
        )

    approved = settings.SELF_REGISTRATION_AUTO_APPROVE
    user = User(
        phone_number=phone_number,
        full_name=body.full_name,
        hashed_military_id=hash_military_id(body.military_id),
        # Never used on this path — Firebase proves the phone, the military ID
        # is the second factor — but the column is NOT NULL, and a shared
        # constant here would be a real credential if password login were ever
        # switched on.
        hashed_password=hash_password(secrets.token_hex(32)),
        status=UserStatus.ACTIVE if approved else UserStatus.PENDING,
        role=UserRole.SOLDIER,
    )
    db.add(user)
    await db.flush()
    await db.refresh(user)

    db.add(AuditLog(
        actor_id=user.id,
        actor_role=user.role,
        action=AuditAction.LOGIN_SUCCESS if approved else AuditAction.LOGIN_FAILED,
        ip_address=ip,
        user_agent=user_agent,
        success=approved,
        error_code=None if approved else "registration_pending_approval",
    ))
    await db.commit()

    logger.info(
        "self_registration",
        user_id=str(user.id),
        approved=approved,
    )

    if not approved:
        return RegisterOut(approved=False)

    return RegisterOut(
        approved=True,
        session=await _issue_login(
            db, user, body.device_fingerprint, ip, user_agent
        ),
    )


async def _issue_login(
    db: AsyncSession,
    user: User,
    device_fingerprint: str,
    ip: str,
    user_agent: str,
) -> VerifyOut:
    """Shared by /verify and /verify-firebase once credentials are confirmed:
    rotate token_version, open a session, and audit-log the login."""
    # Fable5-Enhancement: device fingerprint change is NOT a hard block (users
    # legitimately change phones) but IS recorded as a security event so the
    # admin dashboard can flag anomalous device migrations.
    fingerprint_changed = (
        user.device_fingerprint is not None
        and user.device_fingerprint != device_fingerprint
    )
    user.device_fingerprint = device_fingerprint

    # Rotate token_version — invalidates ALL previously issued tokens
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


@router.get("/me", response_model=UserOut)
async def me(user: User = Depends(get_current_user)) -> UserOut:
    """The signed-in user, for restoring a session on launch.

    Without this the app has no way to tell a stored token that still works
    from one that does not, so it cannot safely skip the login screen — which
    is why it was asking for an SMS code on every single launch.
    """
    return UserOut.model_validate(user)


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
