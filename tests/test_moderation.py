"""Tests for blocking and reporting.

A block is only a block if the server enforces it. Most of this file exists
to make sure the enforcement stays where it has to be — on the path every
message passes through — rather than drifting into the UI, where any modified
client would ignore it.
"""
from __future__ import annotations

import inspect

import pytest


# ── Enforcement is server-side, on the path every message takes ──────────────

def test_block_is_enforced_in_the_message_service_not_the_route() -> None:
    """save_message is the single point both REST and WebSocket go through.
    A check in one caller would leave the other open."""
    from app.services import message_service

    source = inspect.getsource(message_service.save_message)
    assert "_blocked_between" in source
    assert "BlockedDelivery" in source


def test_enforcement_is_symmetric_even_though_a_block_is_directional() -> None:
    """If A blocked B, B must not be able to message A either — otherwise the
    block only stops the person who did not ask for it."""
    from app.services.message_service import _blocked_between

    source = inspect.getsource(_blocked_between)
    assert "or_" in source
    assert source.count("UserBlock.blocker_id") == 2
    assert source.count("UserBlock.blocked_id") == 2


def test_the_sender_is_never_told_they_were_blocked() -> None:
    """Saying "you are blocked" discloses something the recipient chose not
    to share and turns a quiet boundary into a confrontation."""
    from app.api.routes import websocket
    from app.api.routes.moderation import assert_not_blocked

    ws_source = inspect.getsource(websocket)
    api_source = inspect.getsource(assert_not_blocked)

    for source in (ws_source, api_source):
        lowered = source.lower()
        assert "could not be delivered" in lowered
        # The words that would give it away must not appear in what is
        # returned to the sender.
        assert "you have been blocked" not in lowered
        assert "user has blocked you" not in lowered


def test_group_messages_are_not_blocked_by_a_dm_block() -> None:
    """Blocking someone should not silently remove them from shared groups,
    or a block becomes a way to disrupt a whole conversation."""
    from app.services import message_service

    source = inspect.getsource(message_service.save_message)
    assert "recipient_id is not None" in source


# ── Blocking ─────────────────────────────────────────────────────────────────

def test_you_cannot_block_yourself() -> None:
    from app.api.routes.moderation import block_user

    assert "cannot block yourself" in inspect.getsource(block_user)


def test_self_block_is_rejected_by_the_database_too() -> None:
    """The check constraint means a bug in the route cannot produce a row
    that would make someone unable to message themselves."""
    import re
    from pathlib import Path

    migration = Path("alembic/versions/0005_blocks_and_reports.py").read_text(
        encoding="utf-8"
    )
    assert re.search(r"blocker_id\s*<>\s*blocked_id", migration)


def test_blocking_severs_contact_discovery_both_ways() -> None:
    """Leaving the link would keep the blocked person surfacing under
    "people you know", which is the opposite of what was asked."""
    from app.api.routes.moderation import block_user

    source = inspect.getsource(block_user)
    assert "ContactRelation" in source
    assert source.count("ContactRelation.owner_id") == 2


def test_there_is_no_endpoint_revealing_who_blocked_you() -> None:
    """Knowing that is exactly what a block withholds."""
    from app.api.routes import moderation

    source = inspect.getsource(moderation.blocked_users)
    # Only rows where the caller is the blocker.
    assert "UserBlock.blocker_id == user.id" in source
    assert "UserBlock.blocked_id == user.id" not in source


def test_block_status_reports_only_the_callers_own_action() -> None:
    from app.api.routes.moderation import block_status

    source = inspect.getsource(block_status)
    assert "UserBlock.blocker_id == user.id" in source
    # A symmetric check here would let anyone probe whether they were blocked.
    assert "or_" not in source


def test_unblocking_a_user_who_is_not_blocked_is_a_404_not_a_silent_ok() -> None:
    from app.api.routes.moderation import unblock_user

    assert "not blocked" in inspect.getsource(unblock_user)


# ── Reporting ────────────────────────────────────────────────────────────────

def test_reported_message_must_belong_to_the_reported_user() -> None:
    """Without this, anyone could attach an arbitrary message id to a report
    and pull unrelated conversations into moderation review."""
    from app.api.routes.moderation import submit_report

    source = inspect.getsource(submit_report)
    assert "message.sender_id != body.reported_user_id" in source


def test_evidence_comes_from_the_reporter_not_from_decryption() -> None:
    """The server cannot read content_ciphertext. The snapshot is the only
    way a report survives the sender deleting the message."""
    from app.api.routes.moderation import submit_report

    source = inspect.getsource(submit_report)
    assert "content_snapshot=body.content_snapshot" in source
    # Nothing here attempts to read the stored ciphertext. Comments are
    # stripped first — the docstring above says the word legitimately.
    code = "\n".join(
        line for line in source.splitlines()
        if not line.lstrip().startswith("#")
    )
    assert "content_ciphertext" not in code


def test_a_report_survives_the_message_being_deleted() -> None:
    """ON DELETE SET NULL, not CASCADE — otherwise deleting the evidence
    deletes the complaint."""
    from pathlib import Path

    migration = Path("alembic/versions/0005_blocks_and_reports.py").read_text(
        encoding="utf-8"
    )
    idx = migration.index("['message_id'], ['messages.id']")
    assert "SET NULL" in migration[idx:idx + 120]


def test_the_same_message_cannot_be_reported_twice_by_one_reporter() -> None:
    """Re-reporting inflates the queue without adding information."""
    from app.api.routes.moderation import submit_report

    assert "already reported this message" in inspect.getsource(submit_report)


def test_reporting_the_same_user_again_is_still_allowed() -> None:
    """Each incident is different information; only the per-message report is
    deduplicated."""
    from pathlib import Path

    migration = Path("alembic/versions/0005_blocks_and_reports.py").read_text(
        encoding="utf-8"
    )
    idx = migration.index("ix_reports_unique_message")
    window = migration[idx:idx + 400]
    assert "message_id IS NOT NULL" in window


def test_you_cannot_report_yourself() -> None:
    from app.api.routes.moderation import submit_report

    assert "cannot report yourself" in inspect.getsource(submit_report)


def test_snapshot_is_bounded() -> None:
    """Large enough for any real message, small enough that the report table
    cannot be used as free storage."""
    from app.api.routes.moderation import MAX_SNAPSHOT_CHARS

    assert 500 <= MAX_SNAPSHOT_CHARS <= 20_000


def test_report_reason_must_be_one_of_the_known_kinds() -> None:
    from pydantic import ValidationError

    from app.api.routes.moderation import ReportIn
    from app.models import ReportReason

    import uuid

    with pytest.raises(ValidationError):
        ReportIn(reported_user_id=uuid.uuid4(), reason="whatever")

    for reason in ReportReason:
        assert ReportIn(reported_user_id=uuid.uuid4(), reason=reason.value)


def test_client_and_server_agree_on_the_reason_values() -> None:
    """The two enums are written in different languages and drift silently:
    a client-only reason is rejected as 422 at submission time, which the user
    sees as the report button simply not working."""
    import re
    from pathlib import Path

    dart = Path("frontend/lib/features/moderation/moderation_repository.dart")
    if not dart.exists():  # backend checkouts do not carry the client
        pytest.skip("frontend not present")

    source = dart.read_text(encoding="utf-8")
    body = source[source.index("enum ReportReason"):source.index("class BlockedUser")]
    client = set(re.findall(r"\('([a-z_]+)'\)", body))

    from app.models import ReportReason

    assert client == {r.value for r in ReportReason}


def test_a_reporter_can_see_what_they_filed() -> None:
    """Submitting a report into silence gives no reason to trust the process."""
    from app.main import app

    assert "/api/v1/reports/mine" in app.openapi()["paths"]


# ── Route contract ───────────────────────────────────────────────────────────

@pytest.mark.parametrize(
    "path,method",
    [
        ("/api/v1/users/{user_id}/block", "post"),
        ("/api/v1/users/{user_id}/block", "delete"),
        ("/api/v1/users/{user_id}/block-status", "get"),
        ("/api/v1/users/blocked", "get"),
        ("/api/v1/reports", "post"),
        ("/api/v1/reports/mine", "get"),
    ],
)
def test_route_registered(path: str, method: str) -> None:
    from app.main import app

    paths = app.openapi()["paths"]
    assert path in paths, f"{path} is not registered"
    assert method in paths[path]


# ── Integration checklist ────────────────────────────────────────────────────
#
# Needs a live Postgres:
#   * a blocked send is actually refused end-to-end over the WebSocket
#   * the ck_block_not_self constraint rejects a self-block at the DB level
#   * ix_reports_unique_message rejects a duplicate report at the DB level
#   * a report survives its message row being deleted
#   * migration 0005 applies cleanly on a database already at 0004
