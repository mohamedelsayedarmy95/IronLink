# What Is Left

Everything named across the four prompts, checked against the code on
2026-08-18 rather than recalled. Where a row says "done", a path proves it.

**The short answer: 8 of the 20 roadmap features are built, 12 are not, and the
12 are the larger half.** The engineering foundation is finished — Gates A, B
and C are closed — so what remains is almost entirely product surface rather
than repair.

---

## 1. The four prompts, and what each one asked for

| Prompt | Kind | Status |
|---|---|---|
| `IRONLINK_MASTER_PROMPT_v3.md` | Engineering standard, no features | Adopted as `docs/ENGINEERING_STANDARD.md`; the standard the recent work was done under |
| `IronLink-Smart-Keyword-Alert-v4.1.0.md` | One feature, in depth | **Built** — see §3, row 6 |
| `IRONLINK…MASTER EXECUTION SYSTEM v4.0` | 15 subsystems + gates | Audit produced (`REPOSITORY_AUDIT_v4.md`); Gates A–C executed; subsystems mostly unbuilt |
| `IronLink-Controlled-Group-Entry-v3.1.0.md` | One feature, in depth | **Built** — 1,008 lines of backend, 6 screens. Never read by the current session; it was implemented earlier |
| `IronLink.md` | UI/UX redesign | **Never read.** 17,905 bytes, still in Downloads. The one prompt whose contents are genuinely unknown |

---

## 2. Engineering gates — the foundation

| Gate | Contents | Status |
|---|---|---|
| **A** | Content-free push, ciphertext preview, stale comment | ✅ done |
| **B** | Durable outbox, per-device push, versioned protocol, deletion propagation | ✅ done |
| **C** | Journey tests + a database, RTL, scale, failure injection, CI scanning, data classification | ✅ done |
| **D** | Staging environment, `autoDeploy` off, generalised feature flags, canary rollout | ❌ **not started** |
| **E** | New subsystems | ❌ blocked on D |

Gate D is small in code and large in consequence: `render.yaml` has
`autoDeploy: true` to the only environment, so every merge goes straight to
production with no canary and nowhere to test a release first. The v4.0 prompt
requires canary → 10% → 50% → 100%; none of that infrastructure exists.

---

## 3. The 20 roadmap features

Graded against `docs/PRODUCT_MOAT_ROADMAP.md`.

### Built — 8

| # | Feature | Evidence |
|---|---|---|
| 1 | **IronShield** — security centre | `frontend/lib/features/security/` — 7 files, sessions, revoke, posture |
| 6 | **IronWatch** — keyword alert | On-device OCR, 48h retention, per-chat scope, acknowledgement, 0.85 threshold, daily cap |
| 7 | **Controlled Group Entry** | `app/api/routes/group_entry.py` (1,008 lines), 6 screens, forms, audit log |
| 11 | **Scam & fraud intelligence** | `security/domain/scam_signals.dart` — bilingual, on-device, wired into the bubble |
| — | Link safety | `security/domain/link_safety.dart` — homograph, per-label mixed-script |
| — | E2EE messaging + groups | Signal on device, Sender Keys with membership epoch |
| — | Media metadata stripping | `core/media/metadata_scrubber.dart` |
| — | Observability | `app/core/observability.py` |

### Partial — 3

| # | Feature | What exists | What does not |
|---|---|---|---|
| 4 | **IronSearch** | Local search over decrypted history (`message_store.search`) | Permission-aware search across documents, groups, channels; the whole "search everything" premise |
| 5 | **IronAI** | Consent-gated AI via Hugging Face, kill switch | The "local-first" half — everything runs in the cloud today, which is the opposite of the spec's default |
| 20 | **Advanced communities** | Communities, channels, broadcasts, moderation | Roles, events, permission boundaries — and the permission boundary is `UNTESTED`, per the audit |

### Not started — 12

Zero code files each. This is the honest count, not a soft one.

| # | Feature | Rough size | Notes |
|---|---|---|---|
| 2 | **IronDocs** — document intelligence | Large | Cheapest of the twelve: the on-device OCR pipeline already exists and its privacy boundary is established |
| 3 | **IronVault 2.0** — privacy profiles | Medium | Mostly composition of existing switches; the risk is claiming OS guarantees the platform cannot give |
| 8 | **IronMesh** — off-grid | Very large | Bluetooth/Wi-Fi Direct mesh. Nothing may be claimed without real-device testing, which has never happened here |
| 9 | **IronFlow** — automation | Large | Must be explicit, revocable, auditable; no autonomous destructive actions |
| 10 | **IronMemory** — knowledge layer | Large | Encrypted local index |
| 12 | **IronMasks** — contextual identities | Large | Touches identity and keys → full threat model required first |
| 13 | **IronVault Escrow** — conditional delivery | Large | Needs formal cryptographic design review before a line is written |
| 14 | **IronCanvas** — collaborative workspace | Very large | CRDT plus an encryption boundary plus recovery |
| 15 | **IronProof** — document integrity | Medium | Must distinguish cryptographic evidence from metadata |
| 16 | **IronGhost** — privacy scheduling | Medium | Must never misrepresent actual delivery state |
| 17 | **IronLegacy** — digital inheritance | Large | Elevated security review, false-trigger prevention |
| 18 | **Secure voice transcription** | Medium | Voice recording and upload already work; transcription does not exist |
| 19 | **Creator & Business OS** | Very large | Channels and broadcasts are a foundation, not the feature |

---

## 4. Known defects and gaps outside the roadmap

These are not features. They are things that are wrong, or absent, today.

### Blocking anything being called production-ready

| ID | Item | Why it blocks |
|---|---|---|
| **RISK-01** | The Dart Signal implementation has never been cryptographically reviewed | Everything else rests on it. **Cannot be closed from inside this repository** — it needs an external reviewer or a migration to a maintained binding |
| **PERF-01** | No profiling on a real device, ever | Every performance claim in `docs/SLO.md` is `EVIDENCE NOT AVAILABLE`. Device testing has been deferred since the beginning |
| **CI-03** | No staging, `autoDeploy: true` to production | A merge is a deploy. There is nowhere to test a release |

### Privacy and data-governance gaps

Recorded in `docs/DATA_CLASSIFICATION.md`:

1. **No account deletion.** There is no endpoint that removes a user and
   everything referencing them. Message retraction propagates correctly; a
   whole account does not, because the operation does not exist.
2. **No retention limit on `audit_logs`.** It holds actor ids indefinitely.
3. **No retention limit on `user_sessions`.** Revoked rows keep IP addresses
   and approximate locations forever.
4. **Online status cannot be hidden.** No setting exists.

### Product gaps

| Item | State |
|---|---|
| PDF attachments | `UI_ONLY` — a "coming soon" snackbar. The metadata scrubber must learn PDF before they can be sent at all |
| Voice / video calls | Absent entirely. Never specified in any prompt either |
| `WsStatus.outdated` | The transport stops retrying, but **no screen renders connection status at all**, so nothing tells the user to update |
| FL-02 — screen states | No inventory of which screens handle loading / empty / error / offline / permission-denied. Unknown, not absent |
| Push delivery rate | Now measurable (per-device tokens landed), but no SLO is set for it yet |

### Hygiene

- `keyword_rule.dart` contains one raw NUL byte, used correctly as a hash field
  separator but written as a literal rather than `\x00`, so git treats the file
  as binary. Cosmetic. Attempts to rewrite it were reverted by something in the
  local environment; worth a second look from a machine without that hook.
- `TD-02` — no ADRs. Architectural decisions live in commit messages.
- `TD-03` — `Qwen افكار تطويير ironlink.txt` at the repository root describes a
  directory layout that does not match reality.

---

## 5. What to do next, in order

The order is the priority hierarchy's, not appeal's.

**1. RISK-01 — commission the cryptographic review.** It is external, it blocks
nothing day to day, and nothing else matters if it fails. Start it now precisely
because it runs in parallel.

**2. Device testing.** Deferred since the start. Until an APK runs on a real
phone, "works" means "the tests pass", and the two are not the same thing —
Arabic OCR, attachment upload on a poor network, and battery behaviour have
never been observed.

**3. Gate D.** A staging environment and `autoDeploy: false`. Small work,
and it is the difference between shipping and hoping.

**4. Account deletion and retention limits.** Priority 3 in the hierarchy,
above every feature below.

**5. Then IronDocs.** The cheapest of the twelve — the OCR pipeline exists on
the device and its privacy boundary is already argued — and the one that most
extends what the product is for.

**Read `IronLink.md` before any UI work.** It is the only prompt whose contents
are unknown, and it is about the interface. Building screens before reading it
risks doing the work twice.
