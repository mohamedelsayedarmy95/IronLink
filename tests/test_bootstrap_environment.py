"""Synthetic credentials; Linux exec behavior, not a Windows environment mock."""
from __future__ import annotations

import os
from pathlib import Path
import subprocess
import sys

import pytest

from app.config import Settings
from app.core.bootstrap_environment import PRIVILEGED_VARIABLES, runtime_environment

ROOT = Path(__file__).resolve().parents[1]


@pytest.mark.parametrize("name", sorted(PRIVILEGED_VARIABLES))
def test_conflicting_case_variants_are_rejected_without_values(monkeypatch, name):
    monkeypatch.setenv(name, "synthetic-first-secret")
    monkeypatch.setenv(name.lower(), "synthetic-second-secret")
    # Windows collapses env keys. The real Linux test below covers simultaneous
    # variants; test the validator directly here on both platforms.
    from app.core.bootstrap_environment import validate_privileged_environment
    with pytest.raises(ValueError, match="Conflicting case variants") as error:
        validate_privileged_environment({name: "synthetic-first-secret", name.lower(): "synthetic-second-secret"})
    assert "synthetic-first-secret" not in str(error.value)
    if sys.platform != "win32":
        with pytest.raises(ValueError, match="Conflicting case variants"):
            Settings(_env_file=None)


def test_filter_preserves_runtime_credentials():
    runtime = {"DATABASE_URL": "runtime-synthetic", "POSTGRES_PASSWORD": "runtime-only"}
    assert runtime_environment(runtime | {"mIgRaTiOn_DaTaBaSe_Url": "owner-only"}) == runtime


def test_real_linux_uvicorn_process_receives_no_owner_credentials():
    # Use the installed Uvicorn executable. A tiny app import probes its actual
    # environment and exits before any server or external connection is opened.
    script = r'''set -eu
taskdir=$(mktemp -d)
trap 'rm -rf "$taskdir"' EXIT
mkdir "$taskdir/app"
echo 'from pkgutil import extend_path; __path__ = extend_path(__path__, __name__)' > "$taskdir/app/__init__.py"
cat > "$taskdir/app/main.py" <<'PYTHON'
import os
from app.core.bootstrap_environment import PRIVILEGED_VARIABLES
assert not any(key.upper() in PRIVILEGED_VARIABLES for key in os.environ)
assert os.environ['DATABASE_URL'] == 'synthetic-runtime-kept'
print('REAL_UVICORN_ENVIRONMENT_VERIFIED', flush=True)
raise SystemExit(0)
PYTHON
export PYTHONPATH="$taskdir:$PWD"
export DATABASE_URL=synthetic-runtime-kept
export mIgRaTiOn_DaTaBaSe_Url=synthetic-owner
export MIGRATION_POSTGRES_PASSWORD=synthetic-owner
export local_postgres_admin_password=synthetic-admin
export PORT= WEB_CONCURRENCY=
cd "$taskdir"
"$REAL_PYTHON" -m scripts.run_runtime
'''
    if sys.platform == "win32":
        args = ["docker", "run", "--rm", "-i", "--network", "none",
                "--mount", f"type=bind,source={ROOT},target=/task,readonly",
                "--workdir", "/task", "--env", "REAL_PYTHON=/usr/local/bin/python",
                "--entrypoint", "sh", "ironlink-api", "-s"]
        environment = os.environ.copy()
    else:
        args = ["sh", "-s"]
        environment = {"PATH": os.environ["PATH"], "REAL_PYTHON": sys.executable,
                       "PYTHONDONTWRITEBYTECODE": "1"}
    result = subprocess.run(args, input=script.encode(), cwd=ROOT, env=environment,
                            capture_output=True, timeout=30)
    assert result.returncode == 0, result.stderr.decode("utf-8", "replace")
    assert b"REAL_UVICORN_ENVIRONMENT_VERIFIED" in result.stdout


@pytest.mark.parametrize("casing", ["upper", "lower", "mixed", "simultaneous", "conflicting"])
@pytest.mark.parametrize("migrations", ["true", "false"])
@pytest.mark.parametrize("fail", [False, True])
def test_linux_entrypoint_exec_environment(casing, migrations, fail):
    privileged = {}
    for name in PRIVILEGED_VARIABLES:
        names = [name] if casing == "upper" else [name.lower()] if casing == "lower" else [
            "".join(c.lower() if i % 2 else c.upper() for i, c in enumerate(name))]
        if casing in {"simultaneous", "conflicting"}:
            names += [name, name.lower()]
        for key in names:
            privileged[key] = ("postgres://owner:synthetic-owner@localhost/test"
                               if name == "MIGRATION_DATABASE_URL" else
                               "owner" if name == "MIGRATION_POSTGRES_USER" else "synthetic-owner")
        if casing == "conflicting":
            privileged[name.lower()] = "synthetic-conflicting-secret"
    environment = dict(privileged, DATABASE_URL="postgres://runtime:synthetic-runtime@localhost/test",
                       POSTGRES_PASSWORD="", SECRET_KEY="s" * 64, DB_ENCRYPTION_KEY="e" * 32,
                       RUN_MIGRATIONS_ON_START=migrations, BOOTSTRAP_TEST_FAILURE="37" if fail else "0")
    script = r'''set -eu
taskdir=$(mktemp -d)
trap 'rm -rf "$taskdir"' EXIT
mkdir "$taskdir/bin"
cat > "$taskdir/bin/python" <<'PYTHON'
#!/bin/sh
set -e
if [ "$1" = "-m" ] && [ "$2" = "scripts.bootstrap_database" ]; then
    echo DB_ARGS:$*
    if [ "$BOOTSTRAP_TEST_FAILURE" != 0 ]; then exit "$BOOTSTRAP_TEST_FAILURE"; fi
    "$REAL_PYTHON" -c 'from app.config import settings; assert settings.migration_connection_url().username == "owner"'
    exit 0
fi
exec "$REAL_PYTHON" "$@"
PYTHON
cat > "$taskdir/bin/uvicorn" <<'UVICORN'
#!/bin/sh
exec "$REAL_PYTHON" -c 'import os; from app.core.bootstrap_environment import PRIVILEGED_VARIABLES; assert not any(k.upper() in PRIVILEGED_VARIABLES for k in os.environ); assert os.environ["DATABASE_URL"] == "postgres://runtime:synthetic-runtime@localhost/test"; print("API_STARTED")'
UVICORN
chmod +x "$taskdir/bin/python" "$taskdir/bin/uvicorn"
export PATH="$taskdir/bin:$PATH"
sh docker-entrypoint.sh
'''
    if sys.platform == "win32":
        # New networkless container from an existing Python image. Never exec
        # into, stop or otherwise change the developer's running API container.
        args = ["docker", "run", "--rm", "-i", "--network", "none",
                "--mount", f"type=bind,source={ROOT},target=/task,readonly",
                "--workdir", "/task", "--env", "REAL_PYTHON=/usr/local/bin/python"]
        for key, value in environment.items():
            args += ["--env", f"{key}={value}"]
        args += ["--entrypoint", "sh", "ironlink-api", "-s"]
        child_env = os.environ.copy()
    else:
        args = ["sh", "-s"]
        child_env = {"PATH": os.environ["PATH"], "REAL_PYTHON": sys.executable,
                     "PYTHONDONTWRITEBYTECODE": "1", **environment}
    result = subprocess.run(args, input=script.encode(), cwd=ROOT,
                            env=child_env, capture_output=True, timeout=45)
    assert result.returncode == (37 if fail else 1 if casing == "conflicting" else 0), "Linux entrypoint environment assertion failed"
    assert (b"API_STARTED" in result.stdout) == (not fail and casing != "conflicting")
    assert (b"--check-only" in result.stdout) == (migrations == "false")
    assert b"synthetic-conflicting-secret" not in result.stdout + result.stderr


@pytest.mark.parametrize("failure", ["skip", "missing_admin", "deselected", "missing_reporter"])
def test_mandatory_security_gate_fails_on_skip(tmp_path, failure):
    (tmp_path / "test_forced_skip.py").write_text("import pytest\ndef test_skip(): pytest.skip('synthetic')\n")
    environment = os.environ.copy()
    environment["IRONLINK_REQUIRE_POSTGRES_SECURITY"] = "1"
    environment["IRONLINK_TEST_ADMIN_URL"] = "synthetic-not-connected"
    if failure == "missing_admin":
        environment.pop("IRONLINK_TEST_ADMIN_URL")
    extra = ["-k", "absent_test"] if failure == "deselected" else []
    if failure == "missing_reporter":
        extra = ["-p", "no:terminal", "-o", "addopts="]
    verbosity = [] if failure == "missing_reporter" else ["-q"]
    result = subprocess.run([sys.executable, "-m", "pytest", *verbosity, "-p", "no:cacheprovider",
                             "--confcutdir=" + str(ROOT / "tests"),
                             "-p", "tests.conftest", str(tmp_path / "test_forced_skip.py"), *extra],
                            env=environment, cwd=ROOT, capture_output=True, timeout=30)
    assert result.returncode == 1


def test_disposable_runner_fails_when_docker_service_is_unavailable():
    environment = {key: value for key, value in os.environ.items()
                   if not key.upper().startswith("DOCKER_")}
    environment["DOCKER_HOST"] = "tcp://127.0.0.1:1"
    result = subprocess.run([sys.executable, "-m", "scripts.test_postgres_bootstrap", "--security-only"],
                            cwd=ROOT, env=environment, capture_output=True, timeout=30)
    assert result.returncode == 1
    assert b"isolated verification failed" in result.stderr
