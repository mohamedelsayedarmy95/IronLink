"""Metrics, structured logging, and request correlation.

WHAT THIS IS FOR

The engineering standard requires that success and failure both be visible
without exposing user data, and that latency be reported as p50/p95/p99 rather
than as an average. Averages hide the thing that matters: a p50 of 40 ms and a
p99 of 9 s is a service that is broken for one user in a hundred, and its mean
looks fine.

Until this module existed the repository had no metrics of any kind, and
`structlog` was imported in five files without ever being configured — so it
fell back to its console renderer, meaning production logs were neither JSON
nor timestamped, and the word "structured" in the standard was aspirational.

THE PRIVACY CONSTRAINT IS THE DESIGN CONSTRAINT

Telemetry on a messenger is an unusually sharp instrument. It is not enough to
avoid logging message bodies: a metric labelled by user id reveals who is
active and when, and a metric labelled by chat id reveals the shape of the
social graph. Traffic timing on a product whose users may be targeted is itself
intelligence about them.

So the rule here is stronger than "no content". No metric carries a user, a
chat, a group, a device, or a phone number in any label. What is measured is
the *service* — which route, which method, which status, how long — and never
who was asking.

CARDINALITY IS A SAFETY PROPERTY, NOT A TIDINESS ONE

Labels are keyed on the matched route *template* — `/api/v1/chats/{chat_id}` —
never the raw path. The raw path contains identifiers, so labelling by it would
both leak them and let anyone with a URL bar allocate unbounded server memory
by requesting random paths. Unmatched requests collapse into a single bucket
for exactly that reason.
"""

from __future__ import annotations

import logging
import secrets
import time
import uuid
from collections.abc import Awaitable, Callable
from typing import Any

import structlog
from fastapi import APIRouter, FastAPI, HTTPException, Request, Response, status
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Gauge, Histogram
from prometheus_client import generate_latest
from starlette.middleware.base import BaseHTTPMiddleware

from app.config import settings

# ─────────────────────────────────────────────────────────── redaction ──

#: Field names whose values must never reach a log sink.
#:
#: This is enforcement, not documentation. Every log call in the repository was
#: read before this was written and none of them carried a message body, an OTP,
#: or key material — but "we checked once" is not a control. A processor that
#: censors by key name keeps the property true for log calls nobody has written
#: yet, which are the ones that will get it wrong.
#:
#: Matched as substrings, so `otp_code`, `message_content` and `phone_number`
#: are all caught by their stems.
SENSITIVE_FIELDS: tuple[str, ...] = (
    "password",
    "passphrase",
    "secret",
    "otp",
    "credential",
    "authorization",
    "bearer",
    "private_key",
    "session_key",
    "secret_key",
    "api_key",
    "access_key",
    "plaintext",
    "ciphertext",
    "content",
    "body",
    "text",
    "caption",
    "transcript",
    "keyword",
    "phone",
    "msisdn",
    "email",
)

REDACTED = "[redacted]"


def redact_sensitive(
    _logger: Any, _name: str, event: dict[str, Any]
) -> dict[str, Any]:
    """Censors values whose key names indicate they carry user data.

    Deliberately blunt. It will censor a field that happened to be harmless,
    and that is the correct direction to be wrong in: an over-redacted log
    costs a developer one round trip, while an under-redacted one puts a
    message body in a log aggregator that a dozen systems can read and that
    nobody can un-send.
    """
    for key in list(event):
        lowered = key.lower()
        if any(part in lowered for part in SENSITIVE_FIELDS):
            event[key] = REDACTED
    return event


def configure_logging() -> None:
    """Installs the log pipeline. Idempotent; safe to call from tests.

    JSON everywhere except local development, where a human is reading it and
    the console renderer is worth more than machine parsing.
    """
    renderer: Any = (
        structlog.dev.ConsoleRenderer()
        if settings.ENV == "development"
        else structlog.processors.JSONRenderer()
    )

    structlog.configure(
        processors=[
            structlog.contextvars.merge_contextvars,
            structlog.processors.add_log_level,
            structlog.processors.TimeStamper(fmt="iso", utc=True),
            # Last before rendering, so it also censors fields bound into the
            # context by middleware rather than passed at the call site.
            redact_sensitive,
            structlog.processors.StackInfoRenderer(),
            structlog.processors.format_exc_info,
            renderer,
        ],
        wrapper_class=structlog.make_filtering_bound_logger(
            logging.DEBUG if settings.DEBUG else logging.INFO
        ),
        logger_factory=structlog.PrintLoggerFactory(),
        cache_logger_on_first_use=True,
    )


# ───────────────────────────────────────────────────────────── metrics ──

#: Buckets chosen for an API that should answer in tens of milliseconds, with
#: enough resolution above one second to distinguish "slow" from "hung". The
#: default prometheus buckets start at 5 ms and jump to 10 s, which puts almost
#: every request this service serves into one or two buckets and makes the
#: resulting p95 an artefact of the bucket edges rather than a measurement.
_LATENCY_BUCKETS = (
    0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0, 10.0,
)

http_requests = Counter(
    "ironlink_http_requests_total",
    "HTTP requests, by route template, method and status class.",
    ("method", "route", "status"),
)

http_latency = Histogram(
    "ironlink_http_request_duration_seconds",
    "Request handling time, by route template.",
    ("method", "route"),
    buckets=_LATENCY_BUCKETS,
)

unhandled_exceptions = Counter(
    "ironlink_unhandled_exceptions_total",
    "Requests that raised out of the handler.",
    ("route",),
)

websocket_connections = Gauge(
    "ironlink_websocket_connections",
    "Currently open WebSocket connections.",
)

messages_accepted = Counter(
    "ironlink_messages_accepted_total",
    "Ciphertext envelopes accepted for delivery, by conversation kind.",
    ("kind",),
)

message_delivery = Counter(
    "ironlink_message_delivery_total",
    "Delivery attempts by outcome — whether the recipient was connected.",
    ("outcome",),
)

self_destruct_overdue = Gauge(
    "ironlink_self_destruct_overdue",
    "Expired messages found by the most recent sweep — the sweeper's backlog.",
)

self_destruct_wiped = Counter(
    "ironlink_self_destruct_wiped_total",
    "Expired messages wiped since this process started.",
)

retention_deleted = Counter(
    "ironlink_retention_deleted_total",
    "Records removed by the retention sweeper, by table. A sudden spike is "
    "the only warning that a sweeper has started deleting more than it should.",
    ("table",),
)

retention_failures = Counter(
    "ironlink_retention_failures_total",
    "Retention sweeps that raised. A rising count means data is outliving its "
    "stated limit, which is a privacy failure rather than a slow job.",
)

orphaned_attachments = Gauge(
    "ironlink_orphaned_attachments",
    "Attachment bodies whose message was deleted but whose object storage "
    "delete has not yet succeeded. Non-zero means a user's deletion is "
    "incomplete, which is a privacy failure rather than a storage one.",
)

self_destruct_failures = Counter(
    "ironlink_self_destruct_failures_total",
    "Sweeps that raised. A rising count means messages are outliving their "
    "expiry, which is a privacy failure rather than a performance one.",
)


class ObservabilityMiddleware(BaseHTTPMiddleware):
    """Times every request, counts it, and gives it a correlation id.

    The id comes from `X-Request-ID` when the caller supplied one and is
    generated otherwise, is bound into the log context for the life of the
    request, and is echoed back on the response. That is what makes a user's
    report of "it failed at about four o'clock" resolvable to a specific log
    line without needing to search by anything that identifies them.
    """

    async def dispatch(
        self,
        request: Request,
        call_next: Callable[[Request], Awaitable[Response]],
    ) -> Response:
        request_id = request.headers.get("X-Request-ID") or uuid.uuid4().hex
        structlog.contextvars.clear_contextvars()
        structlog.contextvars.bind_contextvars(request_id=request_id)

        started = time.perf_counter()
        try:
            response = await call_next(request)
        except Exception:
            # The route is known even on the failure path, because the router
            # matched before the handler ran.
            unhandled_exceptions.labels(route=_route_of(request)).inc()
            _record(request, "500", time.perf_counter() - started)
            raise

        _record(request, str(response.status_code), time.perf_counter() - started)
        response.headers["X-Request-ID"] = request_id
        return response


def _record(request: Request, status_code: str, elapsed: float) -> None:
    route = _route_of(request)
    http_latency.labels(method=request.method, route=route).observe(elapsed)
    http_requests.labels(
        method=request.method, route=route, status=status_code
    ).inc()


def _route_of(request: Request) -> str:
    """The matched route template, or a single bucket for everything else.

    Anything unmatched — a scanner walking paths, a typo, a probe — collapses
    into one label value. Using the raw path here would leak the identifiers
    embedded in it and would let an anonymous caller grow the metric registry
    without limit, which is a memory-exhaustion vector wearing a monitoring
    costume.
    """
    route = request.scope.get("route")
    path = getattr(route, "path", None)
    return path if isinstance(path, str) else "unmatched"


# ───────────────────────────────────────────────────────────── exposure ──

router = APIRouter(tags=["infra"])


@router.get("/metrics", include_in_schema=False)
async def metrics(request: Request) -> Response:
    """Prometheus exposition, behind a bearer token.

    Not public, and disabled outright when no token is configured rather than
    defaulting to open. A metrics page on this product is not a neutral
    operational detail: it publishes how many people are connected, when
    traffic rises and falls, and which endpoints are failing. For users who may
    be targeted, that pattern is information about them even though no metric
    names one of them.

    Fail-closed matters more than convenience here. An operator who forgets to
    set the token gets a scrape failure, which is loud and gets fixed. The
    other default gets nobody's attention and stays open.
    """
    expected = settings.METRICS_TOKEN
    if not expected:
        raise HTTPException(status.HTTP_404_NOT_FOUND)

    supplied = request.headers.get("Authorization", "")
    scheme, _, token = supplied.partition(" ")
    # compare_digest, not ==, so the failure time does not depend on how many
    # leading characters were right.
    if scheme.lower() != "bearer" or not secrets.compare_digest(token, expected):
        raise HTTPException(status.HTTP_401_UNAUTHORIZED)

    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


def install(app: FastAPI) -> None:
    """Wires logging, the middleware, and the metrics route into an app."""
    configure_logging()
    app.add_middleware(ObservabilityMiddleware)
    app.include_router(router)
