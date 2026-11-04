"""Exec the API with bootstrap-only credentials removed in every casing."""
from __future__ import annotations

import os
import subprocess
import sys

from app.core.bootstrap_environment import runtime_environment


def main() -> None:
    environment = runtime_environment(os.environ)
    # Seeds also receive only runtime credentials.
    if environment.get("SEED_TEST_PHONE_USER", "false") == "true":
        subprocess.run([sys.executable, "-m", "scripts.seed_test_phone_auth_user"],
                       env=environment, check=True)
    os.execvpe("uvicorn", [
        "uvicorn", "app.main:app", "--host", "0.0.0.0",
        "--port", environment.get("PORT") or "8000",
        "--workers", environment.get("WEB_CONCURRENCY") or "1",
        "--loop", "uvloop", "--http", "h11", "--proxy-headers",
        "--forwarded-allow-ips", "*",
    ], environment)


if __name__ == "__main__":
    main()
