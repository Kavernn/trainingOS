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
import tdee
import energy
from routes.nutrition_entries import nutrition_bp


# Baseline adaptive target : 8 jours de TDEE=2600 → compute_target_calories = 2600 (goal=maintain, _GOAL_ADJ=0).
_ADAPTIVE_HISTORY = [{"tdee": 2600} for _ in range(8)]
_ADAPTIVE_CAL = 2600.0


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
        self.db.get_profile.return_value = {"goal": "maintain"}  # pour tdee._GOAL_ADJ
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
        patch.object(tdee, "db", self.db).start()
        patch.object(nutrition, "_today_mtl", return_value="2026-09-28").start()
        patch("planner.get_today_date", return_value="2026-09-28").start()
        # Cible calories adaptative baseline — override via self.energy_history_mock dans les tests.
        self.energy_history_mock = patch.object(
            energy, "compute_energy_history", return_value=_ADAPTIVE_HISTORY
        ).start()
        app = Flask(__name__)
        app.register_blueprint(nutrition_bp)
        self.client = app.test_client()

    # ── Classifier (day_type) ─────────────────────────────────────────────────

    def test_four_day_types_resolve_through_active_program_planning(self):
        for date, kind in [("2026-09-27", "heavy"), ("2026-09-28", "rest"),
                           ("2026-09-29", "light"), ("2026-09-30", "moderate")]:
            with self.subTest(date=date):
                target = nutrition.resolve_daily_target(date)
                self.assertEqual((target["date"], target["day_type"]), (date, kind))
                self.assertEqual(target["calories"], _ADAPTIVE_CAL)
                self.assertEqual(target["proteines"], 180)
        self.db.get_full_program.assert_called_with(program_id="active")

    def test_yesterday_heavy_today_rest_and_existing_entries_unchanged(self):
        response = self.client.get("/api/nutrition?date=2026-09-27&include_target=true")
        self.assertEqual(response.status_code, 200)
        data = response.get_json()
        self.assertEqual(data["target"]["day_type"], "heavy")
        self.assertEqual(data["target"]["calories"], _ADAPTIVE_CAL)
        self.assertEqual(data["target"]["glucides"], 330)
        self.assertEqual(data["target"]["lipides"], 75)
        self.assertEqual((data["calories"], data["proteines"], data["entries_count"]), (400, 25, 1))
        self.db.get_workout_session_by_type.assert_called_with("2026-09-27", "morning")
        self.db.delete_nutrition_entries_for_date.assert_not_called()

    def test_actual_historical_session_precedes_current_schedule(self):
        self.db.get_workout_session_by_type.return_value = {"session_name": "Upper A"}
        self.assertEqual(nutrition.resolve_daily_target("2026-09-27")["day_type"], "light")

    def test_foreign_inactive_program_session_does_not_classify_heavy(self):
        self.db.get_relational_week_schedule.return_value = {"Dim": "Lower inactive"}
        self.assertEqual(nutrition.resolve_daily_target("2026-09-27")["day_type"], "rest")

    def test_date_scoped_override(self):
        self.db.get_session_override.return_value = {"date": "2026-09-27", "session": "Upper A"}
        self.assertEqual(nutrition.resolve_daily_target("2026-09-27")["day_type"], "light")
        self.assertEqual(nutrition.resolve_daily_target("2026-09-28")["day_type"], "rest")

    # ── Erreurs explicites, pas de fallback ───────────────────────────────────

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

    def test_insufficient_tdee_history_raises_explicit_error(self):
        """<7j d'historique TDEE → ValueError dédiée, pas de fallback silencieux."""
        self.energy_history_mock.return_value = []
        with self.assertRaisesRegex(ValueError, "Historique TDEE insuffisant"):
            nutrition.resolve_daily_target("2026-09-27")
        # Côté route: le except Exception renvoie target=None + target_error.
        data = self.client.get("/api/nutrition?date=2026-09-27&include_target=true").get_json()
        self.assertIsNone(data["target"])
        self.assertTrue(data["target_error"])
        # Legacy replace_day_with_estimate: ValueError remonte, aucune suppression.
        with self.assertRaises(ValueError):
            nutrition.replace_day_with_estimate(100, 100)
        self.db.delete_nutrition_entries_for_date.assert_not_called()

    # ── Adaptative : fenêtre respecte la date ──────────────────────────────────

    def test_adaptive_calories_date_window_respected(self):
        """compute_target_calories(J-2) ≠ compute_target_calories(J-1) quand TDEE diffèrent.
        Preuve que `end_date` est effectivement forwardé jusqu'à compute_energy_history."""
        def history_by_end_date(days, end_date=None):
            tdees = {"2026-09-27": [2500] * 8, "2026-09-26": [2800] * 8}.get(end_date, [0] * 8)
            return [{"tdee": t} for t in tdees]

        self.energy_history_mock.side_effect = history_by_end_date
        cal_j1 = tdee.compute_target_calories("2026-09-27")
        cal_j2 = tdee.compute_target_calories("2026-09-26")
        self.assertEqual(cal_j1, 2500)
        self.assertEqual(cal_j2, 2800)
        self.assertNotEqual(cal_j1, cal_j2)

    # ── Estimations rétroactives ──────────────────────────────────────────────

    def test_slider_math_and_legacy_yesterday_resolution(self):
        # 2600 * 0.75 = 1950 ; 180 * 0.80 = 144
        result = nutrition.replace_day_with_estimate(75, 80)
        self.assertEqual((result["date"], result["calories"], result["proteines"]), ("2026-09-27", 1950, 144))
        self.db.delete_nutrition_entries_for_date.assert_called_once_with("2026-09-27")

    def test_confirmation_persists_snapshot_even_if_settings_change(self):
        # Snapshot explicite — ne passe pas par resolve_daily_target / compute_target_calories.
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
