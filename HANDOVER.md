# IronLink — Handover Report

**Date:** 2026-08-07
**Branch:** `fix/boot-crashes-and-backend-merge` (9 commits ahead of `main`, all pushed)
**Live API:** https://ironlink-api.onrender.com
**Status:** Backend is deployed and healthy. The product is not finished.

> Written as a handover to another Claude session. Everything below is verified
> unless explicitly marked otherwise. Where something is unverified, that is
> stated rather than glossed over.

---

## 1. Current state in one paragraph

This repository could not start. `import app.main` raised, so every deploy died
before binding a port. Nine boot-level defects were fixed, an orphaned parallel
codebase was merged, the database schema was created from nothing, and the
service was deployed to Render with managed PostgreSQL and Redis. The API now
returns `{"status":"ok","env":"production"}` and the Flutter client points at
it. What remains is feature work — object storage, push notifications, the AI
endpoints — plus release engineering for the mobile app.

---

## 2. Live infrastructure

| Resource | Name | Type | Plan | Status |
|---|---|---|---|---|
| API | `ironlink-api` | Docker web service | Free | Live |
| Database | `ironlink-db` | PostgreSQL 16 | Free | Available |
| Cache / PubSub | `ironlink-redis` | Valkey 8 (Render "Key Value") | Free | Available |

Declared as code in [`render.yaml`](render.yaml). Region: Oregon.

**Dead service — ignore it:** `srv-d9qq6tqjobas738ip930`, named `IronLink`. It
was a manual attempt, has no database and no environment variables, and every
deploy on it failed. It is abandoned, not broken. Any log or error mentioning
that service ID is irrelevant. Safe to delete.

---

## 3. What was fixed

### 3.1 Nine boot-level defects

The application raised on import. Fixing each error revealed the next.

| # | Location | Defect |
|---|---|---|
| 1 | `app/main.py:23` | `asyncio` used in lifespan, never imported |
| 2 | `app/api/routes/media.py` | `logger` undefined |
| 3 | `app/api/routes/media.py` | `normalize_text` undefined |
| 4 | `app/services/ws_manager.py:13` | imported name `redis` that `app.core.redis` does not export |
| 5 | `app/ocr.py:6` | `import pypdf2` — the PyPI name; the module is `PyPDF2` |
| 6 | `app/api/routes/ocr.py:4` | `List` imported from `pydantic` instead of `typing` |
| 7 | `app/api/routes/keys.py:37` | `List` used without import |
| 8 | `app/services/encryption_service.py:9` | same bad `redis` import as #4 |
| 9 | `app/models/user.py:127` | **latent** — `User.group_memberships` ambiguous |

**#9 deserves attention.** `GroupMember` has two foreign keys to `users.id`
(`user_id`, `added_by_id`) and the `User` side never said which to join on.
SQLAlchemy raised `AmbiguousForeignKeysError` during mapper configuration,
meaning **every group-membership query would have failed at runtime**. It was
invisible because nothing ever called `configure_mappers()`.

### 3.2 The orphaned `backend/app/` tree

A second, parallel copy of the application existed at `backend/app/`, containing
the only implementations of Channels, Communities, and the AI service — none of
which `app/main.py` imported. It was **not** a newer version; it was written
against different assumptions:

| | `app/` (real) | `backend/app/` (orphan) |
|---|---|---|
| Framework | FastAPI | FastAPI **and Flask** |
| DB session | async `AsyncSession` | sync `Session` |
| Auth dependency | `get_current_user` | `get_current_active_user` (did not exist) |
| Primary keys | UUID | Integer |
| Pydantic | v2 | v1 (`orm_mode`) |

It also contained a `SyntaxError` (`from sqlalchemy.orm relationship`) and
imports of modules that do not exist (`app.models.chat`, `app.core.minio`).

Copying it over `app/` — the obvious reading of "merge" — would have replaced
working code with broken code. Instead the genuinely new features were **ported**
onto the real stack (async, UUID, Pydantic v2) and the orphan deleted. It remains
recoverable from git history.

### 3.3 Database

`alembic/versions/` was **empty**. No table had ever been created by a migration,
and `scripts/init_db.sql` provisions only extensions and roles — so the schema
existed nowhere.

- [`alembic/versions/0001_initial_schema.py`](alembic/versions/0001_initial_schema.py) creates all **22 tables**.
- Generated offline (no database was available at the time), then verified in
  production: the deploy log shows `[entrypoint] migrations applied`.
- `alembic/env.py` had a second bug: it set the URL to `sync_database_url`
  (psycopg2) and passed it to `async_engine_from_config`, which rejects a sync
  driver. Online migrations could never have run.

### 3.4 Deployment

| Problem | Fix |
|---|---|
| `requirements.txt` pinned `signal-protocol==0.1.0` — a version that never existed on PyPI | removed (nothing imports it) |
| Dockerfile hardcoded `--port 8000`; Render injects `$PORT` | read at runtime via `sh -c` + `exec` |
| `--workers 4` on a 512 MB instance | `WEB_CONCURRENCY`, default 1 |
| `TrustedHostMiddleware` was given `ALLOWED_ORIGINS` (URLs) but matches the `Host` header (no scheme) — rejected 100% of production traffic | `settings.allowed_hosts` derives hostnames; `RENDER_EXTERNAL_HOSTNAME` read at runtime |
| Redis DB index selected by `str.replace("/0","/2")` — matched nothing against a pathless managed URL, silently collapsing all three pools onto DB 0 | path component replaced outright |
| Migrations had nowhere to run (pre-deploy, Shell, and One-Off Jobs are all paid features) | [`docker-entrypoint.sh`](docker-entrypoint.sh) runs `alembic upgrade head` before uvicorn |
| `COPY . .` copied the entire Flutter app into a Python image | [`.dockerignore`](.dockerignore) |

### 3.5 Object storage

MinIO does not exist on Render. Since MinIO and Cloudflare R2 both speak S3, the
settings were generalised rather than a second backend added: one `S3_*` block
drives both. Legacy `MINIO_*` names are kept as validation aliases, so existing
`.env` files and the docker-compose stack work unchanged.

Storage is **optional at boot**. It used to abort startup, meaning no R2 bucket
meant no API at all. Media routes now return `503` when unconfigured and
everything else runs.

### 3.6 The 204 crash (found in production)

The container built, migrated the database, then died on import:

```
AssertionError: Status code 204 must not have a response body
app/api/routes/auth.py:235
```

Root cause is indirect. Every route module uses `from __future__ import
annotations`, which stores `-> None` as the string `"None"`. FastAPI resolves the
return annotation through `get_type_hints`, which normalises `None` to the
**class** `NoneType`. FastAPI infers `response_model` from that annotation, and
`NoneType` is truthy — so it concludes the route returns a body and trips the
assertion, killing the whole app on import.

Fixed with explicit `response_model=None` on all **11** 204 routes.

**Why it was not caught locally:** the dev venv had FastAPI 0.139.2 while
`requirements.txt` pins **0.115.5**. The newer version tolerates it. See §8.

### 3.7 Frontend

Three screens bypassed `Env` and pointed at unreachable addresses:

```
channel_list_screen.dart:27     http://localhost:8000
community_list_screen.dart:27   http://localhost:8000
chat_room_screen.dart:41        https://api.ironlink.app
```

`localhost` on a handset is the handset. `api.ironlink.app` is not owned by this
project. All three now use `Env.apiBaseUrl`.

`Env` gained `API_BASE_URL` / `WS_BASE_URL` overrides. **The CI workflow had been
passing exactly those flags since it was written, but nothing read them** — so
every release APK it produced silently shipped pointing at the emulator loopback.

Also fixed: `const Container()` in both list screens. `Container` has no const
constructor, so this was a hard compile error that would have failed
`flutter build apk`.

---

## 4. What works now

- API live, `/health` returns `{"status":"ok","env":"production"}`
- 44 registered paths (auth, chats, groups, media, broadcasts, admin, ocr, receipts, keys, channels, communities)
- 22 database tables created by migration
- Redis connected, three isolated DB indices
- 50 tests passing on the pinned FastAPI
- Flutter builds and targets the live backend

---

## 5. What does NOT work — prioritised

### P1 — blocks core features

**5.1 The `/ai/*` endpoints do not exist.**
`frontend/lib/features/chat/bloc/chat_bloc.dart` calls:
```
/ai/smart-replies      /ai/translate      /ai/moderate      /chats/{id}/summary
```
None are registered. `app/services/ai_service.py` was ported and works, but **no
route imports it**. Needs a router (~1 hour). Also needs `HF_API_TOKEN`.

**5.2 Push notifications are dead.**
`render.yaml:142` declares `FIREBASE_CREDENTIALS_JSON`, but
`app/services/push_service.py:26` reads `FIREBASE_CREDENTIALS_FILE` — a file
*path*. A PaaS cannot supply a file. The env var is inert. Config must accept the
JSON blob directly (~20 minutes).

**5.3 File upload returns 503.**
Needs three values from Cloudflare: `S3_ENDPOINT`
(`<ACCOUNT_ID>.r2.cloudflarestorage.com`), `S3_ACCESS_KEY_ID`,
`S3_SECRET_ACCESS_KEY`. Create buckets `ironlink-avatars` and
`ironlink-attachments`, keep them **private**, scope the API token to those two
buckets only. `S3_REGION=auto` is mandatory — R2 rejects any other region in the
SigV4 scope.

### P2 — blocks release

**5.4 `applicationId = "com.example.ironlink"`** — Google Play rejects any
`com.example.*` id. Changing it requires regenerating `google-services.json`.

**5.5 Release APK is signed with debug keys** (`build.gradle.kts:39`).

**5.6 iOS push is impossible** — no `GoogleService-Info.plist`, no APNs key.

### P3 — correctness and scale

**5.7 E2EE is a mock.** `app/services/encryption_service.py` returns
`"mock_ciphertext"` and `"mock_plaintext"`. The Signal Protocol is **not
implemented**. `signal-protocol` was removed from `requirements.txt` because the
pinned version never existed and nothing imported it. **The app is not
end-to-end encrypted despite the UI implying it is.**

**5.8 `assemble_staging()` loads whole files into memory.** A 50 MB upload costs
~100 MB transient on a 512 MB instance. Fix is S3 multipart upload so R2
assembles server-side.

**5.9 Deployed from a feature branch,** not `main`.

---

## 6. Critical warnings

**`DB_ENCRYPTION_KEY`** encrypts columns at rest. It is set in Render and must be
stored in a password manager. **If it is lost or changed, every encrypted row
becomes permanently unreadable.** It is deliberately `sync: false` rather than
`generateValue: true` for this reason. It is not recorded in this repository and
must never be.

**Render's free PostgreSQL expires.** Check the expiry on `ironlink-db`. Do not
put data you care about on it.

**Free instances sleep.** First request after idle takes ~50 s. Not a bug.

**This is described as secure military/enterprise messaging** but currently has
mock encryption (5.7) and runs on free-tier infrastructure. Treat it as a
prototype.

---

## 7. How to verify

```bash
# Backend
.venv/Scripts/python.exe -m pytest -q          # expect 50 passed
.venv/Scripts/python.exe -c "import app.main"  # must not raise

# Frontend
cd frontend && flutter analyze                 # no errors
flutter test test/env_test.dart

# Live
curl https://ironlink-api.onrender.com/health
```

---

## 8. Environment traps — read before debugging

**The local venv drifted from `requirements.txt` and that hid a production
crash.** Always verify against pinned versions:

| Package | Pinned | Was installed locally |
|---|---|---|
| `fastapi` | 0.115.5 | 0.139.2 ← hid the 204 bug |
| `sqlalchemy` | 2.0.36 | 2.0.51 (2.0.36 lacks Python 3.14 support) |

Local Python is **3.14**; the Docker image is **3.12**. Some pins have no 3.14
wheels (Pillow, asyncpg) and were installed unpinned locally. `requirements.txt`
is untouched and correct for the image.

**The test suite was blind.** Nothing imported `app.main`, so 43 tests passed
against code that could not start — and every deploy failure in this project has
been an import-time crash. `tests/test_app_boot.py` now closes that gap and was
validated by mutation: removing the fix turns all 7 tests red.

**`alembic` shadowing.** Running from the repo root, `import alembic` resolves to
the local `alembic/` directory rather than the package.

---

## 9. Recommended next steps, in order

1. **Fix Firebase naming** (5.2) — smallest, unblocks push
2. **Add the `/ai/*` router** (5.1) — the Flutter UI already calls it
3. **Cloudflare R2** (5.3) — unblocks media
4. **Decide on E2EE** (5.7) — implement it or remove the claim from the UI
5. **Release engineering** (5.4–5.6) — app id, signing, iOS
6. **Merge to `main`**, delete the dead service
7. **Multipart upload** (5.8) before real traffic

---

## 10. Commits

```
a505685  fix(frontend): route every screen through Env instead of hardcoded hosts
5902994  fix(api): declare response_model=None on every 204 route
5915be8  chore: pin LF line endings for shell scripts and Linux-consumed config
16119ef  fix(deploy): rename blueprint service and stop hardcoding the assigned hostname
faec629  fix(deploy): make the service deployable on Render's free tier
5a05a68  feat(storage): move object storage to Cloudflare R2
b060a6e  fix(deploy): unbreak the build and make the service deployable on Render
7c59a3b  feat(db): add initial schema migration and fix alembic async driver
d4e732d  fix: repair boot crashes and merge orphaned backend/app into app/
```

Each message documents its own root cause and verification. `git show <hash>`
for detail.
