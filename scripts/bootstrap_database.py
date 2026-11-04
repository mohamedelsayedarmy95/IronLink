"""Fail-closed startup entry point. Never prints a DSN or driver exception."""
from __future__ import annotations

import argparse
import sys


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Validate and initialize IronLink PostgreSQL")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check-only", action="store_true")
    mode.add_argument("--post-migrate-only", action="store_true")
    args = parser.parse_args(argv)
    try:
        from app.config import settings
        from app.core.database_config import DatabaseConfigurationError
        from app.core.database_bootstrap import BootstrapError, bootstrap, verify_runtime
        if args.check_only:
            verify_runtime(settings)
        else:
            bootstrap(settings, migrate=(lambda: None) if args.post_migrate_only else None)
    except Exception as exc:
        # Driver/Pydantic exceptions can contain credentials or SQL parameters.
        # Only our own explicitly sanitized messages may reach container logs.
        safe_types = ("BootstrapError", "DatabaseConfigurationError")
        from pydantic import ValidationError
        if isinstance(exc, ValidationError):
            # Settings validators emit sanitized messages. Never render input,
            # context, a DSN, or the exception's full structured representation.
            errors = exc.errors(include_input=False, include_context=False, include_url=False)
            detail = "; ".join(error["msg"] for error in errors)
        else:
            detail = str(exc) if type(exc).__name__ in safe_types else type(exc).__name__
        print(f"[database] initialization refused: {detail}", file=sys.stderr)
        return 1
    print("[database] schema and runtime privileges verified")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
