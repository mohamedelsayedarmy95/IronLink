from __future__ import annotations

from datetime import datetime, timezone
from uuid import UUID

from fastapi import Depends, HTTPException, status, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import decode_access_token
from app.models import User, UserSession
from app.models.user import UserStatus

_bearer = HTTPBearer(auto_error=False)

_CREDENTIALS_ERROR = HTTPException(
    status_code=status.HTTP_401_UNAUTHORIZED,
    detail="Invalid or expired credentials",
    headers={"WWW-Authenticate": "Bearer"},
)


async def get_current_user(
    request: Request,
    creds: HTTPAuthorizationCredentials | None = Depends(_bearer),
    db: AsyncSession = Depends(get_db),
) -> User:
    if creds is None:
        raise _CREDENTIALS_ERROR

    payload = decode_access_token(creds.credentials)
    if payload is None:
        raise _CREDENTIALS_ERROR

    try:
        user_id = UUID(payload["sub"])
        token_version = int(payload["ver"])
        session_id = UUID(payload["sid"])
    except (KeyError, ValueError, TypeError):
        # A token with no `sid` predates session binding. Rejected rather than
        # accepted for compatibility: honouring it would reopen the hole where
        # a revoked device stays authenticated, and the cost is one re-login.
        raise _CREDENTIALS_ERROR

    user = await db.scalar(select(User).where(User.id == user_id))
    if user is None or user.status != UserStatus.ACTIVE:
        raise _CREDENTIALS_ERROR

    # token_version check: any token minted before a forced logout carries an
    # older version and is rejected here. This is the account-wide lever.
    if token_version != user.token_version:
        raise _CREDENTIALS_ERROR

    # Session check: the per-device lever. Without this, revoking a session
    # did nothing to requests — the kicked device kept working until its
    # token expired on its own.
    session = await db.scalar(
        select(UserSession).where(
            UserSession.id == session_id,
            UserSession.user_id == user.id,
            UserSession.revoked_at.is_(None),
            UserSession.expires_at > datetime.now(timezone.utc),
        )
    )
    if session is None:
        raise _CREDENTIALS_ERROR

    # Stashed on the request so a route that needs the *device* rather than
    # the account can reach it without decoding the token a second time.
    # Request state rather than an attribute on the model: the model instance
    # is attached to a database session, and hanging request-scoped data off it
    # is how something eventually gets flushed that was never a column.
    request.state.session = session
    return user


async def get_current_session(
    request: Request,
    _: User = Depends(get_current_user),
) -> UserSession:
    """The session the caller is authenticated on — that is, this device.

    Separate from `get_current_user` because most routes act on an account and
    a few act on a device. Push registration is the second kind: a token
    belongs to one installation, and storing it on the account is why a second
    device silently stopped the first one receiving notifications.
    """
    return request.state.session
