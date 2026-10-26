"""Tests "Cible calorique unique" : analytics_coach, coach_insights, macro_gap
lisent la cible adaptative (compute_target_calories), pas calorie_limit, et
retombent proprement en "indisponible" si <7j TDEE (pas de fallback 2500).

Lancer : .venv/bin/python -m pytest tests/test_adaptive_target_cal.py -v
"""
from __future__ import annotations

import sys
import os
import unittest
from unittest.mock import patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

from conftest import BaseRouteTest


class AdaptiveTargetCalTests(BaseRouteTest):

    def setUp(self):
        super().setUp()
        # /api/weekly_report cache 30 min — clear entre tests.
        import routes.analytics_coach as _ac
        _ac._weekly_report_cache.clear()

    # ── /api/weekly_report → nutrition_compliance adaptive ────────────────────

    def _set_nutrition_day(self, date: str, calories: float, proteines: float = 180):
        """nutrition_log stub du conftest : {date: {entries: [...]}}."""
        self.store["nutrition_log"] = {
            date: {"entries": [{"calories": calories, "proteines": proteines, "date": date}]}
        }

    def test_weekly_report_uses_adaptive_target_not_calorie_limit(self):
        """Si calorie_limit=2000 mais compute_target_calories=3000, la
        compliance se calcule sur 3000 (±10 %)."""
        # 1 jour nutrition : 3000 kcal → compliance 100 % sur cible 3000,
        # 0 % sur cible 2000 (|3000-2000|/2000 = 0.5 > 0.10).
        self._set_nutrition_day("2026-10-20", 3000)
        self.store["nutrition_settings"] = {"calorie_limit": 2000, "protein_target": 180}
        with patch("tdee.compute_target_calories", return_value=3000):
            resp = self.get("/api/weekly_report")
        self.assertEqual(resp.status_code, 200)
        self.assertEqual(self.json(resp)["nutrition_compliance"], 100)

    def test_weekly_report_nutrition_compliance_null_when_target_unavailable(self):
        """compute_target_calories=None (<7j TDEE) → compliance=null,
        pas de fallback calorie_limit."""
        self._set_nutrition_day("2026-10-20", 2000)
        self.store["nutrition_settings"] = {"calorie_limit": 2000, "protein_target": 180}
        with patch("tdee.compute_target_calories", return_value=None):
            resp = self.get("/api/weekly_report")
        self.assertIsNone(self.json(resp)["nutrition_compliance"])

    # ── /api/macro_gap → cible adaptative + null explicite ────────────────────

    def test_macro_gap_targets_calories_from_adaptive(self):
        self.store["nutrition_settings"] = {"calorie_limit": 2000, "protein_target": 180,
                                             "glucides_target": 250, "lipides_target": 80}
        with patch("tdee.compute_target_calories", return_value=2850):
            resp = self.get("/api/macro_gap")
        self.assertEqual(resp.status_code, 200)
        data = self.json(resp)
        self.assertEqual(data["targets"]["calories"], 2850)
        self.assertNotEqual(data["targets"]["calories"], 2000)

    def test_macro_gap_target_calories_null_when_adaptive_unavailable(self):
        """Pas de fallback 2500 : cible null → gap null + payload l'expose."""
        self.store["nutrition_settings"] = {"calorie_limit": 2000, "protein_target": 180}
        with patch("tdee.compute_target_calories", return_value=None):
            resp = self.get("/api/macro_gap")
        self.assertEqual(resp.status_code, 200)
        data = self.json(resp)
        self.assertIsNone(data["targets"]["calories"])
        self.assertIsNone(data["gaps"]["calories"])

    def test_macro_gap_primary_falls_back_to_protein_without_adaptive(self):
        """Sans cible calorique dispo, la recommandation ne peut PAS être
        'calories' — fallback vers protein (toujours sain)."""
        # Pas de gap_prot significatif (170/180 → 10), pas de gap_carb (220/250 → 30, pile),
        # pas de cal → protein par défaut.
        self._set_nutrition_day("2026-10-20", 1800, proteines=170)
        self.store["nutrition_settings"] = {"protein_target": 180, "glucides_target": 250,
                                             "lipides_target": 80}
        with patch("tdee.compute_target_calories", return_value=None):
            resp = self.get("/api/macro_gap")
        self.assertEqual(self.json(resp)["primary_gap"], "protein")


if __name__ == "__main__":
    unittest.main(verbosity=2)
