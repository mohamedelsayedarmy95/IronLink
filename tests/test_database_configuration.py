"""Configuration tests use synthetic credentials and never open a connection."""
from __future__ import annotations

import pytest
from pydantic import ValidationError

from app.config import Settings
from app.core.database_config import (
    DatabaseConfigurationError, connect_kwargs, discrete_url, postgres_url, sync_url,
)


@pytest.fixture
def config(monkeypatch):
    for key in ("DATABASE_URL", "MIGRATION_DATABASE_URL", "MIGRATION_POSTGRES_USER",
                "MIGRATION_POSTGRES_PASSWORD", "POSTGRES_USER", "POSTGRES_PASSWORD",
                "POSTGRES_HOST", "POSTGRES_PORT", "POSTGRES_DB"):
        monkeypatch.delenv(key, raising=False)
    return lambda **kwargs: Settings(_env_file=None, **kwargs)


@pytest.mark.parametrize("driver", ["postgres", "postgresql", "postgresql+asyncpg", "postgresql+psycopg2"])
def test_supported_dialects_and_ssl_round_trip(driver):
    url = postgres_url(f"{driver}://runtime:test-only@localhost/db?sslmode=require")
    assert url.drivername == "postgresql+asyncpg"
    assert url.query == {"ssl": "require"}
    assert sync_url(url).query == {"sslmode": "require"}
    assert connect_kwargs(url)["sslmode"] == "require"


@pytest.mark.parametrize("port", ["0", "-1", "65536", "bad", "1.5"])
def test_invalid_url_ports_fail_without_echoing_credentials(port):
    with pytest.raises(DatabaseConfigurationError) as error:
        postgres_url(f"postgres://runtime:synthetic-private@localhost:{port}/db")
    assert "synthetic-private" not in str(error.value)


@pytest.mark.parametrize("port", [0, -1, 65536, "bad", "1.5"])
def test_invalid_component_ports_fail(config, port):
    with pytest.raises((ValidationError, DatabaseConfigurationError)):
        config(POSTGRES_PASSWORD="test-only", POSTGRES_PORT=port)


@pytest.mark.parametrize("port", [1, 5432, 6432, 65535])
def test_custom_ports_match_across_configuration_forms(config, port):
    direct = config(POSTGRES_PASSWORD="test-only", POSTGRES_PORT=port)
    by_url = config(DATABASE_URL=f"postgres://runtime:test-only@localhost:{port}/db")
    assert direct.runtime_database_url().port == by_url.runtime_database_url().port == port


def test_missing_port_uses_default():
    assert postgres_url("postgres://runtime:test-only@localhost/db").port == 5432


@pytest.mark.parametrize("password", ["x@:/?#%[] space", "quote'and\"back\\slash", "كلمة-اختبار"])
def test_reserved_credentials_from_components_and_url(config, password):
    settings = config(POSTGRES_PASSWORD=password)
    url = postgres_url(settings.database_url)
    assert url.password == password
    by_url = config(DATABASE_URL=settings.database_url)
    assert by_url.runtime_database_url().password == password
    assert connect_kwargs(url)["password"] == password
    assert postgres_url(by_url.sync_database_url).password == password


def test_url_only_does_not_require_component_password(config):
    settings = config(DATABASE_URL="postgres://runtime:test-only@localhost/db")
    assert settings.runtime_database_url().username == "runtime"


@pytest.mark.parametrize("key,value", [
    ("POSTGRES_USER", "other"), ("POSTGRES_PASSWORD", "other"),
    ("POSTGRES_HOST", "other"), ("POSTGRES_PORT", 6432), ("POSTGRES_DB", "other"),
])
def test_conflicting_components_are_rejected(config, key, value):
    with pytest.raises(ValidationError, match="conflicts"):
        config(DATABASE_URL="postgres://runtime:test-only@localhost:5432/db", **{key: value})


def test_matching_explicit_components_are_accepted(config):
    settings = config(DATABASE_URL="postgres://runtime:test-only@LOCALHOST/db",
                      POSTGRES_USER="runtime", POSTGRES_PASSWORD="test-only",
                      POSTGRES_HOST="localhost", POSTGRES_DB="db")
    assert settings.runtime_database_url().database == "db"


@pytest.mark.parametrize("value", [
    "sqlite:///db", "postgresql+unknown://a:b@host/db", "postgres://user@host/db",
    "postgres://a:b@host", "postgres://a:b@host/db?host=elsewhere",
    "postgres://a:b@host/db?options=-crole=owner", "postgres://a:b@host/db?sslmode=unknown",
    "postgres://a:b@host/db?ssl=require&sslmode=disable", "not-a-url",
])
def test_invalid_urls_and_target_override_parameters_are_rejected(value):
    with pytest.raises(DatabaseConfigurationError):
        postgres_url(value)


def test_missing_runtime_password_fails(config):
    with pytest.raises(ValidationError):
        config()


def test_missing_owner_does_not_fall_back_to_runtime(config):
    settings = config(POSTGRES_PASSWORD="test-only")
    with pytest.raises(DatabaseConfigurationError, match="separate MIGRATION"):
        settings.migration_connection_url()


@pytest.mark.parametrize("owner", [
    "postgres://runtime:other@localhost/db", "postgres://owner:other@elsewhere/db",
    "postgres://owner:other@localhost/other", "postgres://owner:other@localhost:6432/db",
])
def test_invalid_owner_identity_or_database_target_fails(config, owner):
    with pytest.raises(ValidationError):
        config(DATABASE_URL="postgres://runtime:test-only@localhost/db", MIGRATION_DATABASE_URL=owner)


def test_migration_components_target_runtime_database(config):
    settings = config(POSTGRES_PASSWORD="test-only", POSTGRES_HOST="localhost",
                      MIGRATION_POSTGRES_USER="owner", MIGRATION_POSTGRES_PASSWORD="a@:/#%")
    owner = settings.migration_connection_url()
    assert owner.password == "a@:/#%"
    assert owner.host == "localhost"
    assert owner.username == "owner"


def test_conflicting_migration_credentials_fail_without_exposing_secrets(config):
    secret = "distinctive-secret-not-for-logs"
    with pytest.raises(ValidationError) as error:
        config(DATABASE_URL=f"postgres://runtime:{secret}@localhost/db",
               MIGRATION_DATABASE_URL="postgres://owner:owner-only@localhost/db",
               MIGRATION_POSTGRES_PASSWORD="different")
    assert secret not in str(error.value)
    assert "owner-only" not in str(error.value)
    assert "different" not in str(error.value)


def test_cli_does_not_print_driver_exception_secrets(monkeypatch, capsys):
    from app.core import database_bootstrap
    from scripts.bootstrap_database import main
    def fail(_settings, **_kwargs):
        raise RuntimeError("postgres://owner:must-not-print@localhost/db")
    monkeypatch.setattr(database_bootstrap, "bootstrap", fail)
    assert main([]) == 1
    assert "must-not-print" not in capsys.readouterr().err


def test_cli_reports_configuration_conflicts_without_input_secrets(config, monkeypatch, capsys):
    from app.core import database_bootstrap
    from scripts.bootstrap_database import main
    with pytest.raises(ValidationError) as invalid:
        config(DATABASE_URL="postgres://runtime:do-not-log-this@localhost/db", POSTGRES_PASSWORD="different-secret")
    def fail(_settings, **_kwargs):
        raise invalid.value
    monkeypatch.setattr(database_bootstrap, "bootstrap", fail)
    assert main([]) == 1
    error = capsys.readouterr().err
    assert "DATABASE_URL conflicts with POSTGRES_PASSWORD" in error
    assert "do-not-log-this" not in error
    assert "different-secret" not in error
