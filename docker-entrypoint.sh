#!/bin/sh
# Container entrypoint: apply migrations, then hand PID 1 to the server.
#
# Render's preDeployCommand, Shell, and One-Off Jobs are all paid-plan features,
# so on the free tier there is no way to run `alembic upgrade head` other than at
# container start. Alembic is idempotent — once the database is at head this is a
# fast no-op — so running it on every boot is safe.
#
# Set RUN_MIGRATIONS_ON_START=false once a real release process exists (a
# pre-deploy hook or a job), so that N starting replicas do not all race to
# migrate the same database.
set -e

if [ "${RUN_MIGRATIONS_ON_START:-true}" = "true" ]; then
    echo "[entrypoint] alembic upgrade head"
    # Deliberately not guarded: a failed migration must abort the boot rather
    # than let the app serve traffic against a schema it does not expect.
    alembic upgrade head
    echo "[entrypoint] migrations applied"
else
    echo "[entrypoint] RUN_MIGRATIONS_ON_START=false — skipping migrations"
fi

# exec so uvicorn becomes PID 1 and receives SIGTERM directly; without it the
# shell absorbs the signal and the platform kills the container after the grace
# period instead of shutting down cleanly.
exec uvicorn app.main:app \
    --host 0.0.0.0 \
    --port "${PORT:-8000}" \
    --workers "${WEB_CONCURRENCY:-1}" \
    --loop uvloop \
    --http h11 \
    --proxy-headers \
    --forwarded-allow-ips '*'
