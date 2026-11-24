"""Build 3b — cache readiness vidé après toute écriture réussie ; TTL 5 min."""
import os
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

from conftest import BaseRouteTest


class AfterRequestInvalidationTests(BaseRouteTest):
    def setUp(self):
        super().setUp()
        self.readiness = sys.modules["readiness"] if "readiness" in sys.modules else __import__("readiness")

    def seed(self):
        self.readiness._CACHE["result"] = {"data": {"score": 70}, "ts": 0}

    def cached(self):
        return "result" in self.readiness._CACHE

    def hook(self, method, status):
        from flask import Response
        with self.app.test_request_context("/x", method=method):
            return self.idx._invalidate_readiness_after_write(Response(status=status))

    def test_successful_writes_clear_cache(self):
        for method in ("POST", "PUT", "PATCH", "DELETE"):
            self.seed()
            self.hook(method, 200)
            self.assertFalse(self.cached(), method)
        self.seed()
        self.hook("POST", 201)
        self.assertFalse(self.cached())

    def test_reads_and_failed_writes_keep_cache(self):
        for method, status in (("GET", 200), ("POST", 400), ("POST", 404), ("DELETE", 500), ("POST", 302)):
            self.seed()
            self.hook(method, status)
            self.assertTrue(self.cached(), (method, status))

    def test_real_route_post_clears_and_unknown_route_does_not(self):
        self.seed()
        r = self.client.post("/api/route-inexistante", json={})
        self.assertEqual(r.status_code, 404)
        self.assertTrue(self.cached())
        r = self.client.post("/api/delete_recovery", json={"date": "2026-11-23"})
        self.assertEqual(r.status_code, 200)
        self.assertFalse(self.cached())

    def test_session_write_then_readiness_get_recomputes(self):
        self.seed()
        self.client.post("/api/delete_recovery", json={"date": "2026-11-23"})   # écriture réussie
        fresh = {"score": 81, "verdict": "go", "why": "recalculé", "modules": {}, "muscle_recovery": {}}
        with patch("routes.readiness._r.compute", return_value=fresh) as compute:
            r = self.client.get("/api/readiness")
        self.assertEqual(r.status_code, 200)
        compute.assert_called_once()
        self.assertEqual(r.get_json()["score"], 81)


class ReadinessTTLTests(unittest.TestCase):
    def test_ttl_is_five_minutes_and_expires(self):
        import readiness as r
        self.assertEqual(r.READINESS_CACHE_TTL_SECONDS, 300)
        r.invalidate_cache()
        r._CACHE["result"] = {"data": {"score": 70, "cached": True}, "ts": 1_000.0}
        with patch.object(r._time, "time", return_value=1_000.0 + 299):
            self.assertTrue(r.compute().get("cached"))      # encore valide
        with patch.object(r._time, "time", return_value=1_000.0 + 301), \
             patch.object(r.db, "get_recovery_logs", side_effect=RuntimeError("recalcul demandé")):
            with self.assertRaises(RuntimeError):              # expiré → recalcul
                r.compute()
        r.invalidate_cache()


if __name__ == "__main__":
    unittest.main()
