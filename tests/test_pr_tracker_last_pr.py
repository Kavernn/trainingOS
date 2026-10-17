"""pr_tracker_engine.compute() — champ last_pr pour l'état vide iOS."""
import sys, os
import unittest
from unittest.mock import patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

import pr_tracker_engine as engine


class PRTrackerLastPR(unittest.TestCase):

    def _run(self, pr_rows, history):
        with patch.object(engine.db, "get_exercise_prs", return_value=pr_rows), \
             patch.object(engine.db, "get_all_exercise_history", return_value=history):
            return engine._compute()

    def test_last_pr_emitted_from_most_recent_pr_date(self):
        rows = [
            {"exercise_name": "Bench Press",   "pr_e1rm_lbs": 210.0,
             "pr_date": "2026-05-14", "baseline_count": 5},
            {"exercise_name": "Back Squat",    "pr_e1rm_lbs": 350.0,
             "pr_date": "2026-07-20", "baseline_count": 5},
            {"exercise_name": "Overhead Press","pr_e1rm_lbs": 140.0,
             "pr_date": "2026-04-01", "baseline_count": 5},
        ]
        # Aucun exercice ne refait son PR dans les 30 derniers jours.
        result = self._run(rows, history={})
        self.assertEqual(result["recent_prs"], [])
        self.assertIsNotNone(result["last_pr"])
        self.assertEqual(result["last_pr"]["name"], "Back Squat")
        self.assertEqual(result["last_pr"]["date"], "2026-07-20")
        self.assertEqual(result["last_pr"]["est_1rm"], 350.0)

    def test_last_pr_none_when_no_rows(self):
        self.assertIsNone(self._run(pr_rows=[], history={})["last_pr"])

    def test_last_pr_skips_rows_without_valid_e1rm_or_date(self):
        rows = [
            {"exercise_name": "No Date",    "pr_e1rm_lbs": 100.0, "pr_date": None,         "baseline_count": 5},
            {"exercise_name": "Zero E1RM",  "pr_e1rm_lbs": 0,     "pr_date": "2026-09-01", "baseline_count": 5},
            {"exercise_name": "Valid Only", "pr_e1rm_lbs": 150.0, "pr_date": "2026-06-15", "baseline_count": 5},
        ]
        result = self._run(rows, history={})
        self.assertEqual(result["last_pr"]["name"], "Valid Only")
        self.assertEqual(result["last_pr"]["est_1rm"], 150.0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
