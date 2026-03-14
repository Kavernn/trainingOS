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

    db_mock = MagicMock(
        get_json=get_json,
        set_json=set_json,
        update_json=update_json,
        append_json_list=append_json_list,
        _ON_VERCEL=False,
    )
    return store, db_mock


import unittest

_MODULES_TO_EVICT = (
    "index", "planner", "log_workout", "sessions", "inventory",
    "progression", "deload", "goals", "body_weight", "user_profile",
    "hiit", "blocks", "nutrition", "volume", "health_data",
    "life_stress_engine", "mental_health_dashboard", "mood", "journal",
    "breathwork", "self_care", "sleep", "pss", "cardio",
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
