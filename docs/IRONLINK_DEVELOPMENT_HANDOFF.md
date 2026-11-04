# IronLink development baseline

Repository: https://github.com/mohamedelsayedarmy95/IronLink

## Git and verification

- Authoritative development branch: `integration/mission-01a-postgres-hardening`.
- Source integration merge: `329fd116e2e0e7e674973365d2f1d4dace7ffed5`, normal
  GitHub merge of PR #3, preserving feature commit `9f5871ff375fbc1b70549059dbb0d2a0415c5c57`
  and integration ancestor `750039d98169e23f093cc41aaf0cc5f3f5fc0552`.
- PR #3 is merged; PR #2 remains OPEN toward the deployment branch. Do not merge PR #2.
- Final baseline includes this documentation commit: resolve it with `git rev-parse HEAD`.
  Its exact SHA and final Actions run/outcome are recorded in the closeout report and
  PR #2 checks: https://github.com/mohamedelsayedarmy95/IronLink/pull/2/checks .
  This avoids a self-referential commit hash or another documentation-only CI cycle.
- Previous feature verification: https://github.com/mohamedelsayedarmy95/IronLink/actions/runs/41873357380
  passed five jobs (mandatory PG16 124, WS 74, zero gate skips). This is historical
  evidence, not proof of the final documentation commit; inspect its exact-head CI.
- Deployment branch remains `fix/boot-crashes-and-backend-merge` at
  `42f881f4e92c23c99255594d9f9cc10112cffa53`.

## Completed work

01A hardened PostgreSQL bootstrap, owner/runtime configuration, escalation checks,
RLS/retention and shared migration locking. 01B integrated this with Render Free's
single startup bootstrap; unsupported paid pre-deploy hook remains absent.
02A added session-bound one-use WS tickets, fresh authorization for protected
incoming actions/outgoing data, postcommit cross-worker closure, independent
verification and bounded failures; Flutter stops retries and clears invalid
credentials/outbox without treating temporary refresh outages as revocation.
Work authorized before revocation commits may finish; later checks reject.

## Render evidence and production boundary

Owner's independent authenticated investigation found both observed web services
and Blueprint watch the deployment branch, not integration/feature. Blueprint
Auto Sync and primary API Auto-Deploy On Commit are enabled; previews are disabled.
Inspected development workflows have no Render deployment steps; repository
webhooks were empty. GitHub Apps and external hook consumers remain unverified.
The owner explicitly accepts this residual risk for DEVELOPMENT INTEGRATION ONLY.
Stop further mutation if any unexpected Render deployment is observed; record its
ID/state and seek owner approval. Do not change services, Blueprint or credentials.

Production remains BLOCKED: independently verify separate migration-owner/runtime
identities, ownership/grants, credentials, sanitized startup and Render configuration,
plus approved backup/recovery. Roll out the revised ticket contract across all
workers and drain old sockets; mixed old/new contracts are not a safe rollout.

## Preservation, cleanup and remaining validation

Keep all existing worktrees and dirty/untracked files. Original deployment and 01A
checkouts remain dirty intentionally. StockMind, its AVDs and shared SDK/caches are
protected. Never reset, clean, stash, delete worktrees or force-push to tidy them.
Preservation evidence: `C:/Users/Name/.codex/tmp/mission02a-closeout/baseline.json`.

Only the feature worktree's ignored generated Flutter `frontend/build/test_cache`
was deleted in the earlier closeout pass: 50,708,744 file bytes, observed free-space
increase 50,712,576 bytes, no deletion errors. Evidence:
`C:/Users/Name/.codex/tmp/mission02a-closeout/cleanup.json`. No further cleanup needed.

Huawei JSN-L22 Android 10 was discovered, but no physical-device or IronLink emulator
tests ran; available AVDs belong to StockMind. CI APK uses placeholder Firebase;
it proves compilation/R8/assets, not device E2E. Load/performance validation remains.

Known backlog, unselected: atomic OTP/rate limits, community/channel ACL coverage,
production OTP delivery/account-enumeration behavior. No next mission has started.

Awaiting owner selection of the next IronLink development mission.
