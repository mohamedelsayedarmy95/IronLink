# Sprint 3 — Media Engine, Groups & the Ops Room

## 1. Chunked resumable media upload

```
POST /api/v1/media/upload/init          {filename, mime_type, total_size}
  → {upload_id, chunk_size: 5MiB, total_chunks}

PUT  /api/v1/media/upload/{id}/chunk/{n}      (raw bytes)   ×N — any order
GET  /api/v1/media/upload/{id}                → {received_chunks, missing_chunks}   ← RESUME POINT
POST /api/v1/media/upload/{id}/complete       → {media_key, thumbnail_key}
GET  /api/v1/media/{key}/url                  → 5-minute pre-signed URL
```

- **Resume**: after a dropped connection the client calls the status endpoint
  and re-sends only `missing_chunks`. Upload state lives in Redis for 24 h.
- `# Fable5-Enhancement`: chunks are staged **directly in MinIO**
  (`staging/{upload_id}/{n}`), not on API-server disk — any replica can accept
  any chunk, so resumable uploads survive load balancing and pod restarts with
  zero sticky sessions.
- **Images**: recompressed at JPEG q85 (visually lossless for print) only when
  it actually shrinks the file, plus a 320px thumbnail.
- **Video thumbnails**: deliberately deferred to a future ffmpeg worker
  container — transcoding inside the API process would starve the event loop.
- Client (`MediaService` in Flutter) shows a gold progress bar and resumes
  automatically.

## 2. Group permissions (تفوق واتساب)

| Role | Post | See | Manage members | Icon in UI |
|---|---|---|---|---|
| `owner` | ✔ | ✔ | ✔ | ★ gold |
| `admin` | ✔ | ✔ | ✔ | ★ gold |
| `moderator` | ✔ | ✔ | ✖ | — |
| `member` | ✔* | ✔ | ✖ | — |
| `observer` | ✖ **never** | ✔ | ✖ | 👁 grey |

\* In an **announcement group** (`is_announcement_group = true`) only
`admin`/`owner` can post — members are read-only.

- `join_approval_required` (default **true**): joining creates a
  `GroupJoinRequest`; a group admin approves/rejects via
  `POST /groups/{gid}/join-requests/{rid}` — mirroring formal-workplace flow.
- `# Fable5-Enhancement`: `observer` is a new read-only rank for oversight
  officers; enforced server-side by `GroupMember.can_post()`, not just hidden UI.

## 3. The Ops Room (لوحة التحكم)

**Location:** `ironlink_admin/` — plain HTML/CSS/JS, **no build step**.

`# Fable5-Enhancement` — it is a separate app, NOT a tab in the messenger:
1. Deployable behind an IP-restricted Nginx location or VPN:
   ```nginx
   location /ops/ {
       allow 10.20.0.0/24;   # ops subnet only
       deny all;
       alias /srv/ironlink_admin/;
   }
   ```
2. Zero admin code ships inside the APK (nothing to reverse-engineer).
3. Dependency-free static files — no npm supply-chain surface.

**Running it locally:**
```bash
cd ironlink_admin
python -m http.server 8080
# open http://localhost:8080 — paste a superadmin access_token to enter
# (optional) point at a non-default API:
#   localStorage.setItem('mil_api_base', 'https://your-host/api/v1')
```

**Features (all backed by real endpoints):**
| Screen | Endpoint | Notes |
|---|---|---|
| الإحصائيات | `GET /admin/stats` | auto-refresh 10 s; online-now from Redis, storage from indexed DB aggregate |
| المستخدمون | `GET /admin/users` | filter by department/status + name/phone search |
| تعطيل/تفعيل | `POST /admin/users/{id}/status` | **reason mandatory** (≥5 chars) → audit log; suspend also bumps `token_version` (all devices die instantly) + live `account_suspended` WS frame |
| إشعار عاجل | `POST /admin/broadcast` | targets all or one department; WS frame to online devices + FCM to offline; shows delivered counts |

## 4. Urgent broadcasts (client behaviour)

A broadcast appears as a **red banner with gold trim pinned above all
conversations** on every device. It does not disappear until the user taps it,
reads the full text, and presses "علمت" — which calls
`POST /broadcasts/{id}/ack`. Unacked broadcasts are re-fetched on every app
launch (`GET /broadcasts/unacked`), so restarting the app never clears one.

## 5. Push notifications (FCM)

- **Backend** (`app/services/push_service.py`): Firebase Admin SDK, lazy-init
  from `FIREBASE_CREDENTIALS_FILE` (unset = pushes no-op, dev-friendly). When a
  DM arrives for an **offline** recipient (checked against the Redis presence
  registry), an FCM push goes out with the sender's name + 80-char preview and
  `{kind: "dm", peer_id}` data.
- **App** (`lib/core/push_service.dart`): requests permission, registers the
  token via `POST /broadcasts/fcm-token` (re-registered on FCM rotation),
  and routes notification taps straight into the conversation (terminated,
  background, and foreground cases handled).
- **Setup**: place the Firebase service-account JSON on the server and set
  `FIREBASE_CREDENTIALS_FILE=/path/to/sa.json`; add `google-services.json` to
  `frontend/android/app/` (kept out of git).

## 6. Role permission matrix (system-wide)

| Capability | soldier | nco | officer | admin | superadmin |
|---|---|---|---|---|---|
| DM / group messaging | ✔ | ✔ | ✔ | ✔ | ✔ |
| Create groups | ✔ | ✔ | ✔ | ✔ | ✔ |
| Ops panel access | ✖ | ✖ | ✖ | ✔ | ✔ |
| Suspend/activate users | ✖ | ✖ | ✖ | ✔ (not superadmins) | ✔ |
| Urgent broadcast | ✖ | ✖ | ✖ | ✔ | ✔ |

## 7. Database migration

New in this sprint: `users.department`, `users.fcm_token`,
`groups.is_announcement_group`, `groups.join_approval_required`,
`group_join_requests`, `broadcasts`, `broadcast_acks`.

```bash
docker compose exec api alembic revision --autogenerate -m "sprint3 media groups admin"
docker compose exec api alembic upgrade head
```

## Verification status

- Backend: compiles clean, 43 unit tests green.
- Frontend: `flutter pub get` resolves (incl. firebase_messaging, image_picker,
  record), `flutter analyze` — no issues.
- Ops panel: static files load and parse (page title verified in browser);
  full data flows need the Docker stack + a superadmin token.
