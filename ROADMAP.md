# IronLink Development Roadmap

> **Vision:** Deliver a free, open‑source, ultra‑secure messaging platform that surpasses WhatsApp and Telegram in security, features, and cost‑efficiency.  
> **Approach:** Six incremental phases, each delivering a tangible, shippable increment while continuously improving quality, performance, and operability.  
> **Time Estimates:** Based on a small core team (2‑3 engineers) working full‑time; effort can be parallelized where noted. All dates are **working weeks** (5 business days). Calendar dates assume a start **Week 1 of Q3 2026** (early July 2026). Adjust as needed for team size or external dependencies.

---

## Phase 0 – Foundations & Preparation (Week 0‑1)

**Goal:** Establish a solid, reproducible development baseline and CI/CD pipeline.

| Activity | Owner | Outcome |
|----------|-------|---------|
| Project kickoff & architecture review (use ARCHITECTURE.md) | Team Lead | Shared understanding of target stack |
| Set up GitHub repository with branch protections, CODEOWNERS, issue templates | DevOps | Clean source control |
| Initialize CI with GitHub Actions: lint (flake8, dart-analyze), unit tests (pytest, flutter_test), build Docker images, run Trivy scan | DevOps | Fast feedback on every PR |
| Define coding standards & pre‑commit hooks (black, isort, dartfmt) | All Engineers | Consistent code |
| Create baseline performance & security benchmarks (locust/k6 for API, flutter driver for UI) | QA | Metrics for future regressions |
| Documentation sprint: update README, contribute guides for dev setup | Tech Writer | Onboarding material |
| **Deliverable:** Stable `develop` branch, passing CI, artifact repository (GitHub Packages) ready. | | |

**Estimated Duration:** 1 week

---

## Phase 1 – Backend Refactor, Free‑Stack Adoption & OCR Intelligence (Week 2‑4)

**Goal:** Migrate backend to the free, simple Docker‑Compose stack, integrate Firebase Cloud Messaging for push, and build the OCR Intelligence Engine that processes uploads for keyword alerts.

| Week | Activity | Details |
|------|----------|---------|
| 2 | **Set up Nginx reverse proxy** | Write `nginx.conf` (as in repo), add certbot integration for Let’s Encrypt TLS, enable HTTP/2, basic rate limiting. Keep existing proxy config as reference. |
|   | **Confirm Redis as cache/pubsub** | Ensure `docker-compose.yml` uses Redis (already); verify `notify-keyspace-events KEx` works for self‑destruct TTL; run latency/throughput sanity checks. |
|   | **Implement OCR Intelligence Engine (core)** | Add background task triggered on `/media/upload`. Integrate Tesseract OCR (install via Dockerfile) and text extraction for PDF/DOCX/XLSX/TXT. Store user‑defined keywords in Redis hash `user:<uid>:ocr_keywords`. On match, publish to Redis channel `ocr:alerts` and set short TTL flag. |
| 3 | **Wire up OCR alert delivery** | - FastAPI subscribes to `ocr:alerts` (Redis pub/sub) and pushes JSON frame to uploader’s WS connection.<br>- Implement Firebase Admin SDK (free tier) to send data‑only push notification with same payload.<br>- Add client‑side Flutter handler to show toast/badge and in‑app ticker. |
|   | **Add keyword management UI** | Settings screen → OCR Keywords (add/remove, persist to Redis). |
|   | **Optimize OCR worker** | Optional dedicated `ocr-worker` service scaled via `docker compose up --scale ocr-worker=<N>` sharing same codebase but env `OCR_WORKER=true`. |
| 4 | **Firebase Cloud Messaging (FCM) Push Service** | Create Firebase project, add service account secret, implement `PushService.register_token` and `send_push` using FCM HTTP v1 API. Ensure fallback to WS alerts if FCM unavailable. |
|   | **Security hardening** | - Rotate JWT secret and DB passwords via SOPS.<br>- Enable PostgreSQL row‑level security on `audit_logs` (already present).<br>- Add Docker non‑root user (`ironlink` group, `mil_api` user).<br>- Run Trivy scan on all images in CI. |
|   | **Observability (optional, lightweight)** | Deploy Prometheus & Grafana via Docker Compose; instrument FastAPI with `prometheus_fastapi_instrumentator`; expose `/metrics`. |
| **Deliverable:** Fully functional backend running on Docker Compose with Nginx, Redis, PostgreSQL, MinIO, OCR Intelligence Engine, FCM push, basic observability; all existing API contracts unchanged. | | |

**Estimated Duration:** 3 weeks (can overlap Phase 0’s CI work).

---

## Phase 2 – Frontend Adaptation & Push Integration (Week 5‑7)

**Goal:** Ensure Flutter client works seamlessly with the new backend, handles FCM pushes and OCR alerts, and maintains existing chat/media features.

| Week | Activity | Details |
|------|----------|---------|
| 5 | **Integrate Firebase Cloud Messaging Flutter plugin** | Add `firebase_core` and `firebase_messaging`; remove any legacy push plugin. Adjust `PushService` to register token via Firebase and handle incoming data messages (OCR alerts, regular pushes). |
|   | **Background WS maintenance** | Implement Android foreground service (via `android_alarm_manager_plus` or a simple Service) that keeps the WebSocket connection alive when app is in background; respect battery optimizations (whitelist via user prompt). |
|   | **Token storage audit** | Verify `flutter_secure_storage` uses Keystore/Keychain; add biometric fallback for unlocking token store on high‑security devices. |
| 6 | **UI/UX for Push & OCR Settings** | Add Settings screen → “Notifications” toggle, channel selection (DM, group mentions, broadcasts). Show OCR keywords list and allow manual re‑register of FCM token. |
|   | **Offline draft encryption** | Store unsent messages encrypted locally with app‑master key (derived from user PIN) → prevents plaintext leakage if device compromised. |
| 7 | **End‑to‑end test push & OCR flow** | - Register device → receive OCR alert via FCM when a matched file is uploaded while app in background.<br>- Verify tap opens correct conversation via `navigatorKey`.<br>- Test OCR alert via WebSocket when app in foreground.<br>- Test expiration and re‑registration on token rotation. |
| **Deliverable:** Flutter client capable of registering, receiving, and acting on push notifications via Firebase Cloud Messaging and OCR alerts (both WS and FCM); all existing chat/media features remain operational. | | |

**Estimated Duration:** 3 weeks

---

## Phase 3 – Testing, Hardening & Security Audits (Week 8‑10)

**Goal:** Validate correctness, performance, and resistance to attacks; introduce chaos and compliance testing.

| Week | Activity | Details |
|------|----------|---------|
| 8 | **Load & Stress Testing** | - Use **k6** to simulate 5k concurrent WS connections + 2k req/s REST.<br>- Target: 95th‑percentile latency < 200 ms for WS frames, API < 100 ms.<br>- Identify bottlenecks (DB connections, Redis CPU, workerGC). |
|   | **Chaos Engineering** | Deploy simple `kubectl delete pod` (or `docker compose kill`) to test: container failure, network partition. Verify self‑heal via restart policies and healthchecks. |
| 9 | **Static & Dynamic Security Analysis** | - Run **Bandit** (Python) and **flutter_secure_storage** audit.<br>- Run **OWASP ZAP** Docker scan against staging endpoint (auth, WS, media upload).<br>- Review JWT handling, refresh token rotation, token_version increment logic. |
|   | **Compliance Checks** | - GDPR “right to be forgotten” script: shred user data, revoke keys, purge audit log after retention period.<br>- Verify audit log immutability (attempt UPDATE via psql → should fail). |
| 10 | **Pen‑Test & Red‑Team Exercise** | Invite external security researcher (bug‑bounty style) for a 2‑day scoped test (no production data). Document findings, assign remediation tickets. |
| **Deliverable:** Comprehensive test suite (unit, integration, load, chaos), identified and fixed high/medium severity issues, compliance evidence ready. | | |

**Estimated Duration:** 3 weeks

---

## Phase 4 – Performance Optimization & Tuning (Week 11‑13)

**Goal:** Refine resource usage, latency, and cost‑efficiency; prepare for high‑scale deployment.

| Week | Activity | Details |
|------|----------|---------|
| 11 | **Database Tuning** | - Analyze `pg_stat_statements`; add missing indexes (e.g., composite on `(recipient_id, created_at)` for DM fetches).<br>- Enable `hot_standby_feedback` on replicas to avoid query conflicts.<br>- Tune `shared_buffers`, `wal_buffers`, `max_worker_processes` based on VM size. |
|   | **Connection Pooling** | Deploy **PgBouncer** (session pooling) in front of PostgreSQL; adjust `max_connections` accordingly. |
| 12 | **Redis / Dragonfly Optimization** | - Confirm `maxmemory-policy allkeys-lru` and adequate `maxmemory` (256 MiB for dev, scale via `docker compose up --scale redis`).<br>- Monitor key eviction rates; adjust TTL for OTP and WS session keys.<br>- Enable AOF persistence for durability (optional). |
|   | **Media Upload Efficiency** | - Tune MinIO chunk size (currently 4 MiB) based on network tests.<br>- Implement server‑side image thumbnails via `mc` batch job to reduce client CPU. |
| 13 | **Network & Protocol Optimizations** | - Enable HTTP/3 on Nginx (if supported) or keep HTTP/2.<br>- Test WebSocket permessage‑deflate compression (already on by default).<br>- Activate gzip for static assets (CSS/JS) via Nginx. |
| **Deliverable:** Optimized resource profiles (CPU/Memory per pod), baseline < 150 ms p95 latency at 2k WS connections, ready for horizontal scaling. | | |

**Estimated Duration:** 3 weeks

---

## Phase 5 – Global Deployment & High Availability (Week 14‑16)

**Goal:** Deploy a production‑ready, multi‑region, highly available IronLink service using only free tiers.

| Week | Activity | Details |
|------|----------|---------|
| 14 | **Multi‑Region Docker Compose Stacks** | - Provision identical VMs on three free‑tier providers: <br>  • Oracle Cloud Free Tier (2 VMs + AMP) <br>  • AWS Free Tier (t2.micro) <br>  • Google Cloud Always Free (f1‑micro) <br> - Use Docker Compose on each VM; keep same `docker-compose.yml` and environment. |
|   | **Global Load Balancing** | - Deploy Cloudflare Free tier DNS with Load Balancing (origin pools = each region’s ingress IP). <br> - Enable Argo Tunnel (optional) to keep origin IPs private. |
|   | **Active‑Passive DB Replication** | - Set up PostgreSQL streaming replica in each region (primary in us‑west, standbys in eu‑central and ap‑south). <br> - Use `synchronous_standby_names = '*'` for zero‑loss failover (acceptable latency due to small geographic distance). |
|   | **Object Storage Replication** | - Configure MinIO `mc mirror` cron job (every 5 min) to replicate buckets across regions (active‑passive). |
| 15 | **Observability Federation** | - Deploy a central Prometheus (in a fourth free‑tier VM) that scrapes each region’s `/metrics` via federation.<br>- Central Grafana instance for cross‑region dashboards.<br>- Loki cluster with multi‑tenant indexing for log search across regions (optional). |
| 16 | **Disaster‑Recovery Drills** | - Simulate primary region failure: stop Docker Compose, promote standby DB, flip Cloudflare pool.<br>- Measure RTO (target < 5 min) and RPO (near‑zero due to synchronous replication).<br>- Document runbooks and automate with simple bash/Docker commands. |
| **Deliverable:** A globally distributed IronLink deployment serving users from the nearest region, with automated failover, < 5 minute RTO, and zero‑downtime upgrades via rolling updates. | | |

**Estimated Duration:** 3 weeks

---

## Phase 6 – Launch, Growth & Community (Week 17‑20)

**Goal:** Release IronLink to beta users, gather feedback, iterate on features, and establish a sustainable open‑source community.

| Week | Activity | Details |
|------|----------|---------|
| 17 | **Closed Beta Invite** | - Invite 500 power users (existing community, security researchers). <br>- Provide invitation links via email / in‑app. <br>- Collect feedback via structured Form (Google Forms or self‑hosted). |
| 18 | **Feature Request Triage** | - Prioritize: reactions, threaded replies, stickers, avatars, group polls, admin moderation tools. <br>- Implement top‑voted features in two‑week sprints. |
| 19 | **Community Enablement** | - Set up public GitHub repository (`IronLink-Community`) for issue tracking, translations, and contribution guide. <br>- Host monthly public demo via YouTube Live (stream via free OBS + PeerTube). <br>- Launch bounty program (Gitcoin or BountySource) for security and UX improvements. |
| 20 | **Metrics & Roadmap Review** | - Publish monthly transparency report: active users, messages sent, uptime, security incidents. <br>- Review and adjust technical roadmap based on adoption and resource trends. <br>- Prepare for **Version 1.0** release (feature freeze, LTS tag). |
| **Deliverable:** Publicly available IronLink beta, active contributor base, transparent governance, and a clear path to a stable 1.0 release. | | |

**Estimated Duration:** 4 weeks (overlaps can be managed; some activities like community setup start earlier).

---

### Summary of Timeline

| Phase | Weeks | Calendar (2026) | Primary Focus |
|-------|-------|----------------|----------------|
| 0 – Foundations | 0‑1 | Jul 1‑Jul 12 | CI, basics |
| 1 – Backend Free‑Stack + OCR | 2‑4 | Jul 13‑Aug 9 | Nginx, Redis, OCR Engine, FCM, security |
| 2 – Frontend & Push | 5‑7 | Aug 10‑Sep 6 | Flutter FCM, foreground service, OCR UI |
| 3 – Testing & Hardening | 8‑10 | Sep 7‑Oct 4 | Load, chaos, security audits |
| 4 – Performance Opt. | 11‑13 | Oct 5‑Oct 25 | DB tuning, pooling, media, HTTP/2/3 |
| 5 – Global HA Deploy | 14‑16 | Oct 26‑Nov 15 | Multi‑region Docker Compose, Cloudflare LB, DR drills |
| 6 – Launch & Growth | 17‑20 | Nov 16‑Dec 13 | Beta, features, community, metrics |

Total ~20 weeks (�≈ 5 months) from project kickoff to a production‑ready, globally distributed beta.

---

**Note:** All estimates assume a dedicated, experienced team. If resources are limited, phases can be stretched or certain optimizations (e.g., multi‑region) deferred to post‑1.0. The core free‑stack (Nginx, Redis, PostgreSQL, MinIO, OCR Engine, FCM) is delivered by the end of Phase 1, providing a fully functional, secure platform at minimal cost.

--- 

*End of Roadmap.* 