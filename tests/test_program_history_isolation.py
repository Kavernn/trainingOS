"""
Test : modifier le programme ne touche JAMAIS l'historique des poids.

programme  → clé Supabase "program"  : structure des séances (format blocs)
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
        "blocks": [{"type": "strength", "order": 0, "exercises": {
            "Bench Press":    "4x5-7",
            "Barbell Row":    "4x6-8",
            "Overhead Press": "3x6-8",
        }}]
    },
    "Upper B": {
        "blocks": [{"type": "strength", "order": 0, "exercises": {
            "Incline DB Press": "4x8-10",
            "Seated Row":       "3x10-12",
        }}]
    },
    "Lower": {
        "blocks": [{"type": "strength", "order": 0, "exercises": {
            "Back Squat":        "4x5-7",
            "Romanian Deadlift": "3x8-10",
        }}]
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
    """Retourne un store in-memory qui simule les méthodes db."""
    store = {
        "program": copy.deepcopy(FAKE_PROGRAM),
        "weights": copy.deepcopy(FAKE_WEIGHTS),
        "inventory": {},
    }

    def get_json(key, default=None):
        return copy.deepcopy(store.get(key, default))

    def set_json(key, value):
        store[key] = copy.deepcopy(value)
        return True

    def get_full_program(program_id=None):
        return copy.deepcopy(store.get("program", {}))

    def save_full_program(program, program_id=None):
        current = store.get("program", {})
        current.update(copy.deepcopy(program))
        store["program"] = current
        return True

    def get_exercises():
        return copy.deepcopy(store.get("inventory", {}))

    def upsert_exercise(data):
        name = data.get("name", "")
        inv = store.get("inventory", {})
        inv[name] = {k: v for k, v in data.items() if k != "name"}
        store["inventory"] = inv
        return data

    def delete_exercise_by_name(name):
        inv = store.get("inventory", {})
        inv.pop(name, None)
        store["inventory"] = inv
        return True

    def delete_program_session(name):
        prog = store.get("program", {})
        prog.pop(name, None)
        store["program"] = prog
        return True

    def get_relational_week_schedule():
        return None

    def get_evening_week_schedule():
        return None

    return store, get_json, set_json, get_full_program, save_full_program, \
        get_exercises, upsert_exercise, delete_exercise_by_name, \
        delete_program_session, get_relational_week_schedule, get_evening_week_schedule


def _session_exercises(store, jour):
    """Return the exercises dict from the strength block of a program session.

    Works with both the legacy flat format and the new block format so tests
    remain valid across migrations.
    """
    sdef = store["program"][jour]
    if "blocks" in sdef:
        for b in sdef["blocks"]:
            if b.get("type") == "strength":
                return b.get("exercises", {})
        return {}
    # Legacy flat format (pre-migration snapshot)
    return sdef


# ── Test case ───────────────────────────────────────────────────────────────

class TestProgramDoesNotAffectHistory(unittest.TestCase):

    def setUp(self):
        """Crée une app Flask de test avec un store isolé."""
        (self.store, get_json, set_json, get_full_program, save_full_program,
         get_exercises, upsert_exercise, delete_exercise_by_name,
         delete_program_session, get_relational_week_schedule,
         get_evening_week_schedule) = make_db_store()

        # Patch db avant d'importer index
        self.db_patch = patch.dict("sys.modules", {
            "db": MagicMock(
                get_json=get_json,
                set_json=set_json,
                _ON_VERCEL=False,
                get_full_program=get_full_program,
                save_full_program=save_full_program,
                get_exercises=get_exercises,
                upsert_exercise=upsert_exercise,
                delete_exercise_by_name=delete_exercise_by_name,
                delete_program_session=delete_program_session,
                get_relational_week_schedule=get_relational_week_schedule,
                get_evening_week_schedule=get_evening_week_schedule,
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
                               "user_profile", "hiit", "blocks")):
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
        self.assertNotIn("Bench Press", _session_exercises(self.store, "Upper A"))
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
        self.assertEqual("5x3", _session_exercises(self.store, "Upper A")["Bench Press"])
        self.assertEqual(before, self._weights_snapshot(),
                         "scheme : weights modifié !")

    def test_replace_exercise_preserves_history(self):
        before = self._weights_snapshot()
        r = self._post({"action": "replace", "jour": "Upper A",
                        "old_exercise": "Bench Press",
                        "new_exercise": "DB Bench Press",
                        "scheme": "4x8-10"})
        self.assertEqual(r.status_code, 200)
        exos = _session_exercises(self.store, "Upper A")
        # Le programme a changé
        self.assertNotIn("Bench Press",    exos)
        self.assertIn("DB Bench Press",    exos)
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
            list(_session_exercises(self.store, "Upper A").keys()),
            ["Overhead Press", "Barbell Row", "Bench Press"],
        )
        self.assertEqual(before, self._weights_snapshot(),
                         "reorder : weights modifié !")

    def test_history_entries_survive_full_program_replacement(self):
        """Remplacer TOUS les exercices d'un jour ne supprime rien de weights."""
        before = self._weights_snapshot()
        original_exos = list(_session_exercises(self.store, "Upper A").keys())
        for ex in original_exos:
            self._post({"action": "remove", "jour": "Upper A", "exercise": ex})
        for ex in ["Push-up", "Pull-up", "Dip"]:
            self._post({"action": "add", "jour": "Upper A",
                        "exercise": ex, "scheme": "3x15"})
        # Tous les anciens exercices ont disparu du programme
        for ex in original_exos:
            self.assertNotIn(ex, _session_exercises(self.store, "Upper A"))
        # Mais leur historique est intact
        self.assertEqual(before, self._weights_snapshot(),
                         "remplacement complet : weights modifié !")

    def test_add_block_to_session(self):
        """Adding a HIIT block to a session does not affect weights."""
        before = self._weights_snapshot()
        r = self._post({"action": "add_block", "jour": "Upper A",
                        "block_type": "hiit",
                        "hiit_config": {"sprint": 30, "rest": 90, "rounds": 8}})
        self.assertEqual(r.status_code, 200)
        # HIIT block present in the session
        sdef = self.store["program"]["Upper A"]
        hiit_blocks = [b for b in sdef.get("blocks", []) if b.get("type") == "hiit"]
        self.assertEqual(len(hiit_blocks), 1)
        # Weights untouched
        self.assertEqual(before, self._weights_snapshot(),
                         "add_block : weights modifié !")

    def test_remove_block_preserves_history(self):
        """Removing a block does not touch weights."""
        # First add a cardio block so we have something to remove
        self._post({"action": "add_block", "jour": "Lower",
                    "block_type": "cardio",
                    "cardio_config": {"target_min": 20, "intensity": "moderate"}})
        before = self._weights_snapshot()
        r = self._post({"action": "remove_block", "jour": "Lower",
                        "block_type": "cardio"})
        self.assertEqual(r.status_code, 200)
        sdef = self.store["program"]["Lower"]
        cardio_blocks = [b for b in sdef.get("blocks", []) if b.get("type") == "cardio"]
        self.assertEqual(len(cardio_blocks), 0)
        self.assertEqual(before, self._weights_snapshot(),
                         "remove_block : weights modifié !")

    def test_reorder_blocks(self):
        """Reordering blocks within a session does not touch weights."""
        # Build a session with two blocks
        self._post({"action": "add_block", "jour": "Upper B",
                    "block_type": "hiit"})
        before = self._weights_snapshot()
        r = self._post({"action": "reorder_blocks", "jour": "Upper B",
                        "order": ["hiit", "strength"]})
        self.assertEqual(r.status_code, 200)
        sdef = self.store["program"]["Upper B"]
        block_types = [b["type"] for b in sorted(sdef["blocks"], key=lambda b: b["order"])]
        self.assertEqual(block_types, ["hiit", "strength"])
        self.assertEqual(before, self._weights_snapshot(),
                         "reorder_blocks : weights modifié !")


if __name__ == "__main__":
    unittest.main(verbosity=2)
