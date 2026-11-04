"""The shared authoritative session policy for HTTP and WebSockets."""
from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone
import json
from uuid import UUID

from sqlalchemy import or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import User, UserSession
from app.models.user import UserStatus


class SessionInvalid(Exception):
    """No usable authenticated session; contains no supplied credentials."""


@dataclass(frozen=True)
class SessionIdentity:
    user_id: UUID
    session_id: UUID
    token_version: int

    def ticket_value(self) -> str:
        return json.dumps({'user_id': str(self.user_id), 'session_id': str(self.session_id),
                           'token_version': self.token_version})

    @classmethod
    def from_ticket(cls, value: str) -> SessionIdentity:
        try:
            data = json.loads(value)
            if not isinstance(data, dict) or set(data) != {'user_id', 'session_id', 'token_version'}:
                raise ValueError
            version = data['token_version']
            if type(version) is not int or version < 1:
                raise ValueError
            return cls(UUID(data['user_id']), UUID(data['session_id']), version)
        except (ValueError, TypeError, KeyError, AttributeError):
            raise SessionInvalid() from None


async def authenticated_session(db: AsyncSession, identity: SessionIdentity) -> tuple[User, UserSession]:
    """A fresh READ COMMITTED statement is the authorization linearization point.

    No positive session cache. Work authorized before a concurrent revoke commits
    may finish; a check starting after that commit cannot authorize it. The same
    policy applies immediately before each protected WebSocket send.
    """
    now = datetime.now(timezone.utc)
    row = (await db.execute(
        select(User, UserSession).join(UserSession, UserSession.user_id == User.id).where(
            User.id == identity.user_id,
            User.status == UserStatus.ACTIVE,
            User.token_version == identity.token_version,
            or_(User.expiry_date.is_(None), User.expiry_date >= now.date()),
            UserSession.id == identity.session_id,
            UserSession.revoked_at.is_(None),
            UserSession.expires_at > now,
        ).execution_options(populate_existing=True)
    )).one_or_none()
    if row is None:
        raise SessionInvalid()
    return row[0], row[1]
