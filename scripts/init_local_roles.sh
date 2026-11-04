#!/bin/sh
# Docker-only provisioning, run by the disposable/local postgres administrator.
# Managed PostgreSQL identities are provisioned by the owner/provider instead.
set -eu
: "${MIGRATION_POSTGRES_USER:?Set the local schema-owner name}"
: "${MIGRATION_POSTGRES_PASSWORD:?Set the local schema-owner password}"
: "${IRONLINK_RUNTIME_USER:?Set the local runtime name}"
: "${IRONLINK_RUNTIME_PASSWORD:?Set the local runtime password}"
if [ "$MIGRATION_POSTGRES_USER" = "$IRONLINK_RUNTIME_USER" ] ||
   [ "$MIGRATION_POSTGRES_USER" = "$POSTGRES_USER" ] ||
   [ "$IRONLINK_RUNTIME_USER" = "$POSTGRES_USER" ]; then
    echo "Local bootstrap requires independent admin, owner and runtime identities" >&2
    exit 1
fi
psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" --set ON_ERROR_STOP=1 <<'SQL'
\getenv owner_name MIGRATION_POSTGRES_USER
\getenv owner_password MIGRATION_POSTGRES_PASSWORD
\getenv runtime_name IRONLINK_RUNTIME_USER
\getenv runtime_password IRONLINK_RUNTIME_PASSWORD
\getenv database_name POSTGRES_DB
SELECT format('CREATE ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS PASSWORD %L', :'owner_name', :'owner_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'owner_name') \gexec
SELECT format('CREATE ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS PASSWORD %L', :'runtime_name', :'runtime_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'runtime_name') \gexec
SELECT format('ALTER DATABASE %I OWNER TO %I', :'database_name', :'owner_name') \gexec
SELECT format('GRANT CONNECT ON DATABASE %I TO %I', :'database_name', :'runtime_name') \gexec
SQL
