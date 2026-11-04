"""Runtime feature control — the ability to turn a shipped capability off.

WHY THIS IS A SECOND MECHANISM, NOT A REPLACEMENT

`frontend/lib/features/keyword_alert/keyword_feature_flags.dart` already exists
and is correct for what it does: compile-time flags that hide unfinished work.
An unfinished capability *should* be compile-time — nobody should be able to
remotely switch on a half-built feature.

This is the other half, and its absence is why v5's completeness scorecard caps
even core messaging at `PARTIAL`: nine shipped capabilities had no way to be
turned off short of a deploy. On the free tier a deploy is minutes of downtime
and a cold start, which means "we can disable it" was not true when it mattered.

THE TRAP THIS DESIGN AVOIDS

The obvious implementation — ask the server whether a feature is on, and treat
"cannot reach the server" as off — turns the flag system into a larger
availability risk than everything it protects. A Redis blip would disable
messaging for every user. The cure would be worse than any disease it treats.

So the fallback is **asymmetric by stage**:

  A feature at GENERAL that cannot be resolved stays ON.
  A feature below GENERAL that cannot be resolved stays OFF.

That is the only defensible pair. A shipped feature is the status quo and an
unreachable config service is not a reason to withdraw it; an unreleased feature
has never been on, and an unreachable config service is certainly not a reason
to start.

WHY THE SERVER NEVER EVALUATES PER USER

The endpoint returns flag *definitions* — stage, kill state, rollout percentage
— identical for every caller. It does not decide who is in a rollout, and the
client evaluates that locally against a random install seed that never leaves
the device.

The usual design has the server answer "is this on for you?", which requires it
to know who is asking and creates a record of which users have which features —
a per-user behavioural profile assembled by the config system, on a product
whose entire premise is that the server knows as little as possible. The cost of
avoiding it is that per-user targeting is impossible here. That is an acceptable
loss; a percentage rollout does everything a staged release actually needs.
"""

from __future__ import annotations

import enum
from dataclasses import dataclass, replace

import structlog

from app.core.redis import redis_sessions

logger = structlog.get_logger("features")


class FeatureStage(enum.StrEnum):
    """The §31.7 lifecycle.

    Ordered, and the order is meaningful: `GENERAL` is the only stage whose
    fallback is on.
    """

    OFF = "off"
    INTERNAL = "internal"
    BETA = "beta"
    LIMITED = "limited"
    GENERAL = "general"


@dataclass(frozen=True, slots=True)
class FeatureFlag:
    key: str
    stage: FeatureStage
    description: str

    #: Emergency stop, independent of stage.
    #:
    #: Separate from moving the stage to OFF because the two mean different
    #: things and are undone differently. Rolling a stage back is a product
    #: decision; killing is an incident response, and it must be visible as one
    #: in the flag's state rather than indistinguishable from a feature that
    #: was never released.
    killed: bool = False

    #: Only meaningful at LIMITED. The client decides locally whether it falls
    #: inside this share — see the module docstring.
    rollout_percent: int = 100

    @property
    def fallback(self) -> bool:
        """What a client should assume when it cannot reach the server.

        The asymmetry described in the module docstring, in one place so it
        cannot drift between the server and the client.
        """
        return self.stage is FeatureStage.GENERAL and not self.killed

    def as_json(self) -> dict[str, object]:
        return {
            "key": self.key,
            "stage": self.stage.value,
            "killed": self.killed,
            "rollout_percent": self.rollout_percent,
            "fallback": self.fallback,
            "description": self.description,
        }


#: Every capability that can be turned off, declared here.
#:
#: The registry is in code rather than in a database because the *set* of flags
#: is a property of the release — a flag naming a capability this build does not
#: have is meaningless — while their *state* is operational and lives in Redis.
#: That split is what lets an operator disable something in seconds without
#: letting anyone invent a flag that no code reads.
#:
#: Everything already shipped starts at GENERAL. A flag introduced over a live
#: feature must not change its behaviour on the day it is added; the point is
#: to gain a switch, not to stage a re-release.
_REGISTRY: dict[str, FeatureFlag] = {
    f.key: f
    for f in (
        FeatureFlag(
            key="messaging",
            stage=FeatureStage.GENERAL,
            description="Direct end-to-end encrypted messaging.",
        ),
        FeatureFlag(
            key="group_messaging",
            stage=FeatureStage.GENERAL,
            description="Group messaging via Sender Keys.",
        ),
        FeatureFlag(
            key="attachments",
            stage=FeatureStage.GENERAL,
            description="Encrypted attachment upload and download.",
        ),
        FeatureFlag(
            key="voice_notes",
            stage=FeatureStage.GENERAL,
            description="Voice note recording and playback.",
        ),
        FeatureFlag(
            key="contact_discovery",
            stage=FeatureStage.GENERAL,
            description="Salted-hash contact discovery.",
        ),
        FeatureFlag(
            key="controlled_group_entry",
            stage=FeatureStage.GENERAL,
            description="Join requests, verification forms, entry audit log.",
        ),
        FeatureFlag(
            key="security_center",
            stage=FeatureStage.GENERAL,
            description="IronShield — sessions, revocation, device posture.",
        ),
        FeatureFlag(
            key="keyword_alert",
            stage=FeatureStage.GENERAL,
            description="IronWatch — on-device document keyword alerting.",
        ),
        FeatureFlag(
            key="scam_intelligence",
            stage=FeatureStage.GENERAL,
            description="On-device scam and link-safety warnings in the bubble.",
        ),
        FeatureFlag(
            key="communities",
            stage=FeatureStage.BETA,
            description=(
                "Communities and channels. Below GENERAL because the "
                "permission boundary is untested — see the audit."
            ),
        ),
        FeatureFlag(
            key="ai_features",
            stage=FeatureStage.LIMITED,
            rollout_percent=100,
            description=(
                "Summarise, translate, smart reply. The only path where "
                "plaintext reaches a third party, consent-gated per "
                "conversation."
            ),
        ),
    )
}


def _redis_key(key: str) -> str:
    return f"feature:{key}"


async def resolved_flags() -> list[FeatureFlag]:
    """The registry with any operator overrides applied.

    Redis is consulted for state only. A key in Redis naming a flag this build
    does not declare is ignored rather than surfaced — otherwise a stale
    override from a previous release would appear in the response as a
    capability that does not exist.

    An unreachable Redis returns the compiled defaults rather than raising. That
    is the same asymmetry the fallback encodes: losing the override store must
    not change what is running.
    """
    flags = list(_REGISTRY.values())
    try:
        raw = await redis_sessions.mget([_redis_key(f.key) for f in flags])
    except Exception as exc:  # noqa: BLE001 — defaults are the safe answer
        logger.warning("feature_overrides_unavailable", error=str(exc))
        return flags

    resolved: list[FeatureFlag] = []
    for flag, override in zip(flags, raw, strict=True):
        if not override:
            resolved.append(flag)
            continue
        resolved.append(_apply(flag, override))
    return resolved


def _apply(flag: FeatureFlag, override: str) -> FeatureFlag:
    """Applies one override string of the form `stage[:percent][:killed]`.

    Deliberately forgiving in one direction only: an override that cannot be
    parsed is discarded and the compiled default stands. A malformed override
    must never be able to enable something, and it must never be able to
    silently disable something either — it simply does not apply.
    """
    parts = override.split(":")
    try:
        stage = FeatureStage(parts[0])
    except ValueError:
        logger.warning("feature_override_invalid", feature=flag.key)
        return flag

    percent = flag.rollout_percent
    killed = flag.killed
    for part in parts[1:]:
        if part == "killed":
            killed = True
        elif part.isdigit():
            percent = max(0, min(100, int(part)))

    return replace(flag, stage=stage, rollout_percent=percent, killed=killed)


def declared_keys() -> frozenset[str]:
    """Every flag this build knows about. Used by tests and by tooling."""
    return frozenset(_REGISTRY)
