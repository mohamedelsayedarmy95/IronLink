# IronLink

Secure enterprise messaging platform — 7,000 registered users / 500 concurrent.

## Stack

| Layer | Technology |
|---|---|
| API | FastAPI (Python 3.12, async) + Uvicorn |
| Database | PostgreSQL 16 + pgcrypto (column encryption) |
| Cache / Pub-Sub | Redis Stack (3 isolated DB indices) |
| Object storage | MinIO (SSE auto-encryption, 15-min pre-signed URLs) |
| Proxy | Nginx — **TLS 1.3 only**, HTTP/2, HSTS, rate limiting |

## Quick start (development)

```bash
# 1. Configure secrets
cp .env.example .env
#    → edit .env: set all *_PASSWORD, SECRET_KEY, DB_ENCRYPTION_KEY

# 2. Generate a dev TLS certificate
bash scripts/generate_ssl.sh

# 3. Launch the stack
docker compose up -d --build

# 4. Apply migrations
docker compose exec api alembic upgrade head

# 5. Verify
curl -k https://localhost/health
```

## Run tests (no Docker required)

```bash
pip install -r requirements.txt
pytest
```

## Project layout

```
app/
  config.py          # pydantic-settings — all secrets from env, fail-fast
  main.py            # FastAPI app factory + health endpoint
  core/
    database.py      # async SQLAlchemy engine (pool tuned for 500 concurrent)
    redis.py         # 3 pools: pubsub / otp / sessions
    security.py      # bcrypt, JWT + token_version, fingerprint, OTP gen
  models/
    user.py          # hashed_military_id, device_fingerprint, token_version, expiry_date
    user_session.py  # IP, device, city-level geo, remote-disconnect linkage
    message.py       # E2E ciphertext, self-destruct (dual-layer), soft delete
    group.py         # Group + GroupMember with per-member roles
    audit_log.py     # immutable (RLS), JSONB before/after snapshots
  services/
    otp_service.py   # Redis-TTL OTP with attempt burning
    storage_service.py  # MinIO presign + MIME allow-list
alembic/             # async-aware migrations
nginx/nginx.conf     # TLS 1.3, security headers, WS upgrade, rate limits
scripts/
  init_db.sql        # extensions, least-privilege roles, RLS on audit_logs
  generate_ssl.sh    # dev-only self-signed cert
tests/               # plain pytest — no external services needed
```

## Security model (summary)

- **Secrets**: environment-only; config validators refuse to boot without them.
- **Tokens**: JWT access (30 min) embeds `token_version`; incrementing the DB
  column invalidates every outstanding token — O(1) global logout per user.
- **Refresh tokens**: 256-bit random, only SHA-256 stored.
- **Military ID**: bcrypt-hashed, never stored or logged in plaintext.
- **Audit log**: PostgreSQL RLS — INSERT-only role; no code path can alter history.
- **Self-destruct**: `destruct_at` column (worker sweep) + Redis keyspace TTL events.
- **Transport**: TLS 1.3 exclusively; gzip disabled on TLS (BREACH); HSTS preload.
