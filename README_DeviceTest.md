# Two-Device Message Test — Runbook

Verifies a real message travelling phone → server → phone over the production
code path (PostgreSQL + Redis Pub/Sub + WebSocket), not a mock.

## 0. Prerequisites checklist

| Item | Status on this machine | Action |
|---|---|---|
| Docker Desktop | installing | reboot after install completes |
| Flutter SDK | ✔ `C:\tools\flutter` | — |
| Android SDK / adb | ✔ `%LOCALAPPDATA%\Android\Sdk` | — |
| Phone visible to adb | ✖ **not detected** | see §1 |
| PC LAN IP | `10.140.128.63` | re-check if your Wi-Fi changes |

## 1. Make the phone visible to adb

`adb devices` currently returns an empty list, so the phone cannot receive a
build. On the phone:

1. **Settings → About phone** → tap **Build number** 7 times (enables Developer options).
2. **Settings → System → Developer options** → turn on **USB debugging**.
3. Pull down the notification shade → tap the USB notification → change from
   **Charging this device** to **File transfer (MTP)**.
   *(In "charging only" mode Windows never exposes the ADB interface — this is
   the single most common cause of an empty device list.)*
4. Re-plug the cable. A dialog **"Allow USB debugging?"** appears on the phone →
   check *Always allow from this computer* → **Allow**.

Then verify:

```powershell
& "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe" devices -l
```

You should see a serial with `device` (not `unauthorized`, not `offline`).
If it says `unauthorized`, the dialog in step 4 was not accepted.

> If the cable is charge-only (common with cables bundled with power adapters),
> no setting will help — swap to a data-capable cable.

## 2. Bring the stack up

```powershell
cd F:\\Projects\\IronLink
copy .env.example .env     # then edit: set every *_PASSWORD, SECRET_KEY, DB_ENCRYPTION_KEY
bash scripts/generate_ssl.sh
docker compose up -d --build
docker compose exec api alembic revision --autogenerate -m "sprints 0-3 schema"
docker compose exec api alembic upgrade head
docker compose exec api python -m scripts.seed_dev_users
```

Seeded accounts:

| Phone | Name | Military ID | Role |
|---|---|---|---|
| `+201000000001` | الرائد أحمد سالم | `MIL-1001` | officer |
| `+201000000002` | النقيب خالد منصور | `MIL-1002` | officer |
| `+201000000009` | المشرف العام | `MIL-0000` | superadmin |

Health check from the PC:

```powershell
curl.exe -k https://localhost/health
```

## 3. Let the phone reach the PC

The phone is not on `localhost` — it must hit the PC's LAN IP, and both must be
on the **same Wi-Fi network**.

Allow the API port through Windows Firewall (one time, run as admin):

```powershell
New-NetFirewallRule -DisplayName "IronLink API dev" -Direction Inbound `
  -Protocol TCP -LocalPort 8000 -Action Allow -Profile Private
```

Confirm from the phone's browser: `http://10.140.128.63:8000/health`
should return JSON. If it does not, the two devices are not on the same
network, or the firewall rule did not apply.

> **Why plain HTTP for the device test:** the dev certificate is self-signed and
> Android rejects it. `network_security_config.xml` permits cleartext **only**
> for `10.140.128.63`, `10.0.2.2`, and `localhost` — production stays TLS-only.
> Delete that `<domain-config>` block before any release build.

## 4. Install on the phone

```powershell
cd F:\\Projects\\IronLink\frontend
flutter run --dart-define=API_HOST=10.140.128.63 --dart-define=API_PORT=8000 --dart-define=USE_TLS=false
```

For the **second** client, use either a second physical phone or an emulator
(the emulator reaches the host via `10.0.2.2`, which is the built-in default):

```powershell
flutter emulators --launch <emulator_id>
flutter run -d emulator-5554
```

## 5. Log in (both clients)

1. Enter the phone number → **إرسال رمز التحقق**.
2. Fetch the OTP — the SMS gateway never logs codes, by design:
   ```powershell
   docker compose exec api python -m scripts.dev_get_otp +201000000001
   ```
3. Enter the 6 digits → the military-ID step appears automatically.
4. Enter `MIL-1001` (or `MIL-1002`) → **تأكيد الدخول**.

## 6. The actual test

With client A logged in as أحمد and client B as خالد:

| Step | Expected |
|---|---|
| A opens the chat with خالد and starts typing | B sees **"الرائد أحمد سالم يكتب"** with 3 pulsing gold dots |
| A sends "تم استلام الأمر" | Bubble on A: clock → **✓ grey** within ~10 ms |
| Message reaches B | A's tick becomes **✓✓ grey** (delivered) |
| B has the room open | A's tick turns **✓✓ GOLD with glow** (read) |
| A long-presses the bubble → حذف لدى الجميع | Both sides render "تم حذف هذه الرسالة" |
| A sends a photo via 📎 | Preview + caption screen → gold progress bar → arrives on B |
| B force-closes the app, A sends again | B gets an FCM push (requires `google-services.json`) |

Server-side confirmation:

```powershell
docker compose logs -f api          # frame handling
docker compose exec redis redis-cli -n 0 monitor    # live PUBLISH to chan:user:*
```

## 7. Backend-only smoke test (no phone needed)

Useful to prove the engine works while the phone issue is being sorted:

```bash
# request + fetch OTP, then verify to get $ACCESS (see §5)
TICKET=$(curl -s -X POST http://localhost:8000/api/v1/auth/ws-ticket \
  -H "Authorization: Bearer $ACCESS" | jq -r .ticket)
wscat -c "ws://localhost:8000/ws/chat?ticket=$TICKET"
> {"type":"text","to":"<peer-uuid>","content":"اختبار","client_ref":"r1"}
```

Two `wscat` sessions with two different users reproduce the full delivery path.

## Troubleshooting

| Symptom | Cause |
|---|---|
| `adb devices` empty | USB debugging off, or USB mode = charging only, or charge-only cable |
| `unauthorized` | RSA prompt not accepted on the phone |
| App shows "تعذر الاتصال بالخادم" | Wrong `API_HOST`, firewall rule missing, or phone on a different network |
| Login always fails | OTP expired (5 min) or wrong military ID — codes burn after 5 failed attempts |
| WS connects then drops instantly | Ticket already consumed — tickets are strictly one-use, 30 s |
| No push notifications | `google-services.json` missing, or `FIREBASE_CREDENTIALS_FILE` unset server-side |
