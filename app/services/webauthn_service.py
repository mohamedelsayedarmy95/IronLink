from __future__ import annotations

import json
import secrets
from dataclasses import dataclass
from typing import Any
from uuid import UUID

from redis.asyncio import Redis
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from webauthn import (
    generate_authentication_options,
    generate_registration_options,
    options_to_json,
    verify_authentication_response,
    verify_registration_response,
)
from webauthn.helpers import (
    base64url_to_bytes,
    bytes_to_base64url,
    parse_authentication_credential_json,
)
from webauthn.helpers.structs import (
    AttestationConveyancePreference,
    AuthenticatorAttachment,
    AuthenticatorSelectionCriteria,
    CredentialDeviceType,
    PublicKeyCredentialDescriptor,
    ResidentKeyRequirement,
    UserVerificationRequirement,
)

from app.config import settings
from app.models import User, WebAuthnCredential

_REGISTRATION_PREFIX = "webauthn:register:"
_AUTHENTICATION_PREFIX = "webauthn:authenticate:"
_STATE_VERSION = 1


class WebAuthnError(Exception):
    """A ceremony failed. Callers must translate this to a generic response.

    `user` and `credential` are populated when enough was learned to write an
    audit row. They are deliberately not serialised: the client is told only
    that authentication failed, never which check failed.
    """

    def __init__(
        self,
        reason: str,
        *,
        user: User | None = None,
        credential: WebAuthnCredential | None = None,
    ) -> None:
        super().__init__(reason)
        self.reason = reason
        self.user = user
        self.credential = credential


class WebAuthnDuplicateCredential(WebAuthnError):
    """This authenticator is already registered to an account."""


@dataclass(frozen=True)
class Ceremony:
    ceremony_id: str
    options: dict[str, Any]
    expires_in: int


@dataclass(frozen=True)
class AuthenticationResult:
    user: User
    credential: WebAuthnCredential
    user_verified: bool
    new_sign_count: int
    backup_eligible: bool
    backup_state: bool


class WebAuthnService:
    """WebAuthn registration and usernameless authentication.

    Challenges live in Redis, not PostgreSQL. A ceremony is one row in a
    short-lived keyspace, consumed with GETDEL so two concurrent completions
    cannot both use the same challenge. The database only ever holds the
    resulting public credential.
    """

    def __init__(self, redis: Redis, db: AsyncSession) -> None:
        self._redis = redis
        self._db = db

    # ── Registration ────────────────────────────────────────────────────────
    async def begin_registration(self, user: User) -> Ceremony:
        existing = (
            await self._db.scalars(
                select(WebAuthnCredential).where(
                    WebAuthnCredential.user_id == user.id
                )
            )
        ).all()

        options = generate_registration_options(
            rp_id=settings.WEBAUTHN_RP_ID,
            rp_name=settings.WEBAUTHN_RP_NAME,
            user_id=user.id.bytes,
            user_name=user.username or user.phone_number,
            user_display_name=user.full_name,
            timeout=settings.WEBAUTHN_TIMEOUT_MS,
            attestation=AttestationConveyancePreference.NONE,
            authenticator_selection=AuthenticatorSelectionCriteria(
                # A hardware key, not a platform passkey. The product promise
                # is a second physical factor, so cross-platform is explicit.
                authenticator_attachment=AuthenticatorAttachment.CROSS_PLATFORM,
                # Resident keys are what make usernameless login possible: the
                # authenticator can return the credential without being told
                # which account to look for.
                resident_key=ResidentKeyRequirement.REQUIRED,
                user_verification=self._user_verification(),
            ),
            exclude_credentials=(
                [
                    PublicKeyCredentialDescriptor(id=row.credential_id)
                    for row in existing
                ]
                or None
            ),
        )

        ceremony_id = secrets.token_urlsafe(32)
        await self._store(
            _REGISTRATION_PREFIX,
            ceremony_id,
            {
                "v": _STATE_VERSION,
                "kind": "registration",
                "challenge": bytes_to_base64url(options.challenge),
                # Binding the ceremony to the authenticated user prevents one
                # account completing a challenge issued to another.
                "user_id": str(user.id),
            },
        )
        return Ceremony(
            ceremony_id=ceremony_id,
            options=json.loads(options_to_json(options)),
            expires_in=settings.WEBAUTHN_CHALLENGE_TTL_SECONDS,
        )

    async def finish_registration(
        self,
        user: User,
        ceremony_id: str,
        credential: dict[str, Any],
        nickname: str | None = None,
    ) -> WebAuthnCredential:
        state = await self._consume(
            _REGISTRATION_PREFIX, ceremony_id, "registration"
        )
        if state.get("user_id") != str(user.id):
            raise WebAuthnError("registration_user_mismatch", user=user)

        try:
            verified = verify_registration_response(
                credential=credential,
                expected_challenge=base64url_to_bytes(state["challenge"]),
                expected_rp_id=settings.WEBAUTHN_RP_ID,
                expected_origin=settings.WEBAUTHN_ORIGIN,
                require_user_verification=settings.WEBAUTHN_REQUIRE_USER_VERIFICATION,
            )
        except Exception as exc:  # noqa: BLE001 — library raises several types
            raise WebAuthnError("registration_verification_failed", user=user) from exc

        existing = await self._db.scalar(
            select(WebAuthnCredential).where(
                WebAuthnCredential.credential_id == verified.credential_id
            )
        )
        if existing is not None:
            raise WebAuthnDuplicateCredential(
                "credential_already_registered",
                user=user,
                credential=existing,
            )

        row = WebAuthnCredential(
            user_id=user.id,
            credential_id=verified.credential_id,
            public_key=verified.credential_public_key,
            sign_count=int(verified.sign_count),
            transports=_extract_transports(credential),
            aaguid=verified.aaguid or None,
            credential_type=verified.credential_type.value,
            user_verified=bool(verified.user_verified),
            backup_eligible=(
                verified.credential_device_type == CredentialDeviceType.MULTI_DEVICE
            ),
            backup_state=bool(verified.credential_backed_up),
            nickname=_clean_nickname(nickname),
        )
        self._db.add(row)
        await self._db.flush()
        await self._db.refresh(row)
        return row

    # ── Authentication ──────────────────────────────────────────────────────
    async def begin_authentication(self) -> Ceremony:
        options = generate_authentication_options(
            rp_id=settings.WEBAUTHN_RP_ID,
            timeout=settings.WEBAUTHN_TIMEOUT_MS,
            # Empty on purpose. The browser offers the resident credentials it
            # holds; the server learns the account only from the signed
            # assertion. A non-empty list would reveal whether a phone number
            # has a registered key, which is an enumeration oracle.
            allow_credentials=[],
            user_verification=self._user_verification(),
        )

        ceremony_id = secrets.token_urlsafe(32)
        await self._store(
            _AUTHENTICATION_PREFIX,
            ceremony_id,
            {
                "v": _STATE_VERSION,
                "kind": "authentication",
                "challenge": bytes_to_base64url(options.challenge),
            },
        )
        return Ceremony(
            ceremony_id=ceremony_id,
            options=json.loads(options_to_json(options)),
            expires_in=settings.WEBAUTHN_CHALLENGE_TTL_SECONDS,
        )

    async def finish_authentication(
        self,
        ceremony_id: str,
        credential: dict[str, Any],
    ) -> AuthenticationResult:
        state = await self._consume(
            _AUTHENTICATION_PREFIX, ceremony_id, "authentication"
        )

        try:
            parsed = parse_authentication_credential_json(credential)
        except Exception as exc:  # noqa: BLE001 — malformed client JSON
            raise WebAuthnError("malformed_credential") from exc

        row = await self._db.scalar(
            select(WebAuthnCredential).where(
                WebAuthnCredential.credential_id == parsed.raw_id
            )
        )
        if row is None:
            raise WebAuthnError("unknown_credential")

        user = await self._db.scalar(select(User).where(User.id == row.user_id))
        if user is None:
            # The FK cascades, so this is a defensive branch rather than an
            # expected state. Treat it exactly like an unknown credential.
            raise WebAuthnError("unknown_user")

        # A discoverable credential's user handle must name the account that
        # owns the credential. Without this check a credential could be used
        # while claiming a different user handle, which is the one piece of the
        # assertion the signature does not cover.
        user_handle = parsed.response.user_handle
        if user_handle is None or bytes(user_handle) != user.id.bytes:
            raise WebAuthnError(
                "user_handle_mismatch", user=user, credential=row
            )

        try:
            verified = verify_authentication_response(
                credential=credential,
                expected_challenge=base64url_to_bytes(state["challenge"]),
                expected_rp_id=settings.WEBAUTHN_RP_ID,
                expected_origin=settings.WEBAUTHN_ORIGIN,
                credential_public_key=row.public_key,
                credential_current_sign_count=row.sign_count,
                require_user_verification=settings.WEBAUTHN_REQUIRE_USER_VERIFICATION,
            )
        except Exception as exc:  # noqa: BLE001 — library raises several types
            raise WebAuthnError(
                "authentication_verification_failed",
                user=user,
                credential=row,
            ) from exc

        if verified.credential_id != row.credential_id:
            raise WebAuthnError(
                "credential_id_mismatch", user=user, credential=row
            )

        # Do NOT mutate the row here. The route checks account status first;
        # a suspended account's assertion should be rejected without advancing
        # its stored counter or last-used timestamp.
        return AuthenticationResult(
            user=user,
            credential=row,
            user_verified=bool(verified.user_verified),
            new_sign_count=int(verified.new_sign_count),
            backup_eligible=(
                verified.credential_device_type == CredentialDeviceType.MULTI_DEVICE
            ),
            backup_state=bool(verified.credential_backed_up),
        )

    # ── Key management ──────────────────────────────────────────────────────
    async def list_credentials(self, user: User) -> list[WebAuthnCredential]:
        rows = (
            await self._db.scalars(
                select(WebAuthnCredential)
                .where(WebAuthnCredential.user_id == user.id)
                .order_by(WebAuthnCredential.created_at.desc())
            )
        ).all()
        return list(rows)

    async def remove_credential(
        self, user: User, credential_id: UUID
    ) -> WebAuthnCredential:
        row = await self._db.scalar(
            select(WebAuthnCredential).where(
                WebAuthnCredential.id == credential_id,
                WebAuthnCredential.user_id == user.id,
            )
        )
        if row is None:
            raise WebAuthnError("credential_not_found", user=user)
        await self._db.delete(row)
        await self._db.flush()
        return row

    # ── Challenge storage ────────────────────────────────────────────────────
    async def _store(
        self, prefix: str, ceremony_id: str, state: dict[str, Any]
    ) -> None:
        await self._redis.set(
            f"{prefix}{ceremony_id}",
            json.dumps(state, separators=(",", ":")),
            ex=settings.WEBAUTHN_CHALLENGE_TTL_SECONDS,
        )

    async def _consume(
        self, prefix: str, ceremony_id: str, kind: str
    ) -> dict[str, Any]:
        """Consume a challenge atomically. A second completion finds nothing."""
        if not ceremony_id:
            raise WebAuthnError("challenge_expired")
        raw = await self._redis.getdel(f"{prefix}{ceremony_id}")
        if raw is None:
            raise WebAuthnError("challenge_expired")
        try:
            state = json.loads(raw)
        except (TypeError, ValueError) as exc:
            raise WebAuthnError("challenge_invalid") from exc
        if (
            not isinstance(state, dict)
            or state.get("v") != _STATE_VERSION
            or state.get("kind") != kind
            or not isinstance(state.get("challenge"), str)
        ):
            raise WebAuthnError("challenge_invalid")
        return state

    @staticmethod
    def _user_verification() -> UserVerificationRequirement:
        return (
            UserVerificationRequirement.REQUIRED
            if settings.WEBAUTHN_REQUIRE_USER_VERIFICATION
            else UserVerificationRequirement.PREFERRED
        )


def _extract_transports(credential: dict[str, Any]) -> list[str]:
    response = credential.get("response")
    if not isinstance(response, dict):
        return []
    raw = response.get("transports")
    if not isinstance(raw, list):
        return []
    transports = [
        item
        for item in raw
        if isinstance(item, str) and 0 < len(item) <= 32
    ]
    # The set is small and known; cap it so a client cannot use the column as
    # arbitrary storage and deduplicate repeated entries.
    return list(dict.fromkeys(transports))[:10]


def _clean_nickname(nickname: str | None) -> str | None:
    if nickname is None:
        return None
    cleaned = " ".join(nickname.split())
    return cleaned[:100] or None
