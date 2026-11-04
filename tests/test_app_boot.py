"""Import-time smoke tests.

Every deploy failure in this service so far has been an import-time crash:
uvicorn imports app.main, something raises, and the container dies before it
ever binds a port. Nothing in the suite imported app.main, so all of it passed
against code that could not start.

These tests are deliberately shallow. They do not touch the database, Redis, or
object storage — they assert only that the application object can be built,
which is the precondition for every other test being meaningful.
"""
from __future__ import annotations

import pytest
from fastapi.routing import APIRoute


def test_app_imports() -> None:
    """The whole point: catch import-time failures before a deploy does."""
    from app.main import app

    assert app is not None


def test_no_204_route_declares_a_response_body() -> None:
    """FastAPI asserts at import time that a 204 cannot carry a body.

    This is subtle enough to be worth pinning. Every module here uses
    `from __future__ import annotations`, so a `-> None` return annotation is
    stored as a string and later resolved by get_type_hints to the *class*
    NoneType. FastAPI infers response_model from that annotation, and NoneType
    is truthy, so the framework concludes the route returns a body and the
    assertion fires — taking down the entire application on import, not just
    the offending route.

    The fix is an explicit response_model=None on every 204 route. This test
    fails if anyone adds a 204 without it.
    """
    from app.main import app

    offenders = [
        f"{sorted(route.methods)} {route.path}"
        for route in app.routes
        if isinstance(route, APIRoute)
        and route.status_code == 204
        and route.response_model is not None
    ]
    assert not offenders, (
        "204 routes must set response_model=None explicitly; offenders: "
        + ", ".join(offenders)
    )


def test_openapi_schema_builds() -> None:
    """Schema generation exercises every route's models and catches bad refs."""
    from app.main import app

    schema = app.openapi()
    assert schema["paths"], "no routes registered"


@pytest.mark.parametrize(
    "path",
    ["/health", "/api/v1/auth/verify", "/api/v1/channels", "/api/v1/communities"],
)
def test_expected_routes_registered(path: str) -> None:
    """Guards against a router silently failing to be included."""
    from app.main import app

    assert path in app.openapi()["paths"], f"{path} is not registered"
