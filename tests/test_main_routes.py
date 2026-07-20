"""
Tests Flask — routes principales de l'API TrainingOS.

Routes couvertes :
  GET  /api/seance_data     → renvoie programme, suggestions, weights
  GET  /api/historique_data → renvoie session_list + hiit_list
  POST /api/log             → enregistre un exercice
  GET  /api/deload_status   → analyse stagnation + RPE

Factorisation commit tests-sync : BaseRouteTest + make_store proviennent
maintenant du conftest partagé (auparavant dupliqués localement, source de
désynchronisation avec le vrai module db). Le spec-guard conftest protège
contre les typos d'attributs (bug mesocycle-style).
"""
import json
import sys, os
import unittest
from unittest.mock import patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

from conftest import BaseRouteTest, TODAY


# ── /api/seance_data ────────────────────────────────────────────────────────

class TestSeanceData(BaseRouteTest):

    def test_status_200(self):
        r = self.get("/api/seance_data")
        self.assertEqual(200, r.status_code)

    def test_returns_json(self):
        r = self.get("/api/seance_data")
        data = json.loads(r.data)
        self.assertIsInstance(data, dict)

    def test_has_required_keys(self):
        data = json.loads(self.get("/api/seance_data").data)
        for key in ("today", "today_date", "already_logged", "schedule",
                    "full_program", "suggestions", "weights", "inventory_types"):
            self.assertIn(key, data, f"Clé manquante : {key}")

    def test_full_program_is_flat(self):
        """full_program doit être {session: {exercise: scheme}}, pas bloc."""
        data = json.loads(self.get("/api/seance_data").data)
        for session_name, exercises in data["full_program"].items():
            self.assertIsInstance(exercises, dict, f"{session_name} n'est pas un dict plat")
            for ex, scheme in exercises.items():
                self.assertIsInstance(scheme, str, f"{ex} scheme n'est pas une string")

    def test_inventory_types_populated(self):
        data = json.loads(self.get("/api/seance_data").data)
        inv = data["inventory_types"]
        self.assertIn("Bench Press", inv)
        self.assertEqual("barbell", inv["Bench Press"])

    def test_not_already_logged_for_fresh_day(self):
        """Le jour de test n'est pas dans les sessions fictives."""
        data = json.loads(self.get("/api/seance_data").data)
        # TODAY = 2026-03-14 is NOT in conftest SESSIONS (2026-03-10, 2026-03-07)
        self.assertFalse(data["already_logged"])


# ── /api/historique_data ────────────────────────────────────────────────────

class TestHistoriqueData(BaseRouteTest):

    def test_status_200(self):
        r = self.get("/api/historique_data")
        self.assertEqual(200, r.status_code)

    def test_has_required_keys(self):
        data = json.loads(self.get("/api/historique_data").data)
        self.assertIn("session_list", data)
        self.assertIn("hiit_list", data)

    def test_session_list_sorted_desc(self):
        data = json.loads(self.get("/api/historique_data").data)
        dates = [s["date"] for s in data["session_list"]]
        self.assertEqual(dates, sorted(dates, reverse=True))

    def test_known_session_present(self):
        data = json.loads(self.get("/api/historique_data").data)
        dates = {s["date"] for s in data["session_list"]}
        self.assertIn("2026-03-10", dates)

    def test_session_has_exos(self):
        data = json.loads(self.get("/api/historique_data").data)
        march10 = next(s for s in data["session_list"] if s["date"] == "2026-03-10")
        # Bench Press a un log pour ce jour (conftest WEIGHTS history)
        exo_names = [e["exercise"] for e in march10["exos"]]
        self.assertIn("Bench Press", exo_names)


# ── /api/log ─────────────────────────────────────────────────────────────────

class TestApiLog(BaseRouteTest):

    def _log_payload(self, **overrides):
        payload = {
            "exercise": "Bench Press",
            "weight":   185.0,
            "reps":     "6,6,5,5",
        }
        payload.update(overrides)
        return payload

    def test_log_returns_200(self):
        r = self.post("/api/log", self._log_payload())
        self.assertEqual(200, r.status_code)

    def test_log_returns_success(self):
        data = json.loads(self.post("/api/log", self._log_payload()).data)
        self.assertTrue(data.get("success") or "error" not in data)

    def test_log_missing_exercise_returns_error(self):
        r = self.post("/api/log", {"weight": 100.0, "reps": "5,5,5"})
        # Should not crash — either 400 or 200 with an error key
        self.assertIn(r.status_code, (200, 400))

    def test_double_log_same_day_returns_409(self):
        """Logging the same exercise twice the same day returns already_logged."""
        # Bench Press history[0] date = "2026-03-10" (conftest WEIGHTS L43).
        with patch("utils._today_mtl", return_value="2026-03-10"):
            r = self.post("/api/log", self._log_payload())
            data = json.loads(r.data)
            self.assertEqual(409, r.status_code)
            self.assertEqual("already_logged", data.get("error"))

    def test_log_second_empty_sets_morning_logged_returns_409(self):
        """Défense Crime 4 : POST is_second=true avec sets vides + morning déjà loggé
        avec sets_json rempli → 409 morning_log_exists."""
        with patch("utils._today_mtl", return_value="2026-03-10"), \
             patch("db.get_exercise_log_sets_json", return_value=[{"weight": 185, "reps": "6"}]):
            r = self.post("/api/log", self._log_payload(is_second=True, sets=[]))
            data = json.loads(r.data)
            self.assertEqual(409, r.status_code)
            self.assertEqual("morning_log_exists", data.get("error"))

    def test_log_second_with_sets_bypasses_guard(self):
        """POST is_second=true avec sets non-vides → guard non déclenché."""
        with patch("utils._today_mtl", return_value="2026-03-10"), \
             patch("db.get_exercise_log_sets_json", return_value=[{"weight": 185, "reps": "6"}]):
            r = self.post("/api/log", self._log_payload(
                is_second=True,
                sets=[{"weight": 200, "reps": "5"}],
            ))
            self.assertNotEqual(409, r.status_code)

    def test_log_second_empty_sets_no_morning_bypasses_guard(self):
        """POST is_second=true sans row morning existante → guard non déclenché
        (cas nouveau exo du soir)."""
        with patch("utils._today_mtl", return_value="2026-03-10"), \
             patch("db.get_exercise_log_sets_json", return_value=None):
            r = self.post("/api/log", self._log_payload(is_second=True, sets=[]))
            self.assertNotEqual(409, r.status_code)

    def test_log_second_empty_sets_polluted_morning_bypasses_guard(self):
        """Morning polluée (sets_json=[]) → guard non déclenché : on défend
        les vraies données, pas les fantômes du Crime 4 legacy."""
        with patch("utils._today_mtl", return_value="2026-03-10"), \
             patch("db.get_exercise_log_sets_json", return_value=[]):
            r = self.post("/api/log", self._log_payload(is_second=True, sets=[]))
            self.assertNotEqual(409, r.status_code)


# ── /api/deload_status ───────────────────────────────────────────────────────

class TestDeloadStatus(BaseRouteTest):

    def test_status_200(self):
        r = self.get("/api/deload_status")
        self.assertEqual(200, r.status_code)

    def test_has_required_keys(self):
        data = json.loads(self.get("/api/deload_status").data)
        for key in ("deload_actif", "stagnants", "fatigue_rpe", "recommande"):
            self.assertIn(key, data, f"Clé manquante : {key}")

    def test_bench_press_stagnation_detected(self):
        """Bench Press 3 entries à 185 lbs → stagnation. La conftest WEIGHTS a
        2 entries (185, 180) qui ne triggent pas stagnation — override local
        pour rendre le test autonome. stagnants = liste de dicts OU strings
        selon shape backend (a évolué) — supporte les deux via extraction."""
        self.store["weights"]["Bench Press"]["history"] = [
            {"date": "2026-03-10", "weight": 185.0, "reps": "6,6,5,5"},
            {"date": "2026-03-03", "weight": 185.0, "reps": "6,6,5,5"},
            {"date": "2026-02-24", "weight": 185.0, "reps": "7,6,5,5"},
        ]
        data = json.loads(self.get("/api/deload_status").data)
        stagnant_names = [s["exercise"] if isinstance(s, dict) else s for s in data["stagnants"]]
        self.assertIn("Bench Press", stagnant_names)

    def test_recommande_true_when_stagnation(self):
        """With 2+ stagnant exercises the deload should be recommended."""
        self.store["weights"]["Bench Press"]["history"] = [
            {"date": "2026-03-10", "weight": 185.0, "reps": "6,6,5,5"},
            {"date": "2026-03-03", "weight": 185.0, "reps": "6,6,5,5"},
            {"date": "2026-02-24", "weight": 185.0, "reps": "7,6,5,5"},
        ]
        self.store["weights"]["Back Squat"]["history"] = [
            {"date": "2026-03-07", "weight": 225.0, "reps": "5,5,5,5"},
            {"date": "2026-02-28", "weight": 225.0, "reps": "5,5,5,5"},
            {"date": "2026-02-21", "weight": 225.0, "reps": "5,5,5,5"},
        ]
        data = json.loads(self.get("/api/deload_status").data)
        self.assertTrue(data["recommande"])

    def test_no_deload_when_fresh(self):
        """With a single history entry per exercise there is no stagnation."""
        self.store["weights"] = {
            "Bench Press": {
                "current_weight": 185.0,
                "history": [{"date": "2026-03-10", "weight": 185.0, "reps": "6,6,5,5"}],
            }
        }
        data = json.loads(self.get("/api/deload_status").data)
        self.assertEqual([], data["stagnants"])
        self.assertFalse(data["recommande"])


if __name__ == "__main__":
    unittest.main(verbosity=2)
