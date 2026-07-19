"""
Tests: daily_brief cache cycle complet — write → read hit → invalidate → miss.

Prouve que le contrat cache promis par daily_brief.py fonctionne end-to-end,
ce que test_daily_brief_invalidation.py ne teste PAS (il vérifie seulement que
l'invalidate est appelé, pas que le cycle DB round-trip). Régression du bug
prod 18/07 : constraint UNIQUE(user_id,date) mismatché par on_conflict="date"
+ .maybe_single() qui explosait sur 406 zéro row — cf. migration 083 et fix
daily_brief.py (limit(1) au lieu de maybe_single).
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

from unittest.mock import patch, MagicMock
from conftest import BaseRouteTest, TODAY


class _FakeTableQuery:
    """Chaîne fluent PostgREST minimale (select/upsert/delete + eq + limit)
    branchée sur un dict in-memory pour simuler la table daily_brief."""

    def __init__(self, store, name):
        self.store = store
        self.name  = name
        self._op   = None
        self._payload = None
        self._conflict = None
        self._filters = []

    def select(self, *_cols):     self._op = "select"; return self
    def upsert(self, data, on_conflict=None):
        self._op = "upsert"; self._payload = data; self._conflict = on_conflict; return self
    def delete(self):             self._op = "delete"; return self
    def eq(self, col, val):       self._filters.append((col, val)); return self
    def limit(self, _n):          return self

    def execute(self):
        table = self.store.setdefault(self.name, [])
        resp = MagicMock()
        if self._op == "select":
            resp.data = [r for r in table if all(r.get(c) == v for c, v in self._filters)]
        elif self._op == "upsert":
            keys = (self._conflict or "").split(",") if self._conflict else []
            if keys:
                match = tuple(self._payload.get(k) for k in keys)
                for i, r in enumerate(table):
                    if tuple(r.get(k) for k in keys) == match:
                        table[i] = self._payload
                        resp.data = [self._payload]; return resp
            table.append(self._payload)
            resp.data = [self._payload]
        elif self._op == "delete":
            table[:] = [r for r in table if not all(r.get(c) == v for c, v in self._filters)]
            resp.data = []
        return resp


class _FakeSupabaseClient:
    def __init__(self):
        self.store = {}
    def table(self, name):
        return _FakeTableQuery(self.store, name)


_FAKE_MORNING_BRIEF = {
    "recommendation": "go",
    "adjustments":    ["Séance Push prévue."],
    "session_today":  "Push",
    "lss":            78,
    "flags":          {},
}


class TestDailyBriefCacheCycle(BaseRouteTest):
    """Cycle complet : cache miss → write → hit → invalidate → miss."""

    def setUp(self):
        super().setUp()
        import db as _db
        self.fake_client = _FakeSupabaseClient()
        self._client_patch = patch.object(_db, "_client", self.fake_client)
        self._client_patch.start()
        self._brief_patch = patch("morning_brief.get_morning_brief",
                                  return_value=_FAKE_MORNING_BRIEF)
        self._brief_patch.start()
        self._today_util_patch = patch("utils._today_mtl", return_value=TODAY)
        self._today_util_patch.start()

    def tearDown(self):
        self._today_util_patch.stop()
        self._brief_patch.stop()
        self._client_patch.stop()
        super().tearDown()

    def test_full_cycle_write_read_invalidate_miss(self):
        # 1. Premier GET : miss → génère + upsert.
        r1 = self.get("/api/coach/daily_brief")
        self.assertEqual(200, r1.status_code)
        body1 = self.json(r1)
        self.assertFalse(body1["cached"], "premier GET doit être un cache miss")
        self.assertEqual(1, len(self.fake_client.store.get("daily_brief", [])),
                         "l'upsert doit avoir écrit une ligne")

        # 2. Second GET : hit — servi depuis la table, generated_at identique.
        r2 = self.get("/api/coach/daily_brief")
        self.assertEqual(200, r2.status_code)
        body2 = self.json(r2)
        self.assertTrue(body2["cached"], "second GET doit être un cache hit")
        self.assertEqual(body1["generated_at"], body2["generated_at"],
                         "hit doit rendre le generated_at persisté, pas un nouveau")

        # 3. Invalidation : DELETE WHERE date=today.
        from routes.daily_brief import invalidate_cache
        invalidate_cache()
        self.assertEqual(0, len(self.fake_client.store.get("daily_brief", [])),
                         "invalidate_cache doit vider la ligne du jour")

        # 4. Troisième GET : miss à nouveau → nouveau generated_at.
        r3 = self.get("/api/coach/daily_brief")
        self.assertEqual(200, r3.status_code)
        body3 = self.json(r3)
        self.assertFalse(body3["cached"], "post-invalidation, GET doit être un miss")
        self.assertNotEqual(body1["generated_at"], body3["generated_at"],
                            "miss doit générer un nouveau generated_at")


class TestDailyBriefCacheReadNoWarning(BaseRouteTest):
    """Sur zéro row, la lecture ne doit PAS logger de warning (cache miss = info)."""

    def setUp(self):
        super().setUp()
        import db as _db
        self.fake_client = _FakeSupabaseClient()
        self._client_patch = patch.object(_db, "_client", self.fake_client)
        self._client_patch.start()
        self._brief_patch = patch("morning_brief.get_morning_brief",
                                  return_value=_FAKE_MORNING_BRIEF)
        self._brief_patch.start()
        self._today_util_patch = patch("utils._today_mtl", return_value=TODAY)
        self._today_util_patch.start()

    def tearDown(self):
        self._today_util_patch.stop()
        self._brief_patch.stop()
        self._client_patch.stop()
        super().tearDown()

    def test_zero_rows_does_not_warn(self):
        with patch("routes.daily_brief.logger") as spy_logger:
            r = self.get("/api/coach/daily_brief")
        self.assertEqual(200, r.status_code)
        self.assertFalse(self.json(r)["cached"])
        spy_logger.warning.assert_not_called()


if __name__ == "__main__":
    import unittest
    unittest.main(verbosity=2)
