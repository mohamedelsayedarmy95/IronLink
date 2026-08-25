# Smart Keyword Alert — Phase 0 Audit (No Code)

Against `IronLink-Smart-Keyword-Alert-Master-Prompt-v4.1.0.md`, §11 Phase 0.
Method: read the live repository first (R1/R2), classify honestly (R3), no speculation.

Date: 2026-08-16 · Commit at audit time: `9e9ebf1`

---

## 1. Current architecture map

Everything that exists today for this feature:

| Layer | File | Lines | Role |
|---|---|---|---|
| Extraction | `app/ocr.py` | 94 | Tesseract / PyPDF2 / docx / openpyxl text extraction, normalization, matching |
| Keyword store | `app/redis.py` | 90 | Redis SET `user:<id>:ocr_keywords`, pub/sub `ocr:alerts`, alert flag |
| Keyword API | `app/api/routes/ocr.py` | 42 | GET / POST / DELETE `/ocr/keywords` |
| Trigger | `app/api/routes/media.py` | `_process_ocr`, L342–400 | Background task after upload completes |
| Fanout | `app/services/ws_manager.py` | `listen_ocr_alerts`, L84–108 | Redis pub/sub → WebSocket frame `ocr_alert` |
| Push fallback | `app/services/push_service.py` | `send_ocr_push`, L123–147 | Data-only FCM |
| Client transport | `frontend/lib/core/ws_service.dart` | L101–103 | Routes `ocr_alert` frames into `TickerBloc` |
| Client state | `frontend/lib/features/notification/ticker_bloc.dart` | 28 | In-memory queue, max 50 |
| Client UI | `frontend/lib/core/widgets/ticker.dart` | 99 | Scrolling ticker |
| Client settings | `frontend/lib/features/settings/ocr_settings_*.dart` | 462 | Keyword CRUD screen + bloc |
| Runtime deps | `Dockerfile` L17–22, `requirements.txt` | — | tesseract-ocr + eng + ara language packs installed |
| Localization | `app_en.arb` / `app_ar.arb` | 15 keys | `ocrKeywordsTitle`, `ocrAlertFound`, … |
| Tests | — | **0** | No test file references OCR, keywords, or alerts |

There is **no** database table, **no** migration, **no** alert entity, **no** state machine, and
**no** acknowledgement anywhere in the repository.

---

## 2. Data flow, as actually implemented

```
file picked (Flutter)
  → POST /media/upload/init  → chunks → POST /media/upload/complete
      → if state["encrypted"] → OCR IS SKIPPED ENTIRELY (media.py:270)
      → else background_tasks.add_task(_process_ocr, …)
          → tempfile write
          → extract_text(path, mime)                    app/ocr.py:24
          → load_user_keywords(user_id)                 app/ocr.py:89 → app/redis.py:22
          → substring scan over normalize_text(text)    media.py:383-388
          → publish_ocr_alert() on redis db 0, host "redis"   app/redis.py:55
          → set_alert_flag()  (written, never read)     app/redis.py:75
          → push_service.send_ocr_push()
  ↘ ws_manager.listen_ocr_alerts() subscribes on redis_sessions (db 2, REDIS_URL)
      → frame {"type":"ocr_alert","file_id","keyword"}
          → TickerBloc().add(AddOcrAlert(frame))        ws_service.dart:101
              → in-memory list, lost on app restart
```

Nothing in this chain persists. Nothing is acknowledged. The sender is never told anything —
which is the one privacy property (P-1) the current code satisfies, by omission rather than design.

---

## 3. Feature status — honest classification (R3)

| Capability | Status | Evidence |
|---|---|---|
| Keyword CRUD API | **FAKE — 500s on every call** | `app/api/routes/ocr.py` awaits `get_user_keywords`/`set_user_keywords`, which are plain `def` in `app/redis.py` (AST-verified). `await` on a `set`/`bool` raises `TypeError`. All three endpoints have never returned 2xx. |
| Keyword storage | **BROKEN in production** | `app/redis.py:14` hardcodes `redis.Redis(host='redis', port=6379, db=0)` — a docker-compose service name. Production is Render and configures `REDIS_URL` (`app/config.py:187`). No password, no TLS. The connection cannot succeed. |
| Alert delivery | **BROKEN — wrong Redis** | Publisher uses the hardcoded sync client (db 0). Subscriber `ws_manager` uses `redis_sessions` = `REDIS_DB_SESSIONS = 2` via `REDIS_URL` (`app/core/redis.py`, `app/config.py:140`). Different host *and* different database: a published alert can never reach the subscriber. |
| Blocking I/O in event loop | **DEFECT** | `app/redis.py` is the synchronous `redis` client called from `async def _process_ocr` and from async route handlers. Every call blocks the event loop for the whole round trip. |
| Arabic matching | **FAKE** | `normalize_text` (`app/ocr.py:19`) runs `re.sub(r'[^a-z0-9\s]', ' ', text)` after `lower()`. Every Arabic codepoint is outside `a-z0-9` and is replaced by a space. An Arabic keyword can never match, in an Arabic-first product. No diacritic stripping, no alef/hamza/ya/ta-marbuta normalization, no tatweel removal, no Arabic-Indic digit folding. |
| Match semantics | **PARTIAL + INCONSISTENT** | Two implementations disagree. `contains_keywords` (`app/ocr.py:80`) does whole-word set intersection; `_process_ocr` (`media.py:386`) does `kw in normalized` substring. `contains_keywords` is dead code — nothing calls it. No phrase mode, no fuzzy, no regex, no case sensitivity, no word boundaries. |
| Deduplication | **FAKE** | `set_alert_flag` writes `ocr:alert:<file_id>` with a 300s TTL and is never read by any code path. Grep confirms one write site, zero read sites. Re-processing the same file produces a second alert. |
| Per-conversation scope | **NOT IMPLEMENTED** | Keywords are one flat global set per user (`user:<id>:ocr_keywords`). §1 requires per-conversation rules. |
| Keyword attributes (§1.3) | **NOT IMPLEMENTED** | Only a bare string. No priority, category, match_mode, case_sensitive, regex_pattern, notes, cap. |
| Alert domain model (§4.1) | **NOT IMPLEMENTED** | No entity exists. |
| State machine (§4.2) | **NOT IMPLEMENTED** | No states, no transitions, no retry, no `WAITING_FOR_NETWORK`. |
| Acknowledgement (§5.3) | **NOT IMPLEMENTED** | No model, no endpoint, no UI. |
| Alert history (§4.5) | **NOT IMPLEMENTED** | `TickerBloc` holds 50 alerts in RAM and drops them on restart. Fails Definition of Done "survives restart". |
| Confidence / context (§2.5, §4.4) | **NOT IMPLEMENTED** | The alert carries only `file_id` + `keyword`. No snippet, no page, no bbox, no score. |
| Document highlighting (§5.4) | **NOT IMPLEMENTED** | No viewer integration. |
| Sender report (§6) | **NOT IMPLEMENTED** | No permission model, no surface. |
| Pre-flight validation (§3.4) | **NOT IMPLEMENTED** | `extract_text` opens whatever it is handed. No size cap, no page cap, no magic-byte check. |
| Text-native PDF shortcut (§3.2) | **PARTIAL** | PDFs go through PyPDF2 text extraction only — which is correct for text PDFs and yields *nothing at all* for scanned PDFs. There is no page rasterization fallback, so scanned PDFs silently produce zero matches. |
| Ticker (§5.2) | **PARTIAL / UI-ONLY** | Renders, but is fed by a channel that cannot deliver. No priority ordering, no dedup, no persistence. |
| Feature flags (§9.4) | **NOT IMPLEMENTED** | No flag guards any of this. |
| Telemetry (§10) | **NOT IMPLEMENTED** | No metrics emitted. |
| Tests (§10.5) | **NOT IMPLEMENTED** | Zero. |

### Client-side defects found in the same pass

| Defect | Evidence |
|---|---|
| Adding a keyword deletes all the others | `ocr_settings_bloc.dart:64` POSTs `{'keywords': [event.keyword]}`; the endpoint **replaces** the whole set (`ocr.py:34`). The optimistic local list hides it. |
| Removing one keyword deletes all of them | `ocr_settings_bloc.dart:89` sends `DELETE /ocr/keywords` with a `{'keyword': …}` body; the endpoint ignores the body and clears everything (`ocr.py:41`). |

Both are masked today only because the endpoints 500 before doing damage.

---

## 4. The structural finding

**Server-side OCR is now unreachable by design, and must not be revived.**

Encryption is the default for every chat. `media.py:238–244` deliberately skips re-compression,
thumbnailing and OCR for encrypted bodies, because the server holds no key and running text
extraction over user attachments is precisely what E2EE promises does not happen. That decision
is correct and stays.

The consequence is that every server-side line in §3 of this audit is dead code on the live
product. Reviving it would mean either weakening E2EE or shipping a feature that only works for
attachments that bypass it. Neither is acceptable.

This is not a conflict with the spec — it is the spec. P-4 mandates **local-by-default** OCR, §3.3
puts cloud OCR behind explicit consent, and §10.3 treats a cloud opt-in rate above 20% as a
*privacy health failure*. The spec assumed a server pipeline in §9.1 because it also assumed
`alembic/versions` was empty; both assumptions are stale against this repo (R1/R2 — the
repository wins).

### Resulting architecture decision

1. **The authoritative pipeline is on-device (Flutter).** The client already decrypts every
   attachment to render it. OCR, normalization, matching, confidence and context extraction run
   there, on plaintext that never leaves the device.
2. **Keyword rules and alerts are device-local first**, persisted in the existing sqflite database
   (currently schema v4) alongside the message cache, which under E2EE already *is* the message
   history. This satisfies §9.1 "no duplicate source of truth" and P-1 by construction: the server
   cannot leak a keyword it never receives.
3. **The server keeps three narrow jobs**, reusing existing infrastructure (§9 reuse-first):
   an opaque encrypted-blob endpoint for multi-device rule sync (client-side encrypted, server
   sees ciphertext only), the existing WebSocket for cross-device alert fanout, and the existing
   FCM data-push for the backgrounded case.
4. **The legacy plaintext server path is retired behind a flag defaulting to off**, not deleted,
   per "improve, don't rewrite" — and its three fatal bugs are fixed regardless, so that a flag
   flipped on in a self-hosted plaintext deployment behaves correctly rather than 500ing.

---

## 4b. Engine finding: ML Kit has no Arabic recognizer

Added during Phase 2, after inspecting the package rather than trusting the spec.

§3.6 of the master prompt recommends "Google ML Kit Text Recognition v2 (+ Arabic model)"
for Android local OCR, and says Arabic "requires the ML Kit Arabic model (v2)".

**No such model is available.** `google_mlkit_text_recognition` 0.16.0 declares:

```dart
enum TextRecognitionScript { latin, chinese, devanagiri, japanese, korean }
```

Five scripts, no Arabic. This is a factual error in the spec, and it matters more here
than it would almost anywhere, because IronLink is an Arabic-first product. Shipping the
ML Kit engine alone and declaring the feature done would reproduce precisely the defect
this audit opened with: a keyword feature that silently never matches Arabic.

What this means in practice:

| Path | Arabic | Status |
|---|---|---|
| PDF with a text layer | **Works** | IMPLEMENTED — `PdfNativeTextExtractor` reads stated characters; no recognition involved, so no script model is needed. Arabic normalization then does the rest. |
| Plain text attachment | **Works** | IMPLEMENTED — same reason. |
| Photograph or scanned image | **Does not work** | BLOCKED — ML Kit returns nothing for Arabic script. Latin script in images works fully. |
| Scanned (image-only) PDF | **Does not work** | BLOCKED — needs page rasterization plus an Arabic recognizer. |

**STILL BLOCKED, for a different reason than first recorded.** Two wrong
answers preceded this one, and both are worth keeping visible.

### Wrong answer 1: the size

The first version of this section said closing the gap would bundle "15-40 MB"
of model data, making it a product decision about app size. Measured:

| Variant | `ara.traineddata` |
|---|---|
| `tessdata_fast` | 1,432,056 bytes - **1.37 MB** |
| `tessdata` | 2.38 MB |
| `tessdata_best` | 12.02 MB |

Wrong by an order of magnitude, and it was the entire basis for deferring.

### Wrong answer 2: declaring it done

On the strength of that correction, `flutter_tesseract_ocr` 0.4.31 was added,
`ara.traineddata` bundled, an hOCR-parsing extractor written with 18 tests, and
the feature declared working. **The app did not build.**

That was found one commit later, by the Android job added to CI - which is the
point of having added it. The Gradle failure:

```
A problem occurred configuring project ':flutter_tesseract_ocr'.
> Failed to notify project evaluation listener.
   > java.lang.NullPointerException (no error message)
   > 'kotlin-android' plugin requires one of the Android Gradle plugins.
```

### The actual blocker — established twice, second time properly

`flutter_tesseract_ocr`'s own `android/build.gradle` calls **`jcenter()`**, and
Gradle removed that method. JCenter itself shut down in 2021. So the plugin's
project cannot be *evaluated*, let alone configured:

```
1: A problem occurred evaluating project ':flutter_tesseract_ocr'.
   > Could not find method jcenter() for arguments [] on repository container...

2: A problem occurred configuring project ':flutter_tesseract_ocr'.
   > java.lang.NullPointerException
   > 'kotlin-android' plugin requires one of the Android Gradle plugins.
```

Failure 2 is the consequence of failure 1: evaluation died, so
`com.android.library` was never applied, so Kotlin had nothing to attach to.

The first attempt at this diagnosis read only failure 2 and blamed AGP 9. It was
directionally right — the plugin is stuck in a pre-AGP-8 world — and wrong about
the mechanism. Worse, it was judged on a run where `google-services.json` was
also missing, so nothing had configured properly and the run proved nothing.
The retry was done on a green baseline, where the Android job passes and this
project's first release APK had just been produced. The result above is therefore
evidence rather than noise.

Checked and ruled out:

| Option | Why not |
|---|---|
| `android.newDsl=false` | Already set in `gradle.properties`. Never the fix. |
| `tesseract_ocr` (arrrrny) | Same `jcenter()` call, same legacy layout. |
| `flusseract` | Version 0.1.3, published two years ago. |
| Downgrade the project to AGP 8 | Would not help: `jcenter()` is removed by *Gradle*, not by AGP. |
| Add a repository override from the app | Impossible. You cannot restore a DSL method that no longer exists in someone else's build script. |

### The one remaining path, scoped

Vendor the plugin. It is small — a MethodChannel, a thin Java shim, and a
bundled `tesseract4android` AAR — and the Gradle fix is roughly fifteen lines:
drop the `buildscript` block, replace `jcenter()` with `mavenCentral()`, apply
the Android library plugin the modern way, and reference the AAR as a proper
dependency instead of through `flatDir`.

That is a bounded piece of work with an unbounded tail: it means taking
ownership of third-party native code, its licence, and its future. It is a
product decision, not a refactor, and it has not been taken.

### What survives

`ImageTextExtractor` stays, as a one-engine composite. The fall-through logic,
the definition of "nothing usable", and the tests for both are the work; the
second engine is one constructor argument when a compatible one exists. Its
tests run against fakes and still pass.

### So where Arabic stands today

| Path | Arabic |
|---|---|
| PDF with a text layer | **Works** - characters are stated, not recognised |
| Plain text attachment | **Works** |
| Photograph or scanned image | **Does not work** |
| Scanned (image-only) PDF | **Does not work** |

iOS remains the better prospect: Apple Vision handles Arabic well and needs a
platform channel rather than a Gradle-era plugin, so it is not subject to this
problem at all.

---

## 5. Security analysis

| Issue | Severity | Note |
|---|---|---|
| Plaintext keywords stored server-side | High | Redis holds the user's private watchwords in the clear — the §7.3 threat model's central asset. Fixed by decision 2/3 above. |
| Keyword set is global, not per-conversation | Medium | A keyword meant for one counterparty applies everywhere, widening exposure. |
| No pre-flight validation | Medium | Attacker-supplied PDFs/images reach PyPDF2 / Pillow / Tesseract with no size, page or signature check — a decompression-bomb and parser-CVE surface. §3.4. |
| Blocking sync Redis in the event loop | Medium | Availability: a slow Redis stalls the whole API worker. |
| No authorization on the alert channel | Low today | `listen_ocr_alerts` fans out by `user_id` from the message body; the publisher is internal, so not currently exploitable, but there is no defence in depth. |
| No audit trail | Medium | §7.5 insider-access logging absent. |

## 6. UX analysis

- Alerts vanish on restart; there is no history screen and no way to revisit an alert.
- No acknowledgement, so a missed alert is indistinguishable from a handled one.
- No failure surface: extraction failures are logged server-side and the user sees nothing (§5.8).
- No "Checking document…" honest-progress state (§8.3).
- Ticker has no priority ordering, no grouping of multiple matches, no RTL-verified layout.
- Keyword screen offers a bare string list — no priority, category, match mode, or test-a-keyword.

## 7. Performance analysis

Not measurable today, because the pipeline does not run. Structural risks for the on-device design:
Tesseract on a low-tier Android device is the dominant cost, so §8.1.1 device-tier adaptation and
§8.2 "only once per processing version" caching are load-bearing, not optional. Processing must be
triggered by the events in §8.3 (document opened / chat opened / foreground), never by a daemon.

---

## 8. Definition of Ready (§0.2) — confirmed

- Repository inspected before any change (R1/R2). ✅
- Existing architecture identified and reused: sqflite cache, `ws_service`, `push_service`,
  `redis_sessions`, existing auth/session model, existing ARB localization. ✅
- Privacy principles P-1 and P-4 reconciled against the live E2EE default. ✅
- Stale spec assumptions identified and overridden by repo reality (`alembic/versions` non-empty;
  server-side OCR unreachable). ✅

## 9. Implementation plan (grounded in the files above)

| Phase | Work | Gate |
|---|---|---|
| 1 | Keyword rule + alert domain on-device (sqflite v5), state machine, idempotency by `(rule_id, document_hash, processing_version)`, history, acknowledgement. Fix the three fatal server bugs and repurpose the endpoint as an encrypted sync blob. | State-machine + idempotency unit tests green |
| 2 | On-device OCR: image OCR, text-native PDF extraction with scanned fallback, real Arabic+English normalization, confidence, context, pre-flight validation | OCR corpus passes; text PDFs not OCR'd; pre-flight rejects malformed input |
| 3 | Ticker rework, alert center, history, highlighting, keyword management with §1.3 attributes, sender status | RTL/LTR + screen-reader walkthrough |
| 4 | Privacy boundaries, notification privacy, malicious-doc isolation, audit trail, Security Center transparency | Security suite green |
| 5 | Fuzzy, grouping, prioritization, extra formats — all EXPERIMENTAL behind flags | Flagged |
| 6 | Full §10.5 matrix, performance, a11y, localization, regression, rollback rehearsal | All green |
| 7 | Dashboards, guardrail alerting, feedback loop | Dashboards live |

Per the operator's instruction, end-to-end device testing happens at the very end of the work,
not per phase; each phase is nonetheless gated on its automated tests.
