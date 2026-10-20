"""DNA consistency = /api/stats/streaks (source unique).

Garantit que workout_dna._compute_consistency expose les MÊMES valeurs que
/api/stats/streaks pour la même fixture :

  - weekly_streak_current / weekly_streak_best (étape 7a).
  - weekly_counts, sessions_per_week, active_weeks_pct (étape b, lot DNA
    Fiabilité) — tous dérivés de weeks[].days_active.

Protège contre un futur recalcul divergent dans workout_dna. Pattern aligné
sur test_weekly_streak.py (BaseRouteTest + conftest).
"""
import os
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

from conftest import BaseRouteTest


TODAY = "2026-10-19"  # lundi


class _FakeQuery:
    def __init__(self, rows):
        self.rows = rows
    def select(self, _): return self
    def gte(self, *_): return self
    def order(self, _): return self
    def execute(self):
        return type("R", (), {"data": self.rows})()


class _FakeClient:
    def __init__(self, dates):
        self.rows = [{"date": d} for d in sorted(dates)]
    def table(self, _):
        return _FakeQuery(self.rows)


class DnaConsistencyStreakSource(BaseRouteTest):

    def setUp(self):
        super().setUp()
        self._today_patchers = [
            patch("planner.get_today_date", return_value=TODAY),
            patch("utils._today_mtl", return_value=TODAY),
            patch("routes.analytics_stats._today_mtl", return_value=TODAY),
        ]
        for p in self._today_patchers:
            p.start()

    def tearDown(self):
        for p in self._today_patchers:
            p.stop()
        super().tearDown()

    def _set_sessions(self, dates):
        """Alimente conftest : /api/stats/streaks ET DNA._compute_consistency
        passent par weekly_streaks.compute → db.get_workout_sessions, faké
        par le store conftest."""
        self.store["sessions"] = {d: {"completed": True, "rpe": 7} for d in dates}

    def test_dna_consistency_matches_streaks_endpoint(self):
        """Pour une même fixture, DNA.consistency.weekly_streak_* ==
        /api/stats/streaks.weekly_streak_*."""
        w_minus_1 = ["2026-10-12", "2026-10-13", "2026-10-14",
                     "2026-10-16", "2026-10-17", "2026-10-18"]
        w_minus_2 = ["2026-10-05", "2026-10-07", "2026-10-08",
                     "2026-10-09", "2026-10-10", "2026-10-11"]
        current_partial = ["2026-10-19"]
        self._set_sessions(w_minus_1 + w_minus_2 + current_partial)

        streaks = self.json(self.get(f"/api/stats/streaks?date={TODAY}"))

        import workout_dna as _dna
        consistency = _dna._compute_consistency(period_days=90)

        self.assertIn("weekly_streak_current", consistency,
                      "DNA consistency doit exposer weekly_streak_current")
        self.assertIn("weekly_streak_best", consistency,
                      "DNA consistency doit exposer weekly_streak_best")
        self.assertEqual(
            consistency["weekly_streak_current"],
            streaks["weekly_streak_current"],
            msg=f"DNA.weekly_streak_current ({consistency['weekly_streak_current']}) "
                f"≠ /api/stats/streaks ({streaks['weekly_streak_current']})",
        )
        self.assertEqual(
            consistency["weekly_streak_best"],
            streaks["weekly_streak_best"],
            msg=f"DNA.weekly_streak_best ({consistency['weekly_streak_best']}) "
                f"≠ /api/stats/streaks ({streaks['weekly_streak_best']})",
        )

    def test_dna_consistency_streak_zero_matches_empty_fixture(self):
        """Aucune séance → les deux endpoints renvoient 0/0."""
        self._set_sessions([])
        self.store["hiit_log"] = []

        streaks = self.json(self.get(f"/api/stats/streaks?date={TODAY}"))
        import workout_dna as _dna
        consistency = _dna._compute_consistency(period_days=90)

        self.assertEqual(streaks["weekly_streak_current"], 0)
        self.assertEqual(streaks["weekly_streak_best"], 0)
        self.assertEqual(consistency.get("weekly_streak_current", 0), 0)
        self.assertEqual(consistency.get("weekly_streak_best", 0), 0)

    def test_dna_consistency_weekly_counts_matches_streaks_weeks(self):
        """weekly_counts DNA == [days_active for w in weeks] de /api/stats/streaks.
        Preuve que DNA ne recalcule plus la grille 13 semaines.
        Et sessions_per_week DNA == sum(days_active) / 13."""
        w_minus_1 = ["2026-10-12", "2026-10-13", "2026-10-14",
                     "2026-10-16", "2026-10-17", "2026-10-18"]
        w_minus_2 = ["2026-10-05", "2026-10-07", "2026-10-08",
                     "2026-10-09", "2026-10-10", "2026-10-11"]
        current_partial = ["2026-10-19"]
        self._set_sessions(w_minus_1 + w_minus_2 + current_partial)

        streaks = self.json(self.get(f"/api/stats/streaks?date={TODAY}"))
        expected_counts = [int(w["days_active"]) for w in streaks["weeks"]]

        import workout_dna as _dna
        consistency = _dna._compute_consistency(period_days=90)

        self.assertEqual(
            consistency["weekly_counts"], expected_counts,
            msg=f"weekly_counts divergent : DNA={consistency['weekly_counts']} "
                f"vs streaks={expected_counts}",
        )
        total_days = sum(expected_counts)
        expected_spw = round(total_days / 13.0, 1)
        self.assertEqual(
            consistency["sessions_per_week"], expected_spw,
            msg=f"spw DNA={consistency['sessions_per_week']} vs attendu={expected_spw}",
        )
        expected_active_pct = round(sum(1 for c in expected_counts if c > 0) / 13 * 100)
        self.assertEqual(
            consistency["active_weeks_pct"], expected_active_pct,
        )


if __name__ == "__main__":
    unittest.main()
