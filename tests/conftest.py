from __future__ import annotations

import os

# Set required env vars BEFORE app.config is imported anywhere.
os.environ.setdefault("POSTGRES_PASSWORD", "test_pg_password")
os.environ.setdefault("REDIS_PASSWORD", "test_redis_password")
os.environ.setdefault("MINIO_ROOT_PASSWORD", "test_minio_password")
os.environ.setdefault("DB_ENCRYPTION_KEY", "test_encryption_key_32_chars_min_xx")
os.environ.setdefault("SECRET_KEY", "test_secret_key_for_jwt_signing_only_in_tests_xxxxxxxxxxxxxxxxxxx")
