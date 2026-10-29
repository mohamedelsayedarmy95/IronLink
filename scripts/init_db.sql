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

-- audit_writer's INSERT-only grant, the audit_logs RLS policies, and the
-- messages target constraint all reference tables that Alembic creates after
-- this script runs. They are applied by scripts/post_migrate.sql once the
-- schema exists, so a fresh volume never fails initialization here.

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
