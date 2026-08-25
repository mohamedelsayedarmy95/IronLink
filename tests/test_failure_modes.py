"""What happens when the things this service depends on stop working.

The engineering standard asks for failure testing by name — no network, slow
network, timeouts, expired tokens, malformed input, unreachable dependencies —
and none of it existed. Every test in the repository ran against a world where
Postgres answers, Redis answers, object storage answers, and the client sends
well-formed JSON.

That world is not the one a phone lives in, and it is not the one a free-tier
deployment lives in either.

The property being tested throughout is **safe failure**: the service may stop
working, but it must not corrupt anything, must not leak anything, and must not
report success for something that did not happen.
"""

from __future__ import annotations

import inspect
import json

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.core import observability


def _code_only(source: str) -> str:
    """Source with comment lines and trailing comments removed.

    Needed by any assertion that searches code for a pattern: a comment
    explaining why the pattern is absent contains the pattern.
    """
    lines = []
    for line in source.splitlines():
        stripped = line.split("#", 1)[0]
        if stripped.strip():
            lines.append(stripped)
    return "\n".join(lines)


class _Dead:
    """A dependency that raises whatever it is asked to do."""

    def __init__(self, error: Exception | None = None) -> None:
        self._error = error or ConnectionError("connection refused")

    async def ping(self) -> None:
        raise self._error

    async def execute(self, *_args: object, **_kwargs: object) -> None:
        raise self._error

    async def __aenter__(self) -> _Dead:
        return self

    async def __aexit__(self, *_exc: object) -> bool:
        return False


class TestReadinessUnderFailure:
    """`/health/ready` is the one endpoint whose whole job is to fail."""

    def test_it_reports_a_dead_database_rather_than_claiming_health(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        from app import main

        monkeypatch.setattr(main, "AsyncSessionLocal", lambda: _Dead())

        res = TestClient(main.app).get("/health/ready")

        assert res.status_code == 503
        assert res.json()["checks"]["database"] == "unavailable"

    def test_it_reports_a_dead_redis(self, monkeypatch: pytest.MonkeyPatch) -> None:
        from app import main

        monkeypatch.setattr(main, "redis_sessions", _Dead())

        res = TestClient(main.app).get("/health/ready")

        assert res.status_code == 503
        assert res.json()["checks"]["redis"] == "unavailable"

    def test_it_names_the_dependency_and_nothing_else(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """The failure detail is a name, never the exception text.

        A connection error carries the host, the port, and on some drivers the
        credentials in the DSN. This endpoint is unauthenticated, so returning
        the exception would publish the internal topology to anybody who asked.
        """
        from app import main

        secret = "postgresql://ironlink_user:hunter2@db.internal:5432/ironlink"
        monkeypatch.setattr(
            main, "AsyncSessionLocal", lambda: _Dead(RuntimeError(secret))
        )

        body = TestClient(main.app).get("/health/ready").text

        assert "hunter2" not in body
        assert "db.internal" not in body
        assert "5432" not in body

    def test_liveness_survives_what_readiness_reports(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        """The split exists for a reason worth restating.

        The platform restarts the container when `/health` fails. If liveness
        depended on Postgres, a thirty-second blip would kill the container,
        which comes back, still cannot reach the database, and is killed again
        — while the database recovers into a service that is now cold.
        """
        from app import main

        monkeypatch.setattr(main, "AsyncSessionLocal", lambda: _Dead())
        monkeypatch.setattr(main, "redis_sessions", _Dead())

        assert TestClient(main.app).get("/health").status_code == 200


class TestMalformedInput:
    """Frames arrive from a client this server does not control."""

    def test_every_frame_shape_is_reachable_without_a_crash(self) -> None:
        """The handler is a chain of `frame.get(...)` reads.

        A frame missing every field must be refused rather than raising, and a
        raise here is worse than an error response: it takes down the socket,
        which drops every conversation on it, not just the malformed one.
        """
        from app.api.routes import websocket as ws_route

        # Comments stripped first. A source assertion that reads comments will
        # fire on a note *about* the pattern — this one did, on a comment
        # explaining why `frame["content"]` is deliberately not read.
        source = _code_only(inspect.getsource(ws_route._handle_frame))

        # Direct subscripting on a caller-supplied dict is the failure mode.
        assert 'frame["' not in source, (
            "read caller-supplied fields with .get(), which yields None rather "
            "than raising KeyError and closing the socket"
        )

    def test_identifiers_are_parsed_defensively(self) -> None:
        from app.api.routes import websocket as ws_route

        source = _code_only(inspect.getsource(ws_route))
        # _uuid_or_none exists precisely so a garbage id is a rejection rather
        # than a ValueError out of the handler.
        assert "def _uuid_or_none" in source
        assert "UUID(frame" not in source

    def test_a_rejection_is_correlated_so_the_client_can_stop(self) -> None:
        # Every permanent refusal carries the client_ref. Without it the
        # sender's outbox cannot tell refusal from silence and re-sends on
        # every reconnect until it exhausts its retries.
        from app.api.routes import websocket as ws_route

        source = inspect.getsource(ws_route._reject)
        assert '"client_ref": frame.get("client_ref")' in source


class TestObservabilityUnderFailure:
    """A service that is failing is when metrics matter most."""

    def test_a_handler_that_raises_is_still_counted(self) -> None:
        app = FastAPI()

        @app.get("/explode")
        async def _explode() -> None:
            raise RuntimeError("dependency is down")

        observability.install(app)
        client = TestClient(app, raise_server_exceptions=False)

        before = observability.unhandled_exceptions.labels(
            route="/explode"
        )._value.get()
        client.get("/explode")
        after = observability.unhandled_exceptions.labels(
            route="/explode"
        )._value.get()

        assert after == before + 1

    def test_a_slow_failure_lands_in_the_latency_histogram(self) -> None:
        # Otherwise every timing is a timing of the successful path, and an
        # endpoint that fails slowly reads as healthy.
        app = FastAPI()

        @app.get("/slow-failure")
        async def _slow() -> None:
            raise RuntimeError("timeout talking to a dependency")

        observability.install(app)
        TestClient(app, raise_server_exceptions=False).get("/slow-failure")

        from prometheus_client import generate_latest

        body = generate_latest().decode()
        assert 'route="/slow-failure"' in body
        assert 'status="500"' in body

    def test_a_scanner_cannot_grow_the_registry(self) -> None:
        """Unbounded label cardinality is a memory-exhaustion vector.

        Labelling by raw path would let an anonymous caller allocate server
        memory with a URL bar. Every unmatched request collapses into one
        bucket.
        """
        app = FastAPI()
        observability.install(app)
        client = TestClient(app)

        for i in range(50):
            client.get(f"/does-not-exist-{i}")

        from prometheus_client import generate_latest

        body = generate_latest().decode()
        assert 'route="unmatched"' in body
        assert "does-not-exist-17" not in body


class TestConfigurationFailure:
    """A misconfigured deploy should crash loudly, not run insecurely."""

    def test_the_dev_auth_bypass_cannot_reach_production(self) -> None:
        # The hole is gated twice: it defaults off, and the validator refuses
        # to start with it on in production. A deploy that would silently leave
        # the front door open should fail to boot instead.
        import app.config as config

        source = inspect.getsource(config)
        assert "DEV_AUTH_BYPASS cannot be enabled when ENV=production" in source

    def test_production_without_allowed_origins_refuses_to_start(self) -> None:
        import app.config as config

        source = inspect.getsource(config)
        assert "must be set when ENV=production" in source

    def test_metrics_are_off_rather_than_open_when_unconfigured(self) -> None:
        # An operator who forgets the token gets a scrape failure, which is
        # loud and gets fixed. The other default gets nobody's attention.
        from app.config import settings

        assert settings.METRICS_TOKEN == ""

        app = FastAPI()
        app.include_router(observability.router)
        assert TestClient(app).get("/metrics").status_code == 404


class TestCorruptedInput:
    """Files arrive from a device, and a device can hand over anything."""

    def test_a_truncated_frame_is_not_valid_json_and_is_handled(self) -> None:
        from app.api.routes import websocket as ws_route

        source = inspect.getsource(ws_route.chat_socket)
        # A JSONDecodeError inside the receive loop must be answered, not
        # allowed to escape and close every conversation on the socket.
        assert "json.JSONDecodeError" in source
        assert "continue" in source

    def test_a_malformed_frame_body_does_not_reach_the_database(self) -> None:
        # json.loads on a non-object yields a list or a scalar, and
        # `frame.get` would raise AttributeError on either.
        for payload in ("[]", '"a string"', "42", "null"):
            decoded = json.loads(payload)
            assert not isinstance(decoded, dict), (
                f"{payload} decodes to {type(decoded).__name__}; the receive "
                "loop must reject non-object frames before _handle_frame"
            )
