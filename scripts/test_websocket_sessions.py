"""Mandatory WebSocket security tests on disposable loopback-only PG16/Redis."""
from __future__ import annotations

import os
import argparse
from pathlib import Path
import secrets
import subprocess
import sys
import time

import redis


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--focused', nargs='+', metavar='TEST_NAME',
                        help='Explicit named WS cases for diagnosis; omitted by the mandatory CI gate')
    args = parser.parse_args()
    if args.focused and any(not name.startswith('test_') or not name.replace('_','').isalnum()
                            for name in args.focused):
        parser.error('Focused selection accepts only test function names')
    selection = (['tests/test_websocket_sessions.py::'+name for name in args.focused]
                 if args.focused else ['tests/test_websocket_sessions.py',
                                       'tests/test_ws_manager.py', 'tests/test_session_lifecycle.py'])
    print('[ws-security] '+('focused verification' if args.focused else 'mandatory full WS gate'), flush=True)
    token = secrets.token_hex(12)
    name = 'ironlink-ws-tests-' + token
    label = 'ironlink.ws-tests=' + token
    container = None

    def docker(*args):
        result = subprocess.run(['docker', *args], capture_output=True, text=True, timeout=120)
        if result.returncode:
            raise RuntimeError('Disposable Redis command failed')
        return result.stdout.strip()

    try:
        docker('run', '--detach', '--rm', '--name', name, '--label', label,
               '--publish', '127.0.0.1::6379', '--mount', 'type=tmpfs,destination=/data',
               'redis:7.4-alpine', 'redis-server', '--save', '', '--appendonly', 'no')
        container = name
        port = int(docker('port', name, '6379/tcp').rsplit(':', 1)[1])
        url = f'redis://127.0.0.1:{port}/0'
        client = redis.Redis.from_url(url, socket_connect_timeout=1, socket_timeout=1)
        deadline = time.monotonic() + 30
        while True:
            try:
                client.ping()
                break
            except redis.RedisError:
                if time.monotonic() >= deadline:
                    raise RuntimeError('Disposable Redis did not become ready') from None
                time.sleep(0.1)
        client.close()
        environment = os.environ.copy()
        environment['WS_TEST_REDIS_URL'] = url
        environment['IRONLINK_REQUIRE_POSTGRES_SECURITY'] = '1'
        environment['PYTHONDONTWRITEBYTECODE'] = '1'
        # The existing runner creates and labels its own new PostgreSQL cluster.
        return subprocess.run([
            sys.executable, '-B', '-m', 'scripts.test_postgres_bootstrap', '--',
            '-q', '-p', 'no:cacheprovider', *selection,
        ], cwd=Path(__file__).resolve().parents[1], env=environment).returncode
    except Exception as exc:
        print('[ws-security] verification failed (' + type(exc).__name__ + ')', file=sys.stderr)
        return 1
    finally:
        if container:
            actual = docker('inspect', '--format', '{{index .Config.Labels "ironlink.ws-tests"}}', container)
            if actual != token:
                raise RuntimeError('Refusing to stop an unrecognized resource')
            docker('stop', '--time', '5', container)
            print('[ws-security] this invocation\'s disposable Redis stopped', flush=True)


if __name__ == '__main__':
    raise SystemExit(main())
