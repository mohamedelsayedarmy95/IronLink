"""Observability, held to the constraint that makes it hard here.

Most of these are not tests that metrics work. They are tests that metrics do
not become a second, quieter copy of the data the product exists to protect —
a `/metrics` page that any scraper can read, labelled by user id, would undo
the encryption above it without decrypting anything.
"""

from __future__ import annotations

import pytest
from fastapi import FastAPI
from fastapi.testclient import TestClient

from app.config import settings
from app.core import observability
from app.core.observability import REDACTED, redact_sensitive


# ─────────────────────────────────────────────────────── log redaction ──


class TestRedaction:
    def test_a_message_body_never_reaches_a_log(self) -> None:
        event = redact_sensitive(None, "info", {"content": "meet me at six"})
        assert event["content"] == REDACTED

    def test_an_otp_never_reaches_a_log(self) -> None:
        event = redact_sensitive(None, "info", {"otp_code": "418902"})
        assert event["otp_code"] == REDACTED

    def test_a_phone_number_never_reaches_a_log(self) -> None:
        event = redact_sensitive(None, "info", {"phone_number": "+201234567890"})
        assert event["phone_number"] == REDACTED

    def test_key_material_never_reaches_a_log(self) -> None:
        for field in ("private_key", "session_key", "ciphertext", "plaintext"):
            event = redact_sensitive(None, "info", {field: "AAAA"})
            assert event[field] == REDACTED, field

    def test_a_users_own_keyword_never_reaches_a_log(self) -> None:
        # The keyword list is the user's private watchlist. It was already kept
        # out of the FCM payload for the same reason; a log sink is no better a
        # place for it than Google is.
        event = redact_sensitive(None, "info", {"keyword": "extraction"})
        assert event["keyword"] == REDACTED

    def test_operational_fields_survive(self) -> None:
        # Redaction that swallows the diagnostics is a log nobody can use, and
        # a log nobody can use gets replaced by print statements.
        event = redact_sensitive(
            None,
            "info",
            {"event": "sweep", "wiped": 12, "duration_ms": 40, "status": 200},
        )
        assert event == {
            "event": "sweep",
            "wiped": 12,
            "duration_ms": 40,
            "status": 200,
        }

    def test_matching_is_on_the_stem_not_the_exact_name(self) -> None:
        # The point of matching substrings: a field nobody anticipated the
        # exact spelling of is still caught.
        for field in ("user_email_address", "sms_body", "reply_text"):
            event = redact_sensitive(None, "info", {field: "x"})
            assert event[field] == REDACTED, field


# ──────────────────────────────────────────────────────── /metrics gate ──


@pytest.fixture()
def app_with_metrics() -> FastAPI:
    app = FastAPI()
    app.include_router(observability.router)
    return app


class TestMetricsEndpoint:
    def test_absent_entirely_when_no_token_is_configured(
        self, app_with_metrics: FastAPI, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        # 404 rather than 401: an unauthenticated caller should not be able to
        # confirm the endpoint is even there, and an operator who forgets to
        # set the token gets a service with no metrics page rather than an
        # open one.
        monkeypatch.setattr(settings, "METRICS_TOKEN", "")
        assert TestClient(app_with_metrics).get("/metrics").status_code == 404

    def test_rejects_a_request_with_no_token(
        self, app_with_metrics: FastAPI, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "METRICS_TOKEN", "s3cret")
        assert TestClient(app_with_metrics).get("/metrics").status_code == 401

    def test_rejects_a_wrong_token(
        self, app_with_metrics: FastAPI, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "METRICS_TOKEN", "s3cret")
        res = TestClient(app_with_metrics).get(
            "/metrics", headers={"Authorization": "Bearer wrong"}
        )
        assert res.status_code == 401

    def test_rejects_the_right_token_under_the_wrong_scheme(
        self, app_with_metrics: FastAPI, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "METRICS_TOKEN", "s3cret")
        res = TestClient(app_with_metrics).get(
            "/metrics", headers={"Authorization": "Basic s3cret"}
        )
        assert res.status_code == 401

    def test_serves_prometheus_text_to_a_valid_token(
        self, app_with_metrics: FastAPI, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(settings, "METRICS_TOKEN", "s3cret")
        res = TestClient(app_with_metrics).get(
            "/metrics", headers={"Authorization": "Bearer s3cret"}
        )
        assert res.status_code == 200
        assert "ironlink_http_requests_total" in res.text

    def test_is_not_in_the_public_schema(self, app_with_metrics: FastAPI) -> None:
        schema = app_with_metrics.openapi()
        assert "/metrics" not in schema["paths"]


# ────────────────────────────────────────────── labels carry no identity ──


class TestNoIdentityInLabels:
    """The property that makes this telemetry safe to keep.

    A metric labelled by user id tells a reader who was active and when. A
    metric labelled by chat id draws the social graph. Neither needs to decrypt
    anything to do it, so neither is covered by the encryption elsewhere — this
    has to be prevented here or not at all.
    """

    FORBIDDEN = {
        "user",
        "user_id",
        "sender",
        "sender_id",
        "recipient",
        "recipient_id",
        "chat",
        "chat_id",
        "group",
        "group_id",
        "device",
        "device_id",
        "phone",
        "phone_number",
        "ip",
        "ip_address",
        "session",
        "session_id",
    }

    def test_no_metric_is_labelled_by_anything_identifying(self) -> None:
        offenders = []
        for name in dir(observability):
            metric = getattr(observability, name)
            labels = getattr(metric, "_labelnames", None)
            if not labels:
                continue
            for label in labels:
                if label.lower() in self.FORBIDDEN:
                    offenders.append(f"{name}.{label}")
        assert offenders == [], f"identifying labels: {offenders}"

    def test_the_route_label_is_a_template_not_a_path(self) -> None:
        # `/api/v1/chats/{chat_id}` and never `/api/v1/chats/9f3c...`. The raw
        # path carries the identifier, so labelling by it would publish the id
        # and would also let anyone with a URL bar grow the registry without
        # limit by requesting random paths — memory exhaustion in a monitoring
        # costume.
        app = FastAPI()

        @app.get("/things/{thing_id}")
        async def _thing(thing_id: str) -> dict[str, str]:
            return {"id": thing_id}

        observability.install(app)
        client = TestClient(app)
        client.get("/things/9f3c-secret-identifier")

        body = _scrape(app)
        assert 'route="/things/{thing_id}"' in body
        assert "9f3c-secret-identifier" not in body

    def test_unmatched_paths_collapse_into_one_label(self) -> None:
        app = FastAPI()
        observability.install(app)
        client = TestClient(app)
        for path in ("/wp-admin", "/.env", "/phpmyadmin"):
            client.get(path)

        body = _scrape(app)
        assert 'route="unmatched"' in body
        assert "wp-admin" not in body
        assert ".env" not in body


# ───────────────────────────────────────────────────────── middleware ──


class TestMiddleware:
    def test_a_request_is_counted_and_timed(self) -> None:
        app = FastAPI()

        @app.get("/ping")
        async def _ping() -> dict[str, str]:
            return {"ok": "yes"}

        observability.install(app)
        TestClient(app).get("/ping")

        body = _scrape(app)
        assert 'ironlink_http_requests_total{method="GET",route="/ping",status="200"}' in body
        # The histogram is what produces p50/p95/p99. A mean would hide the
        # case that matters: a service fast for everyone except one user in a
        # hundred has an unremarkable average.
        assert 'ironlink_http_request_duration_seconds_bucket{le="0.05"' in body

    def test_a_generated_request_id_comes_back_on_the_response(self) -> None:
        app = FastAPI()

        @app.get("/ping")
        async def _ping() -> dict[str, str]:
            return {"ok": "yes"}

        observability.install(app)
        res = TestClient(app).get("/ping")
        assert res.headers["X-Request-ID"]

    def test_a_supplied_request_id_is_kept(self) -> None:
        # So a user's "it failed around four o'clock" resolves to one log line
        # without searching by anything that identifies them.
        app = FastAPI()

        @app.get("/ping")
        async def _ping() -> dict[str, str]:
            return {"ok": "yes"}

        observability.install(app)
        res = TestClient(app).get("/ping", headers={"X-Request-ID": "abc123"})
        assert res.headers["X-Request-ID"] == "abc123"

    def test_a_handler_that_raises_is_counted_before_the_error_propagates(
        self,
    ) -> None:
        app = FastAPI()

        @app.get("/boom")
        async def _boom() -> None:
            raise RuntimeError("nope")

        observability.install(app)
        client = TestClient(app, raise_server_exceptions=False)

        before = _value(observability.unhandled_exceptions, route="/boom")
        client.get("/boom")
        assert _value(observability.unhandled_exceptions, route="/boom") == before + 1

    def test_a_failed_request_still_lands_in_the_latency_histogram(self) -> None:
        # Otherwise every timing is a timing of the successful path, and an
        # endpoint that fails slowly looks healthy.
        app = FastAPI()

        @app.get("/boom2")
        async def _boom2() -> None:
            raise RuntimeError("nope")

        observability.install(app)
        TestClient(app, raise_server_exceptions=False).get("/boom2")

        body = _scrape(app)
        assert 'route="/boom2"' in body
        assert 'status="500"' in body


# ─────────────────────────────────────────────────────────── helpers ──


def _scrape(app: FastAPI) -> str:
    from prometheus_client import generate_latest

    return generate_latest().decode()


def _value(counter, **labels) -> float:
    return counter.labels(**labels)._value.get()
