# Smart Keyword Alert — Final Report

Against `IronLink-Smart-Keyword-Alert-Master-Prompt-v4.1.0.md` §12.3.
Evidence-based: every claim below points at a file or a test.

---

## 1. Executive summary

The feature did not work. Not partially — at all. Four independent defects sat
on top of each other in one module, and every one was invisible because each
call site caught its own exception and returned an empty result.

`app/redis.py` built its own **synchronous** Redis client pointed at host
`"redis"`, a docker-compose service name that cannot resolve on Render, where
the connection comes from `REDIS_URL`. Being synchronous, its return values
were not awaitable — yet the routes awaited them, so all three keyword
endpoints raised `TypeError` and returned 500 on **every** request. And it
published alerts on database 0 while `ws_manager` subscribes on
`REDIS_DB_SESSIONS`, so even a reachable server could never have delivered
one. Separately, `normalize_text` ran `re.sub(r'[^a-z0-9\s]', ' ', text)`,
which deletes every Arabic character — in an Arabic-first product.

Two client bugs were masked behind those 500s: adding a keyword deleted every
other keyword the user had, and removing one wiped the whole set.

The work since has been to build the feature the spec describes, on the
architecture this codebase actually has. Because encryption is the default for
every chat, the server holds no key and cannot read an attachment — so the
pipeline is on-device, which is what P-4 mandates anyway. Rules and alerts
live on the device; the server never receives a keyword; and the push payload
that used to carry one to Google no longer does.

**Totals: 434 frontend tests, 339 backend tests, analyzer clean.**

---

## 2. Current-state audit

Full detail in [`SMART_KEYWORD_ALERT_AUDIT.md`](SMART_KEYWORD_ALERT_AUDIT.md).
Summary of what existed at Phase 0: extraction code that could not be reached,
a keyword store that could not connect, an alert channel whose publisher and
subscriber used different databases, a normalizer that destroyed Arabic, no
alert entity, no state machine, no acknowledgement, no history, no dedup, and
zero tests.

---

## 3. Architecture changes

| Before | After | Why |
|---|---|---|
| Server-side OCR over plaintext uploads | On-device pipeline over decrypted bytes | The server holds no key; P-4 mandates local-by-default anyway |
| Keywords in Redis, in the clear | Rules in device-local sqflite | The server cannot leak what it never receives |
| No alert entity | `KeywordAlert` with a derived id and an explicit transition table | Idempotency and "did I deal with that?" both need identity |
| Two disagreeing match implementations, one dead | One layered matcher | Two paths that must agree eventually will not |
| Ad-hoc booleans | `KeywordFeatureFlags` registry | §9.4 needs "what is experimental?" to be readable |

---

## 4. UX changes

The ticker was an infinite horizontal marquee of raw maps. It failed WCAG
2.2.2 (moving content with no pause control), was harder to read than static
text, and — decisively — had no button, so acknowledgement could not exist.

It is now a static anchored row at the §5.2.1 dimensions that persists until
answered, with the distinction the feature rests on enforced in the events it
sends: swiping hides it only, opening the document is not acknowledgement, and
only the explicit press clears it.

Added: alert history with Today/Yesterday/Earlier sections and filters;
per-conversation keyword management with the §1.3 attributes and a test box
that runs the real matcher; a transparency card stating where extraction ran.

---

## 5. OCR architecture

```
bytes → pre-flight → already-processed? → extract → normalize → match → score → record
```

Cheapest refusal first. A document nobody has a rule for is never read; one
pre-flight turns away never reaches a decoder; one already processed under this
pipeline version never reaches an engine — which is where §8.2's "only once per
processing version" actually saves battery.

Engines, in preference order: PDF text layer, then plain text, then ML Kit for
images. Registration order *is* the §3.2 rule — a text-native PDF cannot reach
OCR by accident because the text-layer extractor answers first.

---

## 6. Privacy model

| Property | How it holds |
|---|---|
| Keywords never reach the server | They are never sent; the pipeline has no network client |
| Keywords never reach a third party | Removed from the FCM payload; test asserts the absence |
| The sender never learns the keyword | `SenderReportEntry` has no field for one |
| Group admins learn no more than senders | They receive the same type |
| Extracted text is never stored | It is a local variable for one matching pass; test plants a distant marker and asserts no column contains it |
| Alerts expire | 48 hours, swept on read as well as on schedule |
| Telemetry cannot carry content | Every event field is an enum, a count, or a duration — there is no map to slip a string into |

---

## 7. Security model

Pre-flight refuses before anything decodes: signature verification (never the
declared type), size ceilings, minimum resolution, and a decompression-bomb
guard that rejects a 30000×30000 PNG in half a kilobyte by arithmetic on two
header numbers, in under a millisecond.

User-supplied regex is sandboxed before it is ever compiled — nested
quantifiers and backreferences rejected, pattern length capped — and the
matcher separately bounds the input any pattern runs over, because no
heuristic catches every catastrophic pattern.

---

## 8. Data flow

```
EncryptedImage decrypts an attachment to render it   (the one moment plaintext exists)
  → KeywordScanContext.offer(bytes)
  → KeywordAlertService  — skips own messages and secret chats,
                           dedupes repeat offers from list rebuilds,
                           serializes extraction, bounds the queue
  → KeywordAlertPipeline.process(bytes, conversation, message, attachment)
      → rules for this conversation?            no  → skippedNoRules
      → Preflight.inspect(bytes)                bad → unsupportedDocument / failed
      → alreadyProcessed per rule?              all → skippedAlreadyProcessed
      → TextExtractorRegistry.forKind(...)      none→ ocrUnavailable
      → extractor.extract(...)                  err → failed / waitingForNetwork
      → KeywordMatcher.match(rules, document)
      → drop anything below MEDIUM confidence
      → AlertStore.record(...)  (primary-key conflict on duplicate)
      → leadAlert → ticker → presented → opened → acknowledged
```

---

## 9. State machine

`pendingProcessing → processing → {noMatch | matchDetected → alertCreated →
alertPresented → documentOpened → acknowledged}`, with `waitingForNetwork`,
`processingFailed`, `ocrUnavailable`, `unsupportedDocument`, `lowConfidence`,
`dismissed` and `expired`. Written as an explicit table so the illegal moves
are testable: an acknowledged alert can never return to outstanding, and an
expired one can never return at all — which is what a duplicate push or a
replayed socket frame would otherwise do.

---

## 10. API changes

| Endpoint | Change |
|---|---|
| `GET /ocr/keywords` | Now returns 200 instead of 500; sorted for stable ordering |
| `POST /ocr/keywords` | Adds rather than replaces; `?replace=true` for the old behaviour |
| `DELETE /ocr/keywords` | Removes the named keywords; clears only when none are named |

All three are deprecated in favour of device-local rules, and are retained for
the plaintext-attachment deployment mode.

## 11. Database changes

**No server migrations.** The domain is device-local. On-device: a new
`ironlink_alerts.db` (v1) with `keyword_rules` and `keyword_alerts`, separate
from the message cache — that cache is disposable, while a rule the user wrote
and an alert they have not answered cannot be rebuilt from anywhere.

## 12. Testing results

| Suite | Count | Result |
|---|---|---|
| Backend (`tests/`) | 339 | pass |
| Frontend (`frontend/test/`) | 434 | pass |
| Analyzer (`lib/features/keyword_alert`, `test/keyword_alert`) | — | clean |

## 13. Performance results

**Not measured.** Device benchmarking is scheduled for the end-of-work device
test. Structural work done: pre-flight is header-only, extraction is skipped
per processing version, and the retry ladder is bounded at three attempts.
No absolute number is claimed here, per §10.3's rule about the battery
baseline.

---

## 14. Known limitations

1. **Arabic image OCR is blocked, and the reason is now precise.** Two earlier
   answers in this report were wrong: first that it would cost tens of megabytes
   (it is 1.37 MB), then that it was done (the app did not build). The real
   blocker is that this project runs AGP 9.0.1 while every Arabic OCR binding on
   pub still uses the pre-AGP-8 Gradle layout. CI proved that by failing. Section
   3.6 of the spec is also still wrong that ML Kit has an Arabic model. Apple
   Vision on iOS is unaffected and remains the better prospect there.

2. **Scanned (image-only) PDFs are not rasterized**, so a scan inside a PDF is
   not OCR'd at all yet — in either language.
3. **No performance or battery measurements.**
4. **No production dashboards.** The event types and guardrail thresholds
   exist; the sink that ships them does not.
5. **Untested on a device.** Every layer has unit and widget coverage, but the
   native engines (ML Kit, the PDF parser) have only been exercised through
   fakes. The end-to-end device run is the remaining verification.

## 15. Remaining work

- Arabic image OCR (Apple Vision / Tesseract).
- Scanned-PDF rasterization.
- Device measurement of processing time and battery.
- A telemetry sink and dashboards.
- End-to-end device test (deferred to the end of the work, as directed).

---

## 16. Feature status matrix

| Feature | Status | Files | Tests | Notes |
|---|---|---|---|---|
| Keyword rules, §1.3 attributes | IMPLEMENTED | `domain/keyword_rule.dart` | `keyword_rule_test.dart` | 25 tests |
| Regex sandboxing | IMPLEMENTED | `domain/keyword_rule.dart` | `keyword_rule_test.dart` | Nested quantifiers, backreferences, length |
| Alert domain + state machine | IMPLEMENTED | `domain/keyword_alert.dart` | `alert_state_machine_test.dart` | Explicit transition table |
| Idempotency (§4.3) | IMPLEMENTED | `domain/keyword_alert.dart`, `local/alert_store.dart` | `alert_store_test.dart` | Derived primary key |
| History + 48h retention | IMPLEMENTED | `local/alert_store.dart` | `alert_store_test.dart` | Two-stage sweep |
| Acknowledgement (§5.3) | IMPLEMENTED | `bloc/alert_bloc.dart`, `widgets/smart_alert_ticker.dart` | `ticker_widget_test.dart` | Swipe ≠ acknowledge |
| Daily cap | IMPLEMENTED | `domain/processing_job.dart` | `processing_job_test.dart` | Rolling 24h; suppressed, not discarded |
| Arabic normalization | IMPLEMENTED | `text/text_normalizer.dart` | `text_normalizer_test.dart` | 36 tests, offsets preserved |
| Matching pipeline (§2.1) | IMPLEMENTED | `matching/keyword_matcher.dart` | `keyword_matcher_test.dart` | 52 tests |
| Confidence scoring (§2.5) | IMPLEMENTED | `matching/keyword_matcher.dart` | `keyword_matcher_test.dart` | Five factors |
| Context extraction (§4.4) | IMPLEMENTED | `matching/keyword_matcher.dart` | `keyword_matcher_test.dart` | Bounded snippet |
| Pre-flight validation (§3.4) | IMPLEMENTED | `ocr/preflight.dart` | `preflight_test.dart` | 30 tests |
| PDF text-layer extraction | IMPLEMENTED | `ocr/pdf_text_extractor.dart` | — | Untested until device run |
| Plain-text extraction | IMPLEMENTED | `ocr/text_extractor.dart` | `pipeline_test.dart` | |
| Image OCR (Latin) | IMPLEMENTED | `ocr/mlkit_text_extractor.dart` | — | Needs device to verify |
| Image OCR (Arabic) | **BLOCKED** | seam in `ocr/image_text_extractor.dart` | `arabic_ocr_test.dart` (routing only) | No pub binding builds against AGP 9.0.1 - proven by CI, see audit 4b |
| Scanned-PDF OCR | NOT IMPLEMENTED | — | — | Needs rasterization |
| Local/cloud decision matrix | IMPLEMENTED | `ocr/ocr_mode.dart` | `pipeline_test.dart` | Pure function, no silent fallback |
| Cloud OCR engine | NOT IMPLEMENTED | — | — | Flagged off |
| Ticker (§5.2.1) | IMPLEMENTED | `widgets/smart_alert_ticker.dart` | `ticker_widget_test.dart` | 16 tests incl. RTL, a11y |
| Alert centre (§5.6) | IMPLEMENTED | `screens/alert_center_screen.dart` | — | Sections + filters |
| Keyword management (§5.7) | IMPLEMENTED | `screens/keyword_management_screen.dart` | — | Live validation, test box |
| Document highlighting (§5.4) | PARTIAL | region on the alert | `keyword_matcher_test.dart` | Geometry captured; viewer not wired |
| Sender report (§6) | IMPLEMENTED | `domain/sender_report.dart` | `privacy_boundary_test.dart` | No field for a keyword |
| Notification privacy (§7.1) | IMPLEMENTED | `app/services/push_service.py` | `test_keyword_privacy.py` | Keyword removed from payload |
| Security Center (§7.2) | IMPLEMENTED | `widgets/processing_transparency.dart` | — | Per-alert source |
| Feature flags (§9.4) | IMPLEMENTED | `keyword_feature_flags.dart` | `telemetry_and_flags_test.dart` | All off |
| Fuzzy matching | EXPERIMENTAL | `matching/keyword_matcher.dart` | `keyword_matcher_test.dart` | Off by default |
| Semantic / synonym matching | NOT IMPLEMENTED | flag only | `telemetry_and_flags_test.dart` | Declared, not built |
| DOCX / XLSX / PPTX | NOT IMPLEMENTED | flag only | — | |
| Telemetry (§10.1) | IMPLEMENTED | `keyword_telemetry.dart` | `telemetry_and_flags_test.dart` | No free-form payload |
| Guardrails (§10.4) | IMPLEMENTED | `keyword_telemetry.dart` | `telemetry_and_flags_test.dart` | Thresholds from §10.3 |
| Dashboards (§11 Phase 7) | NOT IMPLEMENTED | — | — | Needs a sink and infra |
| Legacy server keyword API | IMPLEMENTED (deprecated) | `app/api/routes/ocr.py`, `app/redis.py` | `test_keyword_alerts.py` | Repaired; flagged off |
| Pipeline → chat integration | IMPLEMENTED | `keyword_alert_service.dart`, `chat/widgets/encrypted_image.dart`, `chat/screens/chat_room_screen.dart`, `groups/screens/group_chat_screen.dart`, `main.dart` | `alert_service_test.dart` | Serialized queue, bounded, own/secret messages skipped |
| Sign-out erases rules and alerts | IMPLEMENTED | `auth/sign_out_service.dart` | `alert_service_test.dart` | Store wiped, scan state reset |

## 17. Sign-off record

Not signed off. §12.2 requires ten named roles to review their areas, and this
work was produced by one engineer against a specification. The matrix above is
the input to that review, not a substitute for it. Phase 7 is not complete and
the feature should not be declared production-ready beyond its experimental
scope until it is.
