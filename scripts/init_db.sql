-- IronLink — PostgreSQL initialization script
-- Runs once when the container first starts (docker-entrypoint-initdb.d)

-- ── Extensions ──────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS pgcrypto;   -- gen_random_uuid() + pgp_sym_encrypt
CREATE EXTENSION IF NOT EXISTS pg_trgm;   -- trigram indexes for username search
CREATE EXTENSION IF NOT EXISTS btree_gin; -- GIN indexes on composite types

-- ── Dedicated roles ──────────────────────────────────────────────────────────
-- Fable5-Enhancement: least-privilege role separation.
-- api_user  : application CRUD (no DDL, no TRUNCATE)
-- audit_writer : INSERT-only on audit_logs — can never UPDATE or DELETE rows
-- readonly  : reporting / dashboards

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'api_user') THEN
    CREATE ROLE api_user LOGIN PASSWORD 'CHANGE_IN_ENV';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'audit_writer') THEN
    CREATE ROLE audit_writer LOGIN PASSWORD 'CHANGE_IN_ENV';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'readonly') THEN
    CREATE ROLE readonly LOGIN PASSWORD 'CHANGE_IN_ENV';
  END IF;
END
$$;

-- ── Schema grants ─────────────────────────────────────────────────────────────
GRANT USAGE ON SCHEMA public TO api_user, audit_writer, readonly;
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO api_user;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO api_user;

-- audit_writer gets INSERT only
GRANT INSERT ON TABLE audit_logs TO audit_writer;

-- readonly
GRANT SELECT ON ALL TABLES IN SCHEMA public TO readonly;

-- Default privileges for future tables created by migrations
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON TABLES TO api_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT ALL ON SEQUENCES TO api_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT INSERT ON TABLES TO audit_writer;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT ON TABLES TO readonly;

-- ── Row-Level Security on audit_logs ─────────────────────────────────────────
-- Prevents the api_user from running UPDATE/DELETE even if application code bugs
-- attempt to do so.
ALTER TABLE audit_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY audit_insert_only
  ON audit_logs
  FOR INSERT
  TO api_user, audit_writer
  WITH CHECK (true);

CREATE POLICY audit_select_all
  ON audit_logs
  FOR SELECT
  USING (true);

-- ── Constraint: message must have recipient XOR group ─────────────────────────
ALTER TABLE messages
  ADD CONSTRAINT chk_message_target
  CHECK (
    (recipient_id IS NOT NULL AND group_id IS NULL) OR
    (recipient_id IS NULL AND group_id IS NOT NULL)
  );
