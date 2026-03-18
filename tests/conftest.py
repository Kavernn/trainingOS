"""
Shared fixtures for TrainingOS route tests.
Provides make_store() and a BaseRouteTest class reused by all test modules.
"""
import copy
import json
import os
import sys
from unittest.mock import patch, MagicMock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

# ── Common fixture data ───────────────────────────────────────────────────────

PROGRAM = {
    "Upper A": {
        "blocks": [{
            "type": "strength", "order": 0,
            "exercises": {
                "Bench Press":    "4x5-7",
                "Barbell Row":    "4x6-8",
                "Overhead Press": "3x6-8",
            },
        }]
    },
    "Lower": {
        "blocks": [{
            "type": "strength", "order": 0,
            "exercises": {
                "Back Squat":        "4x5-7",
                "Romanian Deadlift": "3x8-10",
            },
        }]
    },
}

WEIGHTS = {
    "Bench Press": {
        "current_weight": 185.0,
        "last_reps": "6,6,5,5",
        "history": [
            {"date": "2026-03-10", "weight": 185.0, "reps": "6,6,5,5", "1rm": 210.0},
            {"date": "2026-03-03", "weight": 180.0, "reps": "7,6,5,5"},
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

SESSIONS = {
    "2026-03-10": {"rpe": 7, "comment": "good session"},
    "2026-03-07": {"rpe": 8, "comment": ""},
}

INVENTORY = {
    "Bench Press":    {"type": "barbell", "default_scheme": "4x5-7", "increment": 5, "bar_weight": 45},
    "Back Squat":     {"type": "barbell", "default_scheme": "4x5-7", "increment": 5, "bar_weight": 45},
    "Barbell Row":    {"type": "barbell", "default_scheme": "4x6-8", "increment": 5, "bar_weight": 45},
    "Overhead Press": {"type": "barbell", "default_scheme": "3x6-8", "increment": 5, "bar_weight": 45},
    "Romanian Deadlift": {"type": "barbell", "default_scheme": "3x8-10", "increment": 5, "bar_weight": 45},
    "Cable Fly":      {"type": "cable",   "default_scheme": "3x12-15", "increment": 5},
}

PROFILE = {
    "name": "Test User", "weight": 180.0, "height": 175,
    "age": 30, "level": "intermediate",
}

HIIT_LOG = [
    {"date": "2026-03-11", "session_type": "Tabata", "rounds_planifies": 8,
     "rounds_completes": 8, "rpe": 8, "feeling": "good", "comment": ""},
]


def make_store():
    store = {
        "program":             copy.deepcopy(PROGRAM),
        "weights":             copy.deepcopy(WEIGHTS),
        "sessions":            copy.deepcopy(SESSIONS),
        "inventory":           copy.deepcopy(INVENTORY),
        "user_profile":        copy.deepcopy(PROFILE),
        "hiit_log":            copy.deepcopy(HIIT_LOG),
        "body_weight":         [],
        "goals":               {},
        "deload_state":        {"active": False},
        "nutrition_settings":  {"limite_calories": 2200, "objectif_proteines": 160},
        "nutrition_log":       {},
        "cardio_log":          [],
        "recovery_log":        [],
        "sleep_records":       [],
        "mood_log":            [],
        "journal_entries":     [],
        "breathwork_sessions": [],
        "self_care_habits":    [],
        "self_care_log":       {},
        "pss_records":         [],
        "coach_history":       [],
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

    def append_json_list(key, entry, max_items=None):
        lst = copy.deepcopy(store.get(key, []))
        lst.insert(0, entry)
        if max_items:
            lst = lst[:max_items]
        store[key] = lst
        return True

    # ── Domain methods ────────────────────────────────────────────────────────

    def get_exercises():
        return copy.deepcopy(store.get("inventory", {}))

    def get_exercise_by_name(name):
        inv = store.get("inventory", {})
        info = inv.get(name)
        return {"name": name, **info} if info else None

    def get_exercise_id(name):
        return name  # use name as ID in tests

    def upsert_exercise(data):
        name = data.get("name")
        if not name:
            return None
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
                del inv[old_name]   # new_name already exists — just remove old
            store["inventory"] = inv
            return True
        return False

    def delete_exercise_by_name(name):
        inv = store.get("inventory", {})
        if name in inv:
            del inv[name]
            store["inventory"] = inv
            return True
        return False

    def exercise_has_logs(name):
        weights = store.get("weights", {})
        return bool(weights.get(name, {}).get("history", []))

    def remove_exercise_from_program_blocks(name):
        program = store.get("program", {})
        for sdef in program.values():
            for block in sdef.get("blocks", []):
                if block.get("type") == "strength":
                    block.get("exercises", {}).pop(name, None)
        store["program"] = program

    def get_deleted_exercises():
        return set(store.get("deleted_exercises", []))

    def mark_exercise_deleted(name):
        deleted = list(get_deleted_exercises())
        if name not in deleted:
            deleted.append(name)
        store["deleted_exercises"] = deleted

    def unmark_exercise_deleted(name):
        deleted = list(get_deleted_exercises())
        if name in deleted:
            deleted.remove(name)
        store["deleted_exercises"] = deleted

    def get_full_program():
        return copy.deepcopy(store.get("program", {}))

    def save_full_program(program):
        current = store.get("program", {})
        current.update(copy.deepcopy(program))
        store["program"] = current
        return True

    def get_workout_sessions(limit=100):
        sessions = store.get("sessions", {})
        result = []
        for date in sorted(sessions.keys(), reverse=True)[:limit]:
            entry = copy.deepcopy(sessions[date])
            entry["date"] = date
            result.append(entry)
        return result

    def get_workout_session(date):
        sessions = store.get("sessions", {})
        if date in sessions:
            entry = copy.deepcopy(sessions[date])
            entry["date"] = date
            return entry
        return None

    def create_workout_session(date, rpe=None, comment=None, duration_min=None, energy_pre=None, is_second=False):
        sessions = store.get("sessions", {})
        key = date if not is_second else f"{date}_2"
        entry = {"rpe": rpe, "comment": comment or "", "exos": []}
        if duration_min is not None:
            entry["duration_min"] = duration_min
        sessions[key] = entry
        store["sessions"] = sessions
        return {**entry, "date": date, "id": key}

    def update_workout_session(date, patch):
        sessions = store.get("sessions", {})
        if date in sessions:
            sessions[date].update(patch)
            store["sessions"] = sessions
            return True
        return False

    def delete_workout_session(date):
        sessions = store.get("sessions", {})
        if date in sessions:
            del sessions[date]
            store["sessions"] = sessions
            return True
        return False

    def get_all_exercise_history():
        weights = store.get("weights", {})
        result = {}
        for name, ex_data in weights.items():
            history = ex_data.get("history", [])
            if history:
                result[name] = [{"date": e.get("date"), "weight": e.get("weight"), "reps": e.get("reps")} for e in history]
        return result

    def get_or_create_workout_session(date):
        sessions = store.get("sessions", {})
        if date in sessions:
            entry = copy.deepcopy(sessions[date])
            entry["date"] = date
            entry.setdefault("id", date)
            return entry
        entry = {"rpe": None, "comment": "", "exos": [], "id": date}
        sessions[date] = entry
        store["sessions"] = sessions
        return {**entry, "date": date}

    def get_exercise_history(exercise_name, limit=50):
        weights = store.get("weights", {})
        history = weights.get(exercise_name, {}).get("history", [])
        result = []
        for entry in history[:limit]:
            result.append({
                "date":       entry.get("date"),
                "weight":     entry.get("weight"),
                "reps":       entry.get("reps"),
                "session_id": entry.get("date"),
            })
        return result

    def get_session_exercise_logs(session_date):
        weights = store.get("weights", {})
        result = []
        for name, ex_data in weights.items():
            history = ex_data.get("history", [])
            for entry in history:
                if entry.get("date") == session_date:
                    result.append({"exercise_name": name, "weight": entry.get("weight"), "reps": entry.get("reps")})
        return result

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

    def delete_session_exercise_logs(session_date):
        weights = store.get("weights", {})
        for ex_data in weights.values():
            ex_data["history"] = [e for e in ex_data.get("history", []) if e.get("date") != session_date]
            # Recalculate denormalized fields to reflect the new most-recent entry
            remaining = ex_data["history"]
            if remaining:
                most_recent = max(remaining, key=lambda e: e.get("date", ""))
                ex_data["current_weight"] = most_recent.get("weight", ex_data.get("current_weight", 0))
                ex_data["last_reps"] = most_recent.get("reps", ex_data.get("last_reps", ""))
        store["weights"] = weights
        return True

    def get_body_weight_logs(limit=100):
        return copy.deepcopy(store.get("body_weight", []))[:limit]

    def upsert_body_weight(date, weight, note="", body_fat=None, waist_cm=None,
                           arms_cm=None, chest_cm=None, thighs_cm=None, hips_cm=None):
        bw = store.get("body_weight", [])
        entry_data = {"date": date, "poids": weight, "note": note}
        for field, val in [("body_fat", body_fat), ("waist_cm", waist_cm),
                           ("arms_cm", arms_cm), ("chest_cm", chest_cm),
                           ("thighs_cm", thighs_cm), ("hips_cm", hips_cm)]:
            if val is not None:
                entry_data[field] = val
        for entry in bw:
            if entry.get("date") == date:
                entry.update(entry_data)
                store["body_weight"] = bw
                return True
        bw.insert(0, entry_data)
        store["body_weight"] = bw
        return True

    def get_nutrition_entries(date):
        log = store.get("nutrition_log", {})
        return copy.deepcopy((log.get(date) or {}).get("entries", []))

    def get_nutrition_entries_recent(n=7):
        log = store.get("nutrition_log", {})
        days = sorted(log.keys(), reverse=True)[:n]
        return [
            {
                "date":     d,
                "calories": round(sum(e.get("calories", 0) for e in (log.get(d) or {}).get("entries", []))),
                "nb":       len((log.get(d) or {}).get("entries", [])),
            }
            for d in days
        ]

    def insert_nutrition_entry(data):
        log = store.get("nutrition_log", {})
        d = data.get("date", "")
        if d not in log:
            log[d] = {"entries": []}
        log[d]["entries"].append(copy.deepcopy(data))
        store["nutrition_log"] = log
        return copy.deepcopy(data)

    def delete_nutrition_entry(entry_id):
        log = store.get("nutrition_log", {})
        for day_data in log.values():
            before = len(day_data.get("entries", []))
            day_data["entries"] = [e for e in day_data.get("entries", []) if e.get("id") != entry_id]
            if len(day_data["entries"]) < before:
                store["nutrition_log"] = log
                return True
        return False

    def delete_body_weight(date):
        bw = store.get("body_weight", [])
        store["body_weight"] = [e for e in bw if e.get("date") != date]
        return True

    def get_hiit_logs(limit=100):
        import uuid as _uuid
        logs = store.get("hiit_log", [])
        # Assign stable IDs to entries that don't have one yet
        for entry in logs:
            if "id" not in entry:
                entry["id"] = str(_uuid.uuid4())
        return copy.deepcopy(logs[:limit])

    def insert_hiit_log(data):
        import uuid
        logs = store.get("hiit_log", [])
        entry = copy.deepcopy(data)
        if "id" not in entry:
            entry["id"] = str(uuid.uuid4())
        logs.insert(0, entry)
        store["hiit_log"] = logs
        return entry

    def update_hiit_log(hiit_id, patch):
        logs = store.get("hiit_log", [])
        for entry in logs:
            if entry.get("id") == str(hiit_id) or logs.index(entry) == hiit_id:
                entry.update(patch)
                store["hiit_log"] = logs
                return True
        return False

    def delete_hiit_log_by_id(hiit_id):
        logs = store.get("hiit_log", [])
        before = len(logs)
        store["hiit_log"] = [e for e in logs if e.get("id") != str(hiit_id)]
        return len(store["hiit_log"]) < before

    def get_recovery_logs(limit=100):
        return copy.deepcopy(store.get("recovery_log", []))[:limit]

    def upsert_recovery_log(data):
        logs = store.get("recovery_log", [])
        date = data.get("date")
        for i, entry in enumerate(logs):
            if entry.get("date") == date:
                logs[i] = copy.deepcopy(data)
                store["recovery_log"] = logs
                return True
        logs.insert(0, copy.deepcopy(data))
        store["recovery_log"] = logs
        return True

    def delete_recovery_log(date):
        logs = store.get("recovery_log", [])
        store["recovery_log"] = [e for e in logs if e.get("date") != date]
        return True

    def get_goals():
        return copy.deepcopy(store.get("goals", {}))

    def set_goal(exercise_name, target_weight, target_date=None):
        goals = store.get("goals", {})
        goals[exercise_name] = {"goal_weight": target_weight}
        if target_date:
            goals[exercise_name]["target_date"] = target_date
        store["goals"] = goals
        return True

    def get_cardio_logs(limit=100):
        return copy.deepcopy(store.get("cardio_log", []))[:limit]

    def insert_cardio_log(data):
        logs = store.get("cardio_log", [])
        logs.insert(0, copy.deepcopy(data))
        store["cardio_log"] = logs
        return True

    def delete_cardio_log(date, type_):
        logs = store.get("cardio_log", [])
        store["cardio_log"] = [e for e in logs if not (e.get("date") == date and e.get("type") == type_)]
        return True

    def get_profile():
        return copy.deepcopy(store.get("user_profile", {}))

    def update_profile(patch):
        profile = store.get("user_profile", {})
        profile.update(patch)
        store["user_profile"] = profile
        return True

    def get_nutrition_settings():
        return copy.deepcopy(store.get("nutrition_settings", {}))

    def update_nutrition_settings(patch):
        settings = store.get("nutrition_settings", {})
        settings.update(patch)
        store["nutrition_settings"] = settings
        return True

    def get_deload_state():
        return copy.deepcopy(store.get("deload_state", {"active": False}))

    def set_deload_state(active, started_at=None, reason=None):
        state = {"active": active}
        if started_at:
            state["started_at"] = started_at
        if reason:
            state["reason"] = reason
        store["deload_state"] = state
        return True

    db_mock = MagicMock(
        get_json=get_json,
        set_json=set_json,
        update_json=update_json,
        append_json_list=append_json_list,
        _ON_VERCEL=False,
        # Domain methods
        get_exercises=get_exercises,
        get_exercise_by_name=get_exercise_by_name,
        get_exercise_id=get_exercise_id,
        upsert_exercise=upsert_exercise,
        rename_exercise_table=rename_exercise_table,
        delete_exercise_by_name=delete_exercise_by_name,
        exercise_has_logs=exercise_has_logs,
        remove_exercise_from_program_blocks=remove_exercise_from_program_blocks,
        get_deleted_exercises=get_deleted_exercises,
        mark_exercise_deleted=mark_exercise_deleted,
        unmark_exercise_deleted=unmark_exercise_deleted,
        get_full_program=get_full_program,
        save_full_program=save_full_program,
        get_workout_sessions=get_workout_sessions,
        get_workout_session=get_workout_session,
        get_or_create_workout_session=get_or_create_workout_session,
        create_workout_session=create_workout_session,
        update_workout_session=update_workout_session,
        delete_workout_session=delete_workout_session,
        get_all_exercise_history=get_all_exercise_history,
        get_exercise_history=get_exercise_history,
        get_session_exercise_logs=get_session_exercise_logs,
        upsert_exercise_log=upsert_exercise_log,
        delete_session_exercise_logs=delete_session_exercise_logs,
        get_body_weight_logs=get_body_weight_logs,
        upsert_body_weight=upsert_body_weight,
        delete_body_weight=delete_body_weight,
        get_nutrition_entries=get_nutrition_entries,
        get_nutrition_entries_recent=get_nutrition_entries_recent,
        insert_nutrition_entry=insert_nutrition_entry,
        delete_nutrition_entry=delete_nutrition_entry,
        get_hiit_logs=get_hiit_logs,
        insert_hiit_log=insert_hiit_log,
        update_hiit_log=update_hiit_log,
        delete_hiit_log_by_id=delete_hiit_log_by_id,
        get_recovery_logs=get_recovery_logs,
        upsert_recovery_log=upsert_recovery_log,
        delete_recovery_log=delete_recovery_log,
        get_goals=get_goals,
        set_goal=set_goal,
        get_cardio_logs=get_cardio_logs,
        insert_cardio_log=insert_cardio_log,
        delete_cardio_log=delete_cardio_log,
        get_profile=get_profile,
        update_profile=update_profile,
        get_nutrition_settings=get_nutrition_settings,
        update_nutrition_settings=update_nutrition_settings,
        get_deload_state=get_deload_state,
        set_deload_state=set_deload_state,
    )
    return store, db_mock


import unittest

_MODULES_TO_EVICT = (
    "index", "planner", "log_workout", "sessions", "inventory",
    "progression", "deload", "goals", "body_weight", "user_profile",
    "hiit", "blocks", "nutrition", "volume", "health_data",
    "life_stress_engine", "mental_health_dashboard", "mood", "journal",
    "breathwork", "self_care", "sleep", "pss", "cardio", "weights",
)

TODAY = "2026-03-14"


class BaseRouteTest(unittest.TestCase):
    """Flask test client with in-memory store and mocked db layer."""

    def setUp(self):
        self.store, db_mock = make_store()

        self.db_patch = patch.dict("sys.modules", {"db": db_mock})
        self.db_patch.start()

        for mod in list(sys.modules.keys()):
            if mod in _MODULES_TO_EVICT or any(mod.startswith(m) for m in _MODULES_TO_EVICT):
                del sys.modules[mod]

        self._today_patch = patch("planner.get_today_date", return_value=TODAY)
        self._today_patch.start()

        import index as idx
        self.idx = idx
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
        return self.client.post(url, json=payload,
                                content_type="application/json")

    def json(self, resp):
        return json.loads(resp.data)
