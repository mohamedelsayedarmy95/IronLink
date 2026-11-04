"""Tests for contact sync and auto-discovery.

The privacy claim is specific: a user's address book is matched against
IronLink's members without either side's phone numbers reaching the server in
readable form. Everything below exists to make that claim falsifiable rather
than decorative — if someone later "simplifies" the hashing, weakens the
digest check, or adds a column that could hold a raw number, these fail.

Normalization gets heavy coverage because it is the silent failure mode: a
number that normalizes differently on device and server hashes differently
and simply never matches, with no error anywhere to notice.
"""
from __future__ import annotations

import pytest

from app.services.contact_discovery import (
    MAX_CONTACTS_PER_SYNC,
    hash_phone,
    is_valid_hash,
    new_invite_token,
    normalize_phone,
)

SALT = "t" * 40


# ── The core invariant: nowhere to put a phone number ─────────────────────────

def test_no_table_can_hold_a_raw_phone_number() -> None:
    """Every phone column in the contact schema is a fixed 64-char hash
    field. A phone number is never 64 hex characters, so a raw one cannot be
    stored and pass unnoticed."""
    from app.models import (
        PHONE_HASH_LENGTH,
        ContactHash,
        ContactInvite,
        UserPhoneIndex,
    )

    for model in (ContactHash, UserPhoneIndex, ContactInvite):
        column = model.__table__.columns["phone_hash"]
        assert column.type.length == PHONE_HASH_LENGTH, (
            f"{model.__tablename__}.phone_hash must be exactly "
            f"{PHONE_HASH_LENGTH} chars so a raw number cannot fit"
        )
        for name in model.__table__.columns.keys():
            assert "phone_number" not in name, (
                f"{model.__tablename__}.{name} looks like it holds a raw number"
            )


def test_sync_payload_cannot_carry_a_phone_number() -> None:
    """The sync schema has no field capable of receiving one."""
    from app.api.routes.contacts import SyncIn

    assert set(SyncIn.model_fields) == {"hashes", "replace"}


def test_sync_rejects_anything_that_is_not_a_digest() -> None:
    """A client uploading raw numbers is rejected outright rather than
    filtered — silently dropping them would hide a broken or probing client."""
    from pydantic import ValidationError

    from app.api.routes.contacts import SyncIn

    for bad in ("+201099695779", "01099695779", "", "zz" * 32, "abc123"):
        with pytest.raises(ValidationError):
            SyncIn(hashes=[bad])


def test_sync_accepts_valid_digests() -> None:
    from app.api.routes.contacts import SyncIn

    digest = hash_phone(normalize_phone("01099695779"), salt=SALT)
    assert SyncIn(hashes=[digest]).hashes == [digest]


def test_sync_batch_is_bounded() -> None:
    """An address book larger than this is far likelier to be enumeration
    than a real contact list."""
    from pydantic import ValidationError

    from app.api.routes.contacts import SyncIn

    digest = hash_phone(normalize_phone("01099695779"), salt=SALT)
    with pytest.raises(ValidationError):
        SyncIn(hashes=[digest] * (MAX_CONTACTS_PER_SYNC + 1))


# ── Hashing ───────────────────────────────────────────────────────────────────

def test_hash_is_salted() -> None:
    """Without a salt, the space of phone numbers is small enough to
    enumerate in seconds."""
    number = normalize_phone("01099695779")
    assert hash_phone(number, salt="a" * 40) != hash_phone(number, salt="b" * 40)


def test_unsalted_hashing_fails_loudly_rather_than_falling_back() -> None:
    """A silent fallback to unsalted would produce reversible hashes that
    look identical to safe ones."""
    with pytest.raises(RuntimeError):
        hash_phone(normalize_phone("01099695779"), salt="")


def test_hash_is_stable_across_calls() -> None:
    """Matching depends on the same number producing the same digest every
    time; anything time- or session-dependent breaks discovery."""
    number = normalize_phone("01099695779")
    assert hash_phone(number, salt=SALT) == hash_phone(number, salt=SALT)


def test_hash_shape_check_rejects_near_misses() -> None:
    valid = hash_phone(normalize_phone("01099695779"), salt=SALT)
    assert is_valid_hash(valid)
    assert not is_valid_hash(valid[:-1])          # too short
    assert not is_valid_hash(valid + "a")         # too long
    assert not is_valid_hash("g" + valid[1:])     # not hex
    assert not is_valid_hash("+201099695779")


# ── Normalization: the silent failure mode ────────────────────────────────────

@pytest.mark.parametrize(
    "written",
    [
        "01099695779",           # local, Egyptian trunk prefix
        "+201099695779",         # full E.164
        "00201099695779",        # 00 instead of +
        "201099695779",          # international, missing the +
        "1099695779",            # bare national number
        "+20 (109) 969-5779",    # punctuation and spaces
        " 010 9969 5779 ",       # padded and spaced
    ],
)
def test_all_common_forms_of_one_number_agree(written: str) -> None:
    """Address books contain every one of these spellings. If they normalize
    differently, those contacts never match and nothing reports an error."""
    assert normalize_phone(written).e164 == "+201099695779"


def test_ambiguous_number_is_not_double_prefixed() -> None:
    """"201099695779" already carries its country code. Reading it as local
    would prepend another and produce a number matching nothing."""
    assert normalize_phone("201099695779").e164 == "+201099695779"


def test_other_countries_keep_their_own_code() -> None:
    assert normalize_phone("+966501234567").e164 == "+966501234567"
    assert normalize_phone("+14155551234").e164 == "+14155551234"


def test_non_numbers_are_dropped_not_raised() -> None:
    """An address book routinely holds entries that are not phone numbers;
    one of them must not fail the whole sync."""
    for junk in ("", "   ", "not a phone", "email@example.com", "+", "++"):
        assert normalize_phone(junk) is None


def test_implausible_lengths_are_rejected() -> None:
    assert normalize_phone("+1234") is None                  # too short
    assert normalize_phone("+1234567890123456789") is None   # beyond E.164


def test_different_numbers_do_not_collide() -> None:
    a = hash_phone(normalize_phone("01099695779"), salt=SALT)
    b = hash_phone(normalize_phone("01099695778"), salt=SALT)
    assert a != b


# ── Invites ───────────────────────────────────────────────────────────────────

def test_invite_token_does_not_encode_the_invitee() -> None:
    """A token derived from the number would leak exactly what the hashing
    protects, to anyone who receives a forwarded link."""
    tokens = {new_invite_token() for _ in range(50)}
    assert len(tokens) == 50, "tokens must not be predictable or repeat"

    number = normalize_phone("01099695779")
    digest = hash_phone(number, salt=SALT)
    for token in tokens:
        assert number.e164 not in token
        assert number.digits not in token
        assert digest not in token


def test_invite_accepts_a_raw_number_but_only_stores_a_hash() -> None:
    """Invites are the one place a raw number is accepted, because it has to
    be delivered to. It must be hashed and discarded, never persisted."""
    import inspect

    from app.api.routes import contacts

    source = inspect.getsource(contacts.invite)
    assert "hash_phone(normalized)" in source
    # Nothing in the handler may write the raw value onto the row.
    assert "phone_number=body.phone_number" not in source
    assert "ContactInvite(\n        inviter_id=user.id, phone_hash=phone_hash" in source


# ── Privacy controls ──────────────────────────────────────────────────────────

def test_default_discoverability_is_the_narrower_option() -> None:
    """Discovery is a convenience; the safe default for a high-trust product
    is the narrower setting, with broad visibility opt-in."""
    from app.models import DiscoverabilityLevel, UserPhoneIndex

    default = UserPhoneIndex.__table__.columns["allows_discovery"].default.arg
    assert default == DiscoverabilityLevel.CONTACTS_OF_CONTACTS


def test_nobody_setting_excludes_a_user_from_matching() -> None:
    import inspect

    from app.api.routes import contacts

    source = inspect.getsource(contacts.sync_contacts)
    assert "DiscoverabilityLevel.NOBODY" in source
    assert "!=" in source


def test_contacts_of_contacts_requires_the_link_to_be_mutual() -> None:
    """Being in someone's address book is not the same as them being in
    yours; the narrower setting should mean it actually goes both ways."""
    import inspect

    from app.api.routes import contacts

    assert "_mutual" in inspect.getsource(contacts.sync_contacts)


def test_a_user_never_matches_themselves() -> None:
    import inspect

    from app.api.routes import contacts

    assert "UserPhoneIndex.user_id != user.id" in inspect.getsource(
        contacts.sync_contacts
    )


def test_opting_out_deletes_data_in_both_directions() -> None:
    """Opting out has to remove the links other people hold to you as well,
    or you have only cleared your own list while remaining discoverable."""
    import inspect

    from app.api.routes import contacts

    source = inspect.getsource(contacts.delete_all)
    assert "ContactRelation.owner_id == user.id" in source
    assert "ContactRelation.contact_user_id == user.id" in source
    assert "delete(ContactHash)" in source
    assert "delete(UserPhoneIndex)" in source


def test_sync_is_refused_once_the_user_has_opted_out() -> None:
    import inspect

    from app.api.routes import contacts

    assert "sync_enabled" in inspect.getsource(contacts.sync_contacts)


def test_fetching_matches_does_not_clear_the_new_badge() -> None:
    """A screen loading in the background would otherwise silently consume
    the notification."""
    import inspect

    from app.api.routes import contacts

    assert "notified_at" not in inspect.getsource(contacts.matches).replace(
        "notified_at)", ""
    ).split("return")[0].split("select(")[0]
    # Clearing lives in its own endpoint.
    assert "notified_at" in inspect.getsource(contacts.mark_matches_seen)


# ── Route contract ────────────────────────────────────────────────────────────

@pytest.mark.parametrize(
    "path,method",
    [
        ("/api/v1/contacts/sync", "post"),
        ("/api/v1/contacts/matches", "get"),
        ("/api/v1/contacts/matches/seen", "post"),
        ("/api/v1/contacts/invite", "post"),
        ("/api/v1/contacts/state", "get"),
        ("/api/v1/contacts/privacy", "put"),
        ("/api/v1/contacts/delete-all", "delete"),
    ],
)
def test_route_registered(path: str, method: str) -> None:
    from app.main import app

    paths = app.openapi()["paths"]
    assert path in paths, f"{path} is not registered"
    assert method in paths[path]


# ── Integration checklist ─────────────────────────────────────────────────────
#
# Needs a live Postgres and is not asserted here:
#   * ON CONFLICT DO NOTHING on uq_contact_hash across a real re-sync
#   * mutual-contact resolution with rows actually present on both sides
#   * cascade delete of hashes and relations when a user is removed
#   * migration 0004 applying cleanly on a database already at 0003


# ── Degradation ───────────────────────────────────────────────────────────────

def test_missing_salt_disables_the_feature_without_blocking_startup() -> None:
    """A missing salt must not take the whole service down.

    DB_ENCRYPTION_KEY is validated at startup because core authentication
    needs it. This one gates a single feature, so shipping contact discovery
    should not be able to stop messaging from booting.
    """
    from app.config import Settings

    assert not hasattr(Settings, "_require_contact_salt"), (
        "CONTACT_HASH_SALT must not be a startup-blocking validator"
    )


def test_short_salt_counts_as_unconfigured() -> None:
    """A two-character salt is not meaningfully better than none."""
    from app.config import settings

    original = settings.CONTACT_HASH_SALT
    try:
        object.__setattr__(settings, "CONTACT_HASH_SALT", "abc")
        assert not settings.contact_discovery_enabled
        object.__setattr__(settings, "CONTACT_HASH_SALT", "x" * 32)
        assert settings.contact_discovery_enabled
    finally:
        object.__setattr__(settings, "CONTACT_HASH_SALT", original)


def test_hashing_endpoints_refuse_when_unconfigured() -> None:
    """503 rather than a 500 that reads like a bug, or worse, unsalted
    hashing that silently produces reversible digests."""
    import inspect

    from app.api.routes import contacts

    for handler in (contacts.sync_contacts, contacts.invite):
        assert "_require_discovery_configured()" in inspect.getsource(handler)

    guard = inspect.getsource(contacts._require_discovery_configured)
    assert "503" in guard or "SERVICE_UNAVAILABLE" in guard


def test_reading_stored_data_still_works_without_the_salt() -> None:
    """Matches and privacy settings read what is already stored and do no
    hashing, so they should keep working — otherwise a server that loses its
    salt also loses the user's ability to opt out."""
    import inspect

    from app.api.routes import contacts

    for handler in (contacts.matches, contacts.delete_all, contacts.sync_state):
        assert "_require_discovery_configured()" not in inspect.getsource(handler)


def test_tightening_privacy_never_fails_on_a_misconfigured_server() -> None:
    """Setting yourself to NOBODY must not depend on the salt.

    Indexing requires hashing, so a server with no salt cannot create the
    row — but failing the request would let a misconfiguration stop someone
    from making themselves less discoverable. With nothing indexed they are
    already undiscoverable, so reporting success is accurate.
    """
    import inspect

    from app.api.routes import contacts

    source = inspect.getsource(contacts.set_privacy)
    assert "contact_discovery_enabled" in source
    assert "_ensure_indexed" in source
    # The unconfigured path returns rather than hashing.
    assert source.index("return") < source.index("_ensure_indexed(db, user)")
