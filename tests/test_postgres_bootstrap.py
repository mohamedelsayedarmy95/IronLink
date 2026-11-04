"""Real PostgreSQL role/DDL checks, never mocked permission assertions.

Run with python -m scripts.test_postgres_bootstrap -- -q tests/test_postgres_bootstrap.py
The runner creates a new tmpfs cluster. Refuse any other target, including an
arbitrary TEST_DATABASE_URL. Without the runner these integration tests skip.
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
import os
from pathlib import Path
import secrets
import subprocess
import sys
import shutil
import time
import uuid

import psycopg2
from psycopg2 import sql
import pytest

from app.config import Settings
from app.core.database_config import connect_kwargs, discrete_url, postgres_url
from app.core import database_bootstrap as bootstrap


@pytest.fixture
def database():
    value = os.environ.get("IRONLINK_TEST_ADMIN_URL")
    if not value:
        pytest.skip("Use python -m scripts.test_postgres_bootstrap for an isolated PostgreSQL 16 cluster")
    admin_url = postgres_url(value)
    if admin_url.host != "127.0.0.1" or admin_url.database != "postgres":
        pytest.fail("Refusing a non-isolated PostgreSQL test target")
    admin = psycopg2.connect(**connect_kwargs(admin_url))
    admin.autocommit = True
    with admin.cursor() as cur:
        cur.execute("SHOW cluster_name")
        assert cur.fetchone()[0].startswith("ironlink_m01a_")
        assert 160000 <= admin.server_version < 170000
        token = uuid.uuid4().hex[:16]
        owner_name, runtime_name, name = "owner_" + token, "runtime_" + token, "db_" + token
        owner_password = secrets.token_urlsafe(24) + "@:/?#%"
        runtime_password = secrets.token_urlsafe(24) + "@:/?#%"
        for role, password in [(owner_name, owner_password), (runtime_name, runtime_password)]:
            cur.execute(sql.SQL("CREATE ROLE {} LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS PASSWORD {}").format(
                sql.Identifier(role), sql.Literal(password)))
        cur.execute(sql.SQL("CREATE DATABASE {} OWNER {}").format(sql.Identifier(name), sql.Identifier(owner_name)))
    runtime = discrete_url(user=runtime_name, password=runtime_password, host=admin_url.host,
                           port=admin_url.port, database=name)
    owner = discrete_url(user=owner_name, password=owner_password, host=admin_url.host,
                         port=admin_url.port, database=name)
    settings = Settings(_env_file=None, DATABASE_URL=runtime.render_as_string(hide_password=False),
                        MIGRATION_DATABASE_URL=owner.render_as_string(hide_password=False),
                        POSTGRES_PASSWORD="", POSTGRES_USER="", POSTGRES_HOST="", POSTGRES_DB="")
    yield settings
    admin.close()  # all created test DBs/roles vanish with the owning container


def connect(settings, *, owner=False):
    url = settings.migration_connection_url() if owner else settings.runtime_database_url()
    return psycopg2.connect(**connect_kwargs(url))


@pytest.fixture
def ready(database):
    bootstrap.bootstrap(database)
    return database


def scalar(conn, statement, params=None):
    with conn.cursor() as cur:
        cur.execute(statement, params)
        return cur.fetchone()[0]


def admin_connection(settings):
    url = postgres_url(os.environ["IRONLINK_TEST_ADMIN_URL"])
    return psycopg2.connect(**connect_kwargs(url.set(database=settings.runtime_database_url().database)))


@pytest.mark.parametrize("target", ["database", "schema", "table", "createrole", "superuser", "bypassrls", "audit_grant"])
@pytest.mark.parametrize("indirect", [False, True])
def test_set_role_paths_rejected_before_migrations(ready, target, indirect):
    elevated = "elevated_" + uuid.uuid4().hex[:16]
    bridge = "bridge_" + uuid.uuid4().hex[:16]
    runtime = ready.runtime_database_url().username
    owner = ready.migration_connection_url().username
    with admin_connection(ready) as admin:
        with admin.cursor() as cur:
            attribute = {"createrole": "CREATEROLE", "superuser": "SUPERUSER",
                         "bypassrls": "BYPASSRLS"}.get(target, "")
            cur.execute(sql.SQL("CREATE ROLE {} NOLOGIN " + attribute).format(sql.Identifier(elevated)))
            if target == "database":
                cur.execute(sql.SQL("ALTER DATABASE {} OWNER TO {}").format(
                    sql.Identifier(ready.runtime_database_url().database), sql.Identifier(elevated)))
            elif target == "schema":
                cur.execute(sql.SQL("ALTER SCHEMA public OWNER TO {}").format(sql.Identifier(elevated)))
            elif target == "table":
                cur.execute(sql.SQL("ALTER TABLE public.audit_logs OWNER TO {}").format(sql.Identifier(elevated)))
            elif target == "audit_grant":
                cur.execute(sql.SQL("GRANT DELETE ON public.audit_logs TO {}").format(sql.Identifier(elevated)))
            if target in {"database", "schema", "table"}:
                cur.execute(sql.SQL("GRANT {} TO {} WITH INHERIT TRUE, SET TRUE").format(
                    sql.Identifier(elevated), sql.Identifier(owner)))
            if indirect:
                cur.execute(sql.SQL("CREATE ROLE {} NOLOGIN").format(sql.Identifier(bridge)))
                cur.execute(sql.SQL("GRANT {} TO {} WITH INHERIT FALSE, SET TRUE").format(
                    sql.Identifier(elevated), sql.Identifier(bridge)))
            cur.execute(sql.SQL("GRANT {} TO {} WITH INHERIT FALSE, SET TRUE").format(
                sql.Identifier(bridge if indirect else elevated), sql.Identifier(runtime)))
    with connect(ready) as conn:
        assert not scalar(conn, "SELECT pg_has_role(current_user,%s,'USAGE')", (elevated,))
        assert scalar(conn, "SELECT pg_has_role(current_user,%s,'SET')", (elevated,))
        with conn.cursor() as cur:
            cur.execute(sql.SQL("SET ROLE {}").format(sql.Identifier(elevated)))
        assert scalar(conn, "SELECT current_user") == elevated
    called = []
    with pytest.raises(bootstrap.BootstrapError):
        bootstrap.bootstrap(ready, migrate=lambda: called.append(True))
    assert not called
    with pytest.raises(bootstrap.BootstrapError):
        bootstrap.verify_runtime(ready)


def test_harmless_switchable_role_is_allowed(ready):
    role = "harmless_" + uuid.uuid4().hex[:16]
    with admin_connection(ready) as admin:
        with admin.cursor() as cur:
            cur.execute(sql.SQL("CREATE ROLE {} NOLOGIN").format(sql.Identifier(role)))
            cur.execute(sql.SQL("GRANT {} TO {} WITH INHERIT FALSE, SET TRUE").format(
                sql.Identifier(role), sql.Identifier(ready.runtime_database_url().username)))
    bootstrap.bootstrap(ready)


def test_admin_option_cannot_be_used_to_enable_a_hidden_set_role_path(ready):
    role = "admin_path_" + uuid.uuid4().hex[:16]
    runtime = ready.runtime_database_url().username
    with admin_connection(ready) as admin:
        with admin.cursor() as cur:
            cur.execute(sql.SQL("CREATE ROLE {} NOLOGIN CREATEROLE").format(sql.Identifier(role)))
            cur.execute(sql.SQL("GRANT {} TO {} WITH ADMIN TRUE, INHERIT FALSE, SET FALSE").format(
                sql.Identifier(role), sql.Identifier(runtime)))
    with connect(ready) as conn:
        assert not scalar(conn, "SELECT pg_has_role(current_user,%s,'SET')", (role,))
        with conn.cursor() as cur:
            cur.execute(sql.SQL("GRANT {} TO {} WITH SET TRUE").format(sql.Identifier(role), sql.Identifier(runtime)))
            cur.execute(sql.SQL("SET ROLE {}").format(sql.Identifier(role)))
        assert scalar(conn, "SELECT current_user") == role
        conn.rollback()  # restore hidden path before verification
    called = []
    with pytest.raises(bootstrap.BootstrapError, match="administer"):
        bootstrap.bootstrap(ready, migrate=lambda: called.append(True))
    assert not called


def test_force_rls_is_rejected_and_retention_raises_instead_of_silent_zero(ready):
    with connect(ready, owner=True) as conn:
        with conn.cursor() as cur:
            cur.execute("INSERT INTO public.audit_logs(action,success,created_at) VALUES ('old',true,now()-interval '400 days')")
            cur.execute("ALTER TABLE public.audit_logs FORCE ROW LEVEL SECURITY")
    with pytest.raises(bootstrap.BootstrapError, match="FORCE RLS"):
        bootstrap.verify_runtime(ready)
    called = []
    with pytest.raises(bootstrap.BootstrapError, match="FORCE RLS"):
        bootstrap.bootstrap(ready, migrate=lambda: called.append(True))
    assert not called
    with connect(ready) as conn:
        with conn.cursor() as cur:
            with pytest.raises(psycopg2.errors.InsufficientPrivilege):
                cur.execute("SELECT ironlink_maintenance.prune_audit_logs(now())")
        conn.rollback()
    with admin_connection(ready) as admin:
        assert scalar(admin, "SELECT relforcerowsecurity FROM pg_class WHERE oid='public.audit_logs'::regclass")
        assert scalar(admin, "SELECT count(*) FROM public.audit_logs") == 1


@pytest.mark.parametrize("grantee", ["PUBLIC", "outsider", "runtime_grant_option"])
def test_unexpected_retention_execute_grants_are_rejected(ready, grantee):
    with admin_connection(ready) as conn:
        with conn.cursor() as cur:
            if grantee == "outsider":
                name = "outsider_" + uuid.uuid4().hex[:16]
                cur.execute(sql.SQL("CREATE ROLE {} NOLOGIN").format(sql.Identifier(name)))
                role = sql.Identifier(name)
            else:
                role = sql.SQL("PUBLIC") if grantee == "PUBLIC" else sql.Identifier(ready.runtime_database_url().username)
            cur.execute(sql.SQL("GRANT EXECUTE ON FUNCTION " + bootstrap.RETENTION_SIGNATURE + " TO {}" +
                               (" WITH GRANT OPTION" if grantee == "runtime_grant_option" else "")).format(role))
    with pytest.raises(bootstrap.BootstrapError, match="EXECUTE"):
        bootstrap.verify_runtime(ready)


def test_fresh_database_all_migrations_and_non_admin_identities(database):
    with connect(database, owner=True) as conn:
        assert scalar(conn, "SELECT count(*) FROM pg_tables WHERE schemaname='public'") == 0
        assert not scalar(conn, "SELECT rolsuper OR rolcreaterole OR rolbypassrls FROM pg_roles WHERE rolname=current_user")
    bootstrap.bootstrap(database)
    bootstrap.verify_runtime(database)
    with connect(database) as conn:
        assert scalar(conn, "SELECT version_num FROM public.alembic_version") == "0013_webauthn_credentials"
        assert scalar(conn, "SELECT count(*) FROM pg_tables WHERE schemaname='public'") == len(bootstrap.application_tables()) + 1
        assert not scalar(conn, "SELECT pg_get_userbyid(relowner)=current_user FROM pg_class WHERE oid='public.audit_logs'::regclass")


def snapshot(settings):
    with connect(settings, owner=True) as conn:
        with conn.cursor() as cur:
            cur.execute("""SELECT n.nspname,c.relname,c.relowner,c.relacl::text,c.relrowsecurity
                FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
                WHERE n.nspname IN ('public','ironlink_maintenance') AND c.relkind IN ('r','p','S')
                ORDER BY 1,2""")
            tables = cur.fetchall()
            cur.execute("SELECT polname,polcmd,polroles,pg_get_expr(polqual,polrelid),pg_get_expr(polwithcheck,polrelid) FROM pg_policy ORDER BY polname")
            policies = cur.fetchall()
            function = scalar(conn, "SELECT pg_get_functiondef(%s::regprocedure)", (bootstrap.RETENTION_SIGNATURE,))
            return tables, policies, function


def test_repeated_bootstrap_does_not_change_schema_or_expand_permissions(ready):
    before = snapshot(ready)
    bootstrap.bootstrap(ready)
    assert snapshot(ready) == before


def test_audit_insert_returning_and_read_are_authorized(ready):
    with connect(ready) as conn:
        identifier = scalar(conn, "INSERT INTO public.audit_logs(action,success) VALUES ('bootstrap.test',true) RETURNING id")
        assert scalar(conn, "SELECT action FROM public.audit_logs WHERE id=%s", (identifier,)) == "bootstrap.test"


def test_account_deletion_can_anonymize_audit_via_its_foreign_key(ready):
    with connect(ready) as conn:
        user_id = scalar(conn, """INSERT INTO public.users
            (phone_number,full_name,hashed_military_id,hashed_password)
            VALUES ('+201012345678','Disposable','test-only','test-only') RETURNING id""")
        audit_id = scalar(conn, "INSERT INTO public.audit_logs(actor_id,action,success) VALUES (%s,'account',true) RETURNING id", (user_id,))
        with conn.cursor() as cur:
            cur.execute("DELETE FROM public.users WHERE id=%s", (user_id,))
        assert scalar(conn, "SELECT actor_id FROM public.audit_logs WHERE id=%s", (audit_id,)) is None


@pytest.mark.parametrize("statement", [
    "UPDATE public.audit_logs SET action='tampered'", "DELETE FROM public.audit_logs",
    "TRUNCATE public.audit_logs", "TRUNCATE public.messages CASCADE",
    "ALTER TABLE public.audit_logs DISABLE ROW LEVEL SECURITY",
    "CREATE TABLE public.unauthorized(id integer)",
    "CREATE FUNCTION ironlink_maintenance.unauthorized() RETURNS integer LANGUAGE sql AS 'SELECT 1'",
])
def test_runtime_unauthorized_writes_and_ddl_fail(ready, statement):
    with connect(ready) as conn:
        with conn.cursor() as cur:
            with pytest.raises(psycopg2.errors.InsufficientPrivilege):
                cur.execute(statement)
        conn.rollback()


def test_runtime_cannot_assume_owner(ready):
    with connect(ready) as conn:
        with conn.cursor() as cur:
            with pytest.raises(psycopg2.errors.InsufficientPrivilege):
                cur.execute(sql.SQL("SET ROLE {}").format(sql.Identifier(ready.migration_connection_url().username)))
        conn.rollback()


def test_rls_defends_audit_even_if_an_update_grant_is_accidentally_added(ready):
    with connect(ready) as conn:
        scalar(conn, "INSERT INTO public.audit_logs(action,success) VALUES ('keep',true) RETURNING id")
    with connect(ready, owner=True) as conn:
        with conn.cursor() as cur:
            cur.execute(sql.SQL("GRANT UPDATE ON public.audit_logs TO {}").format(sql.Identifier(ready.runtime_database_url().username)))
    with connect(ready) as conn:
        with conn.cursor() as cur:
            cur.execute("UPDATE public.audit_logs SET action='tampered'")
            assert cur.rowcount == 0
        assert scalar(conn, "SELECT action FROM public.audit_logs") == "keep"
    with pytest.raises(bootstrap.BootstrapError, match="privileges"):
        bootstrap.verify_runtime(ready)


def test_bounded_retention_cannot_shorten_policy_or_delete_all_records(ready):
    with connect(ready, owner=True) as conn:
        with conn.cursor() as cur:
            cur.execute("""INSERT INTO public.audit_logs(action,success,created_at)
                SELECT 'old',true,now()-interval '400 days' FROM generate_series(1,1200)""")
            cur.execute("""INSERT INTO public.audit_logs(action,success,created_at)
                VALUES ('recent',true,now()-interval '30 days'),('boundary',true,now()-interval '364 days')""")
    with connect(ready) as conn:
        future = datetime.now(timezone.utc) + timedelta(days=10000)
        assert scalar(conn, "SELECT ironlink_maintenance.prune_audit_logs(%s)", (future,)) == 1000
        assert scalar(conn, "SELECT ironlink_maintenance.prune_audit_logs(%s)", (future,)) == 200
        assert scalar(conn, "SELECT count(*) FROM public.audit_logs") == 2


@pytest.mark.asyncio
async def test_retention_worker_uses_function_under_actual_runtime_identity(ready, monkeypatch):
    from app.config import settings
    from app.services.retention_worker import RetentionWorker
    from sqlalchemy.ext.asyncio import async_sessionmaker, create_async_engine
    monkeypatch.setattr(settings, "AUDIT_LOG_RETENTION_DAYS", 365)
    with connect(ready, owner=True) as conn:
        with conn.cursor() as cur:
            cur.execute("INSERT INTO public.audit_logs(action,success,created_at) VALUES ('old',true,now()-interval '400 days')")
    engine = create_async_engine(ready.database_url)
    try:
        worker = RetentionWorker(session_factory=async_sessionmaker(engine))
        assert (await worker.sweep_once())["audit_logs"] == 1
    finally:
        await engine.dispose()


def test_disabled_database_retention_policy_does_not_delete_old_rows(database):
    database.AUDIT_LOG_RETENTION_DAYS = 0
    bootstrap.bootstrap(database)
    with connect(database) as conn:
        scalar(conn, "INSERT INTO public.audit_logs(action,success,created_at) VALUES ('old',true,now()-interval '9000 days') RETURNING id")
        assert scalar(conn, "SELECT ironlink_maintenance.prune_audit_logs(now()+interval '100 years')") == 0


def test_missing_runtime_role_fails_before_any_migration(database):
    runtime = database.runtime_database_url().set(username="absent_" + uuid.uuid4().hex)
    database.DATABASE_URL = runtime.render_as_string(hide_password=False)
    called = []
    with pytest.raises(bootstrap.BootstrapError, match="Provision"):
        bootstrap.bootstrap(database, migrate=lambda: called.append(True))
    assert not called


def test_check_only_refuses_an_uninitialized_database(database):
    with pytest.raises(bootstrap.BootstrapError, match="missing"):
        bootstrap.verify_runtime(database)


def test_sequences_receive_usage_without_update_or_ownership(ready):
    with connect(ready, owner=True) as conn:
        with conn.cursor() as cur:
            cur.execute("CREATE SEQUENCE public.future_sequence")
    bootstrap.bootstrap(ready)
    with connect(ready) as conn:
        assert scalar(conn, "SELECT nextval('public.future_sequence')") == 1
        with conn.cursor() as cur:
            with pytest.raises(psycopg2.errors.InsufficientPrivilege):
                cur.execute("SELECT setval('public.future_sequence',100)")
        conn.rollback()


def test_failed_migration_does_not_apply_hardening(database):
    # A real SQL DDL failure in 0001, not a mocked successful migration.
    with connect(database, owner=True) as conn:
        with conn.cursor() as cur:
            cur.execute("CREATE TABLE public.groups(id integer)")
    with pytest.raises(bootstrap.BootstrapError, match="Alembic migration failed"):
        bootstrap.bootstrap(database)
    with connect(database, owner=True) as conn:
        assert scalar(conn, "SELECT to_regclass('public.audit_logs')") is None


def test_failed_hardening_is_rolled_back_and_refuses_startup(database, monkeypatch):
    original = bootstrap.apply_hardening
    def fail(conn, config):
        original(conn, config)
        raise bootstrap.BootstrapError("forced hardening failure")
    monkeypatch.setattr(bootstrap, "apply_hardening", fail)
    with pytest.raises(bootstrap.BootstrapError, match="forced hardening failure"):
        bootstrap.bootstrap(database)
    with connect(database, owner=True) as conn:
        assert not scalar(conn, "SELECT relrowsecurity FROM pg_class WHERE oid='public.audit_logs'::regclass")
        assert scalar(conn, "SELECT to_regnamespace('ironlink_maintenance')") is None


def test_concurrent_real_cli_bootstraps_serialize_without_ddl_races(database):
    env = os.environ.copy()
    for key in list(env):
        if key.startswith(("POSTGRES_", "MIGRATION_")):
            env.pop(key)
    env["DATABASE_URL"] = database.database_url
    env["MIGRATION_DATABASE_URL"] = database.migration_connection_url().render_as_string(hide_password=False)
    command = [sys.executable, "-m", "scripts.bootstrap_database"]
    processes = [subprocess.Popen(command, env=env, cwd=bootstrap.ROOT,
                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True) for _ in range(2)]
    try:
        for process in processes:
            stdout, stderr = process.communicate(timeout=90)
            safe_detail = next((line for line in stderr.splitlines() if line.startswith("[database]")),
                               "Concurrent bootstrap failed without a safe diagnostic")
            assert process.returncode == 0, safe_detail
            assert "privileges verified" in stdout
    finally:
        for process in processes:
            if process.poll() is None:
                process.terminate()
            process.communicate(timeout=10)
    bootstrap.verify_runtime(database)


@pytest.mark.parametrize("terminate", [False, True])
def test_paused_alembic_session_serializes_and_cannot_outlive_its_lock(database, tmp_path, terminate):
    # Add a test-only revision to a private copy, never to application history.
    migration_dir = tmp_path / "alembic"
    shutil.copytree(bootstrap.ROOT / "alembic", migration_dir)
    marker = tmp_path / "entered"
    gate = bootstrap.LOCK_ID + 1
    revision = f'''from alembic import op
from pathlib import Path
revision = "9999_lock_failure_probe"
down_revision = "0013_webauthn_credentials"
def upgrade():
    connection = op.get_bind()
    connection.exec_driver_sql("CREATE TABLE public.lock_failure_probe (id integer)")
    Path({str(marker)!r}).write_text(str(connection.exec_driver_sql("SELECT pg_backend_pid()").scalar()))
    connection.exec_driver_sql("SELECT pg_advisory_lock({gate})")
    connection.exec_driver_sql("INSERT INTO public.lock_failure_probe VALUES (1)")
def downgrade():
    op.drop_table("lock_failure_probe")
'''
    (migration_dir / "versions" / "9999_lock_failure_probe.py").write_text(revision, encoding="utf-8")
    driver = tmp_path / "bootstrap_probe.py"
    driver.write_text(f'''from app.core import database_bootstrap as b
from app.config import settings
original = b.alembic_config
def config():
    value = original()
    value.set_main_option("script_location", {str(migration_dir)!r})
    return value
b.alembic_config = config
b.bootstrap(settings)
''', encoding="utf-8")
    environment = {k: v for k, v in os.environ.items()
                   if not k.upper().startswith(("POSTGRES_", "MIGRATION_")) and k.upper() != "DATABASE_URL"}
    environment.update(DATABASE_URL=database.database_url,
                       MIGRATION_DATABASE_URL=database.migration_connection_url().render_as_string(hide_password=False),
                       PYTHONPATH=str(bootstrap.ROOT))
    processes = []
    admin = admin_connection(database)
    admin.autocommit = True
    try:
        scalar(admin, "SELECT pg_advisory_lock(%s)", (gate,))
        command = [sys.executable, str(driver)]
        first = subprocess.Popen(command, env=environment, cwd=bootstrap.ROOT,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        processes.append(first)
        deadline = time.monotonic() + 30
        while not marker.exists():
            assert first.poll() is None, "Probe bootstrap exited before entering its migration"
            assert time.monotonic() < deadline, "Timed out waiting for paused migration"
            time.sleep(0.05)
        pid = int(marker.read_text())
        # Migration backend must itself hold the bootstrap lock, not a sibling.
        assert scalar(admin, "SELECT EXISTS(SELECT 1 FROM pg_locks WHERE pid=%s AND locktype='advisory' AND granted AND objid=%s)",
                      (pid, bootstrap.LOCK_ID & 0xffffffff))
        second = subprocess.Popen(command, env=environment, cwd=bootstrap.ROOT,
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        processes.append(second)
        # Wait for actual SQL evidence of contention, not just process startup.
        deadline = time.monotonic() + 30
        while scalar(admin, "SELECT count(*) FROM pg_stat_activity WHERE datname=current_database() AND usename=%s",
                     (database.migration_connection_url().username,)) < 2:
            assert second.poll() is None
            assert time.monotonic() < deadline
            time.sleep(0.05)
        assert second.poll() is None
        assert scalar(admin, "SELECT to_regclass('public.lock_failure_probe')") is None
        if terminate:
            assert scalar(admin, "SELECT pg_terminate_backend(%s)", (pid,))
            first.communicate(timeout=20)
            assert first.returncode != 0
            # No DDL or revision from the terminated session was committed.
            assert scalar(admin, "SELECT to_regclass('public.lock_failure_probe')") is None
        scalar(admin, "SELECT pg_advisory_unlock(%s)", (gate,))
        if not terminate:
            first.communicate(timeout=30)
            assert first.returncode == 0, "Healthy paused migration failed"
        second.communicate(timeout=40)
        assert second.returncode == 0, "Following bootstrap failed to recover safely"
        assert scalar(admin, "SELECT count(*) FROM public.lock_failure_probe") == 1
        assert scalar(admin, "SELECT version_num FROM public.alembic_version") == "9999_lock_failure_probe"
    finally:
        admin.close()  # releases only this test's pause lock
        for process in processes:
            if process.poll() is None:
                process.terminate()
            process.communicate(timeout=10)


def test_local_docker_role_init_and_compose_contract(database, tmp_path):
    token = uuid.uuid4().hex[:12]
    env = os.environ.copy()
    env.update(MIGRATION_POSTGRES_USER="local_owner_" + token,
               MIGRATION_POSTGRES_PASSWORD=secrets.token_urlsafe(24),
               IRONLINK_RUNTIME_USER="local_runtime_" + token,
               IRONLINK_RUNTIME_PASSWORD=secrets.token_urlsafe(24))
    args = ["docker", "exec", "-i", "--env", "POSTGRES_USER=postgres",
            "--env", "POSTGRES_DB=" + database.runtime_database_url().database]
    for key in ("MIGRATION_POSTGRES_USER", "MIGRATION_POSTGRES_PASSWORD",
                "IRONLINK_RUNTIME_USER", "IRONLINK_RUNTIME_PASSWORD"):
        args += ["--env", key]
    args += [os.environ["IRONLINK_TEST_CONTAINER"], "sh", "-s"]
    result = subprocess.run(args, env=env,
        input=(bootstrap.ROOT / "scripts/init_local_roles.sh").read_text(encoding="utf-8").encode("utf-8"),
        capture_output=True, timeout=30)
    assert result.returncode == 0, "Local Docker role initialization failed"
    url = database.runtime_database_url()
    local = Settings(_env_file=None, DATABASE_URL="", MIGRATION_DATABASE_URL="",
        POSTGRES_HOST=url.host, POSTGRES_PORT=url.port, POSTGRES_DB=url.database,
        POSTGRES_USER=env["IRONLINK_RUNTIME_USER"], POSTGRES_PASSWORD=env["IRONLINK_RUNTIME_PASSWORD"],
        MIGRATION_POSTGRES_USER=env["MIGRATION_POSTGRES_USER"],
        MIGRATION_POSTGRES_PASSWORD=env["MIGRATION_POSTGRES_PASSWORD"])
    bootstrap.bootstrap(local)
    bootstrap.verify_runtime(local)
    env["LOCAL_POSTGRES_ADMIN_PASSWORD"] = secrets.token_urlsafe(24)
    # Validate the committed Compose file as a clean checkout, without reading
    # a developer's .env. Older Compose versions still require env_file to
    # exist even with --no-env-resolution, so supply an isolated empty fixture.
    compose_file = tmp_path / "docker-compose.yml"
    shutil.copyfile(bootstrap.ROOT / "docker-compose.yml", compose_file)
    (tmp_path / ".env").write_text("", encoding="utf-8")
    result = subprocess.run(["docker", "compose", "--file", str(compose_file), "config", "--quiet"],
        cwd=tmp_path, env=env, capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, "Local Compose configuration validation failed"
