# Cryptographic Review — Scope of Work

**Prepared:** 2026-08-18
**For:** an external reviewer, so this can be quoted against without first
reading 47,000 lines to find out what needs looking at.
**Status of the risk it addresses:** `REPOSITORY_AUDIT_v5.md` §0.3 and RISK-01.

---

## 1. What this is, in one paragraph

IronLink is an end-to-end encrypted messenger. It implements **no cryptographic
primitive of its own**. X3DH, the Double Ratchet and XEdDSA come from
`libsignal_protocol_dart` — a third-party pure-Dart implementation of the Signal
specifications, not a binding to Signal's own audited libsignal. What this
repository owns is roughly **500 lines of composition**: how sessions are
established, how attachment bodies are encrypted, how group sender keys are
scoped, and what the on-the-wire envelope looks like.

**Those 500 lines are the review.** The other 46,500 are not.

---

## 2. The dependency question, which is separate and strategic

```
FACT: libsignal_protocol_dart 0.8.2 is the current release, published
      ~58 days before this document by mixin.dev, a verified pub.dev
      publisher. 150/150 pub points, 66 likes, ~7,020 weekly downloads.
      Not discontinued.
SOURCE: https://pub.dev/packages/libsignal_protocol_dart
VERIFIED: 2026-08-18

FACT: It is described as a "pure Dart/Flutter implementation of the Signal
      Protocol" — an independent implementation of the specifications. No
      security audit is published for it.
SOURCE: same
VERIFIED: 2026-08-18
```

By the standards of §31.4 dependency governance this scores well on every axis
except the one that matters most here: **an unaudited independent
reimplementation of a protocol whose security depends on details.** Signal's own
implementation is audited; a faithful-looking reimplementation of the same specs
is not the same artifact.

Three options, and the choice is the project's rather than the reviewer's:

| Option | Cost | What it buys | What it costs |
|---|---|---|---|
| **A. Accept, with the reasoning recorded** | Free | Ships today | The product's central claim rests on an unaudited dependency, and says so |
| **B. Fund an audit of the package** | High | Closes the risk properly, benefits every user of the package | Auditing a whole protocol implementation is far more work than §3's scope |
| **C. Migrate to a binding to real libsignal** | High engineering | Inherits Signal's audits | A binding for Flutter may not exist in usable form; this needs its own feasibility spike before it is a real option |

**Recommendation: A now, with §3 reviewed, and a decision on B or C recorded as
an ADR before any enterprise or regulatory claim is made.** Option A is only
honest if the limitation is stated wherever the security claim is made —
`docs/DATA_CLASSIFICATION.md` and any future marketing copy.

---

## 3. The actual review scope — 500 lines

Everything below is in `frontend/lib/core/crypto/`.

### 3.1 `attachment_crypto.dart` — 116 lines · **highest priority**

The only place this repository composes a primitive directly.

**What it does.** AES-256-GCM over attachment bodies. A fresh 32-byte key and
12-byte nonce per attachment, from `Random.secure()`. 128-bit tag. No associated
data. Key material travels inside the Signal envelope and never reaches the
server.

**Specific questions for the reviewer:**

1. `Random.secure()` per byte via `nextInt(256)` — is this an adequate CSPRNG on
   both Android and iOS Flutter runtimes, and is per-byte generation sound?
2. **No AAD is bound.** `mimeType` and `sizeBytes` travel in the envelope
   alongside the key. Since the envelope is itself authenticated by the ratchet,
   is leaving AAD empty defensible, or should the metadata be bound into the
   GCM tag?
3. Nonce is random rather than counter-based. With a fresh key per attachment
   the birthday bound is irrelevant — confirm that reasoning holds.
4. `decrypt` maps `InvalidCipherTextException` to `AttachmentTampered` and never
   returns partial plaintext. Confirm PointyCastle's GCM does not emit plaintext
   before tag verification.

### 3.2 `signal.dart` — 370 lines · **high priority**

Session establishment, key directory exchange, envelope format.

1. **Trust on first use.** `signal_store.dart` raises `IdentityChanged` when a
   peer's identity key changes. Is the flow correct — refuse until confirmed,
   no silent accept?
2. **No plaintext fallback.** Every failure path raises `EncryptionFailed`
   rather than sending in the clear. Verify there is no path that downgrades.
3. **Envelope format** — what is authenticated, what is not, and can a field be
   moved or stripped without detection?
4. Pre-key exhaustion: `signal_test.dart` covers "a bundle without a one-time
   pre-key still opens a session". Confirm the security consequence of that
   fallback is understood and acceptable.

### 3.3 `group_signal.dart` — 261 lines · **high priority**

Sender Keys, with a membership epoch built into the key name.

1. **Epoch as part of `SenderKeyName`** means a membership change necessarily
   produces a different key, structurally rather than by convention. Verify
   there is no path where the epoch advances and an old key stays usable.
2. Distribution messages are encrypted pairwise, one per member. Verify a
   removed member cannot obtain the new epoch's key.
3. `sender_key_store.dart` prunes old epochs but keeps the previous one.
   Confirm that window is justified and bounded.

### 3.4 `signal_store.dart` (299) · `key_repository.dart` (147) · `secret_store.dart` (57)

Storage and key directory.

1. Key material is held in `flutter_secure_storage` (Keychain / Keystore).
   Verify nothing sensitive reaches `SharedPreferences` or the sqflite cache.
2. Sign-out erases key material — verify completeness.
3. The key directory is server-provided. What does a malicious server achieve,
   and does the TOFU check in 3.2 bound it correctly?

---

## 4. Explicitly out of scope

Stated so the reviewer does not spend time and the project does not imagine
coverage it did not buy.

- The internals of `libsignal_protocol_dart` — that is §2's decision, not §3's
  review.
- Backend code. The server holds ciphertext and no key; it is not part of the
  cryptographic boundary. `docs/DATA_CLASSIFICATION.md` states what it does see.
- Transport security (TLS), authentication, and session management — reviewed
  separately if wanted; they are not the E2EE boundary.
- Device compromise. If the device is owned, the keys are owned. Out of scope
  for every messenger.

---

## 5. What already exists, so the reviewer does not redo it

| Artifact | Where |
|---|---|
| E2EE boundary — what the server can and cannot see, per data class | `docs/DATA_CLASSIFICATION.md` |
| Existing crypto tests — 587 frontend tests including `signal_test.dart`, `group_signal_test.dart`, `attachment_crypto_test.dart` | `frontend/test/` |
| Threat notes on identity change, reinstall, and epoch rotation | test names in `group_signal_test.dart` read as a threat list |
| What the server stores | `app/models/message.py:50,102` |

**A caution on the tests.** They were written alongside the implementation and
share its assumptions. They are useful as a statement of *intended* properties —
read them as a specification of what the authors believed they were building,
not as evidence that it holds.

---

## 6. Deliverable requested

1. Findings against §3, each with severity and a concrete exploit path or an
   explicit statement that none was found.
2. A judgement on §2 — whether option A is defensible for this product's threat
   model, or whether B or C is required.
3. Anything in §4 that should not have been out of scope.

---

## 7. Threat model the review should assume

| Actor | Capability | In scope |
|---|---|---|
| Malicious server operator | Reads and modifies everything stored; serves key directory responses | **Yes — the primary actor** |
| Network attacker | Full MITM below TLS | Yes |
| Malicious peer | A valid account, messaging the target | Yes |
| Removed group member | Held a valid sender key until removal | **Yes — §3.3** |
| Object-storage attacker | Can rewrite stored attachment bodies | **Yes — §3.1** |
| Device attacker | Physical or malware access to an unlocked device | No — see §4 |
| Nation-state with an unpublished break in X25519 or AES | — | No |
