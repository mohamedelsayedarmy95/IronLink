# Runbook

Written before the first incident, which is the only time a runbook can be
written honestly. Afterwards it gets written to describe the outage that just
happened, and the next one is different.

**Who this is for:** whoever is on call, at three in the morning, without the
context in their head. So every procedure states what to check, what the result
means, and what to do — not "investigate the database".

---

## Ground rules

**1. Never read message content to debug.** There is nothing to read —
`content_ciphertext` is ciphertext and the server has no key. But the reflex to
look is the thing to suppress, because the workaround someone invents to
satisfy it is the breach. If a diagnosis appears to need message content, the
diagnosis is wrong.

**2. Trace by request id, not by user.** Every response carries
`X-Request-ID`. Ask the reporter for it. Searching logs by phone number or user
id means pulling identity into a query someone else can read.

**3. Roll back before you understand.** Restoring service and finding the cause
are separate activities, and doing them in that order is not sloppiness. The
deploy that broke it will still be in the history in an hour.

**4. State what you did not check.** A handover that says "database looks fine"
without saying how it was checked sends the next person down the same path.

---

## Deployment facts

| Thing | Where |
|---|---|
| API | Render web service `ironlink-api`, Docker, region oregon |
| Database | Render PostgreSQL 16, `ironlink-db` |
| Redis | Render Redis `ironlink-redis`, `maxmemory-policy noeviction` |
| Migrations | `alembic upgrade head` from `docker-entrypoint.sh`, at container start |
| Liveness | `GET /health` — shallow, always 200 if the process is up |
| Readiness | `GET /health/ready` — checks Postgres and Redis, 503 when either is down |
| Metrics | `GET /metrics`, bearer `METRICS_TOKEN`; **404 when the token is unset** |

Two consequences of the free plan that will mislead you at 3 a.m.:

- **The instance sleeps when idle.** The first request after a quiet period
  takes tens of seconds. This looks exactly like a latency incident and is not
  one. Check whether traffic had stopped before concluding anything.
- **Migrations run at container start, not pre-deploy.** Render's free tier has
  no pre-deploy hook. So a bad migration fails *during* the rollout, and if
  replicas are ever scaled above one they will race each other running it.

---

## Self-destruct backlog

**Alert:** `SelfDestructBacklogGrowing` or `SelfDestructSweepFailing`
**Severity:** critical — this is a privacy failure, not a performance one.

Messages are outliving the lifetime their sender chose, while the interface
continues to tell the user they expire. The product's statement to the user is
currently false.

**Check:**
```bash
curl -sH "Authorization: Bearer $METRICS_TOKEN" $API/metrics | grep self_destruct
```

| Reading | Meaning | Action |
|---|---|---|
| `overdue` high, `failures_total` flat | Sweeper is running and losing | Volume exceeds one sweep interval. Reduce `SWEEP_INTERVAL_SECONDS`, or batch larger. |
| `failures_total` climbing | Sweeper is raising | Read the `self_destruct_sweep_failed` log lines. Usually the database is refusing connections. |
| Both flat at zero, but users report messages persisting | The worker is not running | The task is started in the lifespan hook — confirm the process actually completed startup. |

**Do not** clear the backlog with a manual `DELETE` before understanding it. If
the sweeper is failing because of a schema problem, a manual delete removes the
evidence and the backlog returns on the next cycle.

**Escalate if** the backlog has been non-zero for over an hour: users have been
given a false assurance for that period, and someone has to decide whether that
is disclosable.

---

## Authentication failing

**Alert:** `AuthErrorRate`
**Severity:** critical — a locked door, with no route around it for the user.

This is the one flow that depends on a third party.

**Check, in order:**

1. **Firebase.** `firebase_id_token_rejected` in the logs, at volume, means the
   dependency and not us. Check Firebase status. Nothing here fixes it.
2. **Redis.** OTPs and session records live there. `curl $API/health/ready` —
   if `redis` reads `unavailable`, that is the cause.
3. **Clock skew.** Token validation is time-sensitive. A container with a
   drifted clock rejects valid tokens with no useful error.
4. **`DEV_AUTH_BYPASS`.** If this is somehow true in production, the config
   validator should have refused to start. If the service is up and it is set,
   that is a separate and more serious incident.

**Never** disable authentication to restore service.

---

## Readiness failing

**Alert:** `NotReady`

`/health/ready` names the dependency:

```bash
curl -s $API/health/ready | jq
```

**`database: unavailable`** — Render free-tier Postgres has a low connection
cap and the pool can exhaust it. Check the instance is not suspended. If a
deploy is in progress, a migration may hold a lock.

**`redis: unavailable`** — check the instance is running. Note the policy is
`noeviction` deliberately: under memory pressure Redis will *refuse writes*
rather than silently discard OTP codes and live session keys. Refused writes
are the intended behaviour. Do not "fix" it by switching to `allkeys-lru`; that
converts a loud failure into random logouts and invalid-code reports that take
weeks to diagnose.

**Both `ok` but the alert is firing** — the failure is between the balancer and
the container. Check the deploy log for a container restarting in a loop.

---

## Latency regression

**Alert:** `LatencyP99`

**Rule out the cold start first.** If request volume was near zero before the
spike, this is the free plan sleeping, and there is nothing to fix.

```promql
histogram_quantile(0.99,
  sum by (le, route) (rate(ironlink_http_request_duration_seconds_bucket[5m])))
```

Read it **by route**. One slow route is a query or a handler. Every route slow
together is the database, Redis, or the instance itself.

If a deploy preceded it, roll back first and diagnose from the history.

---

## WebSocket mass disconnect

**Alert:** `WebSocketCollapse`

A sharp drop in `ironlink_websocket_connections`.

- **The gauge decrements in a `finally`,** so it does not drift upward from
  crashed handlers. A drop is real.
- **After a deploy:** expected. Every connection is dropped and clients
  reconnect. It should recover within a minute or two. If it does not, clients
  are failing to reconnect — check for an error in the connect path.
- **Without a deploy:** the fan-out path is Redis pub/sub. Check
  `/health/ready`.

Messages are not lost while clients are disconnected — they are stored and the
recipient gets a push. A disconnect is a degradation, not data loss.

---

## Elevated error rate

**Alert:** `ErrorRate`

```promql
topk(5, sum by (route) (rate(ironlink_http_requests_total{status=~"5.."}[5m])))
```

`ironlink_unhandled_exceptions_total` counts handlers that raised, which
separates "our bug" from "a dependency returned an error we handled".

If it is concentrated on one route and a deploy preceded it, roll back.

---

## Killing a feature

**When:** a shipped capability is actively harming users and a fix is not
minutes away. This is the lever that did not exist until 2026-08-18, when nine
shipped capabilities could only be disabled by deploying — which on the free
tier means minutes of downtime and a cold start, at exactly the moment you can
least afford them.

The switch lives in Redis, so it takes effect without a deploy.

```bash
redis-cli SET feature:messaging "general:killed"
```

Clients pick it up within a minute — `/features` is cached for 60 seconds.

**To undo:**
```bash
redis-cli DEL feature:messaging
```
Deleting the key restores the compiled default. Setting it back to `general`
would work too, but deleting is better: it leaves no override to be puzzled over
later.

**To narrow a rollout instead of killing it:**
```bash
redis-cli SET feature:ai_features "limited:10"
```

| Flag key | What it turns off |
|---|---|
| `messaging` | Direct encrypted messaging |
| `group_messaging` | Group messaging |
| `attachments` | Encrypted attachment upload and download |
| `voice_notes` | Voice notes |
| `contact_discovery` | Salted-hash contact discovery |
| `controlled_group_entry` | Join requests, forms, entry audit |
| `security_center` | IronShield |
| `keyword_alert` | IronWatch |
| `scam_intelligence` | Scam and link warnings in the bubble |
| `communities` | Communities and channels (already BETA) |
| `ai_features` | Summarise, translate, smart reply |

**Three things to know before you rely on this.**

**A kill does not reach a device that is offline.** It arrives when the device
next reaches the server. There is no push channel for flags, deliberately —
that would be a second mechanism to keep correct.

**A killed feature stays killed even when the flag service is unreachable.**
The client caches the last state it saw, and the fallback rule only applies to
flags it has never resolved. So a kill survives the server going down after it.

**The reverse is also true and is the important half.** A feature at `general`
that the client cannot resolve stays *on*. That is deliberate: the alternative
makes this system a bigger outage risk than everything it protects, since one
unreachable endpoint would disable messaging for every user. If you need a
feature off for someone whose device cannot reach the server, you cannot do it
from here, and nothing else can either.

---

## Rolling back

Render redeploys a previous commit from the dashboard. What needs thinking
about is the database.

**Migrations are additive by policy** (expand → migrate → contract), so a
rollback of application code against a migrated schema is normally safe: the
new columns are simply unused by the old code.

**The exception is a contract step** — a migration that drops or renames. Never
roll back application code past a contract migration; restore from a backup
instead. This is the reason the policy exists.

Before rolling back, check whether the deploy included a migration:
```bash
git log --oneline -- alembic/versions | head -5
```

---

## Suspected compromise

Not a performance incident. Different rules.

1. **Do not restart the service.** It destroys process state that may be the
   only evidence.
2. **Rotate `METRICS_TOKEN` first.** It is the one credential that exposes
   operational data over plain HTTP.
3. **`/auth/security-events`** records authentication actions per user. It is
   scoped to the caller by design — there is no cross-user view, and adding one
   under time pressure would be building a surveillance capability during an
   incident.
4. **E2EE limits the blast radius, and knowing exactly how much matters.**
   Server compromise exposes: who messages whom, when, how often, and message
   sizes. It does not expose message content, and it does not expose
   attachment bodies — those are encrypted on the device and the server never
   holds a key.
5. **Say this accurately to users.** "Your messages are safe" is true;
   "nothing was exposed" is not. Metadata was.

---

## After an incident

The standard requires the runbook to exist before the incident, not after — so
what gets added afterwards is only what was actually learned.

- Add the specific check that would have found it faster, not a general note.
- If an alert did not fire, fix the alert before the code.
- If an alert fired and was ignored, the threshold is wrong. A muted alert is
  worse than a missing one, because the dashboard still shows it as covered.
- Record what was ruled out and how. The next person's first ten minutes are
  the ones this saves.
