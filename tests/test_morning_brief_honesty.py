"""Brief du matin et insight D1 — une absence ne vaut jamais une recommandation (build 2b)."""
import os
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

from morning_brief import _evaluate
from routes.proactive_insights import _check_d1


class MorningBriefEvaluateTests(unittest.TestCase):
    def test_missing_lss_is_unknown_never_go(self):
        for session in ("Push A", None):
            rec, msg, _ = _evaluate(None, "heavy", {}, session_name=session)
            self.assertEqual(rec, "unknown")
            self.assertNotIn("Bonne séance", msg)
            self.assertEqual(msg, "Données limitées.")

    def test_missing_lss_keeps_real_hrv_lead(self):
        rec, msg, _ = _evaluate(None, "moderate", {}, hrv_ms=58, hrv_pct=-4, session_name="Push A")
        self.assertEqual(rec, "unknown")
        self.assertEqual(msg, "HRV 58ms (-4% vs baseline).")

    def test_lss_is_named_equilibre_de_vie_not_readiness(self):
        _, msg, _ = _evaluate(80.0, "moderate", {}, session_name="Push A")
        self.assertIn("Équilibre de vie 80/100", msg)
        self.assertNotIn("Readiness", msg)

    def test_real_lss_still_gives_real_recommendations(self):
        self.assertEqual(_evaluate(80.0, "heavy", {})[0], "go")
        self.assertEqual(_evaluate(50.0, "heavy", {})[0], "go_caution")
        self.assertEqual(_evaluate(30.0, "heavy", {})[0], "reduce")
        self.assertEqual(_evaluate(10.0, "heavy", {})[0], "defer")


class CheckD1ReadinessTests(unittest.TestCase):
    HRV = {"baseline_available": True, "hrv_zone": "green", "hrv_trend": "up", "hrv_score": 110}
    ACWR = {"ratio": 1.0}

    def test_absent_readiness_never_fulfils_the_condition(self):
        self.assertIsNone(_check_d1([], self.ACWR, self.HRV, None))

    def test_low_readiness_blocks(self):
        self.assertIsNone(_check_d1([], self.ACWR, self.HRV, 60.0))

    def test_high_readiness_with_all_green_gives_insight(self):
        insight = _check_d1([], self.ACWR, self.HRV, 82.0)
        self.assertIsNotNone(insight)
        self.assertEqual(insight["dimension"], "optimal_window")


if __name__ == "__main__":
    unittest.main()
