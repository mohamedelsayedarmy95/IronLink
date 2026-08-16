"""Client-side hardening invariants.

These live with the backend suite because they are cheap greps over the
Flutter source, and because the properties they protect are the kind that
break silently: nothing fails, data is simply lost or exposed.
"""
from __future__ import annotations

from pathlib import Path

import pytest

FRONTEND = Path("frontend")
ANDROID_MAIN = FRONTEND / "android/app/src/main"


def _skip_without_frontend() -> None:
    if not FRONTEND.exists():
        pytest.skip("frontend not present")


def _dart_sources() -> list[Path]:
    return [
        p for p in (FRONTEND / "lib").rglob("*.dart")
        if "l10n" not in p.parts
    ]


# ── Secure storage must be configured in exactly one place ───────────────────

def test_no_file_constructs_its_own_secure_storage() -> None:
    """On Android the plugin keeps everything in one preferences file, and the
    plain and EncryptedSharedPreferences backends cannot read each other's
    entries. Two differently-configured instances therefore destroy each
    other's data, with no error anywhere.

    That is not hypothetical: it wiped the auth token on a real device, which
    presented as a 401 at login and a lost session on the next launch.
    """
    _skip_without_frontend()

    offenders = []
    for path in _dart_sources():
        if path.name == "secure_storage.dart":
            continue  # the single definition
        source = path.read_text(encoding="utf-8")
        for line in source.splitlines():
            stripped = line.strip()
            if stripped.startswith("//"):
                continue
            if "FlutterSecureStorage(" in stripped:
                offenders.append(f"{path.as_posix()}: {stripped}")

    assert not offenders, (
        "these construct their own secure storage instead of using "
        "ironSecureStorage, which silently destroys the others' data:\n  "
        + "\n  ".join(offenders)
    )


def test_the_shared_storage_uses_the_encrypted_backend() -> None:
    _skip_without_frontend()

    source = (FRONTEND / "lib/core/secure_storage.dart").read_text(
        encoding="utf-8"
    )
    assert "encryptedSharedPreferences: true" in source


# ── The device must not back up plaintext ────────────────────────────────────

def test_android_backup_is_disabled() -> None:
    """Unset, allowBackup defaults to true and Auto Backup copies /data/data
    to the user's Google Drive — which here means the decrypted message cache
    and the Signal identity and session keys."""
    _skip_without_frontend()

    manifest = (ANDROID_MAIN / "AndroidManifest.xml").read_text(
        encoding="utf-8"
    )
    assert 'android:allowBackup="false"' in manifest
    assert 'android:dataExtractionRules="@xml/data_extraction_rules"' in manifest


def test_android_12_extraction_rules_refuse_both_channels() -> None:
    """Android 12+ splits the old flag into cloud backup and device transfer,
    and both would carry the same material."""
    _skip_without_frontend()

    rules = (ANDROID_MAIN / "res/xml/data_extraction_rules.xml").read_text(
        encoding="utf-8"
    )
    assert "<cloud-backup>" in rules
    assert "<device-transfer>" in rules
    # Every domain that could hold keys or messages.
    for domain in ("database", "sharedpref", "file", "root"):
        assert rules.count(f'domain="{domain}"') == 2, domain


# ── Cleartext cannot be shipped ──────────────────────────────────────────────

def test_the_release_network_config_permits_no_cleartext() -> None:
    """It used to carry developer LAN addresses with a comment asking whoever
    shipped the release to delete them — a control that works until the once
    it does not, and fails silently."""
    _skip_without_frontend()

    import re

    raw = (ANDROID_MAIN / "res/xml/network_security_config.xml").read_text(
        encoding="utf-8"
    )
    # Comments are stripped first: the file explains why the development
    # exceptions were moved out, and that explanation names the very element
    # this asserts is absent.
    config = re.sub(r"<!--.*?-->", "", raw, flags=re.DOTALL)

    assert 'cleartextTrafficPermitted="false"' in config
    assert 'cleartextTrafficPermitted="true"' not in config
    assert "<domain-config" not in config


def test_the_development_exceptions_are_debug_only() -> None:
    """They live in src/debug, which Gradle merges into debug variants only,
    so a release build cannot contain them."""
    _skip_without_frontend()

    debug_config = (
        FRONTEND / "android/app/src/debug/res/xml/network_security_config.xml"
    )
    assert debug_config.exists()
    assert 'cleartextTrafficPermitted="true"' in debug_config.read_text(
        encoding="utf-8"
    )
