#!/bin/sh
# Render Free initializes at container start. Bootstrap serializes replicas
# on the migration session, applies hardening and refuses unsafe identities.
# RUN_MIGRATIONS_ON_START=false still verifies schema and runtime privileges.
set -e

if [ "${RUN_MIGRATIONS_ON_START:-true}" = "true" ]; then
    echo "[entrypoint] validating identities, migrations and database hardening"
    # Deliberately not guarded: a failed migration must abort the boot rather
    # than let the app serve traffic against a schema it does not expect.
    python -m scripts.bootstrap_database
    echo "[entrypoint] migrations applied"
else
    python -m scripts.bootstrap_database --check-only
fi

# Replace this shell with a launcher that removes every case variant before
# execing Uvicorn. Runtime database credentials remain available.
exec python -m scripts.run_runtime
