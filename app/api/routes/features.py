"""Feature flag definitions, identical for every caller.

WHY THIS IS UNAUTHENTICATED AND WHY THAT IS THE POINT

The response is the same bytes for everybody: which capabilities exist, what
stage each is at, whether any has been killed, and what share of installs a
staged rollout covers. It contains nothing about the caller because the server
never evaluates a flag for a caller — the client does that locally against a
random install seed that never leaves the device.

The usual design asks the server "is this on for me?", which requires it to know
who is asking and produces, as a side effect, a record of which users have which
features. That is a per-user behavioural profile assembled by the config system,
on a product whose premise is that the server knows as little as it can. Leaving
this endpoint anonymous is what makes that record impossible rather than merely
unwritten.

It is also the reason the flags must be reachable before sign-in: a kill switch
that only works for authenticated users cannot disable a broken authentication
screen.
"""

from __future__ import annotations

from fastapi import APIRouter, Response

from app.core.feature_flags import resolved_flags

router = APIRouter(tags=["infra"])


@router.get("/features")
async def features(response: Response) -> dict[str, object]:
    """Every capability this build can turn off, and its current state.

    Cached briefly at the edge. Sixty seconds is a deliberate compromise: long
    enough that this is not a request per app launch per user, short enough that
    an emergency kill reaches everyone within a minute. A kill switch nobody
    receives for an hour is a kill switch in name.
    """
    response.headers["Cache-Control"] = "public, max-age=60"
    flags = await resolved_flags()
    return {"flags": [flag.as_json() for flag in flags]}
