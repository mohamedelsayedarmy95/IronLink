# Firebase setup — prompt for Claude in Chrome

Paste everything between the rules into Claude in Chrome, with the Firebase
Console open and signed in.

It is written against the **live** project this app already uses, so it leads
with what must not be touched. The tasks are ordered by what actually blocks
IronLink today, not by where they appear in the console.

---

You are configuring a live Firebase project for a production Android app. The
deployed app authenticates real sessions through it right now, so a wrong change
signs people out or breaks sign-in.

## The project

- **Project:** `ironlink-1fd4c` (number `656160290201`)
- **Console:** https://console.firebase.google.com/project/ironlink-1fd4c

Two Android apps are registered, and **both are in use**:

| Package | What it is |
|---|---|
| `com.ironlink.app` | The real app |
| `com.example.ironlink` | A second build installed side by side for two-account testing. Not dead. Do not remove it. |

## Rules

1. **Never delete an app, a client, or a phone number** without asking me first.
2. **Never regenerate, rotate or revoke an existing key.** The deployed backend
   and the installed app are using them.
3. **Never paste a service-account JSON, a private key, or an API key into this
   chat.** If a task produces one, tell me it is ready and where it is, and I
   will move it myself.
4. **Do not enable anything that starts billing** — no Blaze upgrade, no paid
   product — without asking.
5. If a setting is already correct, say so and move on. Do not re-apply it.
6. Report what you actually saw on each screen, not what you expected to see.

## Task 1 — Phone Auth test numbers (highest priority)

**Authentication → Sign-in method → Phone → Phone numbers for testing**

Confirm both of these exist with verification code `123456`:

- `+201099695779`
- `+201128108020`

If either is missing or has a different code, add or correct it.

**Why this is first:** these are the only way to sign in during testing without
a real SMS, and one of them is currently failing further down the flow. I need
to know whether Firebase's half is correct before looking at the backend's.

Also confirm on the same page that **Phone** is *Enabled*.

## Task 2 — SHA certificate fingerprints

**Project settings → General → Your apps**

For **each** of the two Android apps, check the SHA fingerprint list contains:

```
SHA-1    A0:FC:23:AC:84:C5:72:B8:F8:1C:E1:A2:87:95:D8:B2:0F:C2:4B:C7
SHA-256  DF:F4:D6:99:5E:B5:BF:15:29:BD:DD:0C:65:5A:E1:6B:DB:41:67:43:9C:09:2A:DC:E7:5E:C5:30:6F:F6:4D:F2
```

Add whichever is missing, to whichever app is missing it.

**Why:** that is the Android debug signing certificate, and both builds are
currently signed with it. Phone Auth uses it for Play Integrity verification; an
app whose certificate is not registered falls back to a reCAPTCHA web flow or
fails outright. `com.example.ironlink` is the newer registration and is the more
likely one to be missing it.

Tell me how many fingerprints each app had **before** you changed anything.

## Task 3 — Is there an iOS app at all?

**Project settings → General → Your apps**

Report whether an **iOS** app exists. I believe there is none.

If there is none, **do not create it yet** — tell me, and I will decide. The iOS
side of this codebase has never been built and creating the app is only useful
once it is.

If one *does* exist, report its bundle ID and whether an **APNs authentication
key** is uploaded under **Cloud Messaging**.

## Task 4 — Cloud Messaging, for the backend

**Project settings → Cloud Messaging**

Report:
- Whether the **Firebase Cloud Messaging API (V1)** is enabled
- Whether any **service accounts** are listed

**Do not download or create a service-account key.** The backend needs one as
the `FIREBASE_CREDENTIALS_JSON` environment variable, but that is a credential
and it goes from the console into the hosting provider's environment settings
directly — never through a chat window, never into a git repository. Just tell
me the current state.

## Task 5 — Authorized domains

**Authentication → Settings → Authorized domains**

Report the list. Say specifically whether `ironlink-api.onrender.com` is on it.

## Task 6 — App Check status

**App Check**

Report whether it is enforced for any product, and for which. Do not enable or
enforce anything — turning App Check on without registering the app's attestation
provider first locks the live app out of its own backend.

---

## What to give me at the end

A short report, in this shape:

```
Task 1  Phone test numbers   [done / already correct / problem: ...]
Task 2  SHA fingerprints     [what each app had before, what you added]
Task 3  iOS app              [exists / does not exist]
Task 4  Cloud Messaging      [API state, service accounts count]
Task 5  Authorized domains   [the list]
Task 6  App Check            [enforced or not, for what]
```

Plus anything that looked wrong, misconfigured, or surprising that I did not ask
about. That last part is the most useful thing you can tell me.
