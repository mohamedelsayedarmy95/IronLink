"""Apply table-level hardening after Alembic migrations.

`scripts/init_db.sql` runs before the application schema exists, so grants,
RLS policies, and constraints that reference application tables are applied
here instead. This script is called by docker-entrypoint.sh after
`alembic upgrade head`.
"""
from __future__ import annotations

import os
from pathlib import Path

import psycopg2


def main() -> None:
    conn = psycopg2.connect(
        host=os.environ.get("POSTGRES_HOST", "db"),
        port=os.environ.get("POSTGRES_PORT", "5432"),
        user=os.environ["POSTGRES_USER"],
        password=os.environ["POSTGRES_PASSWORD"],
        dbname=os.environ["POSTGRES_DB"],
    )
    sql = Path(__file__).with_name("post_migrate.sql").read_text(encoding="utf-8")
    try:
        with conn:
            with conn.cursor() as cur:
                cur.execute(sql)
    finally:
        conn.close()
    print("[entrypoint] post-migration hardening applied")


if __name__ == "__main__":
    main()
