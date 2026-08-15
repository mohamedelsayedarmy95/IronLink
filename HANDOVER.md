# IronLink — Project Status & Release Readiness

**Last updated:** 2026-08-07
**Branch:** `fix/boot-crashes-and-backend-merge` — 15 commits ahead of `main`, all pushed
**Live API:** https://ironlink-api.onrender.com → `{"status":"ok","env":"production"}`
**Android package:** `com.ironlink.app`

> Written so a fresh session can pick this up cold. Everything marked ✅ was
> verified by running it, not by reading the code. Where something is unverified
> or uncertain, it says so.

---

## 1. Executive summary

The backend is deployed and healthy. The Android app builds, installs, and runs
on a physical device. **The product is not releasable**, and the gap is larger
than it looks from the outside.

Two facts matter more than anything else in this document:

1. **Nobody can log in.** There is no SMS provider and no self-registration
   endpoint. A temporary dev bypass exists but is switched off in production.
2. **The encryption is fake.** `encryption_service.py` returns the literal
   strings `"mock_ciphertext"` and `"mock_plaintext"`. The UI presents IronLink
   as end-to-end encrypted messaging. It is not.

Item 2 is the single most serious thing in this project. It is a claim the
product makes to users and does not keep.

**Realistic distance to a releasable app:** 3–6 weeks, dominated by E2EE and
real authentication.

---

## 2. Live infrastructure

| Resource | Name | Type | Plan | State |
|---|---|---|---|---|
| API | `ironlink-api` | Docker web service | Free | ✅ Live |
| Database | `ironlink-db` | PostgreSQL 16 | Free | ✅ Available |
| Cache / PubSub | `ironlink-redis` | Valkey 8 | Free | ✅ Available |
| Push | Firebase `ironlink-1fd4c` | FCM | Spark (free) | ✅ Initialises |

Declared as code in [`render.yaml`](render.yaml). Region: Oregon.

**Dead service — ignore it:** `srv-d9qq6tqjobas738ip930`, named `IronLink`. A
manual attempt with no database and no variables; every deploy on it failed.
Any log mentioning that ID is irrelevant. Safe to delete.

### Environment variables set in Render

| Variable | State |
|---|---|
| `POSTGRES_*`, `REDIS_URL`, `SECRET_KEY` | ✅ auto-wired by the blueprint |
| `DB_ENCRYPTION_KEY` | ✅ set — **never rotate, see §7** |
| `HF_API_TOKEN` | ✅ set |
| `FIREBASE_CREDENTIALS_JSON` | ✅ set |
| `S3_ENDPOINT`, `S3_ACCESS_KEY_ID`, `S3_SECRET_ACCESS_KEY` | ❌ empty — media returns 503 |
| `DEV_AUTH_BYPASS` | ❌ off — cannot be on while `ENV=production` |

---

## 3. What was done — 15 commits

### 3.1 The app could not start (`d4e732d`)

`import app.main` raised. Nine defects; fixing each revealed the next.

| # | Location | Defect |
|---|---|---|
| 1 | `app/main.py:23` | `asyncio` used, never imported |
| 2–3 | `app/api/routes/media.py` | `logger` and `normalize_text` undefined |
| 4 | `app/services/ws_manager.py:13` | imported a name `redis` that `app.core.redis` does not export |
| 5 | `app/ocr.py:6` | `import pypdf2` — the PyPI name; the module is `PyPDF2` |
| 6 | `app/api/routes/ocr.py:4` | `List` imported from `pydantic`, not `typing` |
| 7 | `app/api/routes/keys.py:37` | `List` used without import |
| 8 | `app/services/encryption_service.py:9` | same bad `redis` import as #4 |
| 9 | `app/models/user.py:127` | **latent** — ambiguous FK, see below |

**#9 is worth understanding.** `GroupMember` has two foreign keys to `users.id`
(`user_id`, `added_by_id`) and the `User` side never said which to join on.
SQLAlchemy raised `AmbiguousForeignKeysError` at mapper configuration, so
**every group-membership query would have failed at runtime**. It was invisible
because nothing ever called `configure_mappers()`.

### 3.2 An orphaned parallel codebase (`d4e732d`)

`backend/app/` held the only implementations of Channels, Communities and the AI
service — none of which `app/main.py` imported. It was **not** a newer version:

| | `app/` (real) | `backend/app/` (orphan) |
|---|---|---|
| Framework | FastAPI | FastAPI **and Flask** |
| DB session | async `AsyncSession` | sync `Session` |
| Auth dependency | `get_current_user` | `get_current_active_user` (did not exist) |
| Primary keys | UUID | Integer |
| Pydantic | v2 | v1 (`orm_mode`) |

It also contained a `SyntaxError` and imports of modules that do not exist.
Copying it over `app/` — the obvious reading of "merge" — would have replaced
working code with broken code. The genuinely new features were **ported** onto
the real stack and the orphan deleted (recoverable from git history).

### 3.3 The database had no schema (`7c59a3b`)

`alembic/versions/` was **empty**, and `scripts/init_db.sql` provisions only
extensions and roles — so the schema existed nowhere.

- [`alembic/versions/0001_initial_schema.py`](alembic/versions/0001_initial_schema.py) creates all **22 tables**
- Generated offline (no database was available), then **confirmed in production**:
  the deploy log shows `[entrypoint] migrations applied`
- `alembic/env.py` had a second bug — it fed a psycopg2 URL to
  `async_engine_from_config`, which rejects sync drivers. Online migrations
  could never have run.

### 3.4 Deployment (`b060a6e`, `faec629`, `16119ef`, `5915be8`)

| Problem | Fix |
|---|---|
| `signal-protocol==0.1.0` — a version that never existed on PyPI | removed; nothing imports it |
| Dockerfile hardcoded `--port 8000`; Render injects `$PORT` | read at runtime via `sh -c` + `exec` |
| `--workers 4` on a 512 MB instance | `WEB_CONCURRENCY`, default 1 |
| `TrustedHostMiddleware` given URLs, but it matches the `Host` header — rejected **100%** of production traffic | `settings.allowed_hosts` derives hostnames; reads `RENDER_EXTERNAL_HOSTNAME` |
| Redis DB index picked via `str.replace("/0","/2")` — matched nothing against a pathless managed URL, silently collapsing all three pools onto DB 0 | path component replaced outright |
| Migrations had nowhere to run (pre-deploy, Shell, One-Off Jobs are all paid) | [`docker-entrypoint.sh`](docker-entrypoint.sh) runs `alembic upgrade head` before uvicorn |
| Blueprint name collided with the existing service | renamed to `ironlink-api` |
| `COPY . .` copied the whole Flutter app into a Python image | [`.dockerignore`](.dockerignore) |

### 3.5 Object storage → Cloudflare R2 (`5a05a68`, `faec629`)

MinIO does not exist on Render. Since MinIO and R2 both speak S3, the settings
were generalised rather than adding a second backend: one `S3_*` block drives
both, with legacy `MINIO_*` names kept as aliases so existing `.env` files and
docker-compose keep working.

Storage is **optional at boot** — it used to abort startup, meaning no R2 bucket
meant no API at all. Media routes now return `503` and everything else runs.

### 3.6 The 204 crash, found in production (`5902994`)

The container built, migrated the database, then died on import:

```
AssertionError: Status code 204 must not have a response body
```

Every route module uses `from __future__ import annotations`, so `-> None` is
stored as the string `"None"`, which `get_type_hints` normalises to the **class**
`NoneType`. FastAPI infers `response_model` from it, and `NoneType` is truthy —
so it concluded the route returns a body and tripped the assertion, killing the
whole app on import.

Fixed with explicit `response_model=None` on all 11 204 routes.

**Why it was missed locally:** the dev venv had FastAPI 0.139.2 against a
**0.115.5** pin. See §8.

### 3.7 AI endpoints + Firebase credentials (`e93c8aa`)

`ai_service.py` had been ported but no route imported it, so the client was
calling four endpoints that returned 404. Now registered, with field names read
out of the shipped client and frozen by contract tests.

Firebase: `render.yaml` declared `FIREBASE_CREDENTIALS_JSON` while the code read
`FIREBASE_CREDENTIALS_FILE`, a *path* — a PaaS cannot supply a file, so the
variable was inert and push could never have worked. Config now takes the JSON
inline.

Also fixed: `AIService` promised graceful degradation but its cache reads sat
**outside** the `try` guarding the HF call, so an unreachable Redis produced a
500 for a feature designed to fall back.

### 3.8 Frontend (`a505685`, `f8ccea1`, `95effc1`, `966ae67`)

- **Three screens pointed at dead hosts** (`localhost:8000`, `api.ironlink.app`)
  → now `Env.apiBaseUrl`
- **`Env` ignored `API_BASE_URL`** although CI had been passing it since it was
  written — every release APK silently shipped pointing at the emulator loopback
- **Native splash** from the brand animation; logo cropped, background made
  transparent on a luminance ramp, Android 12+ circle-mask variant
- **19 analyzer errors**, three root causes: state classes declared twice as
  events, `IronColors` used without importing the theme, and a dead import.
  These blocked `flutter build apk` entirely
- **Package renamed** `com.example.ironlink` → `com.ironlink.app`

---

## 4. Verified working ✅

Confirmed by execution, not inspection.

**Backend**
```
/health                      200, {"status":"ok","env":"production"}, 0.98s
48 API paths registered
22 database tables (migration applied in production)
62 tests passing on the pinned FastAPI 0.115.5
rate limiting                429 on rapid repeat  ✅
input validation             422 on short device_fingerprint  ✅
```

**Android app** (JSN L22, Android 10, arm64)
```
flutter analyze              0 errors
flutter build apk --release  62.2 MB
install + launch             no crash
FirebaseApp initialization successful   (under com.ironlink.app)
native splash                renders
login UI                     3 steps: phone → OTP → military ID
network                      reaches the deployed backend
error handling               shows a message, does not crash
```

---

## 5. What is missing — by priority

### 🔴 P0 — blocks any real use

**5.1 Nobody can log in.**
`SmsGateway.send_otp` raises `NotImplementedError` outside development
([sms_gateway.py:29](app/services/sms_gateway.py:29)), and there is **no
registration endpoint** — users only exist via `scripts/seed_dev_users.py`.
Verified live: `/auth/verify` returns **401**.

*Decision taken:* **Firebase Phone Auth** (option B). Free quota, project already
exists. Needs the SHA-1 below added in the Firebase console, plus a backend
endpoint that exchanges a Firebase ID token for an IronLink JWT.

```
debug SHA-1: 5E:2B:21:E7:4F:7A:B6:7D:55:0D:2D:7C:1C:09:CE:70:2B:97:DB:90
```
⚠️ The **release** SHA-1 must also be added once release signing exists, or
Phone Auth works in testing and breaks in production.

*Interim:* `DEV_AUTH_BYPASS` is implemented and gated. To test today, set on
Render: `ENV=staging` **first**, then `DEV_AUTH_BYPASS=true`. Login becomes: any
phone → any military ID → code `000000`. Setting the bypass while
`ENV=production` makes the service refuse to start — by design.

**5.2 End-to-end encryption — implemented for secret chats, RESOLVED with one
caveat.**
The server-side mock is gone. Encryption is now real Signal Protocol (X3DH +
Double Ratchet) via `libsignal_protocol_dart`, run entirely on the device:

- [`core/crypto/signal.dart`](frontend/lib/core/crypto/signal.dart) — install,
  session establishment, envelope.
- [`core/crypto/signal_store.dart`](frontend/lib/core/crypto/signal_store.dart)
  — key and ratchet state persisted in the platform keystore, so sessions
  survive a restart.
- [`app/api/routes/keys.py`](app/api/routes/keys.py) — public key directory.
  Public material only; the server cannot decrypt anything.

Verified by [`test/signal_test.dart`](frontend/test/signal_test.dart), where
two devices share nothing but what crosses the wire: round trip, out-of-order
delivery, replay rejection, a third party failing to decrypt, a tampered key
bundle being refused, and state surviving a restart.

Every failure path refuses rather than falling back to plaintext. The previous
code caught encryption errors and sent the message unencrypted anyway, which is
the one outcome worse than not sending.

**Attachments are encrypted too.** Bodies are sealed with AES-256-GCM before
upload; the key and nonce travel inside the Signal envelope alongside the
caption, so the server never sees them. A fresh key per attachment — reusing a
key/nonce pair in GCM leaks the XOR of the two plaintexts.

The server is told a body is opaque (`encrypted: true`, declared as
`application/octet-stream`). That flag is load-bearing: the completion path
re-compresses images, builds thumbnails, and runs OCR, and on ciphertext the
first two destroy the object while the third would be reading the user's
attachments. All three are skipped, and an upload in flight across the deploy
defaults to "encrypted" rather than the other way round.

GCM authenticates, so an attachment altered in storage is refused rather than
displayed — see `attachment_crypto_test.dart`, which covers a flipped byte, a
truncated file, and the wrong key.

**Encryption is now the default for every direct chat.** It was previously
gated behind an `isSecret` flag that was `false` at every call site, so none
of it was reachable. `isSecret` now means only "keep nothing on this device";
encryption is independent of it and on either way.

Two consequences worth knowing:

- **The local cache is the message history.** A ratchet deletes keys as it
  advances — that deletion *is* forward secrecy — so the server's stored
  ciphertext is not decryptable after the fact, and own sent messages never
  were (they are encrypted to the peer). `ChatBloc` loads from the cache
  first and only decrypts server history for messages it has not already
  seen, which is how offline delivery still works.
- **Mixed history.** Messages sent before this change are plaintext. They are
  displayed, but the bubble marks them with an open padlock. The check that
  decides this (`SignalService.isEnvelope`) is strict on purpose: it is the
  one place a downgrade could hide, so it requires the exact envelope shape,
  a known version, and a known message type.

**Still not encrypted: group messages.** Pairwise sessions do not cover a
group; that needs sender keys. There is no group message UI yet either, so
nothing currently misrepresents itself — but that is the gap to close before
groups ship.

**5.3 The summary endpoint sends conversation text to Hugging Face.**
The client posts message bodies because the server holds no plaintext. In a
product claiming E2EE this is a real privacy cost, and it compounds 5.2. Should
be opt-in per conversation with the UI saying so. Documented in the route,
**not enforced**.

### 🟠 P1 — blocks publication

**5.4 Release signing** — [build.gradle.kts:39](frontend/android/app/build.gradle.kts:39)
still uses debug keys. Play Store requires a real keystore.

**5.5 iOS is unconfigured** — no `GoogleService-Info.plist`, no APNs key. iOS
push cannot work. The bundle id was renamed but nothing else is done.

**5.6 APK is 62.2 MB** — bundles all ABIs. `--split-per-abi` cuts it to ~20 MB.

**5.7 No privacy policy / store listing** — Play requires both, and a data-safety
declaration that must honestly describe 5.2 and 5.3.

### 🟡 P2 — quality and cost

**5.8 File upload returns 503** — needs three Cloudflare R2 values. Create
buckets `ironlink-avatars` and `ironlink-attachments`, keep them **private**,
scope the token to those two only. `S3_REGION=auto` is mandatory — R2 rejects
any other region in the SigV4 scope.

**5.9 No rate limiting on AI endpoints** — `RATE_LIMIT_REQUESTS_PER_MINUTE`
exists in config but no middleware reads it. Each AI call is a slow, paid
round-trip that can pin the single worker.

**5.10 `assemble_staging()` buffers whole files in memory** — a 50 MB upload
costs ~100 MB transient on a 512 MB instance. Fix is S3 multipart upload.

**5.11 Backend error strings are English** in an Arabic UI. Verified on device:
*"Verification failed. Check your code and credentials."* appears inside an
otherwise fully Arabic screen.

**5.12 Free Postgres on Render expires.** Check the date on `ironlink-db`. Do
not put real user data on it.

**5.13 Free instance sleeps** — first request after idle takes ~50 s.

**5.14 Deployed from a feature branch,** not `main`.

---

## 6. Release checklist

```
[ ] Real authentication (Firebase Phone Auth)          P0
[x] Real E2EE for secret chats (Signal Protocol)       P0
[x] Encrypt attachment bytes (AES-256-GCM)             P0
[x] Make encryption the default, not opt-in            P1
[ ] Group messages: sender keys (pairwise won't do)    P1
[x] Voice notes: real upload, real waveform, encrypted P0
[ ] Opt-in gate on AI summary                          P0
[ ] Release keystore + signing config                  P1
[ ] iOS: GoogleService-Info.plist + APNs key           P1
[ ] --split-per-abi                                    P1
[ ] Privacy policy + data-safety declaration           P1
[ ] Cloudflare R2 for media                            P2
[ ] Rate limiting on AI endpoints                      P2
[ ] Localise backend error strings                     P2
[ ] Paid Postgres before real users                    P2
[ ] Merge to main, delete the dead service             P2
```

---

## 7. Critical warnings

**`DB_ENCRYPTION_KEY`** encrypts columns at rest. It is set in Render and must
live in a password manager. **If it is lost or changed, every encrypted row
becomes permanently unreadable.** It is deliberately `sync: false` rather than
`generateValue: true` for exactly this reason, and it appears nowhere in this
repository.

**Secrets that were exposed during setup.** Two Hugging Face tokens were pasted
into a chat and have been revoked. If any other token or key was ever pasted
anywhere outside Render, revoke and reissue it. Deleting a *file* does not
revoke a *key* — Firebase service-account keys must be revoked in the console.

**`DEV_AUTH_BYPASS` must never reach production.** It provisions any phone
number on demand and accepts a fixed OTP. The settings validator refuses to
start when it is enabled with `ENV=production`; do not weaken that guard.

---

## 8. Environment traps — read before debugging

**The local venv drifted from `requirements.txt` and hid a production crash.**

| Package | Pinned | Was installed locally |
|---|---|---|
| `fastapi` | 0.115.5 | 0.139.2 ← hid the 204 bug |
| `sqlalchemy` | 2.0.36 | 2.0.51 (2.0.36 lacks Python 3.14 support) |

Local Python is **3.14**; the Docker image is **3.12**. Some pins have no 3.14
wheels and were installed unpinned locally. `requirements.txt` is untouched and
correct for the image.

**The test suite was blind.** Nothing imported `app.main`, so 43 tests passed
against code that could not start — and *every* deploy failure in this project
has been an import-time crash. `tests/test_app_boot.py` closes that gap and was
validated by mutation.

**`alembic` shadowing.** From the repo root, `import alembic` resolves to the
local `alembic/` directory rather than the package.

**Firebase config holds two packages.** `google-services.json` contains both
`com.example.ironlink` and `com.ironlink.app`, so builds work either way.

---

## 9. Useful commands

```bash
# Backend
.venv/Scripts/python.exe -m pytest -q            # expect 62 passed
.venv/Scripts/python.exe -c "import app.main"    # must not raise

# Frontend
cd frontend && flutter analyze lib                # expect 0 errors
flutter build apk --release \
  --dart-define=API_BASE_URL=https://ironlink-api.onrender.com/api/v1 \
  --dart-define=WS_BASE_URL=wss://ironlink-api.onrender.com
flutter install --release -d <device-id>

# Live
curl https://ironlink-api.onrender.com/health
```

---

## 10. Commits

```
966ae67  feat(auth): gated dev login + package rename to com.ironlink.app
95effc1  fix(frontend): repair 19 analyzer errors blocking the APK build
f8ccea1  feat(frontend): native splash screen from the brand animation
5dc08e5  docs: update handover after AI routes and Firebase fix
e93c8aa  feat(ai): register the AI endpoints, load Firebase creds from env
9dd13aa  docs: add handover report
a505685  fix(frontend): route every screen through Env, not hardcoded hosts
5902994  fix(api): declare response_model=None on every 204 route
5915be8  chore: pin LF line endings for shell scripts
16119ef  fix(deploy): rename blueprint service, stop hardcoding the hostname
faec629  fix(deploy): make the service deployable on Render's free tier
5a05a68  feat(storage): move object storage to Cloudflare R2
b060a6e  fix(deploy): unbreak the build, make the service deployable
7c59a3b  feat(db): add initial schema migration, fix alembic async driver
d4e732d  fix: repair boot crashes, merge orphaned backend/app into app/
```

Each message documents its own root cause and how it was verified.
`git show <hash>` for detail.
