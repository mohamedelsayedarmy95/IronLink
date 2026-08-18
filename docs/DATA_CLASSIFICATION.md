# Data Classification

The engineering standard requires every data type classified, with its storage,
retention, logging and deletion policy stated. The policies existed — they were
just scattered across code comments, which means they were enforced by whoever
happened to have read the right file.

This is that policy written down. Where a row says something the code does not
do, it says so.

---

## The four levels

| Level | Meaning | If it leaked |
|---|---|---|
| **PUBLIC** | Safe to show anyone | Nothing happens |
| **INTERNAL** | Operational, not about a person | Reveals how the service runs |
| **CONFIDENTIAL** | About a person, or a pattern of their behaviour | Identifies or profiles a user |
| **RESTRICTED** | Content, credentials, key material | The product's premise fails |

The line that matters is between INTERNAL and CONFIDENTIAL, and it is not where
people expect. **A user id is CONFIDENTIAL, not INTERNAL.** It is not
identifying on its own, but joined against anything else it names a person, and
a metric labelled by it publishes who was active and when without decrypting
anything.

---

## Message content and keys — RESTRICTED

| Data | Where it lives | Server can read | Retention | Logging | Deletion |
|---|---|---|---|---|---|
| Message plaintext | Device only | **No** | Device lifetime | **Never** | Local wipe on sign-out |
| Message ciphertext | `messages.content_ciphertext` | No — no key exists | Until retracted or expired | Never | Nulled on unsend and on self-destruct; tombstone row kept |
| Attachment plaintext | Device only | **No** | Not stored | Never | n/a |
| Attachment ciphertext | Object storage | No | Until retracted or expired | Never | Deleted on unsend; `reap_orphans` retries a failed delete |
| Attachment key | Inside the Signal envelope | **No** | With the message | Never | Goes when the envelope goes |
| Signal identity / session keys | `flutter_secure_storage` | **No** | Until sign-out | Never | Erased on sign-out |
| Sender keys (groups) | Device, epoch-scoped | No | Until epoch rotates | Never | Dropped on leaving a group |
| OTP codes | Redis, TTL | Yes — it issues them | Short TTL, single use | **Never the value** | Expire on their own |
| Session refresh tokens | `user_sessions.refresh_token_hash` | Hash only | Session lifetime | Never | Revoked or expired |
| `SECRET_KEY`, `DB_ENCRYPTION_KEY`, `CONTACT_HASH_SALT`, `METRICS_TOKEN` | Environment | Yes | Until rotated | **Never** | Rotate on exposure |

**Enforced by:** `app/core/observability.py` censors by key stem, so `otp`,
`content`, `plaintext`, `ciphertext`, `private_key` and their relatives never
reach a log sink even from a call site written later.

---

## Who talks to whom — CONFIDENTIAL

This is the category the encryption does **not** cover, and being honest about
it is the point of writing this down.

| Data | Where | Retention | In logs | In metrics |
|---|---|---|---|---|
| `messages.sender_id` / `recipient_id` | Postgres | With the message | No | **No** |
| `messages.created_at` | Postgres | With the message | No | No |
| Message size | Implicit in storage | With the message | No | No |
| Group membership | `group_members` | Until they leave | No | No |
| Contact graph | `contacts`, salted hashes | Until deleted | No | No |
| `users.phone_number` | Postgres | Account lifetime | **Truncated to 5 digits** | No |
| Session IP and device type | `user_sessions` | Session lifetime | No | No |
| Approximate location (city) | `user_sessions` | Session lifetime | No | No |

**A server compromise exposes this table and not the one above it.** That is
what "your messages are safe, but metadata was exposed" means concretely, and
`docs/RUNBOOK.md` says to phrase it that way rather than "nothing was exposed".

**Enforced by:** `tests/test_observability.py::TestNoIdentityInLabels`
enumerates every metric and fails the build on any identifying label — so this
row stays true for metrics nobody has written yet.

---

## The user's own configuration — CONFIDENTIAL

Easy to underrate, because it looks like settings.

| Data | Where | Why it is not INTERNAL |
|---|---|---|
| Keyword watchlist | Device, and Redis for the server-side path | States exactly what its owner is watching for. Removed from the FCM payload for this reason. |
| Blocks | `user_blocks` | Names a relationship the user chose not to have |
| AI consent, per conversation | `ai_consent` | Says which conversations a user considered sensitive |
| Privacy and alert settings | Device | Profiles the user's threat model |

---

## Operational data — INTERNAL

| Data | Where | Retention | Notes |
|---|---|---|---|
| HTTP metrics | Prometheus registry, in-process | Process lifetime | Route templates only, never raw paths |
| Latency histograms | Same | Process lifetime | No identity in any label |
| `X-Request-ID` | Logs, response header | Log retention | Random per request, tied to no account — this is how a report is traced instead of by user id |
| Audit log | `audit_logs` | Indefinite | Contains actor ids, so **CONFIDENTIAL in practice** despite being an operational table |
| Deploy and build logs | GitHub Actions | 90 days | Must never contain env values |

**The audit log is the row to watch.** It is treated as operational and is not:
it records who did what and when, indefinitely, which is the definition of
CONFIDENTIAL. It is not currently subject to any retention limit. See below.

---

## Public — PUBLIC

Display name, username, avatar, and online status, to people who can already
see the user. Nothing here is a secret; online status is the one a user might
reasonably want to hide, and there is no setting for that today.

---

## What this document admits

Written as gaps rather than omitted, because a classification document that
only describes what works is a marketing page.

1. **One retention survives account deletion, deliberately.** A platform ban is
   kept as a salted SHA-256 of the phone number, with the account identifier
   dropped. Without it, evading a ban is one step — delete, register the same
   number again — and a ban a banned person can undo is decorative.

   Privacy outranks abuse prevention in the hierarchy, and the resolution is
   not to skip the retention but to make it minimal and honest: a hash, no
   identifier, no name, no history, and the deletion response tells the user
   in plain words that it happened. Nobody who was not banned leaves anything
   behind.

2. **No retention limit on `audit_logs`.** It grows forever and holds actor
   ids — though an account deletion now anonymises its own entries, clearing
   both `actor_id` and `ip_address`. The standard requires retention limits per
   data type, enforced. This one has none.

3. **No retention limit on `user_sessions`.** Revoked and expired rows are kept
   indefinitely, and they carry IP addresses and approximate locations. There
   is a good reason to keep some history — it is what makes a "new device"
   alert possible — and no reason to keep it forever.

4. ~~**Account deletion is not implemented.**~~ **Closed 2026-08-18.**
   `DELETE /auth/me` erases the account, re-authenticated with a fresh phone
   token rather than a session token — deletion is the one irreversible action
   here, and a bearer token is exactly what a stolen phone already has. No
   grace period: someone deleting an account on this product is often doing it
   because they are at risk, and holding their data for a month in case they
   reconsider is the opposite of what they asked for.

5. **Online status cannot be hidden.** It is PUBLIC to contacts with no way to
   opt out, which is a privacy setting most comparable products have.

6. **The keyword watchlist reaches Redis on the server-side path**, which is
   disabled by default (`SERVER_SIDE_OCR_ENABLED = False`). While it is off,
   the watchlist never leaves the device. If it is ever turned on, this row
   changes from "device only" to "server holds the user's watchlist", and that
   is a decision that deserves its own review rather than a config flag.

---

## Rules that follow from all of this

1. **Never log a value from the RESTRICTED table.** The redaction processor
   enforces it; do not rely on remembering.
2. **Never label a metric with anything from the CONFIDENTIAL table.** A test
   enforces it.
3. **Trace by `X-Request-ID`, never by user id.** Searching logs by phone
   number pulls identity into a query other people can read.
4. **A new column gets classified in this document before it is merged.** A
   column nobody classified is a column stored under no policy.
