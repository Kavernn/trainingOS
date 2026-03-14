"""
Tests: session and HIIT mutation routes.

Routes covered:
  POST /api/session/edit
  POST /api/session/delete
  POST /api/log_session
  POST /api/log_hiit
  POST /api/delete_hiit
  POST /api/hiit/edit
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

from unittest.mock import patch
from conftest import BaseRouteTest, TODAY


# ── /api/session/edit ─────────────────────────────────────────────────────────

class TestSessionEdit(BaseRouteTest):

    def test_edit_rpe(self):
        r = self.post("/api/session/edit", {"date": "2026-03-10", "rpe": 9})
        self.assertEqual(200, r.status_code)
        self.assertTrue(self.json(r).get("success"))
        self.assertEqual(9, self.store["sessions"]["2026-03-10"]["rpe"])

    def test_edit_comment(self):
        self.post("/api/session/edit", {"date": "2026-03-10", "comment": "felt great"})
        self.assertEqual("felt great", self.store["sessions"]["2026-03-10"]["comment"])

    def test_edit_exercise_weight(self):
        r = self.post("/api/session/edit", {
            "date": "2026-03-10",
            "exercises": [{"exercise": "Bench Press", "weight": 190.0, "reps": "7,6,6,5"}],
        })
        self.assertEqual(200, r.status_code)
        entry = next(
            e for e in self.store["weights"]["Bench Press"]["history"]
            if e["date"] == "2026-03-10"
        )
        self.assertEqual(190.0, entry["weight"])
        self.assertEqual("7,6,6,5", entry["reps"])

    def test_edit_recalculates_1rm(self):
        self.post("/api/session/edit", {
            "date": "2026-03-10",
            "exercises": [{"exercise": "Bench Press", "weight": 190.0, "reps": "5,5,5,5"}],
        })
        entry = next(
            e for e in self.store["weights"]["Bench Press"]["history"]
            if e["date"] == "2026-03-10"
        )
        self.assertIn("1rm", entry)
        self.assertGreater(entry["1rm"], 190.0)

    def test_edit_missing_date_returns_400(self):
        r = self.post("/api/session/edit", {"rpe": 7})
        self.assertEqual(400, r.status_code)

    def test_edit_unknown_exercise_skipped(self):
        """Editing an exercise not in weights store should not crash."""
        r = self.post("/api/session/edit", {
            "date": "2026-03-10",
            "exercises": [{"exercise": "Unknown Exercise", "weight": 100.0, "reps": "5,5"}],
        })
        self.assertEqual(200, r.status_code)

    def test_edit_creates_entry_for_missing_date(self):
        """If no history entry exists for the date, a new one is inserted."""
        r = self.post("/api/session/edit", {
            "date": "2026-01-01",
            "exercises": [{"exercise": "Bench Press", "weight": 170.0, "reps": "8,8,8"}],
        })
        self.assertEqual(200, r.status_code)
        dates = [e["date"] for e in self.store["weights"]["Bench Press"]["history"]]
        self.assertIn("2026-01-01", dates)


# ── /api/session/delete ───────────────────────────────────────────────────────

class TestSessionDelete(BaseRouteTest):

    def test_delete_removes_session(self):
        r = self.post("/api/session/delete", {"date": "2026-03-10"})
        self.assertEqual(200, r.status_code)
        self.assertNotIn("2026-03-10", self.store["sessions"])

    def test_delete_removes_history_entries(self):
        r = self.post("/api/session/delete", {"date": "2026-03-10"})
        self.assertEqual(200, r.status_code)
        remaining = [
            e for e in self.store["weights"]["Bench Press"]["history"]
            if e["date"] == "2026-03-10"
        ]
        self.assertEqual([], remaining)

    def test_delete_preserves_other_history(self):
        """Deleting one session must not touch entries from other dates."""
        self.post("/api/session/delete", {"date": "2026-03-10"})
        dates = [e["date"] for e in self.store["weights"]["Bench Press"]["history"]]
        self.assertIn("2026-03-03", dates)

    def test_delete_updates_current_weight(self):
        """After deletion current_weight must reflect the newest remaining entry."""
        self.post("/api/session/delete", {"date": "2026-03-10"})
        self.assertEqual(180.0, self.store["weights"]["Bench Press"]["current_weight"])

    def test_delete_missing_date_returns_400(self):
        r = self.post("/api/session/delete", {})
        self.assertEqual(400, r.status_code)


# ── /api/log_session ─────────────────────────────────────────────────────────

class TestLogSession(BaseRouteTest):

    def test_log_session_success(self):
        r = self.post("/api/log_session", {
            "date": TODAY, "rpe": 7, "comment": "good",
            "exos": ["Bench Press", "Back Squat"],
        })
        self.assertEqual(200, r.status_code)
        self.assertTrue(self.json(r).get("success"))

    def test_log_session_persists(self):
        self.post("/api/log_session", {"date": TODAY, "rpe": 8})
        self.assertIn(TODAY, self.store["sessions"])

    def test_log_session_duplicate_returns_409(self):
        """Second call for same date without second_session flag must be rejected."""
        self.post("/api/log_session", {"date": TODAY, "rpe": 7})
        r = self.post("/api/log_session", {"date": TODAY, "rpe": 7})
        self.assertEqual(409, r.status_code)
        self.assertEqual("already_logged", self.json(r).get("error"))

    def test_log_session_second_session_allowed(self):
        self.post("/api/log_session", {"date": TODAY, "rpe": 7})
        r = self.post("/api/log_session", {"date": TODAY, "rpe": 6, "second_session": True})
        self.assertEqual(200, r.status_code)


# ── /api/log_hiit ────────────────────────────────────────────────────────────

class TestLogHiit(BaseRouteTest):

    def test_log_hiit_success(self):
        r = self.post("/api/log_hiit", {
            "date": TODAY, "session_type": "HIIT", "rounds": 8, "rpe": 8,
        })
        self.assertEqual(200, r.status_code)
        self.assertTrue(self.json(r).get("success"))

    def test_log_hiit_persists(self):
        self.post("/api/log_hiit", {"date": TODAY, "session_type": "HIIT", "rounds": 8})
        entries = [e for e in self.store["hiit_log"] if e["date"] == TODAY]
        self.assertEqual(1, len(entries))

    def test_log_hiit_duplicate_same_type_returns_409(self):
        """Same date + same session_type → 409."""
        self.post("/api/log_hiit", {
            "date": "2026-03-11", "session_type": "Tabata",
        })
        r = self.post("/api/log_hiit", {
            "date": "2026-03-11", "session_type": "Tabata",
        })
        self.assertEqual(409, r.status_code)

    def test_log_hiit_different_type_allowed(self):
        """Same date but different session_type should be allowed."""
        r = self.post("/api/log_hiit", {
            "date": "2026-03-11", "session_type": "Vélo",
        })
        self.assertEqual(200, r.status_code)

    def test_log_hiit_second_session_flag(self):
        self.post("/api/log_hiit", {"date": "2026-03-11", "session_type": "Tabata"})
        r = self.post("/api/log_hiit", {
            "date": "2026-03-11", "session_type": "Tabata", "second_session": True,
        })
        self.assertEqual(200, r.status_code)


# ── /api/delete_hiit ─────────────────────────────────────────────────────────

class TestDeleteHiit(BaseRouteTest):

    def test_delete_by_index(self):
        before = len(self.store["hiit_log"])
        r = self.post("/api/delete_hiit", {"index": 0})
        self.assertEqual(200, r.status_code)
        self.assertEqual(before - 1, len(self.store["hiit_log"]))

    def test_delete_by_date_and_type(self):
        before = len(self.store["hiit_log"])
        r = self.post("/api/delete_hiit", {
            "date": "2026-03-11", "session_type": "Tabata",
        })
        self.assertEqual(200, r.status_code)
        self.assertEqual(before - 1, len(self.store["hiit_log"]))

    def test_delete_nonexistent_returns_400(self):
        r = self.post("/api/delete_hiit", {
            "date": "1900-01-01", "session_type": "Ghost",
        })
        self.assertEqual(400, r.status_code)

    def test_delete_out_of_bounds_index_returns_400(self):
        r = self.post("/api/delete_hiit", {"index": 999})
        self.assertEqual(400, r.status_code)


# ── /api/hiit/edit ───────────────────────────────────────────────────────────

class TestHiitEdit(BaseRouteTest):

    def test_edit_rpe(self):
        r = self.post("/api/hiit/edit", {"index": 0, "rpe": 9})
        self.assertEqual(200, r.status_code)
        self.assertEqual(9, self.store["hiit_log"][0]["rpe"])

    def test_edit_comment(self):
        self.post("/api/hiit/edit", {"index": 0, "comment": "tough one"})
        self.assertEqual("tough one", self.store["hiit_log"][0]["comment"])

    def test_edit_feeling(self):
        self.post("/api/hiit/edit", {"index": 0, "feeling": "great"})
        self.assertEqual("great", self.store["hiit_log"][0]["feeling"])

    def test_edit_rounds_completes(self):
        self.post("/api/hiit/edit", {"index": 0, "rounds_completes": 6})
        self.assertEqual(6, self.store["hiit_log"][0]["rounds_completes"])

    def test_edit_invalid_index_returns_400(self):
        r = self.post("/api/hiit/edit", {"index": 999, "rpe": 8})
        self.assertEqual(400, r.status_code)


if __name__ == "__main__":
    import unittest
    unittest.main(verbosity=2)
