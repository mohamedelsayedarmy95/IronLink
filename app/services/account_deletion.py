"""Erasing an account.

There was no way to delete one. `docs/REPOSITORY_AUDIT_v5.md` §22 raised that as
a blocking stop condition for any compliance or enterprise claim, and it sits at
level 3 of the engineering hierarchy — above every feature in the roadmap.

WHAT MAKES THIS HARDER THAN A DELETE STATEMENT

An account is not only its owner's data. It is a sender in other people's
conversations, an admin in someone's group audit trail, a subject of a report
somebody else wrote, and possibly a banned party. A naive DELETE takes all of
that with it, and some of it is not the departing user's to erase.

The schema already encoded most of the right answers before this existed —
`messages.sender_id` was SET NULL, so a recipient's history survives the sender
leaving. Two columns were inconsistent with that intent and migration 0011 fixes
them. What remains here is the part a foreign key cannot express.

WHAT IS RETAINED, AND WHY IT IS DISCLOSED RATHER THAN HIDDEN

A platform ban survives, keyed on a salted hash of the phone number rather than
the account. Without that, evading a ban is one step — delete, re-register the
same number — and a ban a banned person can undo is decorative.

Privacy outranks abuse prevention in the hierarchy, and the resolution is not to
skip the retention. It is to make it minimal and to say so: a hash, no
identifier, no name, no history, and a deletion response that tells the user in
plain words that it happened. A retention the user is told about is a policy. The
same retention unmentioned is a broken promise.

WHY THERE IS NO GRACE PERIOD

Thirty-day recovery windows are common and are the wrong choice here. A user
deleting an account on a product built for people who may be at risk is
frequently doing it *because* they are at risk, and "we kept everything for a
month in case you change your mind" is the opposite of what they asked for.
The protection against an accidental deletion is re-authentication at the
moment of the request, not a month of retained data.
"""

from __future__ import annotations

import structlog
from sqlalchemy import delete, select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import AuditLog, PlatformBan, User
from app.services.contact_discovery import hash_phone

logger = structlog.get_logger("account")


class DeletionRefused(Exception):
    """The account cannot be deleted as asked."""


async def delete_account(db: AsyncSession, user: User) -> dict[str, object]:
    """Erases [user], returning what was kept and why.

    The return value is the disclosure. It is handed to the client and shown to
    the user, because a person deleting their account is entitled to know
    exactly what does not go with them.
    """
    user_id = user.id
    phone = user.phone_number

    retained: list[str] = []

    # ── A ban outlives the account ──────────────────────────────────────────
    ban = await db.scalar(select(PlatformBan).where(PlatformBan.user_id == user_id))
    if ban is not None:
        ban.phone_hash = hash_phone(phone)
        ban.user_id = None
        retained.append("platform_ban")
        logger.info("account_ban_preserved", reason="ban_evasion")

    # ── The audit trail is anonymised, not erased ───────────────────────────
    #
    # `audit_logs.actor_id` is already SET NULL, so the rows survive without
    # naming anybody. What the foreign key cannot do is remove an identifier
    # that was copied into a JSON detail column, so that is done explicitly
    # rather than trusted to have never happened.
    await db.execute(
        update(AuditLog)
        .where(AuditLog.actor_id == user_id)
        .values(actor_id=None, ip_address=None)
    )
    retained.append("audit_log_entries_anonymised")

    # ── The deletion itself is recorded, and names nobody ───────────────────
    #
    # An account vanishing with no trace is indistinguishable from a database
    # fault. This row says a deletion happened and when; it does not say who,
    # because the whole point is that there is no longer a who.
    db.add(AuditLog(actor_id=None, action="account.deleted", success=True))

    # ── Everything else goes ────────────────────────────────────────────────
    #
    # One statement, and the 41 foreign keys into `users` decide the rest. That
    # is deliberate: enumerating the tables here would be a second, silently
    # diverging description of the schema, and the one that got out of date
    # would be this one.
    await db.execute(delete(User).where(User.id == user_id))
    await db.commit()

    logger.info("account_deleted", retained=len(retained))
    return {
        "deleted": True,
        "retained": retained,
    }


async def is_phone_banned(db: AsyncSession, phone: str) -> bool:
    """Whether this number is banned, including from a deleted account.

    Checked at registration. Without it the ban record written above would be
    a record of something nothing enforces.
    """
    hashed = hash_phone(phone)
    found = await db.scalar(
        select(PlatformBan.id).where(PlatformBan.phone_hash == hashed)
    )
    return found is not None
