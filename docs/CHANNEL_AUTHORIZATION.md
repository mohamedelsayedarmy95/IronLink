# Channel authorization — Mission 02B

The server derives identity from the validated account/session. Channel owner,
visibility and active subscriptions come from PostgreSQL; submitted owner IDs,
membership flags, plan IDs and media keys never grant private-channel access.

| Operation | Owner | Active subscriber | Outsider / inactive subscriber |
|---|---|---|---|
| Discover/read public channel and published posts | Allowed | Allowed | Allowed when authenticated |
| Discover/read private channel and published posts | Allowed | Allowed | Hidden / 404 |
| Preview unpublished, flagged or future-dated posts | Allowed | Hidden | Hidden |
| Publish, edit/delete channel, read analytics | Allowed | 403 if channel visible | 404 private / 403 public |
| Public self-subscription | Allowed | 409 when already active | Allowed; inactive row reactivated |
| Private self-subscription | Owner may subscribe | 409; existing grant unchanged | 404; no grant or reactivation |
| Grant/revoke another subscription | Allowed | 403 if channel visible | 404 private / 403 public |
| Unsubscribe | Own row only | Marks own row inactive | No private access restored |

Unauthenticated requests return 401. Unknown channels and inaccessible private
channels use the same 404. Discovery filters in SQL **before** offset/limit;
descending UUID breaks creation-time ties. Reads do not positively cache access.
Authorization uses each SQL statement's committed snapshot: a request authorized
before a concurrent revocation commits may finish; later statements reject it.

## Explicit owner grants

`PUT /api/v1/channels/{channel_id}/subscribers/{user_id}` grants/reactivates
access (200), idempotently, using the existing unique subscription row.
`DELETE` at the same path revokes it (204, idempotently). Only the authoritative
channel owner can invoke these. The target must exist. Owners can manage their
channels without a subscription row. Self-unsubscription retains the inactive row;
only an owner grant restores private access. These APIs are the minimal onboarding
mechanism; the existing Flutter screen has no grant-management UI.

All channel/subscription mutations lock the channel row until transaction commit,
including visibility changes. PostgreSQL's existing unique subscription index
remains enforced. Repeated/concurrent requests cannot duplicate membership or
double-adjust the count. The count is display metadata, never authorization.

## Publication and media

Non-owner post reads require `is_scheduled = false` and a null or elapsed
`scheduled_at`, using the database clock. An overdue but still-flagged post is not
implicitly published. Owners can preview their own scheduled content. This does
not add a scheduler or a new publication endpoint.

The generic media URL endpoint checks the same channel/publication policy before
signing. Revision `0014_channel_media_keys` binds each channel attachment key to
one channel using a unique database key. New post creation cannot rebind a key
from another channel. The binding survives channel deletion as a null-channel
tombstone and denies fresh URLs. Unbound non-channel uploads keep their existing
contract; this mission does not redesign chat/upload authorization.

Before a key's first binding, the server verifies uploader identity from private
storage metadata written by authenticated upload completion (including thumbnails).
Client-supplied ownership fields are ignored. Unknown or foreign provenance returns
404; unavailable storage verification fails closed with 503. Existing backfilled
channel attachments keep their established scope. Older unattached uploads without
owner metadata require re-upload before first channel use. Ownership lookup is
offloaded from the event loop and bounded at five seconds; underlying synchronous
storage I/O may finish after that request deadline.

Backfill binds existing keys referenced in one channel, deduplicating repeated
posts. A historical key spanning multiple channels receives a denied null binding
instead of guessing its scope; re-upload with a fresh key resolves it. The DDL
downgrade is reversible but removes these controls and tombstones. Do not treat
rollback as preserving the new privacy guarantees. Already-deleted historical
objects with no surviving post cannot be attributed retroactively by this migration.

Previously issued storage URLs are bearer capabilities for up to the existing
300-second lifetime; revocation prevents new URLs, not recall of already-issued
URLs or downloaded bytes. Storage must remain private. No real storage bucket,
production database, Render setting or credential was changed or tested here.

## Verification and boundaries

`python -m scripts.test_channel_authorization` provisions a new loopback-only
PG16 cluster, runs real FastAPI HTTP routes with actual JWT/session authentication
and database constraints, tests migration backfill/downgrade/upgrade, and fails on
any skip. CI runs this mandatory gate alongside the existing PostgreSQL and
two-worker WebSocket gates, within the existing five jobs.

The focused independent review identified deletion fail-open and foreign-reference
media denial. Both were reproduced before correction and have regressions.
Community membership uses independent tables and helpers; channels have no community
relationship. No community permissions were changed. Community detail/discovery
classification remains a separate follow-up, not a confirmed private-content finding
from this mission. OTP, production rollout, device E2E and load tests remain outside
scope. No production performance claim is made.
