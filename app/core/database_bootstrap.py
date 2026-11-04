"""Database-owner operations and independent runtime permission verification.

Credentials/roles must already exist. This never needs CREATEROLE or superuser.
"""
from __future__ import annotations

from pathlib import Path
import time

import psycopg2
from psycopg2 import sql

from app.core.database_config import connect_kwargs, sync_url

ROOT = Path(__file__).resolve().parents[2]
LOCK_ID = 492165628301
RETENTION_SIGNATURE = "ironlink_maintenance.prune_audit_logs(timestamp with time zone)"


class BootstrapError(RuntimeError):
    """Safe to display: messages contain no connection strings or SQL values."""


def application_tables() -> list[str]:
    from app.models import Base
    return sorted(Base.metadata.tables)


def alembic_config():
    from alembic.config import Config
    config = Config(str(ROOT / "alembic.ini"))
    config.set_main_option("script_location", str(ROOT / "alembic"))
    return config


def expected_revision() -> str:
    from alembic.script import ScriptDirectory
    return ScriptDirectory.from_config(alembic_config()).get_current_head()


def retention_function_sql(days: int) -> str:
    # The only substitution is a validated Python integer, never caller SQL.
    return (ROOT / "scripts/audit_retention.sql").read_text(encoding="utf-8").format(
        retention_days=max(0, int(days))
    )


def _reject_admin_memberships(cur, role: str) -> None:
    cur.execute("""SELECT 1 FROM pg_roles WHERE rolname=ANY(%s)
                   AND (pg_has_role(%s,oid,'USAGE') OR pg_has_role(%s,oid,'SET'))""", ([
        "pg_read_server_files", "pg_write_server_files", "pg_execute_server_program",
        "pg_signal_backend", "pg_checkpoint", "pg_create_subscription",
        "pg_write_all_data", "pg_read_all_data",
    ], role, role))
    if cur.fetchone():
        raise BootstrapError("Runtime must not inherit or assume administrative predefined roles")


def _runtime_identity(cur, username: str, *, pre_migration=False) -> list[str]:
    cur.execute("SELECT current_user, session_user")
    if cur.fetchone() != (username, username):
        raise BootstrapError("Unexpected runtime PostgreSQL identity")
    cur.execute("""SELECT 1 FROM pg_auth_members WHERE admin_option AND
                   (pg_has_role(current_user,member,'USAGE') OR
                    pg_has_role(current_user,member,'SET'))""")
    if cur.fetchone():
        # ADMIN can let the login change membership options and create a SET
        # path that does not exist yet. Runtime never administers role grants.
        raise BootstrapError("Runtime must not administer PostgreSQL role memberships")
    # SET follows the complete PG16 SET TRUE chain, independently of INHERIT.
    # Privilege functions below also include each switchable role's inheritance.
    cur.execute("""SELECT rolname, rolsuper OR rolcreatedb OR rolcreaterole OR
                   rolreplication OR rolbypassrls FROM pg_roles
                   WHERE rolname=current_user OR pg_has_role(current_user,oid,'SET')""")
    roles = cur.fetchall()
    for role, administrative in roles:
        if administrative:
            raise BootstrapError("Runtime can assume administrative PostgreSQL attributes")
        _reject_admin_memberships(cur, role)
        cur.execute("""SELECT pg_has_role(%s,datdba,'USAGE'),
                       has_database_privilege(%s,oid,'CREATE')
                       FROM pg_database WHERE datname=current_database()""", (role, role))
        owns, creates = cur.fetchone()
        if owns or (creates and not (pre_migration and role == username)):
            raise BootstrapError("Runtime can assume database ownership or database CREATE")
        cur.execute("""SELECT 1 FROM pg_namespace WHERE
            nspname IN ('public','ironlink_maintenance') AND
            (pg_has_role(%s,nspowner,'USAGE') OR
             (%s AND has_schema_privilege(%s,oid,'CREATE')))""",
                    (role, not (pre_migration and role == username), role))
        if cur.fetchone():
            raise BootstrapError("Runtime can assume schema ownership or schema CREATE")
        cur.execute("""SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname IN ('public','ironlink_maintenance') AND c.relkind IN ('r','p','S')
            AND pg_has_role(%s,c.relowner,'USAGE')""", (role,))
        if cur.fetchone():
            raise BootstrapError("Runtime can assume a table-owner identity")
        # Direct grants are repaired by hardening; switchable roles are never
        # modified by bootstrap and must already be safe before any migrations.
        if pre_migration and role != username:
            _verify_table_privileges(cur, role, require_allowed=False)
    return [role for role, _ in roles]


def _verify_table_privileges(cur, role: str, *, require_allowed: bool) -> None:
    for table in application_tables() + ["alembic_version"]:
        name = "public." + table
        cur.execute("SELECT to_regclass(%s)", (name,))
        if cur.fetchone()[0] is None:
            if require_allowed:
                raise BootstrapError("Required application table is missing")
            continue
        allowed = {"SELECT"} if table == "alembic_version" else (
            {"SELECT", "INSERT"} if table == "audit_logs" else {"SELECT", "INSERT", "UPDATE", "DELETE"}
        )
        for privilege in ("SELECT", "INSERT", "UPDATE", "DELETE", "TRUNCATE", "REFERENCES", "TRIGGER"):
            cur.execute("SELECT has_table_privilege(%s,%s,%s), has_table_privilege(%s,%s,%s)",
                        (role, name, privilege, role, name, privilege + " WITH GRANT OPTION"))
            has, grantable = cur.fetchone()
            if grantable or (has and privilege not in allowed) or (require_allowed and not has and privilege in allowed):
                raise BootstrapError("Unexpected effective runtime table privileges")


def _reject_force_rls(cur) -> None:
    cur.execute("SELECT relforcerowsecurity FROM pg_class WHERE oid=to_regclass('public.audit_logs')")
    row = cur.fetchone()
    if row and row[0]:
        raise BootstrapError("FORCE RLS on audit_logs is unsupported by bounded retention")


def preflight(owner, settings) -> None:
    runtime_url = settings.runtime_database_url()
    migration_url = settings.migration_connection_url()
    with owner.cursor() as cur:
        _reject_force_rls(cur)
        cur.execute("SELECT current_user, session_user")
        if cur.fetchone() != (migration_url.username, migration_url.username):
            raise BootstrapError("Unexpected migration PostgreSQL identity")
        cur.execute("SELECT oid FROM pg_roles WHERE rolname=%s", (runtime_url.username,))
        if cur.fetchone() is None:
            raise BootstrapError("Provision the independent runtime PostgreSQL login before bootstrap")
        cur.execute("""SELECT pg_has_role(current_user,datdba,'USAGE')
                       FROM pg_database WHERE datname=current_database()""")
        if not cur.fetchone()[0]:
            raise BootstrapError("Migration identity must control the target database grants")
        cur.execute("SELECT pg_has_role(current_user,nspowner,'USAGE') FROM pg_namespace WHERE nspname='public'")
        if not cur.fetchone()[0]:
            raise BootstrapError("Migration identity must control the public schema grants")
        cur.execute("""SELECT pg_has_role(%s, current_user, 'MEMBER'),
                              has_schema_privilege(current_user, 'public', 'CREATE')""",
                    (runtime_url.username,))
        member, can_create = cur.fetchone()
        if member or not can_create:
            raise BootstrapError("Require independent runtime and schema-owner identities")
        cur.execute("""SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
            WHERE n.nspname='public' AND c.relkind IN ('r','p','S')
              AND (pg_has_role(%s,c.relowner,'MEMBER') OR NOT pg_has_role(current_user,c.relowner,'USAGE'))""",
                    (runtime_url.username,))
        if cur.fetchone():
            raise BootstrapError("Existing schema ownership is incompatible; owner review required")
    # Connecting independently proves the runtime identity exists and can log in.
    # PUBLIC CREATE is repaired by the owner below, but admin attributes and
    # database ownership are never repaired by changing a login role here.
    with psycopg2.connect(**connect_kwargs(runtime_url)) as runtime:
        with runtime.cursor() as cur:
            _runtime_identity(cur, runtime_url.username, pre_migration=True)


def apply_hardening(owner, settings) -> None:
    role = sql.Identifier(settings.runtime_database_url().username)
    tables = application_tables() + ["alembic_version"]
    with owner.cursor() as cur:
        _reject_force_rls(cur)
        cur.execute("REVOKE CREATE ON SCHEMA public FROM PUBLIC")
        cur.execute(sql.SQL("REVOKE ALL ON SCHEMA public FROM {}; GRANT USAGE ON SCHEMA public TO {}").format(role, role))
        cur.execute(sql.SQL("REVOKE CREATE ON DATABASE {} FROM PUBLIC, {}").format(
            sql.Identifier(settings.runtime_database_url().database), role))
        # Never grant future tables blindly (especially future audit tables).
        cur.execute(sql.SQL("ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON TABLES FROM {}").format(role))
        cur.execute(sql.SQL("ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE ALL ON SEQUENCES FROM {}").format(role))
        for table in tables:
            relation = sql.Identifier("public", table)
            cur.execute(sql.SQL("REVOKE ALL ON TABLE {} FROM PUBLIC, {}").format(relation, role))
            permissions = "SELECT" if table == "alembic_version" else (
                "SELECT, INSERT" if table == "audit_logs" else "SELECT, INSERT, UPDATE, DELETE"
            )
            cur.execute(sql.SQL("GRANT " + permissions + " ON TABLE {} TO {}").format(relation, role))
        # Current migrations use UUID defaults, not sequences. Grant only USAGE
        # for any owner-controlled sequence added later, never UPDATE/TRUNCATE.
        cur.execute("""SELECT c.relname FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
                       WHERE n.nspname='public' AND c.relkind='S'""")
        for (name,) in cur.fetchall():
            relation = sql.Identifier("public", name)
            cur.execute(sql.SQL("REVOKE ALL ON SEQUENCE {} FROM PUBLIC, {}; GRANT USAGE ON SEQUENCE {} TO {}").format(relation, role, relation, role))
        template = (ROOT / "scripts/post_migrate.sql").read_text(encoding="utf-8")
        cur.execute(sql.SQL(template).format(runtime=role))
        cur.execute("CREATE SCHEMA IF NOT EXISTS ironlink_maintenance")
        cur.execute(sql.SQL("REVOKE ALL ON SCHEMA ironlink_maintenance FROM PUBLIC, {}; GRANT USAGE ON SCHEMA ironlink_maintenance TO {}").format(role, role))
        cur.execute(retention_function_sql(settings.AUDIT_LOG_RETENTION_DAYS))
        cur.execute("REVOKE ALL ON FUNCTION " + RETENTION_SIGNATURE + " FROM PUBLIC")
        cur.execute(sql.SQL("GRANT EXECUTE ON FUNCTION " + RETENTION_SIGNATURE + " TO {}").format(role))


def verify_runtime(settings) -> None:
    url = settings.runtime_database_url()
    with psycopg2.connect(**connect_kwargs(url)) as conn:
        with conn.cursor() as cur:
            roles = _runtime_identity(cur, url.username)
            for role in roles:
                _verify_table_privileges(cur, role, require_allowed=role == url.username)
            cur.execute("SELECT version_num FROM public.alembic_version")
            if cur.fetchall() != [(expected_revision(),)]:
                raise BootstrapError("Database is not at the expected Alembic revision")
            _reject_force_rls(cur)
            cur.execute("SELECT relrowsecurity FROM pg_class WHERE oid='public.audit_logs'::regclass")
            if not cur.fetchone()[0]:
                raise BootstrapError("Audit RLS is not enabled")
            cur.execute("""SELECT polname, polcmd,
                polroles=ARRAY[(SELECT oid FROM pg_roles WHERE rolname=current_user)],
                pg_get_expr(polqual,polrelid), pg_get_expr(polwithcheck,polrelid)
                FROM pg_policy WHERE polrelid='public.audit_logs'::regclass ORDER BY polname""")
            if cur.fetchall() != [("audit_insert_only", "a", True, None, "true"),
                                   ("audit_select_all", "r", True, "true", None)]:
                raise BootstrapError("Unexpected audit RLS policies")
            cur.execute("SELECT has_schema_privilege(current_user,'ironlink_maintenance','CREATE'), has_function_privilege(current_user,%s,'EXECUTE')", (RETENTION_SIGNATURE,))
            can_create, can_execute = cur.fetchone()
            if can_create or not can_execute:
                raise BootstrapError("Unexpected retention function privileges")
            cur.execute("""SELECT p.prosecdef, p.proconfig, p.prosrc,
                          pg_has_role(current_user,p.proowner,'MEMBER'),
                          p.proowner=(SELECT relowner FROM pg_class WHERE oid='public.audit_logs'::regclass)
                          FROM pg_proc p WHERE p.oid=%s::regprocedure""", (RETENTION_SIGNATURE,))
            definition = cur.fetchone()
            body = retention_function_sql(settings.AUDIT_LOG_RETENTION_DAYS).split("$retention$")[1]
            if definition != (True, ["search_path=pg_catalog, pg_temp", "row_security=off"], body, False, True):
                raise BootstrapError("Retention function ownership or definition is unsafe")
            cur.execute("""SELECT 1 FROM pg_proc p,
                LATERAL aclexplode(COALESCE(p.proacl,acldefault('f',p.proowner))) acl
                WHERE p.oid=%s::regprocedure AND acl.privilege_type='EXECUTE'
                  AND (acl.grantee NOT IN (p.proowner,(SELECT oid FROM pg_roles WHERE rolname=current_user))
                       OR (acl.grantee<>p.proowner AND acl.is_grantable))""",
                        (RETENTION_SIGNATURE,))
            if cur.fetchone():
                raise BootstrapError("Unexpected retention function EXECUTE privileges")
            cur.execute("""SELECT c.oid FROM pg_class c JOIN pg_namespace n ON n.oid=c.relnamespace
                           WHERE n.nspname='public' AND c.relkind='S'""")
            for (sequence,) in cur.fetchall():
                for role in roles:
                    for privilege in ("USAGE", "SELECT", "UPDATE"):
                        cur.execute("SELECT has_sequence_privilege(%s,%s::oid,%s)", (role, sequence, privilege))
                        has = cur.fetchone()[0]
                        if (has and privilege != "USAGE") or (role == url.username and privilege == "USAGE" and not has):
                            raise BootstrapError("Unexpected runtime sequence privileges")
            cur.execute("SELECT 1 FROM pg_extension WHERE extname='pgcrypto'")
            if cur.fetchone() is None:
                raise BootstrapError("Required pgcrypto extension is missing")
            cur.execute("SELECT convalidated FROM pg_constraint WHERE conname='chk_message_target' AND conrelid='public.messages'::regclass")
            if cur.fetchone() != (True,):
                raise BootstrapError("Message target constraint is missing or unvalidated")


def bootstrap(settings, *, migrate=None) -> None:
    from sqlalchemy import create_engine
    from sqlalchemy.pool import NullPool

    url = settings.migration_connection_url()
    engine = create_engine(sync_url(url), poolclass=NullPool,
                           connect_args={"connect_timeout": 10})
    try:
        with engine.connect() as connection:
            owner = connection.connection.driver_connection
            deadline = time.monotonic() + 60
            while True:
                acquired = connection.exec_driver_sql("SELECT pg_try_advisory_lock(%s)", (LOCK_ID,)).scalar()
                connection.commit()
                if acquired:
                    break
                if time.monotonic() >= deadline:
                    raise BootstrapError("Timed out waiting for another database bootstrap")
                time.sleep(0.2)
            with connection.begin():
                preflight(owner, settings)
                if migrate is None:
                    from alembic import command
                    config = alembic_config()
                    config.attributes["connection"] = connection
                    config.attributes["database_url"] = url.render_as_string(hide_password=False)
                    try:
                        command.upgrade(config, "head")
                    except Exception:
                        raise BootstrapError("Alembic migration failed; startup refused") from None
                else:
                    migrate()
            # The session lock remains held across the migration commit. Both
            # Alembic and hardening use this exact DBAPI session; termination
            # aborts its DDL and cannot leave another migration session running.
            with connection.begin():
                apply_hardening(owner, settings)
            verify_runtime(settings)
    finally:
        engine.dispose()  # NullPool closes the session and releases its lock
