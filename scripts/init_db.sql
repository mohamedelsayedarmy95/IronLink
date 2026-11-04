-- IronLink — PostgreSQL initialization script
-- Runs once when the container first starts (docker-entrypoint-initdb.d)

-- Local Docker prerequisite only; Alembic also asserts this extension for
-- managed databases. No passwords, implicit roles or future blanket grants.
CREATE EXTENSION IF NOT EXISTS pgcrypto;
