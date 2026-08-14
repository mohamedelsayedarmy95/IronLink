"""Tests for the Controlled Group Entry system.

The security boundary here is the form validator. It is the only thing
standing between "the admin mandated these answers" and "a client posted
whatever JSON it liked", so most of this file exercises that rather than the
CRUD around it.

The suite has no database, so these are unit and contract tests: pure
validation logic, schema invariants, and route registration. Behaviour that
genuinely needs Postgres (locking, cascade deletes) is called out in the
integration checklist at the bottom rather than faked here — a mocked test of
row locking would prove nothing about row locking.
"""
from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone

import pytest

from app.models import FormFieldType, JoinRequestStatus, VerificationFormField
from app.services.form_validation import (
    MAX_REGEX_LENGTH,
    MAX_TEXT_LENGTH,
    FormValidationError,
    expiry_for,
    validate_answers,
    validate_field_definition,
)


def _field(
    field_type: str = FormFieldType.TEXT_SHORT,
    *,
    required: bool = True,
    rules: dict | None = None,
    options: dict | None = None,
) -> VerificationFormField:
    field = VerificationFormField(
        field_type=field_type,
        label="Question",
        is_required=required,
        validation_rules=rules,
        options=options,
        order_index=0,
    )
    # Assigned directly: without a DB flush there is no server-generated id,
    # and answers are keyed by field id.
    field.id = uuid.uuid4()
    return field


# ── The core invariant: answers must match what the admin asked ───────────────

def test_required_field_cannot_be_skipped() -> None:
    field = _field(required=True)
    with pytest.raises(FormValidationError) as exc:
        validate_answers([field], {})
    assert str(field.id) in exc.value.errors


def test_required_field_cannot_be_whitespace() -> None:
    """A space is not an answer; without this, every required text field is
    trivially bypassed by pressing the spacebar."""
    field = _field(required=True)
    with pytest.raises(FormValidationError):
        validate_answers([field], {str(field.id): "   "})


def test_optional_field_may_be_omitted() -> None:
    field = _field(required=False)
    assert validate_answers([field], {}) == {}


def test_unknown_keys_are_discarded() -> None:
    """A client must not be able to write arbitrary data into the stored
    request by inventing keys the admin never defined."""
    field = _field(required=False)
    cleaned = validate_answers(
        [field], {"not-a-field": "smuggled", "../../etc/passwd": "x"}
    )
    assert cleaned == {}


def test_answers_are_keyed_by_field_id_only() -> None:
    field = _field()
    cleaned = validate_answers([field], {str(field.id): "Ahmed"})
    assert list(cleaned) == [str(field.id)]


# ── Per-type validation ───────────────────────────────────────────────────────

def test_text_respects_admin_length_bounds() -> None:
    field = _field(rules={"min": 3, "max": 5})
    assert validate_answers([field], {str(field.id): "abcd"})
    for bad in ("ab", "abcdef"):
        with pytest.raises(FormValidationError):
            validate_answers([field], {str(field.id): bad})


def test_text_is_bounded_even_without_admin_rules() -> None:
    """An admin who sets no max must not leave a field that accepts megabytes."""
    field = _field(rules=None)
    with pytest.raises(FormValidationError):
        validate_answers([field], {str(field.id): "x" * (MAX_TEXT_LENGTH + 1)})


def test_number_rejects_non_numeric_and_honours_bounds() -> None:
    field = _field(FormFieldType.NUMBER, rules={"min": 1, "max": 10})
    assert validate_answers([field], {str(field.id): 5})
    for bad in ("not a number", 0, 11):
        with pytest.raises(FormValidationError):
            validate_answers([field], {str(field.id): bad})


def test_number_rejects_bool_disguised_as_number() -> None:
    """bool is a subclass of int in Python, so `True` would otherwise pass as 1."""
    field = _field(FormFieldType.NUMBER)
    with pytest.raises(FormValidationError):
        validate_answers([field], {str(field.id): True})


def test_select_rejects_option_not_offered() -> None:
    """The central select guarantee: an answer must come from the admin's list,
    not from whatever the client chose to send."""
    field = _field(
        FormFieldType.SELECT_SINGLE,
        options={"options": [{"label": "Captain", "value": "captain"}]},
    )
    assert validate_answers([field], {str(field.id): "captain"})
    with pytest.raises(FormValidationError):
        validate_answers([field], {str(field.id): "general"})


def test_multi_select_rejects_duplicates_and_honours_counts() -> None:
    field = _field(
        FormFieldType.SELECT_MULTI,
        options={"options": [
            {"label": "A", "value": "a"},
            {"label": "B", "value": "b"},
            {"label": "C", "value": "c"},
        ]},
        rules={"min_select": 2, "max_select": 3},
    )
    assert validate_answers([field], {str(field.id): ["a", "b"]})

    for bad in (["a"], ["a", "a"], ["a", "b", "c", "a"], ["a", "z"]):
        with pytest.raises(FormValidationError):
            validate_answers([field], {str(field.id): bad})


def test_required_checkbox_must_be_checked() -> None:
    """A required checkbox means consent; false is a refusal, not an answer."""
    field = _field(FormFieldType.CHECKBOX, required=True)
    assert validate_answers([field], {str(field.id): True})
    with pytest.raises(FormValidationError):
        validate_answers([field], {str(field.id): False})


def test_email_and_phone_and_url_formats() -> None:
    email = _field(FormFieldType.EMAIL)
    phone = _field(FormFieldType.PHONE)
    url = _field(FormFieldType.URL)

    assert validate_answers([email], {str(email.id): "a@b.co"})
    assert validate_answers([phone], {str(phone.id): "+201001234567"})
    assert validate_answers([url], {str(url.id): "https://example.com"})

    for field, bad in (
        (email, "not-an-email"),
        (phone, "abc"),
        (url, "ftp://example.com"),
    ):
        with pytest.raises(FormValidationError):
            validate_answers([field], {str(field.id): bad})


def test_url_rejects_script_schemes() -> None:
    """A form answer must not be able to carry javascript: into anything that
    later renders it as a link in the admin dashboard."""
    field = _field(FormFieldType.URL)
    for hostile in (
        "javascript:alert(1)",
        "data:text/html;base64,PHNjcmlwdD4=",
        "file:///etc/passwd",
    ):
        with pytest.raises(FormValidationError):
            validate_answers([field], {str(field.id): hostile})


def test_date_must_be_iso_and_within_bounds() -> None:
    field = _field(
        FormFieldType.DATE, rules={"min": "2020-01-01", "max": "2030-01-01"}
    )
    assert validate_answers([field], {str(field.id): "2025-06-15"})
    for bad in ("15/06/2025", "2019-01-01", "2031-01-01", "not a date"):
        with pytest.raises(FormValidationError):
            validate_answers([field], {str(field.id): bad})


def test_upload_enforces_allowed_types() -> None:
    field = _field(FormFieldType.FILE, rules={"allowed_types": ["pdf", "docx"]})
    assert validate_answers([field], {str(field.id): "uploads/abc.pdf"})
    with pytest.raises(FormValidationError):
        validate_answers([field], {str(field.id): "uploads/payload.exe"})


# ── Errors are per-field, so the client can place them ────────────────────────

def test_every_failing_field_is_reported_not_just_the_first() -> None:
    """Returning one error at a time turns a five-field form into five
    round-trips of trial and error."""
    a, b, c = _field(), _field(), _field(required=False)
    with pytest.raises(FormValidationError) as exc:
        validate_answers([a, b, c], {})
    assert set(exc.value.errors) == {str(a.id), str(b.id)}


# ── Admin-authored definitions are validated too ──────────────────────────────

def test_select_without_options_is_rejected_at_authoring_time() -> None:
    """An unanswerable question should fail for the admin writing it, not for
    the requester who cannot proceed past it."""
    for options in (None, {}, {"options": []}):
        with pytest.raises(ValueError):
            validate_field_definition(FormFieldType.SELECT_SINGLE, options, None)


def test_duplicate_option_values_rejected() -> None:
    with pytest.raises(ValueError):
        validate_field_definition(
            FormFieldType.SELECT_SINGLE,
            {"options": [
                {"label": "A", "value": "x"},
                {"label": "B", "value": "x"},
            ]},
            None,
        )


def test_unknown_field_type_rejected() -> None:
    with pytest.raises(ValueError):
        validate_field_definition("sql_injection", None, None)


def test_inverted_bounds_rejected() -> None:
    with pytest.raises(ValueError):
        validate_field_definition(FormFieldType.NUMBER, None, {"min": 10, "max": 1})
    with pytest.raises(ValueError):
        validate_field_definition(
            FormFieldType.SELECT_MULTI,
            {"options": [{"label": "A", "value": "a"}]},
            {"min_select": 5, "max_select": 2},
        )


def test_invalid_regex_rejected_at_authoring_time() -> None:
    with pytest.raises(ValueError):
        validate_field_definition(FormFieldType.TEXT_SHORT, None, {"regex": "([a-z"})


def test_overlong_regex_rejected() -> None:
    """Admin-supplied patterns run against user input; unbounded ones are
    where catastrophic backtracking lives."""
    with pytest.raises(ValueError):
        validate_field_definition(
            FormFieldType.TEXT_SHORT, None, {"regex": "a" * (MAX_REGEX_LENGTH + 1)}
        )


def test_a_bad_admin_regex_does_not_fail_the_requester() -> None:
    """If a pattern slipped through, the person who cannot submit is the
    requester — who did nothing wrong. The rule is skipped, not enforced."""
    field = _field(rules={"regex": "([a-z"})
    assert validate_answers([field], {str(field.id): "anything"})


# ── Expiry ────────────────────────────────────────────────────────────────────

def test_expiry_is_computed_from_the_group_setting() -> None:
    now = datetime(2026, 1, 1, tzinfo=timezone.utc)
    assert expiry_for(14, now=now) == now + timedelta(days=14)


def test_zero_days_means_no_expiry() -> None:
    """0 must read as "never expires", not "expires immediately"."""
    assert expiry_for(0) is None
    assert expiry_for(-1) is None


# ── Status model ──────────────────────────────────────────────────────────────

def test_expired_and_more_info_statuses_exist() -> None:
    values = {s.value for s in JoinRequestStatus}
    assert {"pending", "approved", "rejected", "more_info_needed", "expired"} == values


def test_only_pending_and_more_info_are_actionable() -> None:
    """An expired or already-decided request must not be approvable after the
    fact — the window closing is the point of having one."""
    from app.models import GroupJoinRequest

    req = GroupJoinRequest()
    for actionable in (JoinRequestStatus.PENDING, JoinRequestStatus.MORE_INFO_NEEDED):
        req.status = actionable
        assert req.is_actionable()
    for settled in (
        JoinRequestStatus.APPROVED,
        JoinRequestStatus.REJECTED,
        JoinRequestStatus.EXPIRED,
    ):
        req.status = settled
        assert not req.is_actionable()


# ── Schema invariants ─────────────────────────────────────────────────────────

def test_platform_ban_requires_a_reason_but_group_ban_does_not() -> None:
    """A platform-wide restriction is severe enough that an unexplained one
    should be impossible to create."""
    from app.models import GroupBan, PlatformBan

    assert PlatformBan.__table__.columns["reason"].nullable is False
    assert GroupBan.__table__.columns["reason"].nullable is True


def test_bans_are_separate_tables() -> None:
    """Conflating the two would let a group-scoped action lock someone out of
    the platform, or the reverse."""
    from app.models import GroupBan, PlatformBan

    assert GroupBan.__tablename__ != PlatformBan.__tablename__
    assert "group_id" not in PlatformBan.__table__.columns


def test_request_snapshots_the_form_it_answered() -> None:
    """Editing a group's active form must not retroactively change what a
    pending request was asked."""
    from app.models import GroupJoinRequest

    assert "form_id" in GroupJoinRequest.__table__.columns


def test_field_order_is_unique_within_a_form() -> None:
    """Duplicate order values would make the rendered sequence depend on
    insertion order, which is not stable across reads."""
    constraints = {
        c.name for c in VerificationFormField.__table__.constraints if c.name
    }
    assert "uq_form_field_order" in constraints


def test_audit_log_has_no_update_or_delete_path() -> None:
    """An audit trail that application code can edit is not evidence."""
    import inspect

    from app.api.routes import group_entry

    source = inspect.getsource(group_entry)
    assert "delete(GroupAuditLog" not in source
    assert "update(GroupAuditLog" not in source


# ── Route contract ────────────────────────────────────────────────────────────

@pytest.mark.parametrize(
    "path,method",
    [
        ("/api/v1/groups/{group_id}/forms", "post"),
        ("/api/v1/groups/{group_id}/forms/active", "get"),
        ("/api/v1/groups/{group_id}/join-mode", "put"),
        ("/api/v1/groups/{group_id}/entry-request", "post"),
        ("/api/v1/groups/{group_id}/entry-request/me", "get"),
        ("/api/v1/groups/{group_id}/entry-request/me", "delete"),
        ("/api/v1/groups/{group_id}/entry-requests", "get"),
        ("/api/v1/groups/{group_id}/entry-requests/counts", "get"),
        ("/api/v1/groups/{group_id}/entry-requests/{request_id}/approve", "post"),
        ("/api/v1/groups/{group_id}/entry-requests/{request_id}/reject", "post"),
        ("/api/v1/groups/{group_id}/entry-requests/{request_id}/request-info", "post"),
        ("/api/v1/groups/{group_id}/entry-requests/bulk-approve", "post"),
        ("/api/v1/groups/{group_id}/entry-requests/bulk-reject", "post"),
        ("/api/v1/groups/{group_id}/audit-log", "get"),
    ],
)
def test_route_registered(path: str, method: str) -> None:
    from app.main import app

    paths = app.openapi()["paths"]
    assert path in paths, f"{path} is not registered"
    assert method in paths[path], f"{path} must accept {method.upper()}"


def test_existing_join_endpoints_still_exist() -> None:
    """The new module adds to the old flow rather than replacing it; removing
    those routes would break clients already shipped."""
    from app.main import app

    paths = app.openapi()["paths"]
    assert "/api/v1/groups/{group_id}/join" in paths
    assert "/api/v1/groups/{group_id}/join-requests" in paths


def test_bulk_actions_are_bounded() -> None:
    """An unbounded bulk action is a request that times out halfway and leaves
    the caller unsure what was applied."""
    from app.api.routes.group_entry import MAX_BULK_SIZE

    assert 0 < MAX_BULK_SIZE <= 1000


def test_bulk_locks_rows_to_prevent_double_approval() -> None:
    """Two admins acting at once must not both approve the same request and
    insert duplicate memberships. Asserted on the mechanism because it is the
    part most easily 'simplified' away later."""
    import inspect

    from app.api.routes.group_entry import _bulk

    source = inspect.getsource(_bulk)
    assert "with_for_update" in source


def test_ban_is_admin_only_not_delegable_to_moderators() -> None:
    """A moderator who can ban can permanently exclude anyone from a group
    they do not own."""
    import inspect

    from app.api.routes.group_entry import ban_from_group

    source = inspect.getsource(ban_from_group)
    assert "GroupRole.ADMIN" in source
    assert "GroupRole.MODERATOR" not in source


def test_ban_removes_membership_and_kills_live_requests() -> None:
    """Leaving someone inside a group they are barred from rejoining is
    incoherent, and a live request would let an admin later approve a banned
    user."""
    import inspect

    from app.api.routes.group_entry import ban_from_group

    source = inspect.getsource(ban_from_group)
    assert "db.delete(target)" in source
    assert "delete(GroupJoinRequest)" in source


def test_admins_cannot_ban_each_other_or_themselves() -> None:
    import inspect

    from app.api.routes.group_entry import ban_from_group

    source = inspect.getsource(ban_from_group)
    assert "cannot ban yourself" in source
    assert "cannot ban another admin" in source


def test_lapsed_time_limited_ban_is_cleared_not_enforced() -> None:
    """A user must not stay blocked by a row nobody remembered to remove."""
    import inspect

    from app.api.routes.group_entry import _assert_not_banned

    source = inspect.getsource(_assert_not_banned)
    assert "is_permanent" in source
    assert "db.delete(ban)" in source


def test_platform_ban_is_checked_before_group_ban() -> None:
    """Telling a platform-banned user only about this one group would be
    misleading about why they cannot proceed."""
    import inspect

    from app.api.routes.group_entry import _assert_not_banned

    source = inspect.getsource(_assert_not_banned)
    assert source.index("PlatformBan") < source.index("GroupBan")


def test_banned_user_is_blocked_before_a_request_is_created() -> None:
    import inspect

    from app.api.routes.group_entry import submit_request

    source = inspect.getsource(submit_request)
    assert "_assert_not_banned" in source
    assert source.index("_assert_not_banned") < source.index("GroupJoinRequest(")


# ── Integration checklist ─────────────────────────────────────────────────────
#
# The following need a live Postgres and are not asserted here, because a
# mocked version would prove nothing about the behaviour it names:
#
#   * bulk approve under genuine concurrency (SELECT ... FOR UPDATE SKIP LOCKED)
#   * ON DELETE CASCADE from verification_forms to its fields
#   * uq_form_field_order rejecting a duplicate order at the database level
#   * migration 0003 applying cleanly on a database already at 0002, including
#     the join_mode backfill from the legacy join_approval_required boolean
#
# Run these against a real database before the feature ships.
