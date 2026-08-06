# IronLink Architecture Blueprint

> **Goal:** Transform the existing IronLink codebase into the world's most secure, scalable, and feature‑rich social‑messaging platform while running on **100% free, open‑source software**.

---

## 1. System Overview

IronLink is a **client‑server** messaging system that provides:

- End‑to‑end encrypted (E2EE) direct messages and group chats  
- Self‑destructing media & texts (dual‑layer: DB column + Redis keyspace events)  
- Military‑grade identity verification (hashed military ID, device fingerprint)  
- Real‑time presence, typing indicators, read receipts, and reactions  
- Push notifications for background/terminated clients (WebSocket + Firebase FCM free tier)  
- Media storage with on‑the‑fly signing and size limits  
- Immutable audit trail with row‑level security and JSONB before/after snapshots  
- Horizontal scalability via simple Docker Compose (stateless services)  

All components run on **free, open‑source software**—no commercial licences or paid SaaS dependencies.

---

## 2. Core Components

| Layer | Technology (Free) | Responsibility |
|-------|-------------------|----------------|
| **Client** | Flutter (Dart) + `flutter_secure_storage` + `dio` + `web_socket_channel` + `firebase_messaging` (FCM) | UI, local token storage, REST/WebSocket APIs, background push handling |
| **API Gateway** | **Nginx** (reverse proxy) | TLS termination (via certbot/letsencrypt), HTTP/2, request logging, basic WAF, rate limiting |
| **Service Mesh** | *None* (direct communication over Docker network) | — |
| **API Server** | **FastAPI** (Python 3.12) + Uvicorn workers | REST endpoints, WebSocket chat server, authentication, token versioning, business logic, OCR Intelligence Engine |
| **Background Workers** | Python asyncio (embedded in FastAPI via lifespan) | Self‑destruct sweep, OTP cleanup, media garbage collection, OCR processing (via BackgroundTasks) |
| **Database** | **PostgreSQL 16** + `pgcrypto` + `btree_gin` + `pg_trgm` | Primary relational store (users, sessions, messages, groups, audit logs) |
| **Cache / PubSub** | **Redis** (7.x) | OTP cache, WebSocket session registry, keyspace notifications for self‑destruct, rate‑limit counters, OCR keyword caching |
| **Object Storage** | **MinIO** (AGPLv3) | Encrypted (SSE‑S3) storage of avatars & attachments; pre‑signed URLs (15 min) |
| **Push Service** | **Firebase Cloud Messaging (FCM)** (free tier) + WebSocket | Register device tokens, send push to Android/iOS/web via FCM; fallback to in‑app WebSocket alerts |
| **Observability** | **Prometheus** (metrics) + **Grafana** (dashboards) (optional, lightweight) | System health, latency, error rates |
| **CI / CD** | **GitHub Actions** (free) | Lint, test, build Docker images, deploy via Docker Compose |
| **Secret Management** | **SOPS** + **age** (encrypted Git‑secrets) or **HashiCorp Vault** (community edition) | Store DB passwords, encryption keys, JWT secrets, MinIO credentials |
| **Orchestration** | **Docker Compose** (production) | Deploy all services as containers, simple scaling via `docker compose up --scale` |

*Optional enhancements (still free):*  
- **cAdvisor** for container metrics.  
- **Trivy** for container image scanning in CI.  

---

## 3. OCR Intelligence Engine

When any file is uploaded (image, PDF, Word, Excel, or any text‑based document), the system automatically extracts text, searches for user‑defined keywords, and triggers an instant alert.

### 3.1 Architecture Diagram (text‑based)

```
[Client] --> (POST /media/upload) --> [Nginx] --> [FastAPI]
                                            |
                                            |---> [Background Task] (OCR Worker)
                                            |        |
                                            |        |---> [Tesseract OCR] / [HuggingFace model]  --> Extracted Text
                                            |        |        |
                                            |        |        |---> Keyword Match (user‑defined set)
                                            |        |                |
                                            |        |                |---> If match --> [Redis] (store alert flag + file_id)
                                            |        |                |
                                            |        |                |---> Publish to Redis channel "ocr:alerts"
                                            |        |
                                            |        |---> [FastAPI] (WebSocket broadcast) --> [Client] (in‑app toast)
                                            |        |
                                            |        |---> [FCM Push] (via Firebase) --> [Device] (notification)
                                            |
                                            |---> [MinIO] (store original file)
                                            |
                                            |---> [PostgreSQL] (metadata: file_id, uploader, timestamp, file_type)
```

### 3.2 Processing Flow

1. **Upload** – Client sends multipart/form‑data to `/media/upload`. Nginx terminates TLS and forwards to FastAPI.
2. **Metadata Persist** – FastAPI stores file record in PostgreSQL (file_id, uploader, mime_type, size, `ocr_processed=false`) and saves the binary to MinIO (SSE‑S3).
3. **Async OCR** – FastAPI adds a BackgroundTask (or uses a lightweight async worker) that:
   - Retrieves the file from MinIO.
   - Runs OCR:
     - For images: `tesseract` CLI (free) or a HuggingFace model (`pytorch` + `transformers`).
     - For PDF/DOCX/XLSX/TXT: extract text via `pypdf2`, `python-docx`, `openpyxl`, or plain read.
   - Normalizes text (lowercase, remove punctuation).
   - Checks against a **per‑user keyword set** stored in Redis (hash `user:<uid>:ocr_keywords`).
   - If any keyword found:
        - Sets a flag in Redis: `ocr:alert:<file_id>` = 1 with short TTL (e.g., 5 min).
        - Publishes a message on Redis channel `ocr:alerts` with `{file_id, user_id, keyword}`.
   - Marks record in PostgreSQL `ocr_processed=true` (optional).
4. **Alert Delivery** – Two parallel paths:
    - **WebSocket** – FastAPI subscribes to `ocr:alerts` (via Redis pub/sub) and pushes a JSON frame to the uploader’s WS connection: `{type: "ocr_alert", file_id, keyword}`.
    - **Push Notification** – FastAPI calls Firebase Admin SDK (free tier) to send a data‑only notification containing the same payload; the Flutter client shows a toast or badge.
5. **Client Response** – Upon receiving the alert, the client displays a non‑intrusive ticker/toast: “Keyword ‘urgent’ found in uploaded file X.pdf”.

### 3.3 Implementation Notes

- **Free OCR** – Tesseract OCR supports 100+ languages; Dockerfile installs `tesseract-ocr` and language packs (`eng`, `ara` etc.).
- **Keyword Management** – Users can add/remove keywords via Settings → OCR Keywords; stored as a Redis set per user.
- **Debounce** – Alerts are rate‑limited per user (e.g., max 1 per 30 s) to avoid spam.
- **Scalability** – OCR is CPU‑intensive; the background worker can be scaled by running multiple FastAPI workers (Uvicorn) or by adding a dedicated worker service using the same image but with env `OCR_WORKER=true`. In Docker Compose we can define a separate service `ocr-worker` that shares the same codebase but only runs the OCR loop.

---

## 4. Data Flow

### 4.1 User Registration & Login
1. **Client** → POST `/auth/request-otp` (phone) → server sends OTP via Redis‑backed service.  
2. **Client** → POST `/auth/verify` (phone, OTP, military ID, device fingerprint) → server:  
   - Validates OTP (Redis TTL),  
   - bcrypt‑hashes military ID (never stored plain),  
   - issues JWT access token (30 min) + refresh token (256‑bit random, SHA‑256 stored).  
   - JWT embeds `token_version`; incrementing this column forces global logout.  
3. Tokens stored in **Flutter Secure Storage** (Keystore/Keychain).  
4. Client opens a **WebSocket** connection via `/auth/ws-ticket` → ticket‑based WS to `/ws/chat`.

### 4.2 Message Sending (E2EE)
1. Client generates a random **Message Key** (AES‑256‑GCM) per conversation (derived from Signal‑like X3DH after initial key exchange).  
2. Plaintext → encrypt → `content_ciphertext`.  
3. Media (if any) → chunked resumable upload to MinIO via `/media/upload/*` → returns `media_key`.  
4. Client sends JSON over WS: `{type: "text|image|…", to: peerId/groupId, content: ciphertext, media_key:…, client_ref: uuid}`.  
5. Server:  
   - Persists minimal metadata (sender, recipient/group, timestamps, `destruct_at` if self‑destruct, `media_key`, `mime_type`, `size`).  
   - Persists **only ciphertext** — never plaintext.  
   - Broadcasts frame to recipient(s) via WS (if online) **and** publishes a push notification via UnifiedPush (FCM) *or* WebSocket alert (see OCR).  
6. Receiver decrypts locally with the conversation key.

### 4.3 Self‑Destruct (Dual Layer)
- **Database:** Column `destruct_at` (UTC timestamp). A periodic worker (`SelfDestructWorker`) scans `ix_msg_destruct` every minute, deletes media from MinIO, wipes `content_ciphertext`, sets `is_destructed=true`, writes audit log entry.  
- **Redis Keyspace:** On message insert, server sets a Redis key with TTL = (`destruct_at` - now) and enables `notify-keyspace-events KEx`. When TTL expires, Redis publishes a `__keyevent@<db>__:expired` message; the worker (or a separate Redis subscriber) immediately triggers the same wipe path, guaranteeing removal even if the DB sweep laggs.

### 4.4 Media Handling
- Uploads are **chunked**, resumable, and stored server‑side with SSE‑S3 encryption.  
- View URLs are short‑lived (15 min) pre‑signed URLs generated on demand (`/media/<key>/url`).  
- Thumbnails generated client‑side (or via MinIO Lambda‑like `mc` script) and stored similarly.

### 4.5 Group Management
- Standard CRUD via REST (`/groups/*`).  
- Membership changes broadcast via WS to online members; offline members receive push + sync on next WS reconnect.  
- Permission checks (admin/owner) performed server‑side; all changes immutably logged to `audit_logs`.

### 4.6 Audit & Compliance
- Every mutating action writes an `AuditLog` row via the `audit_writer` role (INSERT‑only).  
- `before_state` / `after_state` JSONB capture full row snapshots.  
- Row‑level Security (RLS) prevents `UPDATE`/`DELETE` even if application code is compromised.  
- Archived monthly to cold storage (S3‑compatible bucket) via `pg_cron` → no row deletion, only move to cheaper tier.

---

## 5. Security Strategy

| Pillar | Mechanism |
|--------|-----------|
| **Transport Security** | Nginx enforces **TLS 1.3 only**, HTTP/2, HSTS preload, OCSP stapling, `Referrer‑Policy: no‑referrer`, `Permissions‑Policy`, `Content‑Security‑Policy`. |
| **Authentication** | Phone + OTP + hashed military ID (bcrypt). JWT access tokens short‑lived (30 min). Refresh tokens high‑entropy, only SHA‑256 stored server‑side. `token_version` enables O(1) global logout. |
| **Authorization** | Role‑Based Access Control (RBAC) enforced in API endpoints; service‑to‑service calls via Docker network (no mTLS needed for single‑node). |
| **Data at Rest** | - Military ID & device fingerprint: bcrypt hash (irreversible). <br>- Passwords: bcrypt. <br>- Refresh tokens: SHA‑256 hash. <br>- MinIO objects: SSE‑S3 (server‑side). <br>- Audit logs: immutable via RLS + `audit_writer` role. |
| **End‑to‑End Encryption** | Client‑generated per‑conversation symmetric keys (X3DH + Double Ratchet optional). Server never sees plaintext. |
| **Replay & DoS Mitigation** | - Rate limiting per IP (Nginx `limit_req`). <br>- WebSocket ticket short‑lived (30 s). <br>- OTP attempts limited (Redis‑based counter). <br>- CSRF not relevant (API token in header). |
| **Audit & Forensics** | Immutable audit log; cryptographic hash chaining (optional future). Regular integrity checks. |
| **Secrets Management** | All secrets (DB passwords, JWT secret, MinIO keys, encryption key) stored encrypted in repo via SOPS/age or Vault; injected at runtime as env vars. |
| **Least Privilege** | Containers run as non‑root user (`ironlink` group, `mil_api` user). Docker defaults restrict capabilities. Database roles: `api_user` (CRUD), `audit_writer` (INSERT‑only), `readonly` (SELECT). |
| **Secure Coding** | Dependency scanning (Trivy in CI), SAST (Bandit), DAST (OWASP ZAP) on nightly basis. |
| **Privacy** | GDPR‑style right‑to‑erase: hard delete of user data after cryptographic shredding; audit log retention configurable (e.g., 1 year) then archived. |

---

## 6. Free Scalability Strategy (Docker Compose)

1. **Stateless Services** – FastAPI workers, WebSocket handlers, and background workers store no local state; all state lives in DB, Redis, or MinIO.  
2. **Horizontal Scaling** – Increase replica count via `docker compose up --scale api=<N>`; Nginx does round‑robin load balancing.  
3. **Database Read Replicas** – PostgreSQL streaming replica(s) for read‑heavy workloads (conversation lists, user profiles).  
4. **Sharding (future)** – If traffic > 100k msg/s, introduce logical sharding by `user_id_hash` using application‑level routing or Citus‑like extension.  
5. **Redis** – Single instance for dev; can be clustered with Redis‑Alike (still free) for higher throughput.  
6. **Object Storage CDN** – MinIO server‑side signatures plus optional Cloudflare free tier for caching public assets (avatars, static media).  
7. **WebSocket Efficiency** – Nginx handles WS; server‑side keeps a Redis hash `user_id → [connection_id]` for fan‑out.  
8. **Batch Workers** – Self‑destruct and OTP cleanup run as cron jobs (host cron or separate container) to avoid interfering with request latency.  
9. **Observability‑Driven Scaling** – Prometheus alerts trigger manual scale‑up; Grafana dashboards show per‑endpoint latency, error rates, DB load.  
10. **Geodistribution (optional, still free)** – Deploy identical Docker Compose stacks on multiple free‑tier cloud providers (Oracle, AWS Free Tier, GCP Always Free) and use Cloudflare Load Balancer (free) to route users to lowest latency region. Active‑passive PostgreSQL streaming replication + MinIO bucket replication ensures DR.

---

## 7. Migration Plan from Current System

| Step | Action | Details | Estimated Effort |
|------|--------|---------|------------------|
| **0** | Baseline & CI | Ensure full test coverage, add GitHub Actions for lint/test/build. | 1 wk |
| **1** | Container Hardening | Build multi‑stage Dockerfile (distroless base), add non‑root user, scan images with Trivy. | 3 days |
| **2** | Replace Nginx with Caddy (optional) | If prefer automatic HTTPS, write `Caddyfile`; otherwise keep Nginx + certbot. | 2 days |
| **3** | Confirm Redis replaces DragonflyDB | Update `docker‑compose.yml` and values; verify `notify-keyspace-events KEx` works; benchmark. | 2 days |
| **4** | Add Observability Stack (optional) | Deploy Prometheus, Grafana via Helm or Docker Compose; instrument FastAPI with `prometheus_fastapi_instrumentator`; expose `/metrics`. | 4 days |
| **5** | Implement Firebase FCM Push | Create Firebase project (free), add service account to secrets, implement `PushService` using Firebase Admin SDK. | 1 wk |
| **6** | Update Frontend Push Plugin | Replace custom UnifiedPush with `firebase_messaging` Flutter plugin; adjust token registration and message handling. | 4 days |
| **7** | Secret Management Integration | Migrate `.env` values to SOPS‑encrypted files; add age‑key to CI; inject secrets as Docker secrets or env files. | 3 days |
| **8** | Deploy to Docker Compose (Dev) | Write `docker-compose.yml` for all services (api, redis, postgres, minio, nginx). Use `depends_on` and healthchecks. | 1 wk |
| **9** | Data Migration Procedure | - Dump current PostgreSQL (`pg_dump`), import into new cluster. <br>- Export MinIO buckets (`mc mirror`). <br>- Verify consistency. | 2 days |
| **10** | Cutover & Blue/Green | Route Nginx to new stack via DNS weighted routing; monitor metrics; rollback possible via old DNS. | 2 days |
| **11** | Decompose Legacy Docker‑Compose (if any) | archive old compose; keep for local dev reference only. | 1 day |
| **Total** | | | **�≈ 6 weeks** (parallelizable tasks can reduce wall‑time) |

---

## 8. Conclusion

By adopting the free, battle‑tested stack outlined above and following the migration plan, IronLink will inherit the strong security foundations of the original design while gaining simplicity, zero‑cost operations, and a clear path to scaling—all without sacrificing the core principles of privacy, military‑grade authentication, and immutable auditability. The new OCR Intelligence Engine adds a powerful, value‑added feature that runs asynchronously and leverages the same free infrastructure.
