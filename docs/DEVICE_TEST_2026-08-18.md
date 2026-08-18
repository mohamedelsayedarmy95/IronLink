# Device Test — 2026-08-18

The first time this application has run on real hardware.

**Device:** Honor 8X (JSN-L22), Android 10 / API 29, arm64-v8a, 3.7 GB RAM with
230 MB free at test time. A 2018 mid-tier phone, which is the hardware profile
the code comments have been claiming to care about.

**Build:** release APK, R8 enabled, pointed at the deployed backend.

---

## Why this mattered more than another test file

The suite had 1,064 passing tests and a green five-job pipeline. Neither could
see either of the two failures below, and both would have reached a user.

CI *builds* the release APK on every push. It had never once *started* it.

---

## Findings

### 1. The release APK did not start — CRITICAL, fixed

```
FATAL EXCEPTION: main
Unable to get provider com.google.mlkit.common.internal.MlKitInitProvider:
Unsatisfied dependency for component
  Component<[com.google.mlkit.vision.text.internal.zzo]>
  ... com.google.mlkit.common.sdkinternal.d
```

R8 removed a class ML Kit resolves through its dependency-injection graph at
runtime. The existing keep rules held the text-recognition half of that graph
and not the common half it depends on. The app died before any Dart ran.

Unit tests do not run R8 and do not run on Android, so nothing in the suite
could have caught it.

Fixed in `android/app/proguard-rules.pro`, deliberately broadly: a DI graph is
where narrow keep rules fail one edge at a time, and the next edge would have
been found the same way — by an app that will not start, on somebody's phone.

### 2. Losing the network signed the user out — HIGH, fixed

With the app signed in, cutting WiFi and mobile data and relaunching produced
the welcome screen. Not an error — a sign-in wall.

`restoreSession` kept the tokens on a network failure and said so in a comment,
then returned `null` anyway, because `AuthUser?` cannot carry three answers.
Signed in, not signed in, and cannot check right now were squeezed into two.

It defeated the offline-first design at the front door: the cached
conversations, the durable outbox, and the banner promising "your messages will
send when you are back" were all behind a wall that appeared exactly when the
network went away.

Fixed by caching the verified profile and returning it when the server is
unreachable. A 401 still clears everything, because rejected is not unreachable.

**Verified on the device:** online launch to populate the cache, network cut,
cold start in 1.286 s onto the home screen with the offline banner showing.

### 3. Two buttons that do the same thing — MINOR, open

"Get Started" and "Sign in" on the welcome screen both lead to the identical
"Secure Sign-In" screen. They look like a choice and are not one.

### 4. APK size — open

130.5 MB, dominated by ML Kit and the bundled tessdata. Worth a decision:
on-demand model download would cut it substantially, at the cost of the OCR
pipeline needing a network on first use.

---

## Measurements

`docs/SLO.md` has said EVIDENCE NOT AVAILABLE for every performance claim since
it was written. These are the first real numbers.

| Measurement | Result | Against |
|---|---|---|
| Cold start, warm backend | **1.9–2.1 s** | budget 2.5 s ✅ |
| Cold start, no network | 1.27 s | — |
| Cold start, first ever launch | 10.2 s | dex optimisation, once |
| Cold start after data wipe | 5.6 s | asset extraction |
| Release APK | 130.5 MB | — |
| Backend `/health` cold start | **54.2 s** | exactly what SLO.md warned about |
| Backend `/health/ready` | 116.3 s | queued behind the cold start |
| Backend `/api/v1/features` warm | 2.35 s | — |

The backend also confirmed that migrations 0011 and 0012 applied in production,
and that `/health/ready` reports `{"database":"ok","redis":"ok"}`.

---

## What was verified working

- Release build starts, runs, and survives (after finding 1)
- Session restore from stored tokens
- **Full sign-in from a wiped install**: welcome → phone → Firebase SMS
  verification → backend token exchange → home screen. This path had never been
  exercised on hardware.
- Offline cold start with the connection banner (after finding 2)
- Empty state rendering
- Two instances side by side via `-PtestInstance=true`

## What is still untested on hardware

- Sending a message, and everything downstream of it: delivery, read receipts,
  typing indicators, reply, reactions
- The metadata scrubber against a photo from this phone's camera — the unit
  fixtures are built byte by byte and cannot represent a real camera file
- Arabic OCR on device
- The durable outbox across a WiFi-to-mobile handover mid-send
- Battery and memory over a sustained session

All of these need a second signed-in account. The blocker is credentials, not
capability: the second test number reached Firebase verification successfully
and was refused at the military-ID second factor.
