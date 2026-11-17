"""
Tests: RPE au demi-point (migration 107) et complétion de la séance du soir par id.

Incident 2026-11-17 : RPE 7.5 refusé (prod en smallint), séance du soir non terminée.
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

import unittest
from types import SimpleNamespace
from unittest.mock import patch

from conftest import BaseRouteTest, TODAY
import db_core
import db_sessions


class _FakeQuery:
    """Chaîne PostgREST minimale : enregistre update() et filtres, renvoie `rows`."""

    def __init__(self, client):
        self.client = client

    def __getattr__(self, name):          # select / eq / single / limit ... → chaînable
        def chain(*args, **kwargs):
            if name == "update":
                self.client.updates.append(args[0])
            if name == "eq":
                self.client.filters.append(args)
            return self
        return chain

    def execute(self):
        return SimpleNamespace(data=self.client.rows, count=len(self.client.rows))


class _FakeClient:
    def __init__(self, rows):
        self.rows = rows
        self.updates = []
        self.filters = []

    def table(self, name):
        return _FakeQuery(self)


class _OnlineDB(unittest.TestCase):
    def use_client(self, rows):
        client = _FakeClient(rows)
        for p in (patch.object(db_core, "_client", client),
                  patch.object(db_core, "MODE", "ONLINE"),
                  patch.object(db_core, "_is_disconnect", return_value=False)):
            p.start()
            self.addCleanup(p.stop)
        return client


class TestRoundRpeHalf(unittest.TestCase):

    def test_half_points(self):
        for given, expected in [(7.5, 7.5), (7.3, 7.5), (7.25, 7.5), (7.2, 7.0),
                                (8, 8.0), ("7.5", 7.5), (9.75, 10.0)]:
            with self.subTest(given=given):
                self.assertEqual(expected, db_sessions._round_rpe_half(given))

    def test_normalize_patch(self):
        self.assertEqual(
            {"rpe": 7.5, "comment": "", "duration_min": 41, "energy_pre": 3, "session_name": "PM"},
            db_sessions._normalize_session_patch({
                "rpe": 7.3, "comment": "", "duration_min": 41.0, "energy_pre": 3.0,
                "session_name": "PM", "completed": False, "unknown": 1, "date": "x",
            }),
        )
        self.assertEqual({}, db_sessions._normalize_session_patch({"rpe": None}))
        self.assertEqual({}, db_sessions._normalize_session_patch(None))


class TestMorningEveningSameRule(_OnlineDB):

    def test_morning_and_evening_write_same_payload(self):
        patch_in = {"rpe": 7.3, "comment": "ok", "duration_min": 41.0, "energy_pre": 3,
                    "session_name": "Pull A"}
        morning = self.use_client([{"id": "am"}])
        self.assertTrue(db_sessions.complete_workout_session(TODAY, patch=patch_in))
        evening = self.use_client([{"id": "pm"}])
        self.assertTrue(db_sessions.complete_workout_session_by_id("pm", patch_in))
        expected = {"completed": True, "rpe": 7.5, "comment": "ok", "duration_min": 41,
                    "energy_pre": 3, "session_name": "Pull A"}
        self.assertEqual([expected], morning.updates)
        self.assertEqual([expected], evening.updates)

    def test_update_workout_session_keeps_half_point(self):
        client = self.use_client([{"id": "am"}])
        self.assertTrue(db_sessions.update_workout_session(TODAY, {"rpe": 7.5, "duration_min": 40.0}))
        self.assertEqual([{"rpe": 7.5, "duration_min": 40}], client.updates)


class TestCompleteById(_OnlineDB):

    def test_targets_single_id_key(self):
        client = self.use_client([{"id": "pm-1"}])
        self.assertTrue(db_sessions.complete_workout_session_by_id("pm-1", {"rpe": 7.5}))
        self.assertEqual([("id", "pm-1")], client.filters)
        self.assertEqual([{"completed": True, "rpe": 7.5}], client.updates)

    def test_zero_row_is_logged_failure(self):
        self.use_client([])
        with self.assertLogs(db_core.logger, level="ERROR") as logs:
            self.assertFalse(db_sessions.complete_workout_session_by_id("pm-404", {"rpe": 7.5}))
        self.assertIn("complete_workout_session_by_id(pm-404): 0 row updated", logs.output[0])


class TestEveningRouteZeroRow(BaseRouteTest):
    """Route complète : 0 ligne touchée → 500 explicite + log, jamais de succès."""

    def test_zero_row_returns_500_and_logs(self):
        db = sys.modules["db"]
        db.get_or_create_workout_session_second = lambda date: {"id": "pm-1", "completed": False}
        db.complete_workout_session_by_id = db_sessions.complete_workout_session_by_id
        client = _FakeClient([])
        with patch.object(db_core, "_client", client), patch.object(db_core, "MODE", "ONLINE"), \
                patch.object(db_core, "_is_disconnect", return_value=False), \
                self.assertLogs(db_core.logger, level="ERROR") as logs:
            response = self.post("/api/log_session",
                                 {"date": TODAY, "second_session": True, "rpe": 7.5})
        self.assertEqual(500, response.status_code)
        self.assertNotIn("success", self.json(response))
        self.assertEqual([("id", "pm-1")], client.filters)
        self.assertEqual([{"completed": True, "rpe": 7.5, "comment": ""}], client.updates)
        self.assertTrue(any("0 row updated" in line for line in logs.output))


if __name__ == "__main__":
    unittest.main()
