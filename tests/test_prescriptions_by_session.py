"""L6 : prescriptions indexées par séance ; schéma illisible → aucune prescription inventée."""
import sys
from unittest.mock import patch

from conftest import BaseRouteTest
from utils import parse_scheme_strict, prescriptions_by_session


def test_same_exercise_in_two_sessions_keeps_each_session_range():
    out = prescriptions_by_session({"Lundi": {"Dips": "3x6-10"}, "Vendredi": {"Dips": "3x8-12"}}, {}, None)
    assert (out["Lundi"]["Dips"]["rep_min"], out["Lundi"]["Dips"]["rep_max"]) == (6, 10)
    assert (out["Vendredi"]["Dips"]["rep_min"], out["Vendredi"]["Dips"]["rep_max"]) == (8, 12)


def test_unreadable_scheme_has_no_prescription_never_3x8_12():
    assert parse_scheme_strict("1xmax") is None and parse_scheme_strict("") is None
    out = prescriptions_by_session({"Mardi PM": {"Deadhang": "1xmax", "Face Pull": "3x15"}}, {}, None)
    assert "Deadhang" not in out["Mardi PM"] and out["Mardi PM"]["Face Pull"]["sets"] == 3


def test_time_and_distance_schemes_keep_their_sets():
    assert parse_scheme_strict("2x30-45s") == (2, 30, 45)
    assert parse_scheme_strict("2x30-40m") == (2, 30, 40)


class TestSeanceDataPrescriptionsBySession(BaseRouteTest):
    def test_route_exposes_per_session_key_and_keeps_legacy_key(self):
        db = sys.modules["db"]
        program = {"Lundi": {"Dips": "3x6-10"}, "Vendredi": {"Dips": "3x8-12", "Deadhang": "2xmax"}}
        for name, value in {"get_full_program": program, "get_relational_week_schedule": {"Lun": "Lundi"},
                            "get_evening_week_schedule": {}, "get_session_override": {},
                            "get_session_plan_overrides": []}.items():
            p = patch.object(db, name, return_value=value); p.start(); self.addCleanup(p.stop)
        p = patch("weights.coaching_references", return_value={}); p.start(); self.addCleanup(p.stop)
        data = self.json(self.get("/api/seance_data?date=2088-09-25"))
        by = data["prescriptions_by_session"]
        self.assertEqual((by["Lundi"]["Dips"]["rep_min"], by["Lundi"]["Dips"]["rep_max"]), (6, 10))
        self.assertEqual((by["Vendredi"]["Dips"]["rep_min"], by["Vendredi"]["Dips"]["rep_max"]), (8, 12))
        self.assertNotIn("Deadhang", by["Vendredi"])
        self.assertIn("Dips", data["prescriptions"])          # ancienne clé conservée
