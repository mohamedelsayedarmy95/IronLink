# Service Level Objectives

> **Status: initial targets.** Every number below is `[ESTIMATE]`. IronLink has
> never run under production load, so nothing here is derived from measurement
> — these are the thresholds the service is being *designed* to, not thresholds
> it is known to meet. The first thirty days of real traffic should replace
> them. A target invented at a desk and never revised is worse than none,
> because it eventually gets quoted as a fact.
>
> The standard's rule applies: **no feature may claim "stable" while a critical
> SLO is in breach**, and a claim about reliability requires a measurement, not
> an intention.

---

## Why these and not others

An SLO is a promise about the thing the user actually experiences. It is
tempting to write objectives for what is easy to measure — CPU, memory, request
counts — but nobody has ever been upset about CPU. The four objectives below
map to the four ways this product fails a person:

| The user's experience | The objective |
|---|---|
| "My message didn't arrive." | Message durability |
| "It's spinning." | Send latency |
| "It logged me out." / "I can't get in." | Authentication availability |
| "That message was supposed to disappear." | Self-destruct timeliness |

The priority order is the standard's: durability and the disappearing-message
guarantee outrank latency, because a slow message is an annoyance and a lost or
lingering one is a broken promise.

---

## SLO 1 — Message durability (critical)

**Objective:** 99.99% of envelopes acknowledged to a sender are retrievable by
the recipient.

**Why it is the top objective:** every other failure is visible and
recoverable. The user sees the spinner, sees the error, retries. A message that
was acknowledged and then lost is invisible to both sides — the sender believes
it was delivered and the recipient never knew to expect it. In a product used
for coordination, that failure mode is worse than an outage, because an outage
is at least legible.

**Measured by:**
```promql
1 - (
  rate(ironlink_unhandled_exceptions_total{route=~".*messages.*"}[1h])
  / rate(ironlink_messages_accepted_total[1h])
)
```

**Honest limitation:** this is a proxy, not the objective. It counts envelopes
that failed *loudly*. Silent loss — a commit that succeeded and a row that
later vanished — is not visible to it. Closing that gap needs a client-side
delivery-gap probe: the recipient notices a hole in the per-sender sequence and
reports the count, never the content. That probe does not exist yet, and until
it does this objective is `[UNVERIFIED — requires validation]`.

**Error budget:** 0.01% per 30 days. Any confirmed loss burns the entire budget
and stops feature work until the cause is found.

---

## SLO 2 — Send latency

**Objective:**

| Percentile | Target |
|---|---|
| p50 | < 150 ms |
| p95 | < 600 ms |
| p99 | < 2 s |

Measured server-side, from request arrival to response, excluding the client's
network.

**Why three percentiles and no mean:** a mean is the one number guaranteed to
hide the problem. A service with a p50 of 40 ms and a p99 of 9 s is broken for
one user in a hundred and has an unremarkable average. The p99 is the objective
that matters; the p50 is there to catch a regression that slows everyone
slightly.

**Measured by:**
```promql
histogram_quantile(0.99,
  sum by (le, route) (
    rate(ironlink_http_request_duration_seconds_bucket[5m])
  )
)
```

**Known caveat:** the free Render plan spins the instance down when idle. A
cold start is tens of seconds and will dominate the p99 on a quiet day. That is
a plan limitation, not a service regression, and this objective is not
meaningful until the service runs on a plan that does not sleep. Recorded here
rather than quietly excluded from the query.

---

## SLO 3 — Authentication availability

**Objective:** 99.9% of `/auth/*` requests succeed (non-5xx) over 30 days.

**Why it is separate from general availability:** every other endpoint degrades
into an inconvenience. Authentication degrades into a locked door. A user who
cannot get in cannot read the messages they already have, cannot report a
problem, and has no route around it — and this is the one flow that depends on
a third party (Firebase) whose availability is not ours to control.

**Measured by:**
```promql
1 - (
  rate(ironlink_http_requests_total{route=~"/api/v1/auth/.*",status=~"5.."}[30d])
  / rate(ironlink_http_requests_total{route=~"/api/v1/auth/.*"}[30d])
)
```

**Deliberately excluded:** 4xx. A rejected OTP is the system working. Counting
it as unavailability would make the metric improve every time the rate limiter
was loosened, which is precisely backwards.

---

## SLO 4 — Self-destruct timeliness (critical)

**Objective:** 99.9% of expiring messages are wiped within 60 seconds of
expiry, and the sweeper backlog returns to zero every cycle.

**Why it is critical rather than best-effort:** this is a promise made in the
interface. A user who sets a message to vanish in an hour has been told it
vanishes in an hour. A sweeper that falls behind does not degrade the feature —
it makes the product's statement to the user false, while the interface goes on
displaying the same statement. That is a privacy failure, not a slow background
job, and it is silent.

**Measured by:**
```promql
max_over_time(ironlink_self_destruct_overdue[10m])          # must return to 0
increase(ironlink_self_destruct_failures_total[1h])         # must be 0
```

**Error budget:** zero tolerance for a sustained non-zero backlog. A single
failed sweep is noise; a backlog that does not clear across two cycles is an
incident.

---

## Alerts

Thresholds are set to fire on a trend, not a spike. An alert that fires on
every transient blip is an alert that gets muted, and a muted alert is worse
than no alert because the dashboard still shows it as covered.

| Alert | Condition | Severity | Runbook |
|---|---|---|---|
| `SelfDestructBacklogGrowing` | `ironlink_self_destruct_overdue > 0` for 10 min | **critical** | [Self-destruct backlog](RUNBOOK.md#self-destruct-backlog) |
| `SelfDestructSweepFailing` | `increase(...failures_total[15m]) > 0` | **critical** | [Self-destruct backlog](RUNBOOK.md#self-destruct-backlog) |
| `AuthErrorRate` | 5xx rate on `/auth/*` > 1% for 5 min | **critical** | [Authentication failing](RUNBOOK.md#authentication-failing) |
| `NotReady` | `/health/ready` non-200 for 3 min | **critical** | [Readiness failing](RUNBOOK.md#readiness-failing) |
| `LatencyP99` | p99 > 2 s for 15 min | warning | [Latency regression](RUNBOOK.md#latency-regression) |
| `WebSocketCollapse` | `ironlink_websocket_connections` drops > 80% in 5 min | warning | [WebSocket mass disconnect](RUNBOOK.md#websocket-mass-disconnect) |
| `ErrorRate` | overall 5xx > 2% for 10 min | warning | [Elevated error rate](RUNBOOK.md#elevated-error-rate) |

**No alert may quote user-identifying data.** An alert body naming the user who
triggered it puts identity into a notification channel — email, chat, a paging
service — that sits entirely outside this system's privacy boundary and retains
it indefinitely. Alerts name routes and rates. The correlation id in
`X-Request-ID` is how a specific report is traced afterwards.

---

## What is not yet an SLO, and why

Recorded rather than omitted, so the gaps are visible:

- **Delivery latency end-to-end** (sent → shown on the recipient's screen).
  The number a user would actually recognise. Needs client-side timing
  reported without a user identifier attached, which is a design problem more
  than an engineering one.
- **Push notification delivery rate.** Blocked on a real defect: `fcm_token` is
  a single column on the user row, so a second device overwrites the first.
  Measuring the rate before fixing that would measure the bug.
- **Media upload success rate on poor networks.** The resumable path exists and
  is untested against real packet loss.
- **Cold-start frequency.** Only meaningful once the service is on a plan that
  does not sleep.
