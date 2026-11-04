"""Runtime feature control.

Nine shipped capabilities had no way to be turned off short of a deploy, which
is why v5's completeness scorecard caps even core messaging at `PARTIAL`. On the
free tier a deploy is minutes of downtime and a cold start, so "we can disable
it" was not true at the moment it would have mattered.

Most of these tests are about the two ways a flag system does more harm than the
features it governs: by failing in the wrong direction, and by learning who is
asking.
"""

from __future__ import annotations

import inspect

import pytest
from fastapi.testclient import TestClient

from app.core import feature_flags as ff
from app.core.feature_flags import FeatureFlag, FeatureStage


class TestFallbackAsymmetry:
    """The property the whole design exists for."""

    def test_a_shipped_feature_falls_back_on(self) -> None:
        # A config service being unreachable is not a reason to withdraw
        # something that already works. Treating it as one would make this
        # system a larger outage risk than everything it governs.
        flag = FeatureFlag(key="messaging", stage=FeatureStage.GENERAL, description="")
        assert flag.fallback is True

    def test_an_unreleased_feature_falls_back_off(self) -> None:
        for stage in (
            FeatureStage.OFF,
            FeatureStage.INTERNAL,
            FeatureStage.BETA,
            FeatureStage.LIMITED,
        ):
            flag = FeatureFlag(key="x", stage=stage, description="")
            assert flag.fallback is False, stage

    def test_a_killed_feature_falls_back_off_even_at_general(self) -> None:
        # A kill is an incident response. Losing the override store afterwards
        # must not quietly undo it.
        flag = FeatureFlag(
            key="messaging", stage=FeatureStage.GENERAL, killed=True, description=""
        )
        assert flag.fallback is False

    def test_the_rule_lives_in_one_place(self) -> None:
        """Server and client must not drift on this.

        The client re-implements the same rule in Dart. Both derive it from a
        single expression rather than from a list of stages, so adding a stage
        cannot leave one side with a different answer.
        """
        source = inspect.getsource(FeatureFlag.fallback.fget)
        assert "GENERAL" in source and "killed" in source


class TestOverrides:
    @pytest.mark.asyncio
    async def test_an_operator_can_kill_a_shipped_feature(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(ff, "redis_sessions", _Redis({"feature:messaging": "general:killed"}))

        flags = {f.key: f for f in await ff.resolved_flags()}
        assert flags["messaging"].killed is True

    @pytest.mark.asyncio
    async def test_an_operator_can_narrow_a_rollout(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(ff, "redis_sessions", _Redis({"feature:ai_features": "limited:10"}))

        flags = {f.key: f for f in await ff.resolved_flags()}
        assert flags["ai_features"].rollout_percent == 10

    @pytest.mark.asyncio
    async def test_a_malformed_override_changes_nothing(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        # Forgiving in one direction only. A typo must not be able to enable
        # something, and it must not be able to silently disable something
        # either — it simply does not apply.
        monkeypatch.setattr(ff, "redis_sessions", _Redis({"feature:messaging": "genral"}))

        flags = {f.key: f for f in await ff.resolved_flags()}
        assert flags["messaging"].stage is FeatureStage.GENERAL
        assert flags["messaging"].killed is False

    @pytest.mark.asyncio
    async def test_a_percentage_is_clamped(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        monkeypatch.setattr(ff, "redis_sessions", _Redis({"feature:ai_features": "limited:9999"}))

        flags = {f.key: f for f in await ff.resolved_flags()}
        assert flags["ai_features"].rollout_percent == 100

    @pytest.mark.asyncio
    async def test_an_unreachable_override_store_returns_the_defaults(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        # Same asymmetry, one level down. Losing the override store must not
        # change what is running.
        monkeypatch.setattr(ff, "redis_sessions", _DeadRedis())

        flags = {f.key: f for f in await ff.resolved_flags()}
        assert flags["messaging"].stage is FeatureStage.GENERAL
        assert len(flags) == len(ff.declared_keys())

    @pytest.mark.asyncio
    async def test_an_override_for_an_unknown_flag_is_ignored(
        self, monkeypatch: pytest.MonkeyPatch
    ) -> None:
        # A stale override from a previous release must not appear in the
        # response as a capability this build does not have.
        monkeypatch.setattr(
            ff, "redis_sessions", _Redis({"feature:ironcanvas": "general"})
        )

        keys = {f.key for f in await ff.resolved_flags()}
        assert "ironcanvas" not in keys


class TestTheEndpointLearnsNothing:
    """What makes a config service acceptable in this product."""

    def _app(self):
        from fastapi import FastAPI

        from app.api.routes import features

        app = FastAPI()
        app.include_router(features.router)
        return app

    def test_it_needs_no_authentication(self) -> None:
        # A kill switch that requires a session cannot disable a broken
        # sign-in screen.
        res = TestClient(self._app()).get("/features")
        assert res.status_code == 200

    def test_the_response_is_identical_for_every_caller(self) -> None:
        client = TestClient(self._app())
        first = client.get("/features").text
        second = client.get(
            "/features", headers={"Authorization": "Bearer somebody"}
        ).text
        assert first == second

    def test_it_returns_definitions_not_decisions(self) -> None:
        """The server never evaluates a rollout for a caller.

        Had it done so it would need to know who was asking, and would
        accumulate a record of which users have which features — a behavioural
        profile assembled by the configuration system.
        """
        body = TestClient(self._app()).get("/features").json()
        for flag in body["flags"]:
            assert set(flag) == {
                "key",
                "stage",
                "killed",
                "rollout_percent",
                "fallback",
                "description",
            }
            assert "enabled" not in flag, (
                "an 'enabled' field would mean the server decided for someone"
            )

    def test_it_is_cacheable(self) -> None:
        # Sixty seconds: not a request per launch per user, and an emergency
        # kill still reaches everyone within a minute.
        res = TestClient(self._app()).get("/features")
        assert "max-age=60" in res.headers.get("Cache-Control", "")


class TestRegistry:
    def test_every_shipped_capability_starts_general(self) -> None:
        """Adding a flag over a live feature must not change its behaviour.

        The point of introducing one is to gain a switch, not to stage a
        re-release of something people are already using.
        """
        shipped = {
            "messaging",
            "group_messaging",
            "attachments",
            "voice_notes",
            "contact_discovery",
            "controlled_group_entry",
            "security_center",
            "keyword_alert",
            "scam_intelligence",
        }
        registry = {f.key: f for f in ff._REGISTRY.values()}
        for key in shipped:
            assert registry[key].stage is FeatureStage.GENERAL, key
            assert registry[key].killed is False, key

    def test_communities_is_below_general(self) -> None:
        # The audit marks its permission boundary untested. A flag is how that
        # is stated in running code rather than only in a document.
        assert ff._REGISTRY["communities"].stage is FeatureStage.BETA

    def test_every_flag_explains_itself(self) -> None:
        for flag in ff._REGISTRY.values():
            assert flag.description.strip(), flag.key


class _Redis:
    def __init__(self, values: dict[str, str]) -> None:
        self._values = values

    async def mget(self, keys: list[str]) -> list[str | None]:
        return [self._values.get(k) for k in keys]


class _DeadRedis:
    async def mget(self, keys: list[str]) -> list[str | None]:
        raise ConnectionError("override store unreachable")
