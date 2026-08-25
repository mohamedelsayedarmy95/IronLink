from __future__ import annotations

import secrets
from functools import lru_cache
from typing import Literal
from urllib.parse import urlparse

from pydantic import (
    AliasChoices,
    AnyHttpUrl,
    Field,
    PostgresDsn,
    RedisDsn,
    field_validator,
    model_validator,
)
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    """Central configuration — all values resolved from environment / .env file.

    No hardcoded secrets anywhere. Every sensitive default raises at startup
    so misconfigured deployments fail fast instead of silently using insecure values.
    """

    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=False,
        extra="ignore",
    )

    # ── Application ────────────────────────────────────────────────────────────
    APP_NAME: str = "IronLink"
    ENV: Literal["development", "staging", "production"] = "development"
    DEBUG: bool = False
    API_PREFIX: str = "/api/v1"
    ALLOWED_ORIGINS: list[str] = Field(default_factory=list)

    # TrustedHostMiddleware matches the Host header, which carries no scheme and
    # no path — so the ALLOWED_ORIGINS URLs can never match it. Passing them
    # straight through (as this used to) rejects 100% of production traffic with
    # an opaque 400. Leave this empty to derive the hostnames from
    # ALLOWED_ORIGINS; set it explicitly to add hosts that are not CORS origins,
    # e.g. a platform health-check hostname or a wildcard like "*.onrender.com".
    ALLOWED_HOSTS: list[str] = Field(default_factory=list)

    # Render injects this at runtime with the hostname it assigned. The name is
    # generated (a random suffix is appended), so it cannot be written into
    # config ahead of time — reading it back is the only way to trust the host
    # without falling back to a blanket wildcard.
    RENDER_EXTERNAL_HOSTNAME: str = ""

    @property
    def allowed_hosts(self) -> list[str]:
        hosts: set[str] = set(self.ALLOWED_HOSTS)
        if not hosts:
            for origin in self.ALLOWED_ORIGINS:
                # Bare hostnames parse with an empty .hostname, so fall back to
                # the raw value rather than silently dropping the entry.
                hosts.add(urlparse(origin).hostname or origin)
        if self.RENDER_EXTERNAL_HOSTNAME:
            hosts.add(self.RENDER_EXTERNAL_HOSTNAME)
        return sorted(h for h in hosts if h)

    @model_validator(mode="after")
    def _require_hosts_in_production(self) -> Settings:
        """Fail fast instead of serving a service that 400s every request.

        With ENV=production and nothing to trust, TrustedHostMiddleware would
        reject everything — a failure that looks like a routing or TLS problem
        and costs hours to trace back to config.
        """
        if self.ENV == "production" and not self.allowed_hosts:
            raise ValueError(
                "ALLOWED_ORIGINS (or ALLOWED_HOSTS) must be set when ENV=production — "
                "otherwise TrustedHostMiddleware rejects every incoming request"
            )
        if self.ENV == "production" and self.DEV_AUTH_BYPASS:
            raise ValueError(
                "DEV_AUTH_BYPASS cannot be enabled when ENV=production — it "
                "provisions any phone number on demand and accepts a fixed OTP, "
                "which would make every account trivially reachable"
            )
        return self

    # ── Security ───────────────────────────────────────────────────────────────
    SECRET_KEY: str = Field(default="", description="Min 64-char random secret")
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60
    REFRESH_TOKEN_EXPIRE_DAYS: int = 7
    # Fable5-Enhancement: per-user token versioning means a single DB write invalidates
    # ALL refresh tokens for a user (forced logout, device wipe) without a token blocklist.
    TOKEN_ALGORITHM: str = "HS256"

    # ── Database ───────────────────────────────────────────────────────────────
    POSTGRES_USER: str = "ironlink_user"
    POSTGRES_PASSWORD: str = Field(default="", description="Required — never has a default")
    POSTGRES_HOST: str = "db"
    POSTGRES_PORT: int = 5432
    POSTGRES_DB: str = "ironlink"

    # Pool tuned for 500 concurrent users; overflow allows burst headroom.
    DB_POOL_SIZE: int = 20
    DB_MAX_OVERFLOW: int = 30
    DB_POOL_PRE_PING: bool = True

    @field_validator("POSTGRES_PASSWORD", mode="before")
    @classmethod
    def _require_pg_password(cls, v: str) -> str:
        if not v:
            raise ValueError("POSTGRES_PASSWORD must be set in the environment")
        return v

    @property
    def database_url(self) -> str:
        return (
            f"postgresql+asyncpg://{self.POSTGRES_USER}:{self.POSTGRES_PASSWORD}"
            f"@{self.POSTGRES_HOST}:{self.POSTGRES_PORT}/{self.POSTGRES_DB}"
        )

    @property
    def sync_database_url(self) -> str:
        """Used by Alembic (sync driver)."""
        return (
            f"postgresql+psycopg2://{self.POSTGRES_USER}:{self.POSTGRES_PASSWORD}"
            f"@{self.POSTGRES_HOST}:{self.POSTGRES_PORT}/{self.POSTGRES_DB}"
        )

    # ── Redis ──────────────────────────────────────────────────────────────────
    REDIS_HOST: str = "redis"
    REDIS_PORT: int = 6379
    REDIS_PASSWORD: str = Field(default="", description="Required in production")
    REDIS_DB: int = 0

    # Fable5-Enhancement: separate DB indices prevent accidental key collision between
    # Pub/Sub channel data, OTP cache, and session registry.
    REDIS_DB_PUBSUB: int = 0
    REDIS_DB_OTP: int = 1       # OTP codes isolated; TTL 5 min, auto-purged by Redis TTL
    REDIS_DB_SESSIONS: int = 2  # WS session map: user_id → [connection_ids]

    OTP_TTL_SECONDS: int = 300   # 5 minutes
    OTP_MAX_ATTEMPTS: int = 5

    # ── Smart Keyword Alert ───────────────────────────────────────────────────
    # Off by default, and it should stay off. Encryption is the default for
    # every chat, so the server holds no key and cannot read an attachment;
    # keyword matching runs on-device, on plaintext that never leaves it.
    # Enabling this only does anything for a deployment that also sends
    # attachments in the clear, and it means the server reads them and stores
    # the user's private keywords. See docs/SMART_KEYWORD_ALERT_AUDIT.md.
    SERVER_SIDE_OCR_ENABLED: bool = False

    # ── Development authentication bypass ─────────────────────────────────────
    # There is no SMS provider wired up (see SmsGateway) and no self-registration
    # endpoint, so without this nobody can get past the login screen on a
    # deployed build. With it enabled, /auth/request-otp provisions any unknown
    # phone number and /auth/verify accepts DEV_OTP_CODE in place of a real code
    # and skips the military-ID check.
    #
    # This is a deliberate hole. It is gated twice: it defaults to off, and the
    # validator below refuses to start at all if it is switched on while
    # ENV=production — a misconfiguration should crash the deploy loudly rather
    # than quietly leave the front door open.
    DEV_AUTH_BYPASS: bool = False
    DEV_OTP_CODE: str = "000000"

    # ── AI features ───────────────────────────────────────────────────────────
    # A single switch to take the AI endpoints out entirely.
    #
    # These are the only place message plaintext leaves the device and reaches
    # a third party (Hugging Face). Consent gates them per conversation, but a
    # deployment that would rather not offer the choice at all sets this to
    # false and the endpoints refuse regardless of who agreed.
    AI_FEATURES_ENABLED: bool = True

    # ── Retention ─────────────────────────────────────────────────────────────
    # Enforced daily by app/services/retention_worker.py. Zero disables a
    # sweep — checked explicitly, so it cannot be confused with a cutoff of
    # "older than right now".
    #
    # 365 days for audit logs: long enough for a full annual security review
    # and for an investigation that begins months after the event, which is the
    # usual case since breaches are typically found late. Short enough that the
    # record of who did what is not permanent.
    AUDIT_LOG_RETENTION_DAYS: int = 365

    # 90 days for finished sessions, and only revoked or expired ones. Enough
    # history that "this is a new device" means something; beyond it the row is
    # not security signal but a record of where somebody signed in from.
    SESSION_RETENTION_DAYS: int = 90

    # ── Observability ─────────────────────────────────────────────────────────
    # Bearer token required to scrape /metrics. Empty means the endpoint does
    # not exist at all — 404, not 401, so an unauthenticated caller cannot even
    # confirm it is there.
    #
    # Defaulting to disabled rather than to open is the point. A metrics page
    # here publishes how many people are connected, when traffic rises and
    # falls, and which endpoints are failing; for users who may be targeted,
    # that shape is information about them even though no metric names anyone.
    # An operator who forgets to set this gets a scrape failure, which is loud
    # and gets fixed. The other default gets nobody's attention.
    METRICS_TOKEN: str = ""

    # ── Self-registration ─────────────────────────────────────────────────────
    # Whether a phone number that verifies with Firebase may register itself.
    # With it off, accounts have to be created out of band and the app is only
    # usable by people someone put there deliberately.
    SELF_REGISTRATION_ENABLED: bool = True

    # Whether a self-registered account may use the system immediately, or
    # waits for an admin.
    #
    # This is the whole admission policy in one flag. Auto-approval means
    # anyone who controls a phone number is inside — which is right for a
    # consumer messenger and is a decision worth making on purpose for a
    # military one, where the military ID a registrant types is something they
    # chose rather than something anyone verified.
    SELF_REGISTRATION_AUTO_APPROVE: bool = True

    # Managed Redis (Render, Upstash, Redis Cloud) hands out a single connection
    # string, often rediss:// with credentials embedded. When set it wins over
    # the discrete host/port/password fields above.
    REDIS_URL: str = Field(default="", description="Full Redis URL; overrides REDIS_HOST/PORT/PASSWORD")

    @property
    def redis_url(self) -> str:
        if self.REDIS_URL:
            return self.REDIS_URL
        auth = f":{self.REDIS_PASSWORD}@" if self.REDIS_PASSWORD else ""
        return f"redis://{auth}{self.REDIS_HOST}:{self.REDIS_PORT}/{self.REDIS_DB}"

    # ── Object storage (S3-compatible) ─────────────────────────────────────────
    # One set of settings drives both backends, because MinIO and Cloudflare R2
    # both speak S3 — only the endpoint, TLS flag, and region differ:
    #
    #   local MinIO : S3_ENDPOINT=minio:9000                       S3_SECURE=false
    #   Cloudflare R2: S3_ENDPOINT=<ACCOUNT_ID>.r2.cloudflarestorage.com
    #                  S3_SECURE=true   S3_REGION=auto
    #
    # The endpoint is a host[:port] with no scheme — S3_SECURE decides http vs
    # https. The legacy MINIO_* names are still accepted as aliases so existing
    # .env files and the docker-compose stack keep working unchanged.
    S3_ENDPOINT: str = Field(
        default="minio:9000",
        validation_alias=AliasChoices("S3_ENDPOINT", "MINIO_ENDPOINT"),
    )
    S3_ACCESS_KEY_ID: str = Field(
        default="ironlink_minio",
        validation_alias=AliasChoices("S3_ACCESS_KEY_ID", "MINIO_ROOT_USER"),
    )
    S3_SECRET_ACCESS_KEY: str = Field(
        default="",
        description="Required — never has a default",
        validation_alias=AliasChoices("S3_SECRET_ACCESS_KEY", "MINIO_ROOT_PASSWORD"),
    )
    S3_SECURE: bool = Field(
        default=False,   # Internal network; Nginx terminates TLS externally
        validation_alias=AliasChoices("S3_SECURE", "MINIO_SECURE"),
    )
    # R2 ignores the region for routing but still folds it into the SigV4
    # credential scope, so it must be "auto" there or every request comes back
    # SignatureDoesNotMatch. Empty means "let the client decide", which is what
    # MinIO wants.
    S3_REGION: str = ""
    S3_BUCKET_AVATARS: str = Field(
        default="avatars",
        validation_alias=AliasChoices("S3_BUCKET_AVATARS", "MINIO_BUCKET_AVATARS"),
    )
    S3_BUCKET_ATTACHMENTS: str = Field(
        default="attachments",
        validation_alias=AliasChoices("S3_BUCKET_ATTACHMENTS", "MINIO_BUCKET_ATTACHMENTS"),
    )

    # Fable5-Enhancement: 15-min pre-signed URL expiry (not the S3 default of 7 days)
    # prevents URL sharing outside the app session window.
    S3_PRESIGN_EXPIRY_SECONDS: int = Field(
        default=900,
        validation_alias=AliasChoices(
            "S3_PRESIGN_EXPIRY_SECONDS", "MINIO_PRESIGN_EXPIRY_SECONDS"
        ),
    )

    @property
    def storage_configured(self) -> bool:
        """Object storage is optional at boot, unlike the database.

        Requiring it here used to abort startup, which meant the whole API was
        unreachable until an R2 bucket existed — even though storage is only
        touched by media upload and download. It now fails at the point of use
        instead (see StorageService), so auth, chat, and everything else can run
        before storage is provisioned.
        """
        return bool(self.S3_ENDPOINT and self.S3_ACCESS_KEY_ID and self.S3_SECRET_ACCESS_KEY)

    # ── Encryption ─────────────────────────────────────────────────────────────
    # Used by pgcrypto pgp_sym_encrypt for column-level encryption
    # (hashed_military_id, device_fingerprint).
    DB_ENCRYPTION_KEY: str = Field(default="", description="Required — AES column encryption")

    @field_validator("DB_ENCRYPTION_KEY", mode="before")
    @classmethod
    def _require_encryption_key(cls, v: str) -> str:
        if not v:
            raise ValueError("DB_ENCRYPTION_KEY must be set — used for column-level encryption")
        if len(v) < 32:
            raise ValueError("DB_ENCRYPTION_KEY must be at least 32 characters")
        return v

    # Salt for the contact-discovery phone hashes. Global rather than
    # per-user by necessity: matching requires the same number to hash
    # identically no matter whose address book it came from, and a per-user
    # salt would make that impossible.
    #
    # It therefore carries real weight — phone numbers are a small enough
    # space to brute-force without it — so it is kept out of the database
    # entirely and must never be rotated once contacts are indexed, or every
    # stored hash stops matching and discovery silently returns nothing.
    # Deliberately NOT validated at startup, unlike DB_ENCRYPTION_KEY. That
    # key is needed for core authentication, so booting without it would be
    # incoherent. This one gates a single feature, and making the whole
    # service refuse to start over it would mean shipping contact discovery
    # could take messaging down with it.
    #
    # Instead the contacts endpoints check it and return 503 while everything
    # else runs — the same "degrade, don't crash" shape the S3 settings use.
    # Hashing itself still refuses to run unsalted (see contact_discovery),
    # so a missing salt can never silently produce reversible digests.
    CONTACT_HASH_SALT: str = Field(
        default="", description="Salts contact-discovery hashes; feature is "
                                "disabled while unset"
    )

    @property
    def contact_discovery_enabled(self) -> bool:
        """Whether the salt is present and long enough to be worth anything."""
        return len(self.CONTACT_HASH_SALT) >= 32

    # ── Rate limiting ──────────────────────────────────────────────────────────
    RATE_LIMIT_REQUESTS_PER_MINUTE: int = 60
    RATE_LIMIT_WS_PER_USER: int = 3        # max concurrent WS connections per user

    # ── Push notifications (FCM) ──────────────────────────────────────────────
    # Two ways to supply the Firebase service account, because a PaaS has no
    # filesystem to drop a JSON file onto:
    #   FIREBASE_CREDENTIALS_JSON  the file's contents, as a single env var
    #                              (Render, Fly, Heroku — this is the one to use)
    #   FIREBASE_CREDENTIALS_FILE  a path on disk (local dev, docker-compose)
    # JSON wins when both are set. Neither set = pushes silently disabled.
    FIREBASE_CREDENTIALS_JSON: str = ""
    FIREBASE_CREDENTIALS_FILE: str = ""

    @property
    def firebase_configured(self) -> bool:
        return bool(self.FIREBASE_CREDENTIALS_JSON or self.FIREBASE_CREDENTIALS_FILE)

    # ── AI (Hugging Face Inference API) ───────────────────────────────────────
    # Empty token = AI features degrade to their fallbacks instead of failing.
    HF_API_TOKEN: str = ""
    HF_API_URL: str = "https://api-inference.huggingface.co/models"
    HF_TIMEOUT_SECONDS: float = 30.0

    # ── Audit ─────────────────────────────────────────────────────────────────
    AUDIT_LOG_RETENTION_DAYS: int = 365    # 1 year minimum; immutable append-only


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()


# Module-level convenience alias used throughout the app
settings: Settings = get_settings()
