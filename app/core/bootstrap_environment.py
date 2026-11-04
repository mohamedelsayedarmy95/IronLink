"""Credential boundary between bootstrap and the application process."""
from __future__ import annotations

PRIVILEGED_VARIABLES = frozenset({
    "MIGRATION_DATABASE_URL", "MIGRATION_POSTGRES_USER",
    "MIGRATION_POSTGRES_PASSWORD", "LOCAL_POSTGRES_ADMIN_PASSWORD",
})


def validate_privileged_environment(environment) -> None:
    for name in PRIVILEGED_VARIABLES:
        values = {value for key, value in environment.items() if key.upper() == name}
        if len(values) > 1:
            # Never include names supplied by callers, values or connection URLs.
            raise ValueError("Conflicting case variants of bootstrap environment variables")


def runtime_environment(environment) -> dict[str, str]:
    return {key: value for key, value in environment.items()
            if key.upper() not in PRIVILEGED_VARIABLES}
