"""Run pytest against a NEW, loopback-only, tmpfs PostgreSQL 16 container.

Usage: python -m scripts.test_postgres_bootstrap -- -q -p no:cacheprovider
Only this invocation's labeled container is stopped. Existing resources are
never selected, reused, reset or deleted. No production credentials are read.
"""
from __future__ import annotations

import os
from pathlib import Path
import secrets
import subprocess
import sys
from tempfile import TemporaryDirectory
import time
import uuid

import psycopg2
from psycopg2 import sql

from app.core.database_config import connect_kwargs, discrete_url


def main() -> int:
    token = uuid.uuid4().hex
    name = "ironlink-m01a-" + token
    label = "ironlink.mission01a=" + token
    env = os.environ.copy()
    for key in list(env):
        if key.upper().startswith(("POSTGRES_", "MIGRATION_", "IRONLINK_TEST_")) or key.upper() in {
            "DATABASE_URL", "TEST_DATABASE_URL", "PGPASSWORD", "PGSERVICE", "PGOPTIONS",
        }:
            env.pop(key)
    env["POSTGRES_PASSWORD"] = secrets.token_urlsafe(32)
    container = None

    def docker(*args, timeout=120):
        result = subprocess.run(["docker", *args], env=env, text=True,
                                capture_output=True, timeout=timeout)
        if result.returncode:
            raise RuntimeError("Disposable PostgreSQL container operation failed")
        return result.stdout.strip()

    try:
        docker("run", "--detach", "--rm", "--name", name, "--label", label,
               "--publish", "127.0.0.1::5432", "--mount", "type=tmpfs,destination=/var/lib/postgresql/data",
               "--env", "POSTGRES_PASSWORD", "postgres:16-alpine", "postgres",
               "-c", "cluster_name=ironlink_m01a_" + token)
        container = name
        port = int(docker("port", name, "5432/tcp").rsplit(":", 1)[1])
        admin = discrete_url(user="postgres", password=env["POSTGRES_PASSWORD"],
                             host="127.0.0.1", port=port, database="postgres")
        deadline = time.monotonic() + 60
        while True:
            try:
                conn = psycopg2.connect(**connect_kwargs(admin))
                break
            except psycopg2.OperationalError:
                if time.monotonic() >= deadline:
                    raise RuntimeError("Disposable PostgreSQL did not become ready") from None
                time.sleep(0.3)
        conn.autocommit = True
        database = "ironlink_suite_" + token
        with conn.cursor() as cur:
            cur.execute(sql.SQL("CREATE DATABASE {}").format(sql.Identifier(database)))
        conn.close()
        env.pop("POSTGRES_PASSWORD")
        env["TEST_DATABASE_URL"] = admin.set(database=database).render_as_string(hide_password=False)
        env["IRONLINK_TEST_ADMIN_URL"] = admin.render_as_string(hide_password=False)
        env["IRONLINK_TEST_CONTAINER"] = name
        env["PYTHONDONTWRITEBYTECODE"] = "1"
        args = sys.argv[1:]
        if args[:1] == ["--"]:
            args = args[1:]
        if args[:1] == ["--security-only"]:
            if len(args) != 1:
                raise RuntimeError("Security gate does not accept test selection overrides")
            env["IRONLINK_REQUIRE_POSTGRES_SECURITY"] = "1"
            args = ["-q", "-p", "no:cacheprovider", "tests/test_postgres_bootstrap.py",
                    "tests/test_database_configuration.py", "tests/test_bootstrap_environment.py"]
        print("[pg16] new isolated PostgreSQL 16 cluster ready; running pytest", flush=True)
        with TemporaryDirectory(prefix="ironlink-pg16-tests-") as task_temp:
            return subprocess.run([sys.executable, "-m", "pytest",
                                   "--basetemp=" + str(Path(task_temp) / "pytest"), *args], env=env,
                                  cwd=Path(__file__).resolve().parents[1]).returncode
    except Exception as exc:
        print("[pg16] isolated verification failed (" + type(exc).__name__ + ")", file=sys.stderr)
        return 1
    finally:
        if container:
            # Guard cleanup by an unpredictable invocation label, never just a
            # generic container name. --rm removes only this tmpfs container.
            actual = docker("inspect", "--format", '{{index .Config.Labels "ironlink.mission01a"}}', container)
            if actual != token:
                raise RuntimeError("Refusing to stop an unrecognized Docker resource")
            docker("stop", "--time", "5", container)
            print("[pg16] this invocation's disposable container stopped", flush=True)


if __name__ == "__main__":
    raise SystemExit(main())
