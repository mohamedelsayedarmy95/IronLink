"""PostgreSQL URL handling shared by runtime, Alembic and bootstrap.

No environment access or application imports here. Errors never include a DSN.
"""
from __future__ import annotations

from sqlalchemy.engine import URL, make_url


class DatabaseConfigurationError(ValueError):
    pass


def postgres_url(value: str) -> URL:
    try:
        url = make_url(value)
        if url.drivername not in {
            "postgres", "postgresql", "postgresql+asyncpg", "postgresql+psycopg2"
        }:
            raise ValueError
        if not all((url.username, url.password, url.host, url.database)):
            raise ValueError
        port = 5432 if url.port is None else url.port
        if any(c in url.host for c in "@/\\") or not 1 <= port <= 65535:
            raise ValueError
        # Target/identity overrides in libpq query parameters would defeat target
        # comparison. Only the SSL option common to our two drivers is supported.
        if set(url.query) - {"ssl", "sslmode"}:
            raise ValueError
        mode = url.query.get("ssl", url.query.get("sslmode"))
        if "ssl" in url.query and "sslmode" in url.query and url.query["ssl"] != url.query["sslmode"]:
            raise ValueError
        if mode is not None and mode not in {
            "disable", "allow", "prefer", "require", "verify-ca", "verify-full"
        }:
            raise ValueError
        return url.set(
            drivername="postgresql+asyncpg", port=port,
            query={"ssl": mode} if mode else {},
        )
    except Exception:
        raise DatabaseConfigurationError(
            "Invalid PostgreSQL configuration: require a supported PostgreSQL URL "
            "with user, password, host and database; percent-encode URL credentials. "
            "Only ssl/sslmode query parameters are supported."
        ) from None


def discrete_url(*, user: str, password: str, host: str, port: int, database: str) -> URL:
    return postgres_url(URL.create(
        "postgresql", username=user, password=password, host=host,
        port=port, database=database,
    ).render_as_string(hide_password=False))


def sync_url(url: URL) -> URL:
    mode = url.query.get("ssl")
    return url.set(drivername="postgresql+psycopg2", query={"sslmode": mode} if mode else {})


def connect_kwargs(url: URL) -> dict:
    result = dict(host=url.host, port=url.port, user=url.username,
                  password=url.password, dbname=url.database, connect_timeout=10)
    if url.query.get("ssl"):
        result["sslmode"] = url.query["ssl"]
    return result


def same_target(left: URL, right: URL) -> bool:
    return (left.host.lower(), 5432 if left.port is None else left.port, left.database) == (
        right.host.lower(), 5432 if right.port is None else right.port, right.database
    )
