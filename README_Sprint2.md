# Sprint 2 — Real-Time Messaging Engine

## The life of a message: from tapping "إرسال" to the peer's screen

```
 SENDER DEVICE                    SERVER (any replica)                RECIPIENT DEVICE(S)
──────────────                   ─────────────────────               ────────────────────
 1. tap send
 2. optimistic bubble
    (clock icon, pending)
 3. WS frame ──────────────────▶ 4. persist to PostgreSQL
    {type:"text", to, content,      (messages table, status=sent)
     client_ref:"ref_7"}
                                 5. ack ─────────▶ sender
                                    {type:"ack",
                                     client_ref:"ref_7",
                                     message_id:<uuid>,
                                     created_at:<server time>}
 6. bubble confirmed:
    clock → single grey ✓
    (optimistic id replaced
     by canonical UUID)
                                 7. PUBLISH chan:user:{recipient}
                                    on Redis Pub/Sub
                                          │
                                          ▼
                                 8. EVERY replica holding a socket
                                    for that user relays the frame     9. frame arrives on ALL
                                    (multi-device & multi-server          of the recipient's
                                    for free — see ws_manager.py)         connected devices
                                                                      10. if chat room open:
                                 12. UPDATE messages SET               ◀── {type:"message_delivered"}
                                     status=delivered ──▶ publish      ◀── {type:"message_read"}
                                     receipt to sender's channel
13. sender sees ✓✓ grey
    (delivered) then
    ✓✓ GOLD (read)
```

**Latency profile:** steps 3→9 are one DB INSERT + one Redis PUBLISH — typically
under 10 ms server-side. The DB write happens **before** the publish, so a crash
between them can never produce a message the recipient saw but the DB lost.

## Frame protocol (`/ws/chat`)

| Client → Server | Payload | Effect |
|---|---|---|
| `text` / `image` / `file` | `to`, `content`/`media_key`, `client_ref` | Persist → ack → fan-out |
| `typing_start` / `typing_stop` | `to` | Relayed, never persisted |
| `message_delivered` / `message_read` | `message_id` | DB status update → `receipt` to sender |
| `unsend` | `message_id` | 5-min window; wipe + broadcast `unsend` |
| `ping` | — | Heartbeat; refreshes 90s Redis TTL |

| Server → Client | Meaning |
|---|---|
| `welcome` | Connected; includes `connection_id`, `online_users` |
| `ack` | Your message persisted; canonical id + server timestamp |
| `message` | Incoming message |
| `receipt` | One of your messages was delivered/read |
| `typing_start` / `typing_stop` | Peer typing state |
| `unsend` | Drop this message locally (peer unsend OR self-destruct sweep) |
| `session_revoked` | If it matches *your* `session_id` (from login): disconnect |

## Read-state ticks (تفوّق على واتساب)

- ✓ single grey — persisted server-side (`sent`)
- ✓✓ double grey — reached the recipient's device (`delivered`)
- ✓✓ double **gold** with glow — read (`read`), never downgrades

## Unsend (حذف لدى الجميع)

Long-press your own bubble → "حذف لدى الجميع". Server enforces the **5-minute
window** and sender ownership. `# Fable5-Enhancement`: the row is not
hard-deleted — ciphertext and media pointers are wiped (unrecoverable) but a
tombstone remains, because a military audit trail must prove a message existed
and was retracted, by whom, and when. Both parties' devices receive `unsend`
and render the "تم حذف هذه الرسالة" tombstone.

## Self-destruct worker

`app/services/self_destruct_worker.py` sweeps every 60 s:
`destruct_at <= now AND is_destructed = false` → delete media from MinIO →
wipe content → audit log (`message.self_destructed`, system actor) → publish
`unsend` to both parties. MinIO delete failures leave the row queued for the
next sweep (no orphaned files). Read-triggered timers: a burn-after-reading
message gets its `destruct_at` set at **read** time (`mark_read`).

## Multi-device sessions

- `GET /api/v1/auth/sessions` — every active device (type, IP, city, last active).
- `DELETE /api/v1/auth/sessions/{id}` — remote-kick **one** device: its refresh
  token dies instantly (`revoked_at`) and a targeted `session_revoked` frame
  tells that device's live socket to close. Other devices are untouched
  (`token_version` is deliberately NOT bumped here — that's the nuclear option).
- Login response now includes `session_id` so each client knows which session
  is "this device".

## Presence

`ws:online` (Redis SET) holds user-ids with ≥1 live connection; per-user
connection sets track devices. Sockets that die silently expire out of the
registry in ≤ 90 s via heartbeat TTL. The chats list shows the gold dot from
this set — no DB query involved.

## Verifying two-client delivery (real WebSocket, no simulation)

```bash
# 1. Stack up + migrations + two test users seeded
docker compose up -d --build
docker compose exec api alembic upgrade head

# 2. Terminal A and Terminal B (or two emulators / two browsers):
#    log in as user A and user B, open the chat room
# 3. Type in A → B shows "A يكتب…" with animated gold dots
# 4. Send in A → bubble: clock → ✓ → ✓✓ → gold ✓✓ as B's client acks
# 5. Long-press the message in A → "حذف لدى الجميع" → tombstone appears on BOTH
```

For a quick backend-only check without Flutter, `wscat` works:

```bash
TICKET=$(curl -sk -X POST https://localhost/api/v1/auth/ws-ticket \
  -H "Authorization: Bearer $ACCESS" | jq -r .ticket)
wscat -n -c "wss://localhost/ws/chat?ticket=$TICKET"
> {"type":"text","to":"<peer-uuid>","content":"مرحبا","client_ref":"r1"}
```

## Test status

- Backend: 43 unit tests green (`pytest`), full package compiles.
- Frontend: `flutter analyze` — no issues.
- Two-client end-to-end run requires the Docker stack + seeded users
  (see step-list above); it exercises the real Pub/Sub path, not a mock.
