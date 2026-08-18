# IronLink Repository Audit

**Against:** `IRONLINK — PRINCIPAL ARCHITECT MASTER EXECUTION SYSTEM v4.0`, §51–57
**Date:** 2026-08-17
**Branch:** `fix/boot-crashes-and-backend-merge`
**Scope:** Phase 0. v4.0 §51 says *"Then STOP."* — no production code was
modified while producing this document.

> **Update, same day.** The stop condition at the end was answered: push
> notifications carry the sender's name and no content. **Gate A was then
> executed** — SEC-01, SEC-02 and BE-01 are closed, with tests
> (`tests/test_push_privacy.py`). Their entries below are left as written, with
> the finding preserved and a resolution appended, because an audit that edits
> its findings once they are fixed stops being a record of what was true.

Every claim below is labelled **FACT** / **INFERENCE** / **ASSUMPTION** /
**PROPOSAL** / **UNVERIFIED** as §3 requires, and carries a repository path.

---

## 1. Executive Summary

IronLink is a genuinely encrypted messenger with an unusually good ratio of
tests to code and an unusually poor ratio of shipped subsystems to named ones.

**FACT** — 12,087 lines of backend Python, 34,362 lines of Flutter, and 12,040
lines of test code across 923 passing tests (360 backend, 563 frontend). CI runs
four jobs and is green.

**FACT** — The E2EE is real, not a mock. Signal protocol lives on the device
(`frontend/lib/core/crypto/signal.dart`, `group_signal.dart`,
`sender_key_store.dart`), and the server-side `encryption_service.py` that once
faked it has been deleted, with `tests/test_key_directory.py:64`
(`test_encryption_service_is_gone`) failing the build if anyone reintroduces it.
That is a stronger guarantee than a comment.

**FACT** — Of the fifteen subsystems v4.0 names, **one exists**. IronShield has
seven files under `frontend/lib/features/security/`. IronVault, IronDocs,
IronWatch, IronSearch, IronAI, IronMemory, IronFlow, IronMesh, IronCanvas,
IronProof, IronGhost and IronLegacy have **zero code files** between them.

**The headline finding is not the missing subsystems.** It is that the one place
message-derived data reliably leaves the encryption boundary is the push
notification, and both of its branches are wrong: with E2EE on it sends
ciphertext to Google and shows the user a blob of JSON on their lock screen;
with E2EE off it sends the plaintext message. See **SEC-01**.

**INFERENCE** — The repository's problem is not that it overclaims in code. It
is that the *documents* describe a platform and the *code* is a messenger. That
gap is the thing this audit exists to make visible, and it is nobody's fault
that it exists — it is what an audit is for.

---

## 2. Actual Architecture

**FACT**, from direct inspection:

```
Flutter client (34,362 LOC, 11 feature modules)
  auth · chat · groups · community · channel · broadcast
  contacts · moderation · home · keyword_alert · security
        │
        ├── Signal on device — X3DH + Double Ratchet (core/crypto/signal.dart)
        ├── Sender Keys for groups, membership-epoch scoped (group_signal.dart)
        ├── sqflite local store (features/chat/local/message_store.dart)
        └── flutter_secure_storage for tokens — never SharedPreferences
        │
   WebSocket ─────────────── REST
        │                      │
FastAPI (12,087 LOC, 17 route modules, 15 models)
        ├── PostgreSQL 16 — 9 Alembic migrations
        ├── Redis — pub/sub fan-out, OTP store, WS session registry, noeviction
        ├── MinIO / object storage — chunked resumable upload
        └── Firebase — phone auth verification + FCM
```

**FACT** — Deployment is a Render blueprint (`render.yaml`): one Docker web
service, free-tier Postgres and Redis. Migrations run at container start from
`docker-entrypoint.sh` because the free tier has no pre-deploy hook.

**FACT** — The crypto dependency set is `pointycastle ^4.0.0` and `crypto
^3.0.7` (`frontend/pubspec.yaml:32,35`). There is no `libsignal` binding; the
protocol is implemented in Dart in this repository.

**UNVERIFIED** — Whether that Dart Signal implementation is cryptographically
correct. It has tests (`frontend/test/signal_test.dart`), but a passing test
suite written alongside an implementation does not constitute a cryptographic
review. See **RISK-01**.

---

## 3. Feature Reality Matrix

Status vocabulary per v4.0 §5.

| Feature | UI | Domain | Backend | DB | Security | Tests | Status |
|---|---|---|---|---|---|---|---|
| 1:1 messaging (E2EE) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | `INTEGRATED` |
| Group messaging (Sender Keys) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | `INTEGRATED` |
| Attachments (encrypted, resumable) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | `INTEGRATED` |
| Media metadata stripping | n/a | ✅ | n/a | n/a | ✅ | ✅ | `INTEGRATED` |
| Auth — Firebase phone + OTP | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | `INTEGRATED` |
| Session lifecycle / revoke | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | `INTEGRATED` |
| Contact discovery (salted hash) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | `INTEGRATED` |
| Block / report | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | `INTEGRATED` |
| Self-destructing messages | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | `INTEGRATED` |
| Controlled group entry | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | `INTEGRATED` |
| **IronShield** (security centre) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | `INTEGRATED` |
| **IronWatch** (keyword alert) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | `INTEGRATED` — **corrected 2026-08-18, see below** |
| Scam intelligence | ✅ | ✅ | n/a | n/a | ✅ | ✅ | `INTEGRATED` (on-device only) |
| Link safety | ✅ | ✅ | n/a | n/a | ✅ | ✅ | `INTEGRATED` |
| Observability | n/a | ✅ | ✅ | n/a | ✅ | ✅ | `INTEGRATED` |
| **Push notifications** | ✅ | ✅ | ⚠️ | ⚠️ | ❌ | ⚠️ | `BROKEN` — see SEC-01, REL-02 |
| Conversation previews | ✅ | ⚠️ | ❌ | ✅ | ⚠️ | ❌ | `BROKEN` — see SEC-02 |
| Offline outbox | ✅ | ⚠️ | n/a | ❌ | n/a | ⚠️ | `PARTIAL` — in-memory only, see REL-01 |
| AI features | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | `INTEGRATED` (consent-gated, kill-switched) |
| Communities / channels | ✅ | ✅ | ✅ | ✅ | ⚠️ | ⚠️ | `UNTESTED` at the permission boundary |
| PDF attachments | ⚠️ | ❌ | ❌ | ❌ | ❌ | ❌ | `UI_ONLY` — "coming soon" snackbar, `attach_flow.dart:89` |
| Voice meetings / calls | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | Not present |
| IronVault, IronDocs, IronSearch, IronMemory, IronFlow, IronMesh, IronCanvas, IronProof, IronGhost, IronLegacy | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | Not started — **zero code files each** |

> ### Correction — IronWatch, 2026-08-18
>
> The matrix above originally graded IronWatch `PARTIAL` on the grounds that
> "48h history and per-chat scoping" were absent. **Both claims were wrong**,
> and the error was mine: I recorded them without checking the code, which is
> the exact failure §4 of the master prompt exists to prevent.
>
> What is actually there:
>
> | Spec requirement | Where |
> |---|---|
> | 48h history | `keyword_alert/domain/keyword_alert.dart:319` — `retentionWindow = Duration(hours: 48)` |
> | Per-chat keywords | `alert_store.dart:56` — `conversation_scope` column, with two indexes on it |
> | Acknowledgement flow | `keyword_alert.dart:59` — `AlertStatus.acknowledged`, one-way |
> | Confidence threshold | `alert_bloc.dart:165` — `>= 0.85` |
> | False-positive control | `alert_store.dart:308` — rolling 24h soft cap per rule |
> | Local / cloud modes | `ocr/ocr_mode.dart` — `OcrModeOutcome.local` / `.cloud`, never silent |
>
> The `Duration(hours: 24)` occurrences that could look like a shortened
> retention window are the **daily rate cap**, which is a different mechanism
> and documented as one.
>
> IronWatch is `INTEGRATED` against its specification.

---

## 4. Security Findings

### SEC-01 · Push notification body carries message-derived content — **CRITICAL**

**FACT.** `app/api/routes/websocket.py:177-183` builds the FCM notification body
from `frame.get("content")` and passes it to `push_service.send_message_push`,
which sets it as `messaging.Notification(body=preview[:80])`
(`app/services/push_service.py:87`).

`frame["content"]` is whatever the client put on the wire. From
`frontend/lib/features/chat/bloc/chat_bloc.dart:493-495`, in the author's own
words: *"once encryption is on, the latter is the ciphertext envelope"*.

Both branches are defective, in different ways:

| Mode | What is sent to Google | What the user sees |
|---|---|---|
| E2EE on (`_encrypted == true`) | 80 characters of ciphertext envelope | A blob of JSON on the lock screen |
| E2EE off (`_encrypted == false`, `chat_bloc.dart:471`) | **The plaintext message** | The message |

The second is an unambiguous violation of v4.0 §7–11 ("Never log … E2EE
plaintext, private messages") and of the v3 standard's "no private message
content ever leaves device unencrypted". The first is not a content leak of the
same severity, but it ships message-derived bytes to a third party for no
benefit and produces a visibly broken notification.

**Correct behaviour (PROPOSAL):** a content-free push — sender name, or not even
that — with the client decrypting and rendering the preview locally on receipt.
This is what every serious E2EE messenger does, and it is *simpler* than the
current code, not harder.

**Impact:** High. **Confidence:** FACT — read on both sides of the wire.

> **RESOLVED 2026-08-17.** The `preview` parameter was removed from
> `send_message_push` rather than merely passed a safe value — leaving it in
> place would leave the next caller free to fill it. The notification is now
> `Notification(title=sender_name)` with no body, and the call site does not
> read `frame["content"]` at all. No generic body was substituted: the server
> does not know the recipient's language, and "New message" in the wrong one is
> worse than a name on its own. Held by `tests/test_push_privacy.py`, which
> asserts against the whole frame handler rather than one line, since the leak
> was a local variable built two lines above the call.

### SEC-02 · Conversation preview is a slice of ciphertext — **HIGH**

**FACT.** `app/api/routes/chats.py:96`:
```python
preview = (last_msg.content_ciphertext or f"[{last_msg.message_type}]")[:20]
```

The server slices twenty characters off the ciphertext and returns it as
`last_message_preview`. A twenty-character fragment of a Signal envelope cannot
be decrypted by anybody, including the intended recipient.

**INFERENCE** — this preview was designed against a non-E2EE model and never
revisited when encryption landed. It is not a leak (the fragment is useless to
an attacker too); it is a feature that cannot work as written, and its presence
implies to a reader that server-side previews are a supported concept here.

**Impact:** Medium (correctness), High (as a false architectural signal).

> **RESOLVED 2026-08-17.** The server returns no text preview. It may still
> return a message *kind* — `[image]`, `[voice]` — which it already knows from
> a column and which covers the one case the client cannot: a conversation this
> device holds no local copy of. The conversation list now reads its preview
> from the decrypted local history via `MessageStore.latestPerPeer()`, one
> grouped query for the whole list rather than one per row.

### SEC-03 · No cryptographic review of the Dart Signal implementation

**UNVERIFIED.** `frontend/lib/core/crypto/signal.dart` implements X3DH and the
Double Ratchet in Dart. It is tested, but by tests written against the same
understanding that produced it. v4.0 §11 requires a dedicated security review
and threat model for anything touching E2EE and key management.

**Impact:** Critical if wrong. **Recommended action:** external review, or
migration to a maintained binding. Not something to resolve by reading it again.

### SEC-04 · `/metrics` is fail-closed — **no finding, recorded as verified**

**FACT.** `app/core/observability.py` — 404 when `METRICS_TOKEN` is unset,
`secrets.compare_digest` comparison, no identifying metric labels, enforced by
`tests/test_observability.py::TestNoIdentityInLabels`. Checked because a metrics
endpoint is a common accidental leak. This one is not.

### SEC-05 · Log hygiene — **verified clean**

**FACT.** All 38 logging call sites were read. None carries a message body, an
OTP value, key material, or an untruncated phone number
(`app/services/sms_gateway.py:24` truncates to five digits). Since 2026-08-17 a
structlog processor censors by key stem regardless.

---

## 5. E2EE Boundary Findings

**FACT.** What the server can see, established by inspection rather than by
documentation:

| Data | Server sees | Evidence |
|---|---|---|
| Message content | **No** — ciphertext only | `app/models/message.py:50,102` |
| Attachment bodies | **No** — encrypted before upload, key travels in the envelope | `frontend/lib/core/media_service.dart:68` → `uploadEncrypted` |
| Attachment MIME type | **No** — declared as `application/octet-stream` | `media_service.dart:56` (`encryptedMimeType`) |
| Who messages whom | **Yes** | `Message.sender_id`, `recipient_id` |
| When, and how often | **Yes** | `Message.created_at` |
| Message size | **Yes** | inherent to storage |
| Group membership | **Yes** | `app/models/group.py` |
| Contact graph | **Hashed, salted** | `app/services/contact_discovery.py` |
| **Push preview** | **Yes — see SEC-01** | `websocket.py:177` |

**FACT** — OCR runs on the device (`frontend/lib/features/keyword_alert/ocr/`)
and `SERVER_SIDE_OCR_ENABLED` defaults to `False` (`app/config.py`). The
keyword is not in the FCM payload.

**FACT** — AI features are the one deliberate, disclosed exception: plaintext
reaches Hugging Face, gated by per-conversation consent
(`app/services/ai_consent_service.py`) and by a global `AI_FEATURES_ENABLED`
kill switch. This is documented at `app/config.py` and is a legitimate
consented boundary crossing, not a leak.

---

## 6. Privacy Findings

**FACT** — Media metadata is stripped on the device before encryption
(`frontend/lib/core/media/metadata_scrubber.dart`, 22 tests). Prior to
2026-08-17 every photograph carried its GPS coordinates, because
`image_picker_android`'s `ExifDataCopier` copies GPS tags onto the resized copy
and the `imageQuality: 92` re-encode made this look handled.

**FACT** — No metric or log carries a user, chat, group, device or phone
identifier.

**PRIV-01 (open).** **FACT** — There is no data classification document. v4.0
§7–11 requires every data type classified PUBLIC → CRYPTOGRAPHIC_SECRET with
storage, retention, logging and deletion policy. The policies exist in practice,
scattered across code comments. They are not written down as a policy.

**PRIV-02 (open).** **UNVERIFIED** — Whether user-initiated deletion propagates
fully. `deleted_for_everyone` exists on `Message`, and the self-destruct sweeper
wipes expired rows, but there is no test that a deletion reaches object storage
for attachments. A message deleted while its encrypted body stays in the bucket
is a deletion that did not happen.

---

## 7. Reliability Findings

### REL-01 · The outbox is in-memory and silently lossy — **HIGH**

**FACT.** `frontend/lib/core/ws_service.dart:42` — `final _outbox = <String>[]`.

It correctly fixes a worse bug (the comment at `:36-41` records that `send` was
a null-aware no-op, so a message typed on a dropped connection drew an
optimistic bubble and vanished — on every WiFi-to-mobile handover). But:

- **It is a Dart list, not a table.** Kill the app and the queue is gone. The
  optimistic bubble was already persisted to sqflite, so the user sees their
  message in the conversation and it was never sent.
- **It drops the oldest silently** when full (`:164`,
  `if (_outbox.length >= _maxOutbox) _outbox.removeAt(0)`). No user-visible
  signal.
- **`disconnect()` clears it** (`:68`). Correct on sign-out; the risk is any
  future caller that treats disconnect as a reconnect step.

v4.0 §27–30 requires an outbox with acknowledgements and reconciliation. This is
an outbox in name.

**Impact:** High — silent message loss is the failure mode SLO 1 calls the worst
one, because both parties believe it succeeded.

> **RESOLVED 2026-08-17.** The queue is a sqflite table
> (`frontend/lib/core/outbox_store.dart`). Two other changes matter as much as
> the durability: an entry now leaves the queue **on acknowledgement rather
> than on write**, because handing bytes to a sink is not delivery and a socket
> that dies in between loses the frame with no error on either side; and a drop
> is **announced** on a `dropped` stream that marks the bubble failed, rather
> than being silent. Ack-based removal is only safe because the server
> deduplicates on `client_ref`, which it already did.
>
> It also exposed a server-side gap: several permanent rejections carried no
> `client_ref`, so a refused frame was indistinguishable from silence and would
> re-send on every reconnect until it exhausted its retries. All of them now go
> through one `_reject` helper that cannot omit the reference.

### REL-02 · One FCM token per user — **HIGH**

**FACT.** `fcm_token` is a single column on `User`. A second device overwrites
the first, so only the most recently registered device receives push. Known and
recorded in `HANDOVER.md`. It also makes push delivery rate unmeasurable, which
is why `docs/SLO.md` deliberately declines to set an objective for it.

> **RESOLVED 2026-08-17.** The token moved to `user_sessions`
> (`alembic/versions/0010_per_session_fcm_token.py`), additive — `users.fcm_token`
> is still written so a rollback finds it populated, and the write goes away
> with the contract migration. All three senders fanned out: direct messages,
> admin broadcasts, and document wake-ups each had their own copy of the bug.
> Revoked and expired sessions are excluded, so remote sign-out now also stops
> that device's notifications — otherwise revocation was cosmetic, since the
> person holding the phone kept seeing who was messaging whom.

### REL-03 · Idempotency exists — **verified**

**FACT.** `alembic/versions/0009_message_idempotency.py` plus the `client_ref`
de-duplication in `app/services/message_service.py:80-90` — a resend with the
same `client_ref` returns the existing row rather than creating a second.
Checked because §27–30 warns against assuming HTTP 200 means delivered.

### REL-04 · Ordering guarantees are not documented — **MEDIUM**

**UNVERIFIED.** Messages carry `created_at` server timestamps and are fanned out
through Redis pub/sub. Whether ordering is guaranteed under concurrent sends,
and what happens to a message that arrives out of order after a reconnect, is
not written down anywhere and not tested.

---

## 8. Performance Findings

**EVIDENCE NOT AVAILABLE — VERIFICATION REQUIRED.**

There are no benchmarks, no profiling output, and no device testing in this
repository. v4.0 §31–45 forbids fabricating them, so nothing is claimed.

**FACT** — Latency instrumentation now exists
(`ironlink_http_request_duration_seconds`, histogram, p50/p95/p99). It has never
run under load.

**FACT** — Two bounded caches exist with stated limits: `MessageSafety`
(200 entries) and the WebSocket outbox. §31–45 requires LRU with defined limits;
`MessageSafety` drops oldest-first rather than least-recently-used, which for
this access pattern (scroll position) is close enough and is documented as such.

**INFERENCE** — The untested performance risk is the message list. There is no
test with 10,000 messages, which §31–45 explicitly asks for, and the scam/link
assessment now runs per visible bubble (cached, but the cache is cold on first
scroll).

---

## 9. Database Findings

**FACT** — 9 migrations, `alembic/versions/`. Additive: the most recent three
(`0007_ai_consent`, `0008_session_bound_tokens`, `0009_message_idempotency`) add
tables and columns and drop nothing.

**FACT** — Migrations run at container start (`docker-entrypoint.sh:18`), not
pre-deploy, because Render's free tier has no pre-deploy hook. **Documented risk
already recorded in `render.yaml`:** if replicas ever scale above one they race
each other running `alembic upgrade head`.

**DB-01 (open).** **FACT** — There are no down-migrations. Rollback of a schema
change is restore-from-backup only. Acceptable while every migration is
additive; it becomes a data-loss risk the first time one is not.

---

## 10. Realtime / WebSocket Findings

**FACT** — `app/api/routes/websocket.py`, per-connection Redis pub/sub relay,
supporting multiple devices per user and targeted force-disconnect for remote
device revocation (`:52`).

**WS-01 (open).** **FACT** — Events are **not versioned**. Frames are matched on
a bare `type` string. v4.0 §27–30 requires versioned, typed events with explicit
delivery state. Today, changing a frame's shape breaks every client that has not
updated, with no negotiation and no fallback.

**FACT** — Connection count is now instrumented, decrementing in a `finally`.

---

## 11. Flutter Findings

**FACT** — 563 tests. `flutter analyze lib test` reports 40 issues, all `info`,
zero warnings and zero errors. CI treats warnings as fatal
(`.github/workflows/ci.yml:95`).

**FL-01 — RESOLVED 2026-08-17, and the finding was half wrong.**

> Writing the tests showed the code was already direction-clean: **zero**
> `EdgeInsets.only(left:/right:)`, zero hardcoded `Alignment.centerLeft`, zero
> `TextAlign.left`. The gap was verification, not correctness.
>
> `test/rtl_layout_test.dart` pumps widgets under `ar` at 320px and at 2× text
> scale, and — more usefully — statically guards the source, because the
> directional bugs that matter never throw. `EdgeInsets.only(left: 16)` renders
> perfectly in both directions and is simply wrong in one of them.
>
> Gradient stops are excluded deliberately: `Alignment.topLeft` on a
> `LinearGradient` names a decorative sweep, not a reading direction.

**Original finding.** **FACT** — RTL is not tested. Arabic is the template locale
(`app_ar.arb`) and strings exist for both languages, but there is no widget test
that pumps a screen under `Directionality.rtl` and asserts layout. v4.0 §31–45
says Arabic and RTL are first-class and warns specifically against
English-first design. The strings are done; the layout verification is not.

**FL-02 (open).** **UNVERIFIED** — Screen-state completeness. §31–45 requires
every screen to define Loading / Empty / Success / Error / Offline / Permission
Denied / Retry / Partial / Locked / Processing. No inventory exists, so the
answer for any given screen is unknown.

---

## 12. Backend Findings

**FACT** — 360 tests. Config validation refuses to start on dangerous
misconfiguration: `DEV_AUTH_BYPASS` with `ENV=production` raises at import
(`app/config.py:80`), as does production without `ALLOWED_ORIGINS`.

**FACT** — `/health` is liveness, `/health/ready` checks Postgres and Redis and
returns 503, naming the dependency but never the exception text.

**BE-01 (open).** **FACT** — `requirements.txt:31` documents
`app/services/encryption_service.py` as "still a mock". **The file does not
exist** — `tests/test_key_directory.py:64` asserts its absence and fails the
build if it returns. A stale comment claiming a security-relevant mock still
exists is precisely the "Documentation Reality Check" failure v4.0 §4 asks for.
One-line fix.

> **RESOLVED 2026-08-17.** The comment now records that the file was deleted and
> that a test enforces its absence.

---

## 13. Dependency Findings

**FACT** — All backend dependencies are pinned to exact versions. Two notes:

**DEP-01.** `pypdf2==3.0.1` emits `PyPDF2 is deprecated. Please move to the
pypdf library instead` on every test run. Deprecated and unmaintained, in a
component that parses untrusted user files.

**DEP-02.** `frontend/packages/flutter_tesseract_ocr/` is vendored, with
`VENDORING.md` recording the AAR and jar SHA-256 digests. This is the right way
to depend on an unmaintained plugin, and is recorded here as satisfying §31–45's
dependency-governance requirement rather than as a finding.

---

## 14. Testing Gaps

Ordered by what their absence would let through.

| Gap | Why it matters | §Ref |
|---|---|---|
| No RTL layout tests | Arabic is the primary language | §31–45 |
| No 10k-message list test | Explicitly required; the likeliest perf cliff | §31–45 |
| No failure-injection tests | No test for slow network, timeout, expired token mid-request, app kill, corrupted file, partial migration | §31–45 |
| No auth-bypass / injection tests | §31–45 requires security tests as a tier | §31–45 |
| No E2E journey tests | send → receive → offline → reconnect → delete is never exercised end to end | §31–45 |
| No deletion-propagation test | PRIV-02 — deletion may not reach object storage | §7–11 |
| No cross-user leakage test for AI | §12–26 requires this be *architecturally* impossible; nothing asserts it | §12–26 |

---

## 15. CI/CD Findings

**FACT** — `.github/workflows/ci.yml`, four jobs, all green: Backend (pytest),
Backend (image builds), Frontend (analyze + test), Android (release APK). The
Android job builds a real release APK with a placeholder `google-services.json`
and verifies the bundled tessdata.

**CI-01 (open).** **FACT** — No dependency vulnerability scanning, no secret
scanning, no SAST. For a product in this category that is a notable absence.

**CI-02 (open).** **FACT** — No coverage measurement or floor. 923 tests is a
number, not a coverage figure.

**CI-03 (open).** **FACT** — There is no staging environment and no canary.
`autoDeploy: true` in `render.yaml` means a merge goes straight to the only
environment. v4.0 §46–50 requires canary → 10% → 50% → 100%; the infrastructure
for it does not exist.

---

## 16. Technical Debt

| ID | Debt | Cost of leaving it |
|---|---|---|
| TD-01 | Feature flags exist for exactly one feature (`keyword_feature_flags.dart`) | §31–45's OFF → INTERNAL → BETA → LIMITED → GENERAL lifecycle cannot be run |
| TD-02 | No ADRs | §6 requires one for any replacement; architectural decisions live in commit messages |
| TD-03 | `Qwen افكار تطويير ironlink.txt` at repository root | A 1000-line ideas file describing a directory layout that does not match reality |
| TD-04 | Mixed logging idioms | Some modules use `structlog`, others stdlib `logging` with `%s` formatting |
| TD-05 | No dashboards | Metrics are scrapeable; nothing renders them |

---

## 17. Critical Risks

| ID | Risk | Likelihood | Impact | Status |
|---|---|---|---|---|
| **RISK-01** | Dart Signal implementation has a cryptographic flaw | Unknown | **Catastrophic** — the product's entire premise | UNVERIFIED, unreviewed |
| **RISK-02** | Plaintext reaches Google via push when E2EE is off (SEC-01) | **Certain, on every such message** | Critical | Confirmed |
| **RISK-03** | Silent message loss on app kill with a queued outbox (REL-01) | High on mobile | High | Confirmed |
| **RISK-04** | Deletion does not propagate to object storage (PRIV-02) | Unknown | High | Unverified |
| **RISK-05** | A non-additive migration with no down-path and no staging | Low now, rises with schema churn | High | Structural |

---

## 18. Quick Wins

Small, safe, independently shippable.

1. **BE-01** — delete the stale `encryption_service.py` comment in
   `requirements.txt`. One line. Removes a false security claim.
2. **SEC-02** — remove the ciphertext-slice preview from `chats.py:96` and
   return `None`, letting the client render from its local decrypted store.
   Deletes code.
3. **DEP-01** — `pypdf2` → `pypdf`.
4. **TD-03** — move the Qwen ideas file into `docs/` or delete it.
5. **CI-01** — add `pip-audit` and secret scanning to CI. Configuration only.

---

## 19. P0 Blockers

Nothing new should be built before these.

| # | Blocker | Why it is P0 |
|---|---|---|
| **P0-1** | **SEC-01 — content-free push notifications** | The product sends plaintext to a third party in one mode and broken ciphertext in the other. Every hour this stays is more messages through Google. Fixing it *removes* code. |
| **P0-2** | **REL-01 — durable outbox** | Silent message loss is the one failure both parties believe succeeded. Persist the queue to sqflite alongside the optimistic bubble already stored there. |
| **P0-3** | **RISK-01 — cryptographic review** | Everything else is built on the assumption this is correct. It is the only P0 that cannot be closed from inside this repository. |
| **P0-4** | **REL-02 — per-session FCM tokens** | Multi-device push is broken today, and this blocks measuring push at all. |

---

## 20. Recommended Execution Order

Derived from v4.0 §2's priority hierarchy, not from feature appeal.

**Gate A — stop the leak** (priority 2–3: cryptographic security, privacy) — ✅ **DONE 2026-08-17**
1. ~~P0-1 content-free push (SEC-01)~~ ✅
2. ~~Quick wins 1 and 2 (BE-01, SEC-02)~~ ✅

**Gate B — stop the loss** (priority 4–7: data integrity, reliability) — ✅ **DONE 2026-08-17**
3. ~~P0-2 durable outbox (REL-01)~~ ✅
4. ~~P0-4 per-session FCM tokens (REL-02)~~ ✅
5. ~~WS-01 versioned WebSocket events~~ ✅
6. ~~PRIV-02 deletion-propagation test, then the fix it reveals~~ ✅ — the test
   found a real defect, described below

> **One gap left open deliberately.** `WsStatus.outdated` exists and the client
> stops reconnecting on it, but no screen renders connection status at all —
> `WsStatus` has no consumer outside the transport. The reliability half is
> done (the retry loop is gone); the surfacing is a UI gap, tracked with FL-02.

**Gate C — establish the floor** (priority 8–9) — ✅ **DONE 2026-08-17**
7. ~~Failure-injection and E2E journey tests~~ ✅ — the suite had no database at
   all; one was added (Postgres in CI, skipped locally) rather than faking a
   journey, since a fake cannot answer the question a journey asks
8. ~~RTL layout tests, 10k-message list test~~ ✅ — RTL turned out to be clean;
   the tests lock it in
9. ~~CI-01 vulnerability and secret scanning, CI-02 coverage floor~~ ✅
10. ~~PRIV-01 data classification~~ ✅ — `docs/DATA_CLASSIFICATION.md`

**Gate D — make rollout possible** (§46–50)
10. Generalise the feature-flag mechanism beyond one feature (TD-01)
11. A staging environment; turn off `autoDeploy` to production

**Gate E — only now, new subsystems**
Per v4.0's P0 roadmap, the next subsystem is **IronDocs** — it reuses the OCR
pipeline that already exists on the device, which makes it the cheapest of the
thirteen and the one whose privacy boundary is already established.

**RISK-01 runs in parallel with all of it.** It is external work and blocks
nothing, but nothing else matters if it fails.

---

## 21. Evidence Ledger

| ID | Finding | Evidence | Confidence | Impact | Action |
|---|---|---|---|---|---|
| SEC-01 ✅ | Push body carries message content | `websocket.py:177-183`, `push_service.py:87`, `chat_bloc.dart:471,493-495` | **FACT** | Critical | P0-1 |
| SEC-02 ✅ | Preview is a 20-char ciphertext slice | `chats.py:96` | **FACT** | Medium | Quick win 2 |
| SEC-03 | Signal implementation unreviewed | `core/crypto/signal.dart` | **UNVERIFIED** | Catastrophic | P0-3 |
| SEC-04 | `/metrics` fail-closed, no identifying labels | `observability.py`, `test_observability.py` | **FACT** | — | Verified, no action |
| SEC-05 | No sensitive data in any log call | 38 call sites read; `sms_gateway.py:24` | **FACT** | — | Verified, no action |
| PRIV-01 ✅ | No data classification document | absence | **FACT** | Medium | Gate C |
| PRIV-02 ✅ | Deletion did not reach object storage — **confirmed defect**, `unsend_message` nulled the key without deleting the object | `tests/test_deletion_propagation.py` | **FACT** (was UNVERIFIED) | High | Fixed |
| REL-01 ✅ | Outbox is in-memory, silently lossy | `ws_service.dart:42,68,164` | **FACT** | High | P0-2 |
| REL-02 ✅ | One FCM token per user | `app/models/user.py:64` | **FACT** | High | P0-4 |
| REL-03 | Idempotency implemented | `0009_message_idempotency.py`, `message_service.py:80-90` | **FACT** | — | Verified, no action |
| REL-04 | Ordering undocumented and untested | absence | **UNVERIFIED** | Medium | Gate B |
| WS-01 ✅ | WebSocket events unversioned | `websocket.py` frame dispatch | **FACT** | Medium | Gate B |
| DB-01 | No down-migrations | `alembic/versions/` | **FACT** | Medium | Gate D |
| BE-01 ✅ | Stale comment claims a deleted mock exists | `requirements.txt:31` vs `test_key_directory.py:64` | **FACT** | Low | Quick win 1 |
| DEP-01 | `pypdf2` deprecated, parses untrusted files | test output | **FACT** | Medium | Quick win 3 |
| FL-01 ✅ | No RTL layout tests — **the code was already clean**; the tests lock it in | absence | **FACT** | Medium | Gate C |
| FL-02 | Screen-state completeness unknown | no inventory | **UNVERIFIED** | Medium | Gate C |
| CI-01 ✅ | No vulnerability / secret scanning / SAST | `ci.yml` | **FACT** | Medium | Gate C |
| CI-02 ✅ | No coverage floor — now 55% against an actual 59% | `ci.yml` | **FACT** | Low | Gate C |
| CI-03 | No staging, `autoDeploy: true` to production | `render.yaml:44` | **FACT** | High | Gate D |
| PERF-01 ◑ | No benchmarks of any kind — a 10k-message scale test now exists; **still no device profiling** | absence | **EVIDENCE NOT AVAILABLE** | Unknown | Gate C |
| ARCH-01 | 12 of 15 named subsystems have zero code | name search across `app/`, `frontend/lib/` | **FACT** | — | Gate E |

---

## Stop Conditions Encountered

Per v4.0 §51–57. One, and it is not blocking this document — it blocks the work
that would follow.

> ⚠️ **EXECUTION BLOCKED**
> **Reason:** SEC-01 requires deciding what a push notification may contain, and
> that is a product decision with a security consequence, not an implementation
> detail.
> **Evidence:** `websocket.py:177-183` sends `frame["content"]` — ciphertext
> when E2EE is on, plaintext when it is off — to FCM.
> **Decision required:** which of these:
> **(a)** Sender name only, no content. Maximum privacy; the notification says
> who, never what.
> **(b)** Sender name plus a client-decrypted preview, requiring a data-only
> push and a background handler. Better UX, meaningfully more work, and it puts
> decryption in a background isolate.
> **(c)** No sender name either — "New message". Strongest against a shoulder
> surfer, weakest as a notification.
>
> **PROPOSAL:** (a) now, because it is a strict improvement over both current
> branches and can ship today; (b) as a follow-up once REL-02 gives us
> per-session tokens, since a data-only push needs a correct token per device
> anyway.

---

## What This Audit Did Not Cover

Stated so that its silence is not read as a clean bill.

- **The Dart Signal implementation was not reviewed line by line.** That is
  SEC-03/RISK-01 and needs a cryptographer, not another reading.
- **No code was executed against a real device.** Device testing remains
  deferred, as recorded in `HANDOVER.md`.
- **Community and channel permission boundaries were inventoried, not probed.**
  They are marked `UNTESTED` in §3 rather than assessed.
- **No load was applied.** Every performance statement is an absence of
  evidence, labelled as such.
