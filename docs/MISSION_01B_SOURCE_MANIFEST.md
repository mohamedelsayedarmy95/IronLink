# MISSION 01B source manifest

Integration date: 2026-11-04. This is a scoped integration, not a merge of the source branch.

- Historical implementation baseline: `654ddb793ab06b78ff3d06f18428f1005b9986ee`.
- Source HEAD: `86b36769fc512b007e9173607e258306dcd5d468`.
- Target deployment branch, fetched and verified: `fix/boot-crashes-and-backend-merge` at `42f881f4e92c23c99255594d9f9cc10112cffa53`.
- Integration branch: `integration/mission-01a-postgres-hardening`.
- First integration commit: `4dd0c9a`, normal revert of the target's one-line pre-deploy hook addition.

## Source accounting

`git diff --name-only 654ddb7` plus `git ls-files --others --exclude-standard` in the source worktree produced 28 paths: 14 tracked paths (13 working-tree modifications plus committed Render changes) and 14 untracked paths. Of these, 26 files were copied byte-for-byte, one was reconciled, and one was excluded. SHA-256 comparisons verified all copied contents. Both protected checkouts' HEAD, branch, status and changed/untracked file hashes were recorded before integration and rechecked afterwards; private preservation metadata stays outside the repository.

The only committed source change since the historical baseline is the Render change in `86b3676`: pinned database identities plus an obsolete pre-deploy hook. The target's `42f881f` adds only that hook to the historical baseline. Neither commit was cherry-picked or merged.

| Path | Source | Integration action |
|---|---|---|
| `.env.example` | tracked modifications | transferred byte-identical |
| `.github/workflows/ci.yml` | tracked modifications | transferred byte-identical |
| `alembic/env.py` | tracked modifications | transferred byte-identical |
| `app/config.py` | tracked modifications | transferred byte-identical |
| `app/core/database.py` | tracked modifications | transferred byte-identical |
| `app/models/audit_log.py` | tracked modifications | transferred byte-identical |
| `app/services/retention_worker.py` | tracked modifications | transferred byte-identical |
| `docker-compose.yml` | tracked modifications | transferred byte-identical |
| `docker-entrypoint.sh` | tracked modifications | transferred byte-identical |
| `render.yaml` | committed Render history | reconciled: pinned identities, obsolete hook excluded, startup comment aligned |
| `scripts/apply_post_migrate.py` | tracked modifications | transferred byte-identical |
| `scripts/init_db.sql` | tracked modifications | transferred byte-identical |
| `scripts/post_migrate.sql` | tracked modifications | transferred byte-identical |
| `tests/conftest.py` | tracked modifications | transferred byte-identical |
| `app/core/bootstrap_environment.py` | untracked implementation/documentation | transferred byte-identical |
| `app/core/database_bootstrap.py` | untracked implementation/documentation | transferred byte-identical |
| `app/core/database_config.py` | untracked implementation/documentation | transferred byte-identical |
| `docs/MISSION_01A_HARDENING_BASELINE.json` | untracked implementation/documentation | excluded |
| `docs/MISSION_01A_HARDENING_REPORT.md` | untracked implementation/documentation | transferred byte-identical |
| `docs/POSTGRES_BOOTSTRAP.md` | untracked implementation/documentation | transferred byte-identical |
| `scripts/audit_retention.sql` | untracked implementation/documentation | transferred byte-identical |
| `scripts/bootstrap_database.py` | untracked implementation/documentation | transferred byte-identical |
| `scripts/init_local_roles.sh` | untracked implementation/documentation | transferred byte-identical |
| `scripts/run_runtime.py` | untracked implementation/documentation | transferred byte-identical |
| `scripts/test_postgres_bootstrap.py` | untracked implementation/documentation | transferred byte-identical |
| `tests/test_bootstrap_environment.py` | untracked implementation/documentation | transferred byte-identical |
| `tests/test_database_configuration.py` | untracked implementation/documentation | transferred byte-identical |
| `tests/test_postgres_bootstrap.py` | untracked implementation/documentation | transferred byte-identical |

## Reconciliation and exclusions

`render.yaml` retains the Free service, its existing deployment branch, container-start bootstrap, and separately entered `DATABASE_URL` / `MIGRATION_DATABASE_URL`. The obsolete `preDeployCommand` key is absent. The source's automatic `fromDatabase` runtime credential references were replaced with the source's pinned URL design; no live Render settings or credentials were changed.

The internal baseline JSON contains local preservation/environment metadata and is unnecessary at runtime or in CI. The original checkout's `.claude/settings.local.json`, Gradle lock and unfinished `MISSION_00_REPORT.md` were not transferred. Ignored secrets, virtual environments, caches and temporary test outputs were never used as transfer sources. The copied MISSION 01A report is historical evidence; its test results and approval boundary are not MISSION 01B results. Current evidence is reported in the pull request and the separately delivered MISSION 01B Arabic report.

This manifest is new integration documentation. The final Arabic verification report is delivered separately without changing the tested branch after CI.

## Security corrections retained

| Finding | Integrated boundary and verification |
|---|---|
| REV-01 | `bootstrap_environment.py` rejects conflicting casing; `run_runtime.py` strips every privileged-name variant before seeds/Uvicorn; Linux process tests retained. |
| REV-02 | `database_bootstrap.py` validates direct/indirect PostgreSQL 16 SET paths, attributes, ownership, grants and membership ADMIN options before migrations and at final runtime verification. |
| REV-03 | FORCE RLS fails startup without changing its flag; bounded SECURITY DEFINER retention sets `row_security=off`, fixed search_path and restricted EXECUTE; real runtime retention tests retained. |
| REV-04 | One NullPool-backed physical PostgreSQL session holds the advisory lock and runs injected Alembic migrations and hardening; concurrency/backend-termination tests retained. |
| REV-05 | `database_config.py` defaults a port only when absent and enforces 1..65535; component/URL boundary and error-redaction tests retained. |
| REV-06 | CI runs the fixed PostgreSQL 16 `--security-only` gate; missing Docker/admin/reporter, zero tests, skip, xfail and deselection cannot pass. |

## Scope boundary

No user-facing feature change, dependency upgrade, production operation, database-role provisioning or broad architecture rewrite is included. Runtime continues to use the shared Settings URL resolver. Compatibility standalone Alembic/hardening tools remain available, while the container has one deliberate startup bootstrap path. Database prerequisites and recovery approval remain deployment blockers, independent of merge review.
