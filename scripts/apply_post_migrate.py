"""Compatibility entry point for owner hardening after standalone Alembic.

The supported startup path is scripts.bootstrap_database; both paths share
configuration, identity checks, locking, grants and verification.
"""
from __future__ import annotations

if __package__ in (None, ""):
    import sys
    from pathlib import Path
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

def main() -> None:
    from scripts.bootstrap_database import main as bootstrap_main
    raise SystemExit(bootstrap_main(["--post-migrate-only"]))


if __name__ == "__main__":
    main()
