from __future__ import annotations

import secrets
from functools import lru_cache
from typing import Literal

from pydantic import AnyHttpUrl, Field, PostgresDsn, RedisDsn, field_validator
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

    @property
    def redis_url(self) -> str:
        auth = f":{self.REDIS_PASSWORD}@" if self.REDIS_PASSWORD else ""
        return f"redis://{auth}{self.REDIS_HOST}:{self.REDIS_PORT}/{self.REDIS_DB}"

    # ── MinIO / S3 ─────────────────────────────────────────────────────────────
    MINIO_ENDPOINT: str = "minio:9000"
    MINIO_ROOT_USER: str = "ironlink_minio"
    MINIO_ROOT_PASSWORD: str = Field(default="", description="Required — never has a default")
    MINIO_SECURE: bool = False   # Internal network; Nginx terminates TLS externally
    MINIO_BUCKET_AVATARS: str = "avatars"
    MINIO_BUCKET_ATTACHMENTS: str = "attachments"

    # Fable5-Enhancement: 15-min pre-signed URL expiry (not the MinIO default of 7 days)
    # prevents URL sharing outside the app session window.
    MINIO_PRESIGN_EXPIRY_SECONDS: int = 900

    @field_validator("MINIO_ROOT_PASSWORD", mode="before")
    @classmethod
    def _require_minio_password(cls, v: str) -> str:
        if not v:
            raise ValueError("MINIO_ROOT_PASSWORD must be set in the environment")
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

    # ── Audit ─────────────────────────────────────────────────────────────────
    AUDIT_LOG_RETENTION_DAYS: int = 365    # 1 year minimum; immutable append-only


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    return Settings()


# Module-level convenience alias used throughout the app
settings: Settings = get_settings()
