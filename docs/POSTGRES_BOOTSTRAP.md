# PostgreSQL 16 bootstrap

## Identities and privileges

Two independently provisioned login identities target one database:

* **Migration owner** owns the database/public schema and application objects.
  It needs schema/database CREATE for migrations and the trusted pgcrypto
  extension. It does not need SUPERUSER, BYPASSRLS or CREATEROLE. Existing
  objects must be owned by it (or an owner role it can legitimately use).
* **Runtime** is not a database/table owner and cannot assume an owner role.
  It has schema USAGE, SELECT/INSERT/UPDATE/DELETE on current application
  tables, SELECT on alembic_version, and SELECT/INSERT on audit_logs. No
  TRUNCATE, REFERENCES, TRIGGER, grant options, schema CREATE or administrative
  role attributes are permitted. Audit insertion is a logical responsibility
  of this identity, not an extra login/password.

PostgreSQL 16 `SET` paths are checked separately from inherited `USAGE`:
every switchable identity is checked for administrative attributes, ownership,
CREATE and forbidden table/sequence grants. Direct and indirect `INHERIT FALSE,
SET TRUE` membership is not an isolation boundary. Runtime must not hold role
membership ADMIN options, which could enable a previously blocked SET path.

RLS provides an additional SELECT/INSERT-only audit policy. The table owner
remains trusted and can change its own objects; this is not an immutability
claim against the owner, database administrator or host compromise.

Retention uses the owner-installed SECURITY DEFINER function
`ironlink_maintenance.prune_audit_logs(timestamptz)`. It has a fixed search_path,
fully qualified table references, no dynamic SQL and no PUBLIC EXECUTE. Runtime
can only request an earlier cutoff, never shorten the policy compiled from
AUDIT_LOG_RETENTION_DAYS at bootstrap. At most 1000 rows are removed per call;
zero/negative policy disables removal. Policy changes require owner bootstrap.
Foreign-key SET NULL anonymization during account deletion remains authorized.
`FORCE ROW LEVEL SECURITY` on audit_logs is explicitly unsupported: startup
refuses it without changing the flag. The function sets `row_security=off` so
enabling FORCE RLS after startup raises an error rather than returning a silent
zero-row result. EXECUTE is restricted to the owner and runtime without runtime
grant options; grants to other roles are rejected by verification.

## Configuration

For managed PostgreSQL set **DATABASE_URL** (runtime) and
**MIGRATION_DATABASE_URL** (owner) explicitly. They must use distinct usernames
and the same host/port/database. Exact target equality is deliberate: do not
mix pooler/direct endpoints or hostname aliases. Credentials must be
percent-encoded in URLs; PostgreSQL, postgres, asyncpg and psycopg2 URL schemes
are normalized through SQLAlchemy. Only ssl/sslmode URL query parameters are
supported, with driver-appropriate conversion. Other parameters are rejected
instead of silently changing connection identity or target.

Alternatively runtime uses POSTGRES_USER/PASSWORD/HOST/PORT/DB. Local migration
credentials use MIGRATION_POSTGRES_USER/PASSWORD on that same target. A URL
and explicitly supplied conflicting components fail validation; omit unused
components when choosing URL configuration. No password has a default.
Ports must be in 1..65535. Only an absent URL port defaults to 5432; zero,
negative, malformed and oversized ports fail validation.

The owner identity must already exist. Startup never creates managed users,
changes passwords, grants owner membership or assumes CREATEROLE. If the managed
account cannot establish the required identities/grants, have the provider or
authorized database owner provision them; bootstrap refuses unsafe fallback.

## Startup and repeatability

`python -m scripts.bootstrap_database` validates both identities, takes a
database advisory lock, runs all Alembic upgrades as owner, applies grants/RLS,
retention and the message target constraint transactionally, and verifies the
effective privileges using a fresh runtime connection. The lock spans migrations
and hardening on the same physical PostgreSQL session. Alembic receives an
injected synchronous SQLAlchemy connection; standalone CLI migrations keep
their async path. PostgreSQL backend termination aborts that session's DDL and
releases its lock together, allowing another bootstrap to recover. Current
migrations share a transaction (including version tracking); migrations must
not open independent DDL connections or introduce unreviewed autocommit blocks.
Failure aborts startup; successful migrations may already be
committed when hardening fails, so fix the prerequisite and rerun bootstrap.
It does not stamp, reset, clean or rewrite migration history.

`RUN_MIGRATIONS_ON_START=false` still runs runtime security/schema checks and
refuses uninitialized or overprivileged databases. It does not bypass hardening.
The entrypoint execs `python -m scripts.run_runtime`, which removes every case
variant of MIGRATION_DATABASE_URL, MIGRATION_POSTGRES_USER,
MIGRATION_POSTGRES_PASSWORD and LOCAL_POSTGRES_ADMIN_PASSWORD from the explicit
environment supplied to seeds and Uvicorn. Settings rejects simultaneous case
variants with different values before bootstrap. Equal variants are accepted
and all removed. Runtime DATABASE_URL/POSTGRES credentials are preserved.
Do not mount a credential-bearing .env into the API container or embed
owner credentials in its image. Python processes launched directly outside this
entrypoint do not inherit its environment-scrubbing guarantee.

For compatibility, `python -m scripts.apply_post_migrate` applies/verifies
hardening after standalone Alembic, using the SAME validated target and owner
configuration. Standalone Alembic may use its runtime URL when no owner is set
for offline/test tooling; this cannot authorize startup or give runtime DDL.

## Render Free

Container-start migrations remain supported; there is no paid preDeployCommand,
new service or job. Later, an authorized owner must provision the two identities
and enter their pinned URLs in Render. No remote resources are configured by
these repository changes.

Render documents that new Dashboard/API-managed credentials become the default
and Blueprint-synchronized references can subsequently change identities. The
Blueprint therefore uses explicit sync:false URLs instead of fromDatabase
credentials. Keep both identities pinned and review both when rotating.
Before adding a managed credential, retain the existing owner's URL in the
owner's secret store: Render does not subsequently display the old password.

* https://render.com/docs/postgresql-credentials
* https://render.com/docs/postgresql-pg-repack (no superuser access)
* https://www.postgresql.org/docs/16/ddl-rowsecurity.html

## Local Docker

For a NEW disposable/local volume, .env.example defines independent runtime,
migration and initial local postgres-admin passwords. The database container's
00_roles.sh provisions two non-superuser logins with safely quoted psql input;
01_init.sql prepares pgcrypto. The API only needs migration/runtime identities.
Existing volumes are NOT reprovisioned by Docker init scripts. Their ownership
must be assessed separately; do not delete or reset them to adopt this setup.
Legacy api_user/audit_writer grants and memberships are not silently repaired
cluster-wide. Bootstrap refuses incompatible effective privileges/ownership.

## Verification without persistent resources

From this checkout, with Docker available and existing Python dependencies:

```
python -m scripts.test_postgres_bootstrap -- -q -p no:cacheprovider
```

The runner starts one uniquely labeled PostgreSQL 16 tmpfs container on a random
loopback port, creates fresh databases/identities, runs focused security tests
and the existing backend suite, then stops ONLY that labeled container. No
existing database, volume, container or network is reused or removed. Without
this runner the dedicated PostgreSQL tests skip with an explicit reason; they
must not be mistaken for passed permission tests.

CI also runs this mandatory, fixed-selection gate in the backend job:

```
python -m scripts.test_postgres_bootstrap --security-only
```

It provisions its own PostgreSQL 16 container, independently of the journey
service. Docker/service failures, migration/permission failures, missing admin
configuration, zero collected tests, skips, xfails or deselection fail the gate.
Local runs use the same command; GitHub-hosted execution requires an approved
push and is not proved by a local run. The Windows environment tests use only
new networkless containers from the existing `ironlink-api` image for Linux
exec behavior; they never exec into the running developer API. Ubuntu CI runs
those shell/Uvicorn checks directly using its installed Python dependencies.

Reverting application code is not a database permission rollback. A rollback
must preserve non-owner runtime and the retention function or disable retention
until an owner-approved compatible version is deployed. Never restore blanket
grants, owner runtime credentials or historical migrations to recover startup.
