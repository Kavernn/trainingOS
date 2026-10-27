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

    # /api/macro_gap retiré en phase B2.2 — plus de consommateur iOS.


if __name__ == "__main__":
    unittest.main(verbosity=2)
