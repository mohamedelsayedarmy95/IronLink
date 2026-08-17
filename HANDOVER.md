# IronLink — Project Status & Release Readiness

**Last updated:** 2026-08-17
**Branch:** `fix/boot-crashes-and-backend-merge` — 25 commits ahead of `main`, all pushed, PR #1 open
**Live API:** https://ironlink-api.onrender.com → `{"status":"ok","env":"production"}`
**Android package:** `com.ironlink.app`
**Tests:** 426 frontend, 339 backend, all passing. CI runs both on every PR.

> Written so a fresh session can pick this up cold. Everything marked ✅ was
> verified by running it, not by reading the code. Where something is unverified
> or uncertain, it says so.

---

## 1. Executive summary

The backend is deployed and healthy. The Android app builds, installs, and runs
on a physical device.

Since this document was last written in full, two of the three things it called
blockers have been dealt with:

* **Encryption is real.** The `"mock_ciphertext"` stub is gone. Signal Protocol
  (X3DH + Double Ratchet) for one-to-one, Sender Keys with a membership epoch
  baked into the key name for groups, AES-256-GCM for attachments and voice.
  Encryption is the default for every chat.
* **Self-registration works.** Firebase Phone Auth, real numbers, no manually
  provisioned test accounts. Session-bound JWTs with refresh rotation and
  reuse detection.
* **Smart Keyword Alert is built** — see §11 below, and the two documents in
  `docs/`.

What is still genuinely open is listed in §5 and §11. The largest single item
is that **none of the recent work has been exercised on a physical device**:
two native dependencies were added and have never been through an Android
build.

⚠️ **Sections 2 through 10 were written on 2026-08-07 and have not been
re-audited line by line since.** They are broadly right about infrastructure
and environment traps, and wrong wherever they describe encryption or
authentication as missing. Trust §1 and §11 over them where they conflict.

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

**5.0 Real phone numbers: configuration now done, one cap remains.**

Resolved 2026-08-16 in the Firebase console for `ironlink-1fd4c`:

- The build machine's debug SHA-1 and SHA-256 are registered against
  `com.ironlink.app`. The pre-existing `5e:2b:21:e7:…` SHA-1 belongs to a
  different machine and was left in place so that build keeps working.
- Play Integrity API enabled at the Google Cloud project level. Phone Auth
  depends on it and it had never been switched on.
- A refreshed `google-services.json` is in `frontend/android/app/`. It now
  carries two `certificate_hash` values for `com.ironlink.app`; the previous
  copy had none, which is why real numbers could not be attested.

**That file is gitignored** (`.gitignore` line 7), so it is not in the repo
and a fresh clone will not have it. Download it from Project settings → Your
apps → `com.ironlink.app`. A build with the stale or missing file fails
real-number sign-in in exactly the way described below, silently.

Still outstanding, and both will bite:

- **Spark plan: 10 verification SMS per day.** Once exhausted, real-number
  sign-in hangs with no error — indistinguishable from the bug that was just
  fixed. The console reports no live counter, so the remaining budget cannot
  be checked. Blaze removes the cap.
- **SMS region policy is Allow → Egypt only.** Correct for testing here, and
  a silent wall for anyone outside +20. Widen it before anyone else signs up.

App Check is deliberately untouched: nothing is registered and nothing is
enforced. Turning enforcement on before the app ships an App Check SDK would
block every sign-in, including the test numbers.

**Historical — what was wrong before the above:**

Only Firebase *test* numbers sign in today. One reason, in
`frontend/android/app/google-services.json`: **no signing fingerprint is
registered**. Both client entries have an empty `oauth_client` array, so
Firebase cannot attest the app and refuses real-number verification. Test
numbers skip attestation entirely, which is exactly why they are the only
ones that work.

(An earlier revision of this file also blamed a package mismatch. That was
wrong, from reading only the first client entry: the file registers both
`com.example.ironlink` and the real `com.ironlink.app`. The stale
`com.example.ironlink` registration is untidy and worth deleting, but it is
not what breaks sign-in.)

Fix, in the Firebase console for project `ironlink-1fd4c`:

- Project Settings → Your apps → the `com.ironlink.app` entry
- Add the debug signing fingerprints:
  - SHA-1: `A0:FC:23:AC:84:C5:72:B8:F8:1C:E1:A2:87:95:D8:B2:0F:C2:4B:C7`
  - SHA-256: `DF:F4:D6:99:5E:B5:BF:15:29:BD:DD:0C:65:5A:E1:6B:DB:41:67:43:9C:09:2A:DC:E7:5E:C5:30:6F:F6:4D:F2`
- Download the new `google-services.json` over the existing one
- Enable the Play Integrity API for the project

Release builds will need their own SHA once release signing exists — there is
still a TODO for it in `android/app/build.gradle.kts`, so release APKs are
signed with the debug key today.

The code half is done: `POST /auth/register-firebase` lets a verified number
create its own account, so no phone number ever needs adding by hand again.
The military ID is *set* at registration and remains the second factor at
every later sign-in. Admission policy is two flags —
`SELF_REGISTRATION_ENABLED` and `SELF_REGISTRATION_AUTO_APPROVE`; with
auto-approval off, an account registers as `PENDING` and is told so plainly
rather than being handed a token that does not work.

**Worth deciding deliberately:** auto-approval means anyone who controls a
phone number is inside, and the military ID they type is one they chose rather
than one anyone verified. That is right for a consumer messenger; for this
product it is a policy call, which is why it is a flag and not a hard-coded
default.

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

**Group messages are encrypted too, with sender keys.** A group message is
encrypted once with a key belonging to the sender that every member holds a
copy of — encrypting once per member would cost O(members) per message.

The consequence, and the thing group encryption usually gets wrong: a member
who leaves still holds that key, so removing them from the member list does
not remove their access. Only rotation ends it.

Rotation here is structural rather than remembered. `Group.members_epoch`
bumps on every membership change, and the epoch is part of the sender key's
*name* (`SenderKeyName` scope is `groupId@epoch`), so a changed epoch is
necessarily a different key — there is no code path where the epoch moves and
the old key is still used, because one cannot be written.

Distribution messages ride the existing pairwise sessions, one ciphertext per
recipient, which is what stops the server substituting its own key.

Attachments and voice notes work in groups too. The body is sealed once with
its own AES-GCM key, and that key rides the group envelope — one attachment
encryption for the whole group, not one per member. The pointer, caption,
duration and waveform are all inside the envelope rather than wire fields, so
the server cannot tell which stored object a group message refers to, or how
long a voice note is.

The honest limits, both covered by tests rather than left to assumption:

- A removed member can still read what was sent *before* they left. Nothing
  retracts a message someone already received.
- Object storage has no per-group access control: any authenticated user who
  knows a media key can fetch the object. Under encryption they get
  ciphertext they hold no key for, which is why this is a privacy nuisance
  (it leaks that an object exists and its size) rather than a disclosure. A
  membership check on `/media/{key}/url` would still be worth adding.

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
[x] Group messages: sender keys + epoch rotation       P1
[x] Group attachments and voice notes, encrypted       P1
[ ] Membership check on the media presign endpoint     P2
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

---

## 11. Smart Keyword Alert — current state (2026-08-17)

Built against `IronLink-Smart-Keyword-Alert-Master-Prompt-v4.1.0.md`, phases 0
through 7. Two documents carry the detail:

* [`docs/SMART_KEYWORD_ALERT_AUDIT.md`](docs/SMART_KEYWORD_ALERT_AUDIT.md) —
  what was found at Phase 0 and why the architecture is what it is.
* [`docs/SMART_KEYWORD_ALERT_REPORT.md`](docs/SMART_KEYWORD_ALERT_REPORT.md) —
  the final report, with a status matrix naming a file and a test for every
  capability.

### The short version

The feature had never worked. Four defects stacked in one module, each hidden
because every call site swallowed its own exception: a synchronous Redis client
pointed at a docker-compose hostname that cannot resolve on Render; awaited
non-awaitables making all three keyword endpoints return 500; a publisher and
subscriber on different Redis databases; and a normalizer that deleted every
Arabic character.

Because encryption is now the default, the server holds no key and cannot read
an attachment — so the pipeline runs **on the device**, which is what the
specification mandates anyway. Rules and alerts live in `ironlink_alerts.db`
(sqflite, separate from the message cache), the server never receives a
keyword, and the push payload that used to carry one to FCM no longer does.

### Where the code is

```
frontend/lib/features/keyword_alert/
  domain/          rules, alerts, the state machine, the sender-report boundary
  text/            Arabic + Latin normalization, offsets preserved
  matching/        the layered matcher and five-factor confidence scoring
  ocr/             pre-flight, extractor interface, PDF text layer, ML Kit
  local/           sqflite store, plus an in-memory one
  bloc/ screens/ widgets/
  keyword_alert_pipeline.dart    one document, end to end
  keyword_alert_service.dart     the queue between the widget and the pipeline
```

### Open decisions — these need a human

1. **Arabic image OCR is blocked by the Android toolchain, not by app size.**
   This entry has been wrong twice; `docs/SMART_KEYWORD_ALERT_AUDIT.md` section
   4b keeps both versions. Short form: the model is 1.37 MB, not tens of
   megabytes, so size was never the issue - but this project is on AGP 9.0.1 and
   every Arabic OCR binding on pub calls `jcenter()` in its Gradle script, and
   Gradle removed that method — JCenter shut down in 2021. The plugin project
   cannot even be evaluated. Established twice by CI, the second time on a green
   baseline so the result means what it says. Downgrading AGP would not help,
   because the removal is Gradle's, not AGP's. The only path left is vendoring
   the plugin and rewriting ~15 lines of its Gradle script — bounded work with an
   unbounded tail, since it means owning third-party native code. Not taken. iOS
   is unaffected: Apple Vision needs a platform channel, not a Gradle plugin.
2. **The native surface builds in CI, and has never run anywhere.**
   `flutter build apk --release` verifies Gradle configuration, compilation,
   every native plugin, R8 shrinking and asset bundling. It required a
   placeholder `google-services.json` (`android/app/google-services.ci.json`) —
   the real one is gitignored, and without any the Google Services plugin
   refuses to configure the project, which is why the whole native surface had
   gone unverified for want of a config file.
   That job deliberately publishes nothing. An APK with a placeholder Firebase
   config would look like a working build and fail at sign-in. Build the
   shippable one where the real config lives.
   What no build can verify is behaviour: whether ML Kit actually recognises
   text on a real photograph, and whether the PDF reader copes with a real
   document. That still needs a device.
3. ~~`deploy.yml` targets Fly.io.~~ **Settled 2026-08-17: the file is gone.**
   `fly.toml` has never existed anywhere in this repository's history, and
   `flyctl deploy` requires one — so that step could not have worked even with
   a token. It was template scaffolding nobody removed. Render deploys from its
   own git integration (`render.yaml`, `autoDeploy: true`), so no workflow
   should be deploying anything. Its two genuinely useful steps moved into
   `ci.yml`.

### Deliberately not done

* Scanned (image-only) PDFs are not rasterized.
* No performance or battery measurement — the numbers in §10.3 of the
  specification are targets, not observations.
* No telemetry sink or dashboards. The event types and guardrail thresholds
  exist; nothing ships them anywhere.
* Semantic matching, synonym expansion and Office formats are declared in the
  feature-flag registry and not implemented. The flags exist so the inventory
  is honest, not so the features look present.

---

## 12. Continuous integration (added 2026-08-17)

`.github/workflows/ci.yml` runs on every pull request and on pushes to `main`:

| Job | What it runs |
|---|---|
| Backend | `pytest tests/` on Python 3.12 |
| Backend (image) | `docker build` of the same Dockerfile Render builds |
| Frontend | `flutter analyze --no-fatal-infos`, a strict analyze over `keyword_alert`, then `flutter test` |
| Android | `flutter build apk --release`, then confirms `ara.traineddata` is inside the APK |

**Nothing deploys from CI.** Render watches the branch itself. `deploy.yml` was
deleted rather than fixed: it targeted Fly.io, and `fly.toml` has never existed
in this repository, so it could not have worked under any configuration.

The Android job is the one that changes the risk picture. Three native plugins —
ML Kit, Tesseract, Syncfusion PDF — had never been through an Android build,
and unit tests cannot reach a platform channel. It builds `--release` rather
than `--debug` on purpose: R8 shrinking is where ML Kit and Tesseract break, by
stripping classes reached only reflectively, and a debug build would pass while
saying nothing about what ships. It signs with the debug key because
`android/app/build.gradle` still does — a real gap for shipping, no obstacle to
verifying the build.

Before this, 765 tests existed and ran nowhere but a developer's machine.

**The analyzer bar is real.** The repository carries 40 pre-existing `info`
lints, which are tolerated; every warning and error was cleared, so any new one
fails the build. Do not weaken this to `--no-fatal-warnings` — clear the
warning instead.

Flutter is pinned to 3.47.0 in both workflows deliberately. A toolchain that
moves on its own turns an unrelated pull request red and sends its author
hunting a bug they did not write.

---

## 13. IronShield — Security Center (added 2026-08-17)

The first P0 feature from `IRONLINK-Competitive-Moat-Master-Prompt`, which named
it "the highest-value, lowest-dependency P0 feature". The audit confirmed that:
its stated dependency, the authentication system, already provided everything it
needed.

### Built on what already existed

| Endpoint | Status |
|---|---|
| `GET /auth/sessions` | Already present. Returns device type/name, IP, city, created, last-active, and which session is the caller's. |
| `DELETE /auth/sessions/{id}` | Already present. Per-device revoke: kills the refresh token and closes that device's socket. |

**No server change was made.** A Security Center is the last place to introduce
new privileged operations, so "Secure my account" composes from the per-device
endpoint rather than adding a bulk one.

### Where the code is

```
frontend/lib/features/security/
  domain/security_posture.dart     findings, levels, session model
  security_repository.dart         the two endpoints
  bloc/security_bloc.dart          load, revoke, revoke-others
  screens/security_center_screen.dart
```

### The design decisions worth knowing

**No percentage.** A number implies precision that a handful of boolean signals
cannot support. Three levels — high, medium, low.

**The worst finding sets the level**, never an average. Averaging lets four
reassuring facts bury one critical one, which is the failure mode of every
security score that tells users what they want to hear.

**An unestablished signal produces no finding.** Not a default that flatters the
score. If the app cannot confirm encryption is on, the screen says nothing about
encryption rather than assuming the best.

**Good news is stated too**, so "checked and fine" is distinguishable from "not
checked". Every finding carries a "why am I seeing this?" in one sentence.

**Findings are codes, not sentences**, localized at the edge — a finding
carrying its own English text would be shown in English to an Arabic speaker.

**A partial "secure my account" is counted and reported.** Signing out three of
four devices and saying "account secured" would be the worst lie this screen
could tell.

The avatar tap used to sign out in one gesture, taking every key on the device
with it. It opens an account menu now, with the Security Center above the
irreversible action.

### All eight capabilities

| Capability | Where |
|---|---|
| Session management | `security_repository.dart` — the two endpoints that already existed |
| Device trust | session list with current-device marking and staleness |
| Security score | `domain/security_posture.dart` |
| Secure my account | composed from the per-device revoke, never a bulk endpoint |
| Login alerts | `GET /auth/security-events` — new-device logins were already detected and audit-logged by `_issue_login`; nothing detected them *for the user* until now |
| Suspicious activity | same feed: failed logins, revocations, rate-limit hits, forced disconnects |
| Link safety | `domain/link_safety.dart` — structural only, no network |
| Scam intelligence | `domain/scam_signals.dart` — on-device, bilingual |

### The two on-device engines, and why they are shaped that way

**Link safety consults nothing.** The obvious build checks each URL against a
reputation service, which would send the user's browsing to a third party from
inside an end-to-end encrypted messenger. So it reads the URL and nothing
leaves. That bounds it — it cannot know a domain registered yesterday serves
malware — in exchange for catching deception encoded in the URL itself, which is
how nearly all phishing reaches someone in a chat app.

Its most valuable check is per-*label* mixed-script detection. "pаypal.com" with
a Cyrillic а is invisible at any font size and defeats any amount of care, but
the codepoints say so instantly. Per label, not per host: every
internationalised domain has a Latin TLD, so a whole-host comparison would flag
the entire non-Latin internet.

Two bugs found while building it, both silent:

- Dart percent-encodes non-ASCII hosts rather than punycoding them, so
  "pаypal.com" arrived as "p%D0%B0ypal.com" and looked like pure ASCII. The
  homograph check — the whole point of the class — was passing its tests by
  finding nothing.
- Fixing that made a genuine Arabic domain look mixed-script, because of the
  Latin TLD. Hence per-label.

**Scam intelligence is built to under-fire.** A detector that fires on ordinary
conversation is worse than none: every false positive spends trust, and once the
banner is learned as noise the one real warning goes with it. One signal never
warns; two must agree. The exception is a request for a verification code, which
warns alone because it has no innocent reading in an app that sends codes — and
which is the commonest account-takeover vector against this product.

The patterns are bilingual. A scam detector that only reads English would
protect this product's users selectively, which is how a security feature
becomes a false assurance.

Most of that test file is ordinary messages that must stay silent. It earned its
keep immediately: a fix for one pattern would have warned on "what is the code
review process here?" — a false positive on the one signal allowed to warn
alone.

### Still not done

- **Nothing pushes a login alert.** The events are recorded and shown; the
  device is not woken. `send_ocr_push` reads a single `User.fcm_token`, so a
  push would also reach the device that just logged in. Doing it properly wants
  a token per session.
- **Link and scam analysis are not wired into the chat UI.** Both engines are
  complete and tested; no message bubble consults them yet. That is a UI
  decision — where a warning appears, and how a user dismisses one — rather
  than more detection work.

63 tests across the feature. Analyzer clean.
