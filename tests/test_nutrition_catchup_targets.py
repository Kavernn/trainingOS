"""Focused catch-up tests; real Nutrition classifier + canonical date planning.
Run: .venv/bin/python tests/test_nutrition_catchup_targets.py
"""
import copy
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "api"))

from flask import Flask
import nutrition
from routes.nutrition_entries import nutrition_bp


class CatchupTargetsTests(unittest.TestCase):
    def setUp(self):
        self.settings = {
            "limite_calories": 2400, "objectif_proteines": 180, "lipides": 75,
            "day_type_targets": {
                kind: {"calories": cal, "glucides": carbs}
                for kind, cal, carbs in [("heavy", 2800, 330), ("moderate", 2500, 270),
                                          ("light", 2250, 210), ("rest", 2000, 160)]
            },
        }
        self.db = MagicMock()
        self.db.get_nutrition_settings.side_effect = lambda: copy.deepcopy(self.settings)
        self.db.get_active_program_id.return_value = "active"
        self.db.get_full_program.return_value = {"Lower B": {}, "Upper A": {}, "Conditioning": {}}
        self.db.get_relational_week_schedule.return_value = {
            "Dim": "Lower B", "Lun": "Repos", "Mar": "Upper A", "Mer": "Conditioning"}
        self.db.get_evening_week_schedule.return_value = {}
        self.db.get_session_override.return_value = None
        self.db.get_workout_session_by_type.return_value = None
        self.db.get_nutrition_entries.return_value = [{"calories": 400, "proteines": 25}]
        self.db.delete_nutrition_entries_for_date.return_value = True
        self.db.insert_nutrition_entry.side_effect = lambda entry: entry
        self.addCleanup(patch.stopall)
        patch.dict(sys.modules, {"db": self.db}).start()
        patch.object(nutrition, "db", self.db).start()
        patch.object(nutrition, "_today_mtl", return_value="2026-09-28").start()
        patch("planner.get_today_date", return_value="2026-09-28").start()
        app = Flask(__name__)
        app.register_blueprint(nutrition_bp)
        self.client = app.test_client()

    def test_four_day_types_resolve_through_active_program_planning(self):
        for date, kind, cal in [("2026-09-27", "heavy", 2800), ("2026-09-28", "rest", 2000),
                                ("2026-09-29", "light", 2250), ("2026-09-30", "moderate", 2500)]:
            with self.subTest(date=date):
                target = nutrition.resolve_daily_target(date)
                self.assertEqual((target["date"], target["day_type"], target["calories"]), (date, kind, cal))
                self.assertEqual(target["proteines"], 180)
        self.db.get_full_program.assert_called_with(program_id="active")

    def test_yesterday_heavy_today_rest_and_existing_entries_unchanged(self):
        response = self.client.get("/api/nutrition?date=2026-09-27&include_target=true")
        self.assertEqual(response.status_code, 200)
        data = response.get_json()
        self.assertEqual(data["target"]["day_type"], "heavy")
        self.assertEqual(data["target"]["calories"], 2800)
        self.assertEqual(data["target"]["glucides"], 330)
        self.assertEqual(data["target"]["lipides"], 75)
        self.assertEqual((data["calories"], data["proteines"], data["entries_count"]), (400, 25, 1))
        self.db.get_workout_session_by_type.assert_called_with("2026-09-27", "morning")
        self.db.delete_nutrition_entries_for_date.assert_not_called()

    def test_actual_historical_session_precedes_current_schedule(self):
        self.db.get_workout_session_by_type.return_value = {"session_name": "Upper A"}
        self.assertEqual(nutrition.resolve_daily_target("2026-09-27")["calories"], 2250)

    def test_foreign_inactive_program_session_does_not_classify_heavy(self):
        self.db.get_relational_week_schedule.return_value = {"Dim": "Lower inactive"}
        self.assertEqual(nutrition.resolve_daily_target("2026-09-27")["day_type"], "rest")

    def test_date_scoped_override(self):
        self.db.get_session_override.return_value = {"date": "2026-09-27", "session": "Upper A"}
        self.assertEqual(nutrition.resolve_daily_target("2026-09-27")["calories"], 2250)
        self.assertEqual(nutrition.resolve_daily_target("2026-09-28")["calories"], 2000)

    def test_missing_targets_never_expose_global_2400_180(self):
        self.settings.pop("day_type_targets")
        data = self.client.get("/api/nutrition?date=2026-09-27&include_target=true").get_json()
        self.assertIsNone(data["target"])
        self.assertTrue(data["target_error"])
        with self.assertRaises(ValueError):
            nutrition.replace_day_with_estimate(100, 100)
        self.db.delete_nutrition_entries_for_date.assert_not_called()

    def test_invalid_explicit_date_never_uses_today(self):
        response = self.client.get("/api/nutrition?date=invalid&include_target=true")
        self.assertEqual(response.status_code, 422)
        self.db.get_nutrition_entries.assert_not_called()

    def test_missing_protein_never_supplies_180(self):
        self.settings.pop("objectif_proteines")
        with self.assertRaises(ValueError):
            nutrition.resolve_daily_target("2026-09-27")

    def test_program_failure_does_not_fall_back_to_moderate(self):
        self.db.get_full_program.return_value = None
        with self.assertRaises(ValueError):
            nutrition.resolve_daily_target("2026-09-27")

    def test_legitimately_configured_2400_180_is_allowed(self):
        self.settings["day_type_targets"]["heavy"]["calories"] = 2400
        self.assertEqual(nutrition.resolve_daily_target("2026-09-27")["calories"], 2400)

    def test_slider_math_and_legacy_yesterday_resolution(self):
        result = nutrition.replace_day_with_estimate(75, 80)
        self.assertEqual((result["date"], result["calories"], result["proteines"]), ("2026-09-27", 2100, 144))
        self.db.delete_nutrition_entries_for_date.assert_called_once_with("2026-09-27")

    def test_confirmation_persists_snapshot_even_if_settings_change(self):
        self.settings["day_type_targets"]["heavy"]["calories"] = 3100
        with patch.dict(sys.modules, {"readiness": MagicMock(), "routes.daily_brief": MagicMock()}):
            response = self.client.post("/api/nutrition/estimate_yesterday", json={
                "date": "2026-09-20", "pct_calories": 75, "pct_proteines": 80,
                "calories": 2100, "proteines": 144,
            })
        self.assertEqual(response.status_code, 200)
        data = response.get_json()
        self.assertEqual((data["date"], data["calories"], data["proteines"]), ("2026-09-20", 2100, 144))
        self.db.delete_nutrition_entries_for_date.assert_called_once_with("2026-09-20")
        entry = self.db.insert_nutrition_entry.call_args.args[0]
        self.assertEqual((entry["calories"], entry["proteines"]), (2100, 144))
        self.assertEqual((entry["glucides"], entry["lipides"]), (0, 0))

    def test_invalid_confirmation_never_deletes_entries(self):
        for kwargs in [{"date": "2026-09-28"}, {"date": "2026-09-27", "calories": float("nan"), "proteines": 144},
                       {"date": "2026-09-27", "calories": 2100}, {"calories": 2100, "proteines": 144}]:
            with self.subTest(kwargs=kwargs), self.assertRaises(ValueError):
                nutrition.replace_day_with_estimate(75, 80, **kwargs)
        self.db.delete_nutrition_entries_for_date.assert_not_called()


if __name__ == "__main__":
    unittest.main(verbosity=2)
