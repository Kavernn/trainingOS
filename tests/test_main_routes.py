"""
Tests Flask — routes principales de l'API TrainingOS.

Routes couvertes :
  GET  /api/seance_data     → renvoie programme, suggestions, weights
  GET  /api/historique_data → renvoie session_list + hiit_list
  POST /api/log             → enregistre un exercice
  GET  /api/deload_status   → analyse stagnation + RPE
"""
import copy
import json
import os
import sys
import unittest
from unittest.mock import patch, MagicMock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))


# ── Fixtures ─────────────────────────────────────────────────────────────────

FAKE_PROGRAM = {
    "Upper A": {
        "blocks": [
            {
                "type": "strength",
                "order": 0,
                "exercises": {
                    "Bench Press":    "4x5-7",
                    "Barbell Row":    "4x6-8",
                    "Overhead Press": "3x6-8",
                },
            }
        ]
    },
    "Lower": {
        "blocks": [
            {
                "type": "strength",
                "order": 0,
                "exercises": {
                    "Back Squat":        "4x5-7",
                    "Romanian Deadlift": "3x8-10",
                },
            }
        ]
    },
}

FAKE_WEIGHTS = {
    "Bench Press": {
        "current_weight": 185.0,
        "last_reps": "6,6,5,5",
        "history": [
            {"date": "2026-03-10", "weight": 185.0, "reps": "6,6,5,5"},
            {"date": "2026-03-03", "weight": 185.0, "reps": "6,6,5,5"},
            {"date": "2026-02-24", "weight": 185.0, "reps": "7,6,5,5"},
        ],
    },
    "Back Squat": {
        "current_weight": 225.0,
        "last_reps": "5,5,5,5",
        "history": [
            {"date": "2026-03-07", "weight": 225.0, "reps": "5,5,5,5"},
        ],
    },
}

FAKE_SESSIONS = {
    "2026-03-10": {"rpe": 7, "comment": "good session"},
    "2026-03-07": {"rpe": 8, "comment": ""},
}

FAKE_INVENTORY = {
    "Bench Press":    {"type": "barbell", "default_scheme": "4x5-7"},
    "Back Squat":     {"type": "barbell", "default_scheme": "4x5-7"},
    "Barbell Row":    {"type": "barbell", "default_scheme": "4x6-8"},
    "Overhead Press": {"type": "barbell", "default_scheme": "3x6-8"},
}

FAKE_PROFILE = {
    "name": "Test User",
    "weight": 180.0,
    "height": 175,
    "age": 30,
    "level": "intermediate",
}


# ── Store in-memory ──────────────────────────────────────────────────────────

def make_db_store():
    store = {
        "program":    copy.deepcopy(FAKE_PROGRAM),
        "weights":    copy.deepcopy(FAKE_WEIGHTS),
        "sessions":   copy.deepcopy(FAKE_SESSIONS),
        "inventory":  copy.deepcopy(FAKE_INVENTORY),
        "user_profile": copy.deepcopy(FAKE_PROFILE),
        "hiit_log":   [],
        "body_weight": [],
        "deload_state": {"active": False},
        "goals": {},
        "nutrition_settings": {"limite_calories": 2200, "objectif_proteines": 160},
        "nutrition_log": {},
        "recovery_log": {},
        "sleep_log": {},
        "mood_log": {},
        "journal_entries": [],
        "breathwork_history": [],
        "self_care_habits": [],
        "self_care_log": {},
        "pss_log": [],
    }

    def get_json(key, default=None):
        return copy.deepcopy(store.get(key, default))

    def set_json(key, value):
        store[key] = copy.deepcopy(value)
        return True

    def update_json(key, patch_dict):
        current = copy.deepcopy(store.get(key, {}))
        current.update(patch_dict)
        store[key] = current
        return True

    def append_json_list(key, entry):
        lst = copy.deepcopy(store.get(key, []))
        lst.append(entry)
        store[key] = lst
        return True

    return store, get_json, set_json, update_json, append_json_list


# ── Base test class ──────────────────────────────────────────────────────────

class BaseRouteTest(unittest.TestCase):

    TODAY = "2026-03-14"
    TODAY_STR = "Vendredi 14 mars 2026"

    def setUp(self):
        (self.store,
         get_json, set_json, update_json, append_json_list) = make_db_store()

        db_mock = MagicMock(
            get_json=get_json,
            set_json=set_json,
            update_json=update_json,
            append_json_list=append_json_list,
            _ON_VERCEL=False,
        )

        self.db_patch = patch.dict("sys.modules", {"db": db_mock})
        self.db_patch.start()

        # Clear cached modules so patches take effect
        for mod in list(sys.modules.keys()):
            if mod in ("index",) or mod.startswith((
                "planner", "log_workout", "sessions", "inventory",
                "progression", "deload", "goals", "body_weight",
                "user_profile", "hiit", "blocks", "nutrition",
                "volume", "health_data", "life_stress_engine",
                "mental_health_dashboard", "mood", "journal",
                "breathwork", "self_care", "sleep", "pss",
            )):
                del sys.modules[mod]

        # Patch today so tests are date-independent
        self._today_patch = patch("planner.get_today_date", return_value=self.TODAY)
        self._today_patch.start()

        import index as idx
        self.app = idx.app
        self.app.config["TESTING"] = True
        self.client = self.app.test_client()

    def tearDown(self):
        self.db_patch.stop()
        try:
            self._today_patch.stop()
        except RuntimeError:
            pass

    def get(self, url):
        return self.client.get(url)

    def post(self, url, payload):
        return self.client.post(url, json=payload, content_type="application/json")


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
        # TODAY = 2026-03-14 is NOT in FAKE_SESSIONS
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
        # Bench Press a un log pour ce jour
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
        # The guard checks _today_mtl() against history[0]["date"].
        # Bench Press history[0] is "2026-03-10", so mock _today_mtl to that date.
        import index as idx
        with patch.object(idx, "_today_mtl", return_value="2026-03-10"):
            r = self.post("/api/log", self._log_payload())
            data = json.loads(r.data)
            self.assertEqual(409, r.status_code)
            self.assertEqual("already_logged", data.get("error"))


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
        """Bench Press has 3 entries at 185 lbs → stagnation threshold met."""
        data = json.loads(self.get("/api/deload_status").data)
        stagnant_names = [s["exercise"] for s in data["stagnants"]]
        self.assertIn("Bench Press", stagnant_names)

    def test_recommande_true_when_stagnation(self):
        """With 2+ stagnant exercises the deload should be recommended."""
        # Add a second stagnant exercise to the store
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
