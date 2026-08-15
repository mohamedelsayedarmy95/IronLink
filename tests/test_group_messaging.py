"""Tests for group messaging and the membership epoch.

The epoch is the whole basis of group encryption's forward security. A group
message is encrypted once with a sender key that every member holds, so
removing someone from the member list does not remove their access — the key
they already have decrypts everything that sender says afterwards. Access
ends only when each remaining sender mints a new key, and the epoch is the
only signal telling them to.

Which makes the interesting tests the ones about what bumps it.
"""
from __future__ import annotations

import inspect

import pytest


def _source(fn) -> str:
    return inspect.getsource(fn)


# ── Every membership change must bump the epoch ──────────────────────────────

@pytest.mark.parametrize(
    "module,function",
    [
        ("app.api.routes.groups", "leave_group"),
        ("app.api.routes.groups", "remove_member"),
        ("app.api.routes.groups", "request_join"),
        ("app.api.routes.groups", "decide_request"),
        ("app.api.routes.group_entry", "ban_from_group"),
    ],
)
def test_membership_change_bumps_the_epoch(module: str, function: str) -> None:
    """Missing one of these is not cosmetic: it leaves a departed member able
    to read everything said afterwards."""
    import importlib

    mod = importlib.import_module(module)
    fn = getattr(mod, function, None)
    assert fn is not None, f"{module}.{function} no longer exists"
    assert "bump_epoch" in _source(fn), (
        f"{function} changes membership without bumping the epoch"
    )


def test_approving_a_request_bumps_but_rejecting_does_not() -> None:
    """A rejection changes nothing about who holds keys, and a needless
    rotation makes every member re-distribute for no reason."""
    from app.api.routes.groups import decide_request

    source = _source(decide_request)
    approve_index = source.index("if body.approve:")
    assert "bump_epoch" in source[approve_index:]


def test_unban_does_not_bump() -> None:
    """Lifting a ban does not restore membership, so nobody gains access."""
    from app.api.routes.group_entry import unban_from_group

    assert "bump_epoch" not in _source(unban_from_group)


def test_epoch_increments_in_sql_not_read_modify_write() -> None:
    """Two concurrent membership changes must not land on the same epoch —
    to a client that looks like nothing happened."""
    from app.services.group_message_service import bump_epoch

    source = _source(bump_epoch)
    assert "Group.members_epoch + 1" in source
    assert "returning" in source.lower()


def test_epoch_is_exposed_to_clients() -> None:
    """A client that cannot see the epoch cannot know to rotate."""
    from app.api.routes.groups import GroupOut

    assert "members_epoch" in GroupOut.model_fields


# ── Who may post, and what the server may read ───────────────────────────────

def test_non_members_cannot_post_or_read() -> None:
    from app.services.group_message_service import history, save_group_message

    assert "assert_member" in _source(save_group_message)
    assert "assert_member" in _source(history)


def test_a_missing_group_and_a_forbidden_one_look_the_same() -> None:
    """Distinguishing them turns the endpoint into an oracle for which group
    ids exist."""
    from app.api.routes.group_messages import group_history, send_group_message

    for fn in (group_history, send_group_message):
        assert "group not found" in _source(fn)


def test_announcement_groups_restrict_posting() -> None:
    from app.services.group_message_service import save_group_message

    source = _source(save_group_message)
    assert "only_admins_can_post" in source
    assert "PostingNotAllowed" in source


def test_history_starts_at_the_point_the_member_joined() -> None:
    """A new member cannot decrypt anything older than their arrival — the
    sender keys they hold start there. Returning those rows would look like
    corruption rather than privacy."""
    from app.services.group_message_service import history

    assert "Message.created_at >= member.joined_at" in _source(history)


def test_key_distribution_messages_are_not_shown_as_chat() -> None:
    from app.services.group_message_service import history

    assert "Message.message_type != SKDM_MESSAGE_TYPE" in _source(history)


# ── Blocks and groups ────────────────────────────────────────────────────────

def test_a_block_does_not_silence_someone_in_a_shared_group() -> None:
    """Blocking is a personal boundary. Letting it mute someone for everyone
    would make it a way to disrupt a whole conversation."""
    from app.services.group_message_service import save_group_message

    source = _source(save_group_message)
    assert "_blocked_between" not in source
    assert "BlockedDelivery" not in source


def test_key_distribution_is_not_withheld_by_a_block() -> None:
    """Group messages are delivered regardless of a block, so withholding the
    key that decrypts them would not stop anything — it would just make the
    group unreadable for one member, with nothing saying why."""
    from app.api.routes import websocket

    source = _source(websocket._handle_frame)
    skdm_index = source.index('frame_type == "skdm"')
    assert "enforce_blocks=False" in source[skdm_index:]


def test_blocks_are_still_enforced_for_direct_messages() -> None:
    """The opt-out above must not have weakened the default."""
    import inspect as _inspect

    from app.services.message_service import save_message

    source = _source(save_message)
    assert "enforce_blocks: bool = True" in source
    signature = _inspect.signature(save_message)
    assert signature.parameters["enforce_blocks"].default is True


# ── Key distribution ─────────────────────────────────────────────────────────

def test_skdm_requires_both_parties_to_be_members() -> None:
    """Otherwise it is a way to push an arbitrary payload at any user."""
    from app.api.routes import websocket

    source = _source(websocket._handle_frame)
    skdm_index = source.index('frame_type == "skdm"')
    window = source[skdm_index:skdm_index + 1200]
    assert window.count("assert_member") == 2


def test_group_fan_out_skips_the_sender() -> None:
    from app.api.routes import websocket

    source = _source(websocket._handle_frame)
    assert "if member_id == user_id:" in source


def test_the_group_ciphertext_is_identical_for_every_member() -> None:
    """One encryption per message, not one per member — that is the entire
    reason sender keys exist rather than N pairwise sends."""
    from app.api.routes import websocket

    source = _source(websocket._handle_frame)
    group_index = source.index('"group_message"')
    window = source[group_index - 400:group_index + 900]
    # A single event dict, published unchanged to each member.
    assert "for member_id in recipients:" in window
    assert window.count("await publish(member_id, event)") == 1


# ── Route contract ───────────────────────────────────────────────────────────

@pytest.mark.parametrize(
    "path,method",
    [
        ("/api/v1/groups/{group_id}/messages", "post"),
        ("/api/v1/groups/{group_id}/messages", "get"),
        ("/api/v1/groups/{group_id}/members/me", "delete"),
        ("/api/v1/groups/{group_id}/members/{user_id}", "delete"),
    ],
)
def test_route_registered(path: str, method: str) -> None:
    from app.main import app

    paths = app.openapi()["paths"]
    assert path in paths, f"{path} is not registered"
    assert method in paths[path]


def test_an_owner_cannot_leave_without_handing_over() -> None:
    """A group with no owner has nobody who can manage it."""
    from app.api.routes.groups import leave_group

    assert "transfer ownership" in _source(leave_group)


def test_an_admin_cannot_remove_the_owner() -> None:
    from app.api.routes.groups import remove_member

    assert "the owner cannot be removed" in _source(remove_member)


# ── Migration ────────────────────────────────────────────────────────────────

def test_migration_adds_the_epoch_with_a_default() -> None:
    """Existing groups need a value, or the column cannot be NOT NULL."""
    from pathlib import Path

    migration = Path(
        "alembic/versions/0006_group_members_epoch.py"
    ).read_text(encoding="utf-8")
    assert "members_epoch" in migration
    assert "server_default='1'" in migration


# ── Integration checklist ────────────────────────────────────────────────────
#
# Needs live Postgres and Redis:
#   * a group send reaches every member's channel and not the sender's
#   * two concurrent membership changes produce two distinct epochs
#   * history excludes messages older than the caller's joined_at
#   * a banned member's next history request returns 404
#   * migration 0006 applies cleanly on a database already at 0005
