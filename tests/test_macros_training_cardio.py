"""E — `get_macros_by_day_type` : cardio compte comme jour d'entraînement
via le helper `weekly_streaks.active_dates` partagé avec le streak.

Lancer : .venv/bin/python -m pytest tests/test_macros_training_cardio.py -v
"""
from __future__ import annotations

import sys
import os
import unittest
from unittest.mock import patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

from conftest import BaseRouteTest


class MacrosTrainingCardioTests(BaseRouteTest):
    """Hérite BaseRouteTest pour que sys.modules['db'] soit correctement stubbé
    et que les modules api/* se bindent sur ce stub (via l'éviction setup)."""

    def _run(self, nutr_days, active_dates):
        # Import APRÈS BaseRouteTest.setUp pour hériter de la fresh binding db.
        import db_stats
        p1 = patch("db_stats.get_nutrition_daily_full", return_value=nutr_days)
        p2 = patch("weekly_streaks.active_dates", return_value=active_dates)
        p3 = patch("db_stats._today_mtl", return_value="2026-10-20")
        self.addCleanup(p1.stop); self.addCleanup(p2.stop); self.addCleanup(p3.stop)
        p1.start(); p2.start(); p3.start()
        return db_stats.get_macros_by_day_type(days=10)

    def test_cardio_only_day_counts_as_training(self):
        """Un jour sans séance muscu mais avec cardio doit être training."""
        nutr = [{"date": "2026-10-15", "calories": 2500, "proteines": 180,
                 "glucides": 300, "lipides": 80, "source": "detailed"},
                {"date": "2026-10-16", "calories": 2200, "proteines": 160,
                 "glucides": 230, "lipides": 70, "source": "detailed"}]
        # 15/10 = cardio only. 16/10 = repos.
        result = self._run(nutr, {"2026-10-15"})
        self.assertEqual(result["n_training"], 1)
        self.assertEqual(result["n_rest"],     1)

    def test_detailed_only_filter_still_applies(self):
        """Les estimations rétroactives sont toujours exclues des moyennes."""
        nutr = [{"date": "2026-10-15", "calories": 2500, "proteines": 180,
                 "glucides": 300, "lipides": 80, "source": "detailed"},
                {"date": "2026-10-16", "calories": 2200, "proteines": 160,
                 "glucides": 0, "lipides": 0, "source": "estimated"}]
        result = self._run(nutr, {"2026-10-15"})
        self.assertEqual(result["n_training"], 1)
        self.assertEqual(result["n_rest"],     0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
