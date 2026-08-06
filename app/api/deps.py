from __future__ import annotations

from uuid import UUID

from fastapi import Depends, HTTPException, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.database import get_db
from app.core.security import decode_access_token
from app.models import User
from app.models.user import UserStatus

_bearer = HTTPBearer(auto_error=False)

_CREDENTIALS_ERROR = HTTPException(
    status_code=status.HTTP_401_UNAUTHORIZED,
    detail="Invalid or expired credentials",
    headers={"WWW-Authenticate": "Bearer"},
)


async def get_current_user(
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
    except (KeyError, ValueError):
        raise _CREDENTIALS_ERROR

    user = await db.scalar(select(User).where(User.id == user_id))
    if user is None or user.status != UserStatus.ACTIVE:
        raise _CREDENTIALS_ERROR

    # token_version check: any token minted before the last login / forced
    # logout carries an older version and is rejected here.
    if token_version != user.token_version:
        raise _CREDENTIALS_ERROR

    return user
