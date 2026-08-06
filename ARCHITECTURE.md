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
- **Channels** (public/private) for broadcasting content to subscribers
- **Communities** (like Discord/Reddit) with spaces, roles, events, and resources
- **Creator economy** tools for monetization and analytics

All components run on **free, open‑source software**—no commercial licences or paid SaaS dependencies.

---

## 2. Core Components

| Layer | Technology (Free) | Responsibility |
|-------|-------------------|----------------|
| **Client** | Flutter (Dart) + `flutter_secure_storage` + `dio` + `web_socket_channel` + `firebase_messaging` (FCM) | UI, local token storage, REST/WebSocket APIs, background push handling; **Premium UI/UX with glassmorphism, dark/light mode, micro-interactions, and news ticker** |
| **API Gateway** | **Nginx** (reverse proxy) | TLS termination (via certbot/letsencrypt), HTTP/2, request logging, basic WAF, rate limiting |
| **Service Mesh** | *None* (direct communication over Docker network) | — |
| **API Server** | **FastAPI** (Python 3.12) + Uvicorn workers | REST endpoints, WebSocket chat server, authentication, token versioning, business logic, OCR Intelligence Engine |
| **Background Workers** | Python asyncio (embedded in FastAPI via lifespan) | Self‑destruct sweep, OTP cleanup, media garbage collection, OCR processing (via BackgroundTasks) |
| **Database** | **PostgreSQL 16** + `pgcrypto` + `btree_gin` + `pg_trgm` | Primary relational store (users, sessions, messages, groups, channels, communities, audit logs) |
| **Cache / PubSub** | **Redis** (7.x) | OTP cache, WebSocket session registry, keyspace notifications for self‑destruct, rate‑limit counters, OCR keyword caching, channel/subscription analytics, **OCR alert history and debouncing** |
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

### 3.4 Team Ticker System (Group-Level Personalized Alerts)

The OCR Intelligence Engine is extended to support group‑level personalized alerts with a real‑time scrolling news ticker UI.

#### 3.4.1 Backend Logic (FastAPI + PostgreSQL + Redis)

- **Modified OCR Background Worker** (`app/api/routes/media.py` -> `_process_ocr`):
  - If the file is uploaded to a `group_id` (or `chat_id` with multiple members):
    1. Extract text from the file (using existing `extract_text`).
    2. Fetch all members of the group (from `GroupMember` table).
    3. For **each** member, fetch their keyword set (from Redis `user:{user_id}:ocr_keywords`).
    4. If a keyword match is found for that specific member, publish an alert **only to that member's Redis channel** (`ocr:alerts` with `user_id` set to that member).
  - **For Direct Chats**: Keep the existing logic (alert the recipient, not just the sender).
- **Performance Optimization**:
  - Use Redis pipelines to batch fetch keywords for all members.
  - Limit the text length sent to keyword search (e.g., first 5000 chars and last 5000 chars, or just search the whole text, which is fine for 3k users).
  - Add a 5-second debounce per file per user to avoid alert spam.
- **New API Endpoint (Optional)**:
  - `GET /ocr/group-alerts/{group_id}` – to fetch recent alerts for the group when the user opens the screen.

#### 3.4.2 Database & Redis Enhancements

- **Store Alert History**: Create a Redis list `user:{user_id}:alerts` (with a TTL of 24 hours) or a PostgreSQL table `ocr_alerts` to store the last 50 alerts per user so they can see history if they miss the ticker.
- **Alert Payload**: Ensure the alert contains `file_name`, `matched_keyword`, `file_id` (media_key), `group_id`, and a `snippet` of the surrounding text (e.g., 20 characters before and after the keyword).

#### 3.4.3 Frontend UI (Flutter) – "News Ticker" Component

- **Create a new Widget `NewsTicker`**:
  - This widget sits at the top of the `HomeScreen` and `ChatRoomScreen` (or a dedicated `AlertScreen`).
  - It displays a horizontally scrolling marquee of alerts.
  - Each alert shows: "��🔔 [Keyword] found in [File Name]".
  - The ticker auto-scrolls. Tapping on it opens the relevant file/chat.
- **BLoC/Cubit**: Create `TickerBloc` to manage a queue of alerts.
  - When a WebSocket `ocr_alert` is received, add it to the queue.
  - The UI listens to the queue. If multiple alerts arrive, they scroll one after another.
- **Persistent Notification**: If the user is not in the chat screen, show a badge on the Home tab indicating new OCR alerts.

#### 3.4.4 WebSocket Integration

- Update `app/services/ws_manager.py` to ensure the alert is broadcast only to the specific user (already done via `chan:user:{pid}`).
- Update Flutter `WsService` to handle the `ocr_alert` and push it to the `TickerBloc` instead of just showing a SnackBar (though we can keep SnackBar as a secondary fallback).

#### 3.4.5 Security & Privacy

- **Data Minimization**: Only send the snippet of text to the UI, not the entire document.
- **E2EE**: For Secret Chats, this feature is disabled (as per previous requirements).

---

## 4. Data Flow

[The rest of the document remains unchanged from the previous version, starting from section 4.1 User Registration & Login]

Due to the length, the remaining sections (4. Data Flow through 9. Conclusion) are preserved exactly as in the previous version.