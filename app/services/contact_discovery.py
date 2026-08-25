from __future__ import annotations

import hashlib
import re
import secrets
from dataclasses import dataclass

from app.config import settings

#: Cap on one sync. A book larger than this is far more likely to be an
#: enumeration attempt than a real address book, and refusing is safer than
#: accepting a payload that pins a worker.
MAX_CONTACTS_PER_SYNC = 5_000

#: E.164 allows at most 15 digits; anything longer is not a phone number.
MAX_E164_DIGITS = 15
MIN_E164_DIGITS = 7

#: Default country for numbers written in local form. Egypt, since that is
#: where the deployment is. A number that already carries a country code is
#: never reinterpreted against this.
DEFAULT_COUNTRY_CODE = "20"

#: National trunk prefixes stripped when a local-form number is promoted to
#: E.164. '0' covers Egypt and most of Europe; kept as a set so adding a
#: market is a one-line change rather than a rewrite.
TRUNK_PREFIXES = ("0",)

_NON_DIGITS = re.compile(r"[^\d+]")


@dataclass(frozen=True)
class NormalizedPhone:
    """A phone number reduced to the single form everyone hashes."""

    e164: str

    @property
    def digits(self) -> str:
        return self.e164.lstrip("+")


def normalize_phone(
    raw: str, *, default_country: str = DEFAULT_COUNTRY_CODE
) -> NormalizedPhone | None:
    """Reduce a phone number to E.164, or None if it cannot be one.

    Matching only works if both sides agree on the exact string being hashed,
    so this has to be deterministic and shared: the Flutter client implements
    the same rules, and the two must not drift. Any change here is a change
    to the wire format.

    Returns None rather than raising — an address book routinely contains
    entries that are not phone numbers at all, and one bad row must not fail
    the whole sync.
    """
    if not raw:
        return None

    cleaned = _NON_DIGITS.sub("", raw.strip())
    if not cleaned:
        return None

    # A '+' anywhere but the front is meaningless; keep only a leading one.
    explicit_international = cleaned.startswith("+")
    digits = cleaned.replace("+", "")

    if not digits.isdigit():
        return None

    if not explicit_international:
        # 00 is the other way of writing '+'.
        if digits.startswith("00"):
            digits = digits[2:]
        else:
            stripped_trunk = False
            for prefix in TRUNK_PREFIXES:
                if digits.startswith(prefix):
                    digits = digits[len(prefix):]
                    stripped_trunk = True
                    break

            # A number with no '+', no '00' and no trunk prefix is ambiguous:
            # "201099695779" could be a local number needing a country code,
            # or an international one written without its '+'. Treating it as
            # local would prepend the code twice and produce a number that
            # matches nothing, so it is read as already-international when it
            # begins with the country code and the remainder is a plausible
            # national number. Address books are full of both forms, and
            # guessing wrong here means those contacts silently never match.
            already_international = (
                not stripped_trunk
                and digits.startswith(default_country)
                and MIN_E164_DIGITS
                <= len(digits)
                <= MAX_E164_DIGITS
                and len(digits) > len(default_country) + 6
            )
            if not already_international:
                digits = f"{default_country}{digits}"

    if not (MIN_E164_DIGITS <= len(digits) <= MAX_E164_DIGITS):
        return None
    # A leading zero after country-code resolution means the trunk prefix was
    # never stripped, so the result is not valid E.164.
    if digits.startswith("0"):
        return None

    return NormalizedPhone(e164=f"+{digits}")


def hash_phone(normalized: NormalizedPhone | str, *, salt: str | None = None) -> str:
    """Salted SHA-256 of an E.164 number, hex-encoded.

    The salt is applied as a prefix rather than via HMAC only because the
    client must reproduce it identically in Dart with no shared crypto
    library; the security property that matters here — that a database dump
    alone cannot be brute-forced against the phone-number space — comes from
    the salt being secret and absent from the database, not from the
    construction.
    """
    e164 = normalized.e164 if isinstance(normalized, NormalizedPhone) else normalized
    effective = salt if salt is not None else settings.CONTACT_HASH_SALT
    if not effective:
        # Never fall back to unsalted: an unsalted phone hash is reversible
        # in seconds, so failing loudly is the only safe behaviour.
        raise RuntimeError("CONTACT_HASH_SALT is not configured")
    return hashlib.sha256(f"{effective}{e164}".encode()).hexdigest()


def hash_many(
    raw_numbers: list[str], *, default_country: str = DEFAULT_COUNTRY_CODE
) -> dict[str, str]:
    """Hash a batch, dropping anything that is not a phone number.

    Returns {e164: hash}. Server-side use only — on the client the raw
    numbers never leave the device, so this exists for the invite flow and
    for tests that need to construct a matching payload.
    """
    out: dict[str, str] = {}
    for raw in raw_numbers[:MAX_CONTACTS_PER_SYNC]:
        normalized = normalize_phone(raw, default_country=default_country)
        if normalized is None:
            continue
        out[normalized.e164] = hash_phone(normalized)
    return out


def is_valid_hash(value: str) -> bool:
    """Whether a submitted string is shaped like one of our digests.

    Enforced on every inbound hash so a client cannot upload raw phone
    numbers into a hash column by mistake or on purpose — the whole privacy
    claim rests on nothing but digests arriving.
    """
    if len(value) != 64:
        return False
    try:
        int(value, 16)
    except ValueError:
        return False
    return True


def new_invite_token() -> str:
    """Opaque token for an invite deep link.

    Random rather than derived from the invitee's number: a token that
    encodes who it was for would leak exactly what the hashing is meant to
    protect, to anyone who receives a forwarded link.
    """
    return secrets.token_urlsafe(32)[:64]
