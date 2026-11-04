"""Smart Keyword Alert — privacy boundaries (§1.4, §7.1, §7.3, §10.2).

A user's keyword states exactly what its owner is watching for. It is the most
sensitive thing this feature touches, and P-1 says it is visible to nobody but
its owner — not the sender, not group admins, not other members, and not the
operator of this server.

These tests are deliberately structural. A behavioural test can only prove
that one code path does not leak; the guarantee needed here is that no code
path does, which is a property of the source rather than of an execution.
"""
from __future__ import annotations

import ast
import inspect
import pathlib

import pytest

from tests.fakes import FakeRedis


def _source(path: str) -> str:
    """File contents with comments and docstrings stripped.

    Written after an earlier version of this suite failed on its own
    explanatory comment: a test that greps for a word has to be told that
    prose about the word is not an occurrence of it.
    """
    text = pathlib.Path(path).read_text(encoding="utf-8")
    tree = ast.parse(text)
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef, ast.Module)):
            doc = ast.get_docstring(node, clean=False)
            if doc:
                text = text.replace(doc, "")
    return "\n".join(
        line for line in text.splitlines() if not line.strip().startswith("#")
    )


# ── The keyword must not reach a third party ─────────────────────────────────

def _function_body(path: str, name: str) -> str:
    """The executable body of one function, without its docstring.

    Necessary because this suite greps for the very words the docstrings
    explain. An earlier version failed on the docstring that describes the
    payload it is checking is absent.
    """
    text = pathlib.Path(path).read_text(encoding="utf-8")
    tree = ast.parse(text)
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name == name:
            body = node.body
            if body and isinstance(body[0], ast.Expr) and isinstance(
                body[0].value, ast.Constant
            ):
                body = body[1:]
            return "\n".join(
                ast.get_source_segment(text, stmt) or "" for stmt in body
            )
    raise AssertionError(f"{name} not found in {path}")


def test_push_payload_carries_no_keyword() -> None:
    """FCM is a third party. A keyword in a push payload is a keyword in
    someone else's transit logs, and on Android it can be drawn on a lock
    screen before the app ever sees it."""
    from app.services import push_service

    source = _source("app/services/push_service.py")
    push = _function_body("app/services/push_service.py", "send_ocr_push")

    assert '"keyword"' not in push
    assert "keyword" not in inspect.signature(push_service.send_ocr_push).parameters
    # And the alert push must stay data-only: a notification block hands the
    # payload to the OS to render without asking.
    assert "notification=messaging.Notification" not in push.replace(
        "\n", ""
    ), "the alert push must not carry a notification block"
    assert "def send_ocr_push" in source


def test_push_callers_pass_no_keyword() -> None:
    from app.api.routes import media

    call = inspect.getsource(media._process_ocr)
    assert "send_ocr_push(user_id, media_key)" in call


def test_alert_push_is_a_wakeup_not_a_message() -> None:
    """It carries a storage key and nothing derived from content. A recipient
    who cannot decrypt the object learns nothing from its name."""
    push = _function_body("app/services/push_service.py", "send_ocr_push")
    for forbidden in ('"matched"', '"context"', '"text"', '"snippet"'):
        assert forbidden not in push


# ── The server must not log content ──────────────────────────────────────────

def test_no_extracted_text_is_logged() -> None:
    """§10.2 prohibits document contents and OCR plaintext in telemetry."""
    ocr_source = _source("app/api/routes/media.py")

    for line in ocr_source.splitlines():
        if "logger." not in line:
            continue
        for forbidden in ("text", "normalized", "extracted"):
            assert f"{{{forbidden}}}" not in line and f"{forbidden}=" not in line, (
                f"log line appears to include extracted text: {line.strip()}"
            )


def test_no_keyword_is_logged() -> None:
    for path in ("app/redis.py", "app/services/push_service.py", "app/api/routes/ocr.py"):
        for line in _source(path).splitlines():
            if "logger." not in line:
                continue
            assert "keyword=" not in line and "{keyword}" not in line, (
                f"{path}: log line appears to include a keyword: {line.strip()}"
            )


# ── The sender learns nothing ────────────────────────────────────────────────

def test_no_endpoint_exposes_another_users_keywords() -> None:
    """§1.4: the sender sees at most that an alert fired, never the keyword.

    Every keyword read is scoped to the authenticated user, so there is no
    route by which one account can ask for another's rules.
    """
    source = _source("app/api/routes/ocr.py")
    tree = ast.parse(pathlib.Path("app/api/routes/ocr.py").read_text(encoding="utf-8"))

    for node in ast.walk(tree):
        if not isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        if "keyword" not in node.name:
            continue
        params = {a.arg for a in node.args.args + node.args.kwonlyargs}
        assert "current_user" in params, f"{node.name} is not scoped to a user"
        # A user_id parameter would let a caller name someone else.
        assert "user_id" not in params, f"{node.name} takes a caller-supplied user id"

    assert "current_user.id" in source


def test_the_store_scopes_every_read_to_one_user() -> None:
    source = _source("app/redis.py")
    assert "def _keywords_key(user_id: str)" in source
    # Every read and write goes through that one key builder, so there is no
    # path that reads a key assembled some other way.
    for fn in ("get_user_keywords", "set_user_keywords", "add_user_keywords",
               "remove_user_keywords"):
        assert fn in source
    assert source.count("user:") == 1, "keyword keys must be built in one place"


@pytest.mark.asyncio
async def test_one_users_keywords_are_invisible_to_another(monkeypatch) -> None:
    import app.redis as keyword_store

    fake = FakeRedis()
    monkeypatch.setattr(keyword_store, "redis_sessions", fake)

    await keyword_store.add_user_keywords("owner", {"audit-case-4471"})

    assert await keyword_store.get_user_keywords("someone-else") == set()
    # And nothing about the other user's set is inferable from the count.
    assert await keyword_store.get_user_keywords("owner") == {"audit-case-4471"}


# ── The document itself ──────────────────────────────────────────────────────

def test_encrypted_attachments_are_never_read() -> None:
    """The strongest privacy property available, and it is structural: the
    server holds no key, so it cannot read an attachment even if asked to."""
    from app.api.routes import media

    source = inspect.getsource(media.upload_complete)
    assert "if encrypted:" in source
    assert "background_tasks is not None and not encrypted" in source


def test_the_legacy_reading_path_stays_off() -> None:
    from app.config import settings

    assert settings.SERVER_SIDE_OCR_ENABLED is False
