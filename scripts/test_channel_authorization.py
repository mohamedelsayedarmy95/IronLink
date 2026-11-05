"""Run the channel HTTP security gate on a new isolated PostgreSQL 16 cluster."""
import os
from pathlib import Path
import subprocess
import sys


def main() -> int:
    if len(sys.argv) != 1:
        raise SystemExit('Channel security gate does not accept test selection overrides')
    env = os.environ.copy()
    env['IRONLINK_REQUIRE_POSTGRES_SECURITY'] = '1'
    return subprocess.run([
        sys.executable, '-B', '-m', 'scripts.test_postgres_bootstrap', '--',
        '-q', '-p', 'no:cacheprovider', 'tests/test_channel_authorization.py',
        'tests/test_channel_media_migration.py',
    ], env=env, cwd=Path(__file__).resolve().parents[1]).returncode


if __name__ == '__main__':
    raise SystemExit(main())
