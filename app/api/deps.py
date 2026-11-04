from __future__ import annotations

from uuid import UUID

from fastapi import Depends, HTTPException, status, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import decode_access_token
from app.core.session_auth import SessionIdentity, SessionInvalid, authenticated_session
from app.models import User, UserSession

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

    try:
        user, session = await authenticated_session(
            db, SessionIdentity(user_id, session_id, token_version)
        )
    except SessionInvalid:
        raise _CREDENTIALS_ERROR from None

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
