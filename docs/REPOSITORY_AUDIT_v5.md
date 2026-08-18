# IronLink Repository Audit — v5.0

**Against:** `IRONLINK — PRINCIPAL ARCHITECT MASTER EXECUTION SYSTEM v5.0`
**Date:** 2026-08-18
**Branch:** `fix/boot-crashes-and-backend-merge`
**Supersedes:** `REPOSITORY_AUDIT_v4.md` — which is kept, not deleted, per §58's
no-silent-deletions rule. Findings resolved since then are marked there.
**Scope:** Phase 0. §51–57 says *"Then STOP."* No production code was modified
while producing this document.

---

## 0. Three corrections before anything else

§3.2 forbids an assumption hardening into a fact through repetition. Three
findings across the v4 and v5 audits were stated as **FACT** and were wrong. All
three were mine, and all three came from writing a conclusion without opening
the file — the exact failure §4 exists to prevent. The third is in the highest
risk in the product and survived into this document's own first draft.

### Correction 1 — IronWatch was graded `PARTIAL` on false grounds

> **v4 claimed:** "48h history and per-chat scoping absent."

```
FACT: Both are implemented.
SOURCE: frontend/lib/features/keyword_alert/domain/keyword_alert.dart:319
        — retentionWindow = Duration(hours: 48)
        frontend/lib/features/keyword_alert/local/alert_store.dart:56
        — conversation_scope column, two indexes on it
VERIFIED: 2026-08-18
```

The `Duration(hours: 24)` occurrences that resemble a shortened retention
window are the **daily rate cap**, a separate mechanism, documented as one.
IronWatch is `INTEGRATED` against its specification.

### Correction 2 — DB-01 claimed there are no down-migrations

> **v4 claimed:** "There are no down-migrations. Rollback of a schema change is
> restore-from-backup only."

```
FACT: All ten migrations have real, non-stub downgrade() implementations.
SOURCE: alembic/versions/*.py — 0001 (84 operations) through
        0010 (2 operations); none is `pass`
VERIFIED: 2026-08-18
```

This materially changes §24 below. Rollback readiness is far better than v4
recorded.

### Correction 3 — the top risk in both audits was mischaracterised

> **v4 and v5 both claimed:** "There is no `libsignal` binding; the protocol is
> implemented in Dart in this repository," and treated RISK-01 as unreviewed
> hand-rolled cryptography with catastrophic impact.

```
FACT: This repository implements no cryptographic primitive. The protocol is
      provided by the package libsignal_protocol_dart 0.8.2.
SOURCE: frontend/lib/core/crypto/signal.dart:5; pubspec.yaml:25;
        pubspec.lock:719. The file's own docstring says so explicitly:
        "No cryptographic primitive is implemented here on purpose —
        hand-rolled crypto is how these systems fail."
VERIFIED: 2026-08-18
```

I asserted the opposite of what the file says in its second line, in the
section of the audit devoted to the highest risk in the product, twice.

The corrected risk is narrower and answerable: the package is an independent
pure-Dart implementation of the Signal specifications rather than a binding to
audited libsignal, is actively maintained (current release, verified publisher,
150/150 pub points), and has **no published security audit**. The review scope
this implies is in `docs/CRYPTO_REVIEW_SCOPE.md` — roughly 500 lines of
app-level composition, not 1,377 lines of protocol.

**What both errors have in common:** they were plausible, they were about
absence, and absence is the easiest thing to assert without checking. Any future
finding of the form "X does not exist" in this document carries a path proving
the search that was run.

---

## 1. Executive Summary

```
FACT: 13,000+ lines of backend Python, 34,500+ lines of Flutter,
      417 backend tests and 587 frontend tests, all green in CI across
      five jobs.
SOURCE: CI run on commit 3e7ac8e — Backend (pytest), Backend (image builds),
        Frontend (analyze + test), Android (release APK),
        Security (dependencies + secrets), all success
VERIFIED: 2026-08-18
```

**The engineering foundation is finished; the product is a third built.** Gates
A, B and C from the v4 execution order are closed. What remains is Gate D
(release infrastructure) and twelve unbuilt subsystems.

**The single most important line in this audit** is unchanged from v4 and cannot
be closed from inside this repository:

```
FACT: This repository implements no cryptographic primitive. X3DH and the
      Double Ratchet come from the package libsignal_protocol_dart 0.8.2.
SOURCE: frontend/lib/core/crypto/signal.dart:5 (import) and its class
        docstring — "No cryptographic primitive is implemented here on
        purpose"; frontend/pubspec.yaml:25; pubspec.lock:719
VERIFIED: 2026-08-18

FACT: 0.8.2 is the current release, published ~58 days ago by mixin.dev, a
      verified pub.dev publisher. 150/150 pub points, 66 likes, ~7,020 weekly
      downloads. Not discontinued.
SOURCE: https://pub.dev/packages/libsignal_protocol_dart
VERIFIED: 2026-08-18

FACT: The package describes itself as a "pure Dart/Flutter implementation of
      the Signal Protocol" — an independent implementation of the X3DH,
      Double Ratchet and XEdDSA specifications, NOT a binding to the audited
      libsignal library. No security audit is published for it.
SOURCE: same
VERIFIED: 2026-08-18
```

**See §0, Correction 3.** Both prior audits described this as hand-rolled
in-repository crypto, and it is not.

The risk is real but differently shaped, and smaller: not *our* unreviewed
crypto, but a **well-maintained third-party reimplementation of Signal with no
published audit**. That is better than hand-rolling and worse than binding to
libsignal proper, and it is a dependency-governance question (§31.4) at least as
much as a cryptographic one. See `docs/CRYPTO_REVIEW_SCOPE.md`.

---

## 2. Actual Architecture

Unchanged from `REPOSITORY_AUDIT_v4.md` §2, re-verified 2026-08-18. Additions
since:

| Component | Added | Path |
|---|---|---|
| Durable outbox | Gate B | `frontend/lib/core/outbox_store.dart` |
| Per-device push tokens | Gate B | `alembic/versions/0010_per_session_fcm_token.py` |
| Protocol version negotiation | Gate B | `app/api/routes/websocket.py` — `PROTOCOL_VERSION`, close code 4426 |
| Orphan attachment reaper | Gate B | `SelfDestructWorker.reap_orphans` |
| Real test database | Gate C | `tests/conftest.py` — Postgres, skipped without `TEST_DATABASE_URL` |

---

## 3. Feature Reality Matrix

Per §5, now with Owner, Last Verified, and Blocking Dependency.

**Owner is recorded as `unassigned` throughout, and that is itself a finding.**
There is no accountability register for this repository; §5 asks who is
accountable for closing each gap and the honest answer is that nobody is
formally named.

| Feature | UI | Domain | Backend | DB | Security | Tests | Status | Owner | Last Verified | Blocking Dependency |
|---|---|---|---|---|---|---|---|---|---|---|
| 1:1 messaging (E2EE) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | `INTEGRATED` | unassigned | 2026-08-18 | RISK-01 caps this at `INTEGRATED`, not `PRODUCTION_READY` |
| Group messaging (Sender Keys) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | `INTEGRATED` | unassigned | 2026-08-18 | RISK-01 |
| Attachments (encrypted, resumable) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | `INTEGRATED` | unassigned | 2026-08-18 | No device test on a poor network |
| Media metadata stripping | n/a | ✅ | n/a | n/a | ✅ | ✅ | `INTEGRATED` | unassigned | 2026-08-18 | PDF unsupported — blocks PDF attachments |
| Auth (Firebase phone + OTP) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | `INTEGRATED` | unassigned | 2026-08-18 | — |
| Session lifecycle / revoke | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | `INTEGRATED` | unassigned | 2026-08-18 | — |
| Contact discovery (salted hash) | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | `INTEGRATED` | unassigned | 2026-08-18 | — |
| Block / report | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | `INTEGRATED` | unassigned | 2026-08-18 | — |
| Self-destructing messages | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | `INTEGRATED` | unassigned | 2026-08-18 | — |
| Controlled Group Entry | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | `INTEGRATED` | unassigned | 2026-08-18 | — |
| **IronShield** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | `INTEGRATED` | unassigned | 2026-08-18 | — |
| **IronWatch** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | `INTEGRATED` | unassigned | 2026-08-18 | **corrected — see §0** |
| Scam intelligence | ✅ | ✅ | n/a | n/a | ✅ | ✅ | `INTEGRATED` | unassigned | 2026-08-18 | — |
| Link safety | ✅ | ✅ | n/a | n/a | ✅ | ✅ | `INTEGRATED` | unassigned | 2026-08-18 | — |
| Observability | n/a | ✅ | ✅ | n/a | ✅ | ✅ | `INTEGRATED` | unassigned | 2026-08-18 | No dashboards |
| Push notifications | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | `INTEGRATED` | unassigned | 2026-08-18 | Was `BROKEN` in v4; fixed in Gates A and B |
| Offline outbox | ✅ | ✅ | n/a | ✅ | n/a | ✅ | `INTEGRATED` | unassigned | 2026-08-18 | Was `PARTIAL` in v4; fixed in Gate B |
| Conversation previews | ✅ | ✅ | ✅ | ✅ | ✅ | ⚠️ | `INTEGRATED` | unassigned | 2026-08-18 | No widget test on the list itself |
| AI features | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | `PARTIAL` | unassigned | 2026-08-18 | **Cloud-only.** The spec's "local-first" is not implemented |
| **IronSearch** | ✅ | ✅ | n/a | ✅ | ✅ | ✅ | `PARTIAL` | unassigned | 2026-08-18 | Local history search only; no cross-surface permission-aware search |
| Communities / channels | ⚠️ | ✅ | ✅ | ✅ | ⚠️ | ⚠️ | `UNTESTED` | unassigned | 2026-08-18 | Permission boundary untested; **two unlocalized strings** (§23) |
| PDF attachments | ⚠️ | ❌ | ❌ | ❌ | ❌ | ❌ | `UI_ONLY` | unassigned | 2026-08-18 | Metadata scrubber must learn PDF first |
| Voice / video calls | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | Not present | unassigned | 2026-08-18 | Never specified in any prompt |
| IronVault, IronDocs, IronMemory, IronFlow, IronMesh, IronMasks, IronVault Escrow, IronCanvas, IronProof, IronGhost, IronLegacy, Voice transcription, Business OS | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | Not started | unassigned | 2026-08-18 | Gate D (no staging, no flag lifecycle) |

### 3.1 Feature Completeness Scorecard — applied to the flagship

§0.1 requires the 18 layers scored. Applied to **1:1 E2EE messaging**, the
feature everything else depends on:

| Layer | Score | Evidence |
|---|---|---|
| UI | `PARTIAL` | Loading, empty, error and offline exist; **Permission Denied, Locked and Retry are not distinguished** — see §23 |
| State | `PRESENT` | `chat_bloc.dart` — explicit states, including `failed` since Gate B |
| Domain Logic | `PRESENT` | `signal.dart`, `message_service.py` — testable units |
| Local Persistence | `PRESENT` | `message_store.dart`; survives restart, verified by `ws_service_test.dart` restart test |
| Network/API | `PRESENT` | Versioned since Gate B; correlated error envelope via `_reject` |
| Backend Logic | `PRESENT` | Idempotent on `client_ref`; integration-tested in `test_journeys.py` |
| Database | `PRESENT` | Real migrations, all reversible |
| Realtime Events | `PRESENT` | WS emitted, subscribed, reconnect-tested |
| Authentication | `PRESENT` | Ticket handshake, session-bound tokens |
| Authorization | `PRESENT` | Block enforcement server-side |
| Encryption | `PARTIAL` | Boundary documented (`DATA_CLASSIFICATION.md`); **implementation unreviewed (RISK-01)** |
| Error Handling | `PRESENT` | Failure modes exercised in `test_failure_modes.py` |
| Retry/Recovery | `PRESENT` | Bounded — `_maxAttempts = 5`, exponential backoff with jitter |
| Observability | `PRESENT` | Privacy-safe metrics with a test enforcing no identifying labels |
| Tests | `PRESENT` | Unit + journey, green in CI |
| Documentation | `PRESENT` | `HANDOVER.md` §§11–17 |
| Migration Safety | `PRESENT` | Reversible migrations |
| Rollback Strategy | **`ABSENT`** | **No feature flag.** Messaging cannot be disabled without a deploy |

> **Computed status: `PARTIAL`.** Two `PARTIAL`s and one `ABSENT`. Per §0.1's
> rule, a single `ABSENT` on an applicable layer caps status at `PARTIAL`
> regardless of the other sixteen.
>
> This is the scorecard doing its job. Nobody would have called core messaging
> "partial" by judgement; the computation says so because it cannot be turned
> off without a deploy, and that is a true and consequential gap.

---

## 4–21. Sections carried forward from v4

Re-verified 2026-08-18. Findings **SEC-01, SEC-02, BE-01, REL-01, REL-02,
WS-01, PRIV-02, FL-01, CI-01, CI-02, PRIV-01** are resolved and marked in
`REPOSITORY_AUDIT_v4.md`. Findings **DB-01** and the IronWatch grade are
withdrawn as incorrect (§0).

Still open and unchanged:

| ID | Finding | Confidence | Impact |
|---|---|---|---|
| **SEC-03 / RISK-01** | Protocol comes from an unaudited third-party pure-Dart reimplementation; ~500 lines of app-level composition also unreviewed | `FACT` (see §0.3) | High — **downgraded from Catastrophic**, since nothing is hand-rolled here |
| **PERF-01** | No profiling on any real device, ever | `EVIDENCE NOT AVAILABLE` | Unknown |
| **CI-03** | No staging; `autoDeploy: true` to the only environment | `FACT` (`render.yaml:44`) | High |
| **REL-04** | Message ordering guarantees undocumented and untested | `UNVERIFIED` | Medium |
| **TD-01** | Feature flags exist for exactly one feature | `FACT` | High — see §3.1 |
| **TD-02** | No ADRs | `FACT` | Medium |

---

## 22. Compliance & Data Rights Findings *(new in v5.0)*

Assessed against §7.2's five data classes. `docs/DATA_CLASSIFICATION.md` already
maps the repository's data to four classes; this section maps it to v5's five
and reports the rights posture.

### 22.1 Class mapping

| §7.2 Class | IronLink data | Storage matches spec | Logging matches spec | Retention matches spec |
|---|---|---|---|---|
| `PUBLIC` | Display name, username, avatar, online status | ✅ | ✅ | ⚠️ online status cannot be hidden |
| `INTERNAL` | Feature flags, config, HTTP metrics | ✅ | ✅ | ✅ |
| `SENSITIVE_PERSONAL` | Phone numbers, contact hashes, device metadata, session IP and city | ✅ truncated in logs (`sms_gateway.py:24`) | ✅ | ❌ **no retention limit** |
| `PRIVATE_CONTENT` | Message metadata, alert history, audit log | ✅ | ✅ | ⚠️ alerts bounded at 48h; **`audit_logs` unbounded** |
| `CRYPTOGRAPHIC_SECRET` | Signal keys, session tokens, OTPs, plaintext | ✅ device keystore; server holds hashes only | ✅ enforced by a redaction processor | ✅ |

### 22.2 Data rights posture

```
FACT: There is no account-deletion endpoint.
SOURCE: grep over app/api/routes/*.py for @router.delete returns ten routes —
        sessions, channels, communities, contacts/delete-all, group entry,
        groups, moderation. None deletes a user.
VERIFIED: 2026-08-18
```

| Right | State | Evidence |
|---|---|---|
| **Erasure (account)** | ❌ **Not implemented** | No endpoint exists |
| Erasure (contacts) | ✅ | `contacts.py:399` — `/delete-all` |
| Erasure (messages) | ✅ | `unsend_message` + `reap_orphans`, propagates to object storage since Gate B |
| Erasure (sessions) | ✅ | `auth.py:720` |
| **Portability / export** | ❌ **Not implemented** | No export endpoint of any kind |
| **Access (what is held about me)** | ⚠️ Partial | `/auth/security-events` shows auth history only |
| **Rectification** | ✅ | Profile edit exists |
| **Retention limits** | ❌ | `audit_logs` and `user_sessions` unbounded |

> ⚠️ **EXECUTION BLOCKED — for any enterprise or compliance claim**
> **Reason:** Erasure and portability are absent, and retention is unbounded for
> two tables holding `SENSITIVE_PERSONAL` and `PRIVATE_CONTENT` data.
> **Evidence:** §22.2 above.
> **Decision Required:** whether IronLink intends to make any regulatory claim
> (GDPR-style rights, enterprise procurement) before P1. If yes, these move
> ahead of every roadmap feature — Privacy is level 3 in §2's hierarchy and
> Feature Scope is level 12. If no, they remain open and must never be claimed.

### 22.3 Admin trust model — §27.1 template

No enterprise admin capability with elevated content visibility exists today.
`app/api/routes/admin.py` grants broadcast and user administration, not message
access. Filling in the §27.1 template for what exists:

```
CAPABILITY: Send an urgent broadcast to all or filtered users; administer
            account status
SCOPE:      All users, or filtered by department
E2EE IMPACT: None. Admins have no access to message content and no key.
USER VISIBILITY: A broadcast is visibly a broadcast. Account status changes
            are not currently surfaced to the affected user — GAP.
AUDIT:      audit_logs entry per administrative action
REVOCATION: Not applicable; users cannot opt out of platform administration
```

**One gap surfaced by the template:** an account status change is not disclosed
to the affected user. Small, and exactly the kind of thing the template exists
to catch.

---

## 23. Accessibility & Localization Findings *(new in v5.0)*

### 23.1 Localization — measured, not claimed

```
FACT: 494 keys in app_ar.arb, 494 in app_en.arb, zero missing on either
      side, zero empty values.
SOURCE: JSON key-set comparison of frontend/lib/l10n/app_*.arb
VERIFIED: 2026-08-18
```

```
FACT: Exactly two user-facing strings in the entire Flutter codebase are
      hardcoded English rather than localized.
SOURCE: frontend/lib/features/community/screens/community_list_screen.dart:16
        — Text('Communities')
        frontend/lib/features/community/screens/community_list_screen.dart:45
        — Text('No communities found')
VERIFIED: 2026-08-18
```

Two strings out of 494 is a 99.6% localization rate, and both offenders are in
the same screen — the same screen §3 marks `UNTESTED`. That correlation is
worth noting: the least-finished feature is where the localization discipline
also lapsed.

### 23.2 RTL

Resolved in Gate C and re-verified. **Zero** hardcoded `EdgeInsets.only(left:/
right:)`, `Alignment.centerLeft/Right`, or `TextAlign.left/right` across `lib/`,
enforced by static guards in `frontend/test/rtl_layout_test.dart`. Widgets are
pumped under `ar` at 320 logical pixels and at 2× text scale.

### 23.3 Screen reader

```
FACT: 13 files use Semantics(); the repository has 22 screens plus widgets.
SOURCE: grep -rc "Semantics(" frontend/lib
VERIFIED: 2026-08-18
```

§31.10 requires semantic labels on all interactive elements. Thirteen files is
meaningful coverage of the newest work — `MessageSafetyBanner` reads as one
statement, deliberately — but it is **not** all interactive elements, and no
test asserts screen-reader coverage anywhere except that one banner.

```
ASSUMPTION: Older screens have inadequate semantic labelling.
BASIS: Semantics() appears in 13 of ~40 widget-bearing files, concentrated in
       recent work.
FALSIFIED IF: an audit of each screen under TalkBack/VoiceOver shows Material
              defaults are sufficient — which for standard widgets they often
              are.
```

### 23.4 UX State Matrix — §31.11, closing FL-02

FL-02 was `UNVERIFIED` in v4 ("screen-state completeness unknown"). Measured
across all 22 screens:

| State | Screens handling it | Notes |
|---|---|---|
| Loading | 16 / 22 | Missing on `auth_screen`, `splash_screen`, `contacts_permission_screen`, `form_builder_screen`, `home_screen`, `alert_center_screen` — several legitimately have nothing to load |
| Empty | 17 / 22 | Good coverage; `IronEmptyState` is a shared component |
| Error | 15 / 22 | `chats_list_screen`, `message_search_screen`, `community_list_screen`, `groups_screen`, `alert_center_screen` have **no error state** |
| Offline | ~0 / 22 | **`WsStatus` has no consumer outside the transport.** No screen distinguishes cached from live data |
| Permission Denied | 1 / 22 | Only `contacts_permission_screen` |
| Retry | Partial | Pull-to-refresh on lists; no explicit retry affordance after a failure |
| Partial | 1 / 22 | Keyword alert processing only |
| Locked | 0 / 22 | No plan/verification gating exists yet |
| Processing | 2 / 22 | Keyword alert, media upload |

> **FL-02 is now measured rather than unknown.** The headline gap is **Offline**:
> zero screens distinguish live from cached data, and `WsStatus.outdated` — added
> in Gate B so an outdated client stops reconnecting — renders nowhere, so a user
> whose build the server refuses is simply told nothing.

---

## 24. Rollback Readiness Findings *(new in v5.0)*

§24 asks which features have a **tested** rollback path versus an assumed one.
This is where correction 2 changes the picture substantially.

### 24.1 Database rollback — better than v4 recorded

```
FACT: All ten migrations implement a real downgrade(), from 0001
      (84 operations) to 0010 (2 operations). None is a stub.
SOURCE: alembic/versions/*.py
VERIFIED: 2026-08-18
```

| Aspect | State |
|---|---|
| Down-migrations exist | ✅ all ten |
| Down-migrations **tested** | ❌ **none.** Never executed in CI or anywhere else |
| Migrations additive | ✅ policy holds; 0010 is explicitly expand-phase |
| Rollback of code across a migration | ✅ safe while migrations stay additive |

> An untested downgrade is a **plan**, not a capability. §24 asks specifically
> about tested paths, and the honest answer is that a downgrade has never been
> run once. The fix is cheap now that CI has a Postgres: upgrade to head,
> downgrade to base, upgrade again.

### 24.2 Feature-level rollback

```
FACT: One feature-flag file exists in the entire repository.
SOURCE: find frontend/lib app -iname "*flag*" → keyword_feature_flags.dart
VERIFIED: 2026-08-18
```

| Capability | Flag | Kill switch | Lifecycle per §31.7 |
|---|---|---|---|
| Keyword alert (IronWatch) | ✅ | ✅ | ❌ no `OFF → INTERNAL → BETA → LIMITED → GENERAL` |
| AI features | ✅ `AI_FEATURES_ENABLED` | ✅ | ❌ |
| Server-side OCR | ✅ `SERVER_SIDE_OCR_ENABLED` | ✅ defaults off | ❌ |
| Self-registration | ✅ `SELF_REGISTRATION_ENABLED` | ✅ | ❌ |
| Metrics endpoint | ✅ `METRICS_TOKEN` empty = off | ✅ | n/a |
| **Everything else** — messaging, groups, attachments, contacts, blocks, self-destruct, controlled group entry, IronShield, scam intelligence | ❌ | ❌ | ❌ |

**Four global switches and one client flag.** Nine shipped capabilities have no
way to be turned off short of a deploy, and there is no flag *lifecycle* at all
— §31.7's five-stage progression exists nowhere, which is why §3.1's scorecard
caps core messaging at `PARTIAL`.

### 24.3 Deployment rollback

| Aspect | State |
|---|---|
| Redeploy a previous commit | ✅ Render dashboard |
| Staging to verify a rollback first | ❌ none exists |
| Canary / gradual rollout | ❌ `autoDeploy: true` straight to the only environment |
| Rollback runbook | ✅ `docs/RUNBOOK.md` — written, never exercised |

---

## 25. Sign-Off Record *(new in v5.0)*

§25 requires named reviewers before Phase 1 work begins.

| Role | Reviewer | Date | Status |
|---|---|---|---|
| Security | Fskalony | 2026-08-18 | ⚠️ recorded, **awaiting confirmation** |
| Privacy / Compliance | Fskalony | 2026-08-18 | ⚠️ recorded, **awaiting confirmation** |
| Principal Engineering | Fskalony | 2026-08-18 | ⚠️ recorded, **awaiting confirmation** |

**Resolved 2026-08-18 by recording reality.** `git shortlog` shows 99 of 99
commits by one contributor, so all three roles collapse onto that person. §25
states this is a legitimate answer; what is not legitimate is leaving the roles
blank, because a reader then assumes somebody is reviewing security and nobody
is. `.github/CODEOWNERS` now records it, and enumerates the security-sensitive
paths that should move to a second person the moment there is one — so that no
single person both writes and approves changes to the encryption boundary.

**The residual risk, stated plainly:** a sole maintainer cannot provide
independent review of their own work. That is precisely why
`docs/CRYPTO_REVIEW_SCOPE.md` exists and why RISK-01 must be closed externally.

```
FACT (at time of audit): No sign-off process existed. No CODEOWNERS file, no
      review requirement, no named accountable party for any feature.
SOURCE: absence of .github/CODEOWNERS; Owner column in §3 is `unassigned`
VERIFIED: 2026-08-18 — addressed the same day; see above.
```

> **This stop condition is cleared**, on the terms above: the roles are named,
> the sole-maintainer limitation is written down rather than implied, and the
> independent-review gap it creates is tracked as RISK-01 with a scoped work
> package rather than left as an assumption.

---

## 26. Recommended Execution Order

Unchanged in principle from v4's, updated for what closed and what §§22–25
surfaced.

**Immediately, and in parallel — external, blocks nothing daily**
1. **RISK-01** — commission the cryptographic review.
2. **§25** — name the sign-off roles, even if they collapse to one person.

**Gate D — release infrastructure** *(the gate everything else waits behind)*
3. Staging environment; `autoDeploy: false` to production.
4. Test a downgrade in CI — upgrade → downgrade → upgrade. Cheap now that CI has
   a Postgres, and it converts ten *plans* into ten *capabilities*.
5. Generalise feature flags with §31.7's five-stage lifecycle. This is what
   lifts core messaging off `PARTIAL` in §3.1.

**Priority 3 — privacy, above every feature**
6. Account deletion endpoint (§22.2).
7. Retention limits on `audit_logs` and `user_sessions` (§22.1).
8. Data export (§22.2).

**Priority 13 — the cheap UX gaps §23 measured**
9. Offline state on list screens; render `WsStatus`.
10. Error states on the five screens lacking one.
11. Localize the two remaining strings.

**Then, and only then — Gate E, new subsystems**
12. **IronDocs** first: the on-device OCR pipeline exists and its privacy
    boundary is already argued, making it the cheapest of the twelve and the one
    that most extends what the product is for.

**Before any UI work:** read `IronLink.md`, still unread in Downloads. It is the
only prompt whose contents are unknown and it is about the interface.

---

## 27. Self-Validation Checklist

Per §51–57, applied to this audit.

| Check | Result |
|---|---|
| Modified more than necessary? | No — zero production code changed |
| Broke existing functionality? | No |
| Introduced security/privacy regressions? | No |
| Created migration risk? | No |
| Added dependencies? | No |
| Skipped failure testing? | n/a — audit only |
| Skipped RTL/offline verification? | No — §23 measures both |
| Skipped documentation? | No |
| Skipped §27.1 admin trust disclosure? | No — §22.3, and it surfaced a gap |
| Left a defined rollback path untested? | **Yes, and it is reported** — §24.1 |
| Let an ASSUMPTION become a FACT? | **This audit corrects two instances of exactly that** — §0 |
