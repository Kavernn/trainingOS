"""
Test : modifier le programme ne touche JAMAIS l'historique des poids.

programme  → clé Supabase "program"  : structure des séances
weights    → clé Supabase "weights"  : historique par exercice

Ces deux stores sont indépendants. On le prouve en simulant chaque
action de /api/programme et en vérifiant que weights reste byte-for-byte
identique avant/après.
"""
import copy
import json
import os
import sys
import unittest
from unittest.mock import patch, MagicMock

# Ajoute /api au path pour les imports
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

# ── Fixtures ────────────────────────────────────────────────────────────────

FAKE_PROGRAM = {
    "Upper A": {
        "Bench Press":      "4x5-7",
        "Barbell Row":      "4x6-8",
        "Overhead Press":   "3x6-8",
    },
    "Upper B": {
        "Incline DB Press": "4x8-10",
        "Seated Row":       "3x10-12",
    },
    "Lower": {
        "Back Squat":       "4x5-7",
        "Romanian Deadlift":"3x8-10",
    },
}

FAKE_WEIGHTS = {
    "Bench Press": {
        "current_weight": 185.0,
        "last_reps": "6,6,5,5",
        "history": [
            {"date": "2026-03-03", "weight": 185.0, "reps": "6,6,5,5"},
            {"date": "2026-02-24", "weight": 180.0, "reps": "7,7,6"},
        ],
    },
    "Barbell Row": {
        "current_weight": 155.0,
        "last_reps": "8,8,7,7",
        "history": [
            {"date": "2026-03-03", "weight": 155.0, "reps": "8,8,7,7"},
        ],
    },
    "Back Squat": {
        "current_weight": 225.0,
        "last_reps": "5,5,5,5",
        "history": [
            {"date": "2026-02-28", "weight": 225.0, "reps": "5,5,5,5"},
            {"date": "2026-02-21", "weight": 215.0, "reps": "6,5,5,5"},
        ],
    },
}


# ── Helpers ─────────────────────────────────────────────────────────────────

def make_db_store():
    """Retourne un store in-memory qui simule get_json / set_json."""
    store = {
        "program": copy.deepcopy(FAKE_PROGRAM),
        "weights": copy.deepcopy(FAKE_WEIGHTS),
    }

    def get_json(key, default=None):
        return copy.deepcopy(store.get(key, default))

    def set_json(key, value):
        store[key] = copy.deepcopy(value)
        return True

    return store, get_json, set_json


# ── Test case ───────────────────────────────────────────────────────────────

class TestProgramDoesNotAffectHistory(unittest.TestCase):

    def setUp(self):
        """Crée une app Flask de test avec un store isolé."""
        self.store, get_json, set_json = make_db_store()

        # Patch db avant d'importer index
        self.db_patch = patch.dict("sys.modules", {
            "db": MagicMock(
                get_json=get_json,
                set_json=set_json,
                _ON_VERCEL=False,
            )
        })
        self.db_patch.start()

        # Import tardif pour que le patch soit actif
        import importlib
        if "index" in sys.modules:
            del sys.modules["index"]
        for mod in list(sys.modules.keys()):
            if mod.startswith(("planner", "log_workout", "sessions", "inventory",
                               "progression", "deload", "goals", "body_weight",
                               "user_profile", "hiit")):
                del sys.modules[mod]

        import index as idx
        self.app = idx.app
        self.app.config["TESTING"] = True
        self.client = self.app.test_client()

    def tearDown(self):
        self.db_patch.stop()

    def _weights_snapshot(self):
        return json.dumps(self.store["weights"], sort_keys=True)

    def _post(self, payload):
        return self.client.post(
            "/api/programme",
            json=payload,
            content_type="application/json",
        )

    # ── Tests ────────────────────────────────────────────────────────────────

    def test_add_exercise_preserves_history(self):
        before = self._weights_snapshot()
        r = self._post({"action": "add", "jour": "Upper A",
                        "exercise": "Cable Fly", "scheme": "3x12-15"})
        self.assertEqual(r.status_code, 200)
        self.assertEqual(before, self._weights_snapshot(),
                         "add : weights modifié !")

    def test_remove_exercise_preserves_history(self):
        before = self._weights_snapshot()
        r = self._post({"action": "remove", "jour": "Upper A",
                        "exercise": "Bench Press"})
        self.assertEqual(r.status_code, 200)
        # Bench Press doit avoir disparu du PROGRAMME
        self.assertNotIn("Bench Press", self.store["program"]["Upper A"])
        # Mais son HISTORIQUE doit exister
        self.assertIn("Bench Press", self.store["weights"])
        self.assertEqual(2, len(self.store["weights"]["Bench Press"]["history"]))
        # Et le snapshot complet doit être inchangé
        self.assertEqual(before, self._weights_snapshot(),
                         "remove : weights modifié !")

    def test_change_scheme_preserves_history(self):
        before = self._weights_snapshot()
        r = self._post({"action": "scheme", "jour": "Upper A",
                        "exercise": "Bench Press", "scheme": "5x3"})
        self.assertEqual(r.status_code, 200)
        self.assertEqual("5x3", self.store["program"]["Upper A"]["Bench Press"])
        self.assertEqual(before, self._weights_snapshot(),
                         "scheme : weights modifié !")

    def test_replace_exercise_preserves_history(self):
        before = self._weights_snapshot()
        r = self._post({"action": "replace", "jour": "Upper A",
                        "old_exercise": "Bench Press",
                        "new_exercise": "DB Bench Press",
                        "scheme": "4x8-10"})
        self.assertEqual(r.status_code, 200)
        # Le programme a changé
        self.assertNotIn("Bench Press",    self.store["program"]["Upper A"])
        self.assertIn("DB Bench Press",    self.store["program"]["Upper A"])
        # L'historique de Bench Press est intact
        self.assertIn("Bench Press", self.store["weights"])
        self.assertEqual(2, len(self.store["weights"]["Bench Press"]["history"]))
        self.assertEqual(before, self._weights_snapshot(),
                         "replace : weights modifié !")

    def test_reorder_preserves_history(self):
        before = self._weights_snapshot()
        r = self._post({"action": "reorder", "jour": "Upper A",
                        "ordre": ["Overhead Press", "Barbell Row", "Bench Press"]})
        self.assertEqual(r.status_code, 200)
        self.assertEqual(
            list(self.store["program"]["Upper A"].keys()),
            ["Overhead Press", "Barbell Row", "Bench Press"],
        )
        self.assertEqual(before, self._weights_snapshot(),
                         "reorder : weights modifié !")

    def test_history_entries_survive_full_program_replacement(self):
        """Remplacer TOUS les exercices d'un jour ne supprime rien de weights."""
        before = self._weights_snapshot()
        for ex in list(FAKE_PROGRAM["Upper A"].keys()):
            self._post({"action": "remove", "jour": "Upper A", "exercise": ex})
        for ex in ["Push-up", "Pull-up", "Dip"]:
            self._post({"action": "add", "jour": "Upper A",
                        "exercise": ex, "scheme": "3x15"})
        # Tous les anciens exercices ont disparu du programme
        for ex in FAKE_PROGRAM["Upper A"]:
            self.assertNotIn(ex, self.store["program"]["Upper A"])
        # Mais leur historique est intact
        self.assertEqual(before, self._weights_snapshot(),
                         "remplacement complet : weights modifié !")


if __name__ == "__main__":
    unittest.main(verbosity=2)
