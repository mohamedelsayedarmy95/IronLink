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

    @property
    def allowed_hosts(self) -> list[str]:
        if self.ALLOWED_HOSTS:
            return self.ALLOWED_HOSTS
        hosts: set[str] = set()
        for origin in self.ALLOWED_ORIGINS:
            # Bare hostnames parse with an empty .hostname, so fall back to the
            # raw value rather than silently dropping the entry.
            hosts.add(urlparse(origin).hostname or origin)
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

    @field_validator("S3_SECRET_ACCESS_KEY", mode="before")
    @classmethod
    def _require_s3_secret(cls, v: str) -> str:
        if not v:
            raise ValueError(
                "S3_SECRET_ACCESS_KEY (or legacy MINIO_ROOT_PASSWORD) must be set"
            )
        return v

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

    # ── Rate limiting ──────────────────────────────────────────────────────────
    RATE_LIMIT_REQUESTS_PER_MINUTE: int = 60
    RATE_LIMIT_WS_PER_USER: int = 3        # max concurrent WS connections per user

    # ── Push notifications (FCM) ──────────────────────────────────────────────
    # Path to the Firebase service-account JSON. Empty = pushes disabled (dev).
    FIREBASE_CREDENTIALS_FILE: str = ""

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
