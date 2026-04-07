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

    # ── Relational layer mocks ──────────────────────────────────────────────

    def get_all_exercise_history():
        weights = store.get("weights", {})
        result = {}
        for name, ex_data in weights.items():
            history = ex_data.get("history", [])
            if history:
                result[name] = [{"date": e.get("date"), "weight": e.get("weight"), "reps": e.get("reps")} for e in history]
        return result

    def get_workout_sessions(limit=100):
        sessions = store.get("sessions", {})
        result = []
        for date in sorted(sessions.keys(), reverse=True)[:limit]:
            entry = copy.deepcopy(sessions[date])
            entry["date"] = date
            entry.setdefault("id", date)
            result.append(entry)
        return result

    def get_workout_session(date):
        sessions = store.get("sessions", {})
        if date in sessions:
            entry = copy.deepcopy(sessions[date])
            entry["date"] = date
            entry.setdefault("id", date)
            return entry
        return None

    def get_or_create_workout_session(date):
        existing = get_workout_session(date)
        if existing:
            return existing
        entry = {"rpe": None, "comment": "", "exos": [], "id": date}
        sessions = store.get("sessions", {})
        sessions[date] = entry
        store["sessions"] = sessions
        return {**entry, "date": date}

    def create_workout_session(
        date,
        rpe=None,
        comment=None,
        duration_min=None,
        energy_pre=None,
        is_second=False,
        session_type="morning",
        session_name=None,
    ):
        sessions = store.get("sessions", {})
        key = date if not is_second else f"{date}_2"
        entry = {"rpe": rpe, "comment": comment or "", "exos": [], "id": key}
        if session_type is not None:
            entry["session_type"] = session_type
        if session_name is not None:
            entry["session_name"] = session_name
        sessions[key] = entry
        store["sessions"] = sessions
        return {**entry, "date": date}

    def update_workout_session(date, patch_dict):
        sessions = store.get("sessions", {})
        if date in sessions:
            sessions[date].update(patch_dict)
            store["sessions"] = sessions
            return True
        return False

    def upsert_exercise_log(session_date, exercise_name, weight, reps):
        weights = store.get("weights", {})
        if exercise_name not in weights:
            weights[exercise_name] = {"current_weight": weight or 0, "last_reps": reps or "", "history": []}
        history = weights[exercise_name].get("history", [])
        for entry in history:
            if entry.get("date") == session_date:
                entry["weight"] = weight
                entry["reps"] = reps
                store["weights"] = weights
                return True
        history.insert(0, {"date": session_date, "weight": weight, "reps": reps})
        weights[exercise_name]["history"] = history
        if weight:
            weights[exercise_name]["current_weight"] = weight
        if reps:
            weights[exercise_name]["last_reps"] = reps
        store["weights"] = weights
        return True

    def upsert_exercise_log_by_type(session_date, session_type, exercise_name, weight, reps, sets_json=None):
        return upsert_exercise_log(session_date, exercise_name, weight, reps)

    def delete_exercise_log_entry_by_type(session_date, session_type, exercise_name):
        return delete_exercise_log_entry(session_date, exercise_name)

    def get_full_program(program_id=None):
        return copy.deepcopy(store.get("program", {}))

    def save_full_program(program, program_id=None):
        current = store.get("program", {})
        current.update(copy.deepcopy(program))
        store["program"] = current
        return True

    def get_relational_week_schedule():
        return None  # fall back to hardcoded schedule

    def get_evening_week_schedule():
        return None

    def get_exercise_history_grouped_by_session():
        weights = store.get("weights", {})
        result = {}
        for name, ex_data in weights.items():
            for entry in ex_data.get("history", []):
                d = entry.get("date")
                if d:
                    result.setdefault(d, []).append({
                        "exercise": name,
                        "weight":   entry.get("weight"),
                        "reps":     entry.get("reps"),
                    })
        return result

    def get_hiit_logs(limit=100):
        return copy.deepcopy(store.get("hiit_log", []))[:limit]

    def get_all_programs():
        return []

    def get_default_program_id():
        return None

    def get_all_session_names():
        return sorted(store.get("program", {}).keys())

    def delete_exercise_by_name(name):
        inv = store.get("inventory", {})
        inv.pop(name, None)
        store["inventory"] = inv
        return True

    def delete_exercise_log_entry(session_date, exercise_name):
        weights = store.get("weights", {})
        if exercise_name in weights:
            weights[exercise_name]["history"] = [
                e for e in weights[exercise_name].get("history", [])
                if e.get("date") != session_date
            ]
            store["weights"] = weights
        return True

    def get_nutrition_settings():
        return copy.deepcopy(store.get("nutrition_settings", {}))

    def delete_program_session(name):
        program = store.get("program", {})
        program.pop(name, None)
        store["program"] = program
        return True

    return store, get_json, set_json, update_json, append_json_list, \
        get_all_exercise_history, get_workout_sessions, get_workout_session, \
        get_or_create_workout_session, create_workout_session, update_workout_session, \
        upsert_exercise_log, upsert_exercise_log_by_type, get_full_program, save_full_program, \
        get_relational_week_schedule, get_evening_week_schedule, \
        get_exercise_history_grouped_by_session, get_hiit_logs, \
        get_all_programs, get_default_program_id, get_all_session_names, \
        delete_exercise_by_name, delete_exercise_log_entry, delete_exercise_log_entry_by_type, \
        get_nutrition_settings, delete_program_session


# ── Base test class ──────────────────────────────────────────────────────────

class BaseRouteTest(unittest.TestCase):

    TODAY = "2026-03-14"
    TODAY_STR = "Vendredi 14 mars 2026"

    def setUp(self):
        (self.store,
         get_json, set_json, update_json, append_json_list,
         get_all_exercise_history, get_workout_sessions, get_workout_session,
         get_or_create_workout_session, create_workout_session,
         update_workout_session, upsert_exercise_log, upsert_exercise_log_by_type,
         get_full_program, save_full_program,
         get_relational_week_schedule, get_evening_week_schedule,
         get_exercise_history_grouped_by_session, get_hiit_logs,
         get_all_programs, get_default_program_id, get_all_session_names,
         delete_exercise_by_name, delete_exercise_log_entry, delete_exercise_log_entry_by_type,
         get_nutrition_settings, delete_program_session) = make_db_store()

        store = self.store   # capture local ref for closures

        def get_exercises():
            return copy.deepcopy(store.get("inventory", {}))

        def upsert_exercise(data):
            name = data.get("name", "")
            inv = store.get("inventory", {})
            inv[name] = {k: v for k, v in data.items() if k != "name"}
            store["inventory"] = inv
            return data

        def rename_exercise_table(old_name, new_name):
            inv = store.get("inventory", {})
            if old_name in inv:
                if new_name not in inv:
                    inv[new_name] = inv.pop(old_name)
                else:
                    del inv[old_name]
                store["inventory"] = inv
                return True
            return False

        def get_deload_state():
            return copy.deepcopy(store.get("deload_state", {"active": False, "started_at": None, "reason": None}))

        def set_deload_state(active=False, started_at=None, reason=None):
            store["deload_state"] = {"active": active, "started_at": started_at, "reason": reason}
            return True

        db_mock = MagicMock(
            get_json=get_json,
            set_json=set_json,
            update_json=update_json,
            append_json_list=append_json_list,
            get_exercises=get_exercises,
            upsert_exercise=upsert_exercise,
            rename_exercise_table=rename_exercise_table,
            _ON_VERCEL=False,
            get_all_exercise_history=get_all_exercise_history,
            get_workout_sessions=get_workout_sessions,
            get_workout_session=get_workout_session,
            get_or_create_workout_session=get_or_create_workout_session,
            create_workout_session=create_workout_session,
            update_workout_session=update_workout_session,
            upsert_exercise_log=upsert_exercise_log,
            upsert_exercise_log_by_type=upsert_exercise_log_by_type,
            get_full_program=get_full_program,
            save_full_program=save_full_program,
            get_relational_week_schedule=get_relational_week_schedule,
            get_evening_week_schedule=get_evening_week_schedule,
            get_exercise_history_grouped_by_session=get_exercise_history_grouped_by_session,
            get_hiit_logs=get_hiit_logs,
            get_all_programs=get_all_programs,
            get_default_program_id=get_default_program_id,
            get_all_session_names=get_all_session_names,
            delete_exercise_by_name=delete_exercise_by_name,
            delete_exercise_log_entry=delete_exercise_log_entry,
            delete_exercise_log_entry_by_type=delete_exercise_log_entry_by_type,
            get_nutrition_settings=get_nutrition_settings,
            delete_program_session=delete_program_session,
            get_deload_state=get_deload_state,
            set_deload_state=set_deload_state,
        )

        self.db_patch = patch.dict("sys.modules", {"db": db_mock})
        self.db_patch.start()

        # Clear cached modules so patches take effect
        for mod in list(sys.modules.keys()):
            if mod in ("index", "weights") or mod.startswith((
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
        with patch("utils._today_mtl", return_value="2026-03-10"):
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
