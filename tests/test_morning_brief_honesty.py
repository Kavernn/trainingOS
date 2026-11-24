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

    def test_missing_lss_never_quotes_hrv_figure(self):
        rec, msg, _ = _evaluate(None, "moderate", {}, hrv_zone="green", session_name="Push A")
        self.assertEqual(rec, "unknown")
        self.assertEqual(msg, "Données limitées.")

    def test_red_hrv_never_called_optimal(self):
        # 23 nov : HRV −44 % (zone rouge) + Équilibre de vie 78 → avant « récupération optimale ».
        for lss in (65.0, 78.4, 100.0):
            for intensity in ("heavy", "moderate", "light"):
                rec, msg, adj = _evaluate(lss, intensity, {}, hrv_zone="red", session_name="Lundi AM — Push A")
                low = msg.lower()
                self.assertNotIn("optimal", low, (lss, intensity))
                self.assertNotIn("pousse fort", low, (lss, intensity))
                self.assertEqual(rec, "go_caution")
                self.assertIn("HRV bas — évite les efforts maximaux", adj)
                self.assertNotIn("ms", msg)                 # aucun chiffre HRV

    def test_red_hrv_never_optimal_at_any_lss(self):
        for lss in (10.0, 30.0, 50.0, 70.0, 95.0):
            for intensity in ("heavy", "moderate", "light"):
                _, msg, _ = _evaluate(lss, intensity, {}, hrv_zone="red")
                self.assertNotIn("optimal", msg.lower(), (lss, intensity))

    def test_green_hrv_keeps_optimal_message(self):
        rec, msg, _ = _evaluate(80.0, "moderate", {}, hrv_zone="green", session_name="Push A")
        self.assertEqual(rec, "go")
        self.assertIn("récupération optimale", msg)

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
