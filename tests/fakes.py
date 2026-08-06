from __future__ import annotations


class FakePipeline:
    """Records Redis ops and replays them against FakeRedis on execute()."""

    def __init__(self, redis: "FakeRedis") -> None:
        self._redis = redis
        self._ops: list = []

    def __getattr__(self, name: str):
        def _record(*args, **kwargs):
            self._ops.append((name, args, kwargs))
            return self
        return _record

    async def execute(self):
        results = []
        for name, args, kwargs in self._ops:
            results.append(await getattr(self._redis, name)(*args, **kwargs))
        self._ops.clear()
        return results


class FakeRedis:
    """In-memory async Redis fake — strings + sets, enough for the app surface."""

    def __init__(self) -> None:
        self.store: dict[str, str] = {}
        self.sets: dict[str, set[str]] = {}

    def pipeline(self):
        return FakePipeline(self)

    # ── Strings ────────────────────────────────────────────────────────────────
    async def set(self, key, value, ex=None):
        self.store[key] = str(value)
        return True

    async def get(self, key):
        return self.store.get(key)

    async def getdel(self, key):
        return self.store.pop(key, None)

    async def delete(self, *keys):
        removed = 0
        for k in keys:
            if self.store.pop(k, None) is not None:
                removed += 1
            if self.sets.pop(k, None) is not None:
                removed += 1
        return removed

    async def incr(self, key):
        val = int(self.store.get(key, "0")) + 1
        self.store[key] = str(val)
        return val

    async def exists(self, key):
        return 1 if key in self.store else 0

    async def ttl(self, key):
        return 42 if key in self.store else -2

    async def expire(self, key, seconds):
        return True

    # ── Sets ───────────────────────────────────────────────────────────────────
    async def sadd(self, key, *members):
        s = self.sets.setdefault(key, set())
        before = len(s)
        s.update(str(m) for m in members)
        return len(s) - before

    async def srem(self, key, *members):
        s = self.sets.get(key, set())
        before = len(s)
        s.difference_update(str(m) for m in members)
        return before - len(s)

    async def scard(self, key):
        return len(self.sets.get(key, set()))

    async def sismember(self, key, member):
        return str(member) in self.sets.get(key, set())
