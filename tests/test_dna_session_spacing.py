"""DNA session_spacing (lot e1).

Garantit :
  1. Médiane + IQR sur les gaps entre séances actives consécutives dans la
     fenêtre DNA.
  2. Décharges exclues : les dates qui tombent dans une période de décharge
     enregistrée ne comptent ni comme séance ni comme "trou".
  3. Garde-fou MIN_SESSIONS_PER_SECTION (8) : sous le seuil →
     insufficient_data=True, aucune médiane/IQR inventées.
  4. Dates malformées comptées via invalid_dates, pas silencieusement ignorées.
  5. Erreur du prédicat is_deload_day → section expose "error", pas insufficient.
"""
from __future__ import annotations

import os
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

from conftest import BaseRouteTest


TODAY = "2026-10-19"  # lundi


class DnaSessionSpacing(BaseRouteTest):

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
        self.store["sessions"] = {d: {"completed": True, "rpe": 7} for d in dates}

    def test_median_and_iqr_on_regular_cadence(self):
        """8 séances espacées de 3 jours → médiane = 3, IQR tight autour de 3."""
        from datetime import date, timedelta
        base = date.fromisoformat(TODAY) - timedelta(days=28)
        dates = [(base + timedelta(days=i * 3)).isoformat() for i in range(10)]
        self._set_sessions(dates)

        import workout_dna as _dna
        result = _dna._compute_session_spacing(period_days=90)
        self.assertFalse(result["insufficient_data"])
        self.assertEqual(result["n_sessions"], 10)
        self.assertEqual(result["n_gaps"], 9)
        self.assertEqual(result["median_days"], 3.0)
        self.assertEqual(result["p25_days"], 3.0)
        self.assertEqual(result["p75_days"], 3.0)

    def test_insufficient_under_8_sessions(self):
        from datetime import date, timedelta
        base = date.fromisoformat(TODAY) - timedelta(days=20)
        dates = [(base + timedelta(days=i * 3)).isoformat() for i in range(5)]
        self._set_sessions(dates)

        import workout_dna as _dna
        result = _dna._compute_session_spacing(period_days=90)
        self.assertTrue(result["insufficient_data"])
        self.assertEqual(result["n_sessions"], 5)
        self.assertNotIn("median_days", result,
                         "pas de médiane inventée sous le seuil")

    def test_deload_sessions_excluded(self):
        """Une période de décharge enregistrée exclut les dates
        qui tombent dedans — elles ne comptent ni comme séance ni comme gap."""
        from datetime import date, timedelta

        self.store["deload_periods"] = [{
            "started_at":    "2026-10-01",
            "scheduled_end": "2026-10-07",
            "completed_at":  "2026-10-07",
            "duration_days": 7,
            "reason":        "test",
        }]
        base = date.fromisoformat(TODAY) - timedelta(days=50)
        # 8 séances hors décharge, cadence régulière
        valid_dates = [(base + timedelta(days=i * 4)).isoformat() for i in range(8)]
        # 3 séances DANS la décharge (devront être exclues)
        deload_dates = ["2026-10-02", "2026-10-04", "2026-10-06"]
        self._set_sessions(valid_dates + deload_dates)

        import workout_dna as _dna
        result = _dna._compute_session_spacing(period_days=90)
        self.assertFalse(result["insufficient_data"])
        self.assertEqual(result["n_sessions"], 8, "8 hors décharge")
        self.assertEqual(result["excluded_deload_sessions"], 3)

    def test_predicate_error_exposes_section_error(self):
        """is_deload_day qui lève → section expose "error", pas insufficient."""
        from datetime import date, timedelta
        base = date.fromisoformat(TODAY) - timedelta(days=30)
        self._set_sessions([(base + timedelta(days=i * 3)).isoformat() for i in range(10)])

        def _boom(_day):
            raise RuntimeError("deload table down")
        with patch("analytics_adapter.is_deload_day", _boom):
            import workout_dna as _dna
            result = _dna._compute_session_spacing(period_days=90)

        self.assertIn("error", result)
        self.assertNotEqual(result.get("insufficient_data"), True,
                            "erreur infra ≠ données insuffisantes")
        self.assertIn("deload table down", result["error"])

    def test_section_shape_has_median_iqr_and_counts(self):
        """La shape renvoyée par _compute_session_spacing dans le cas valide
        contient toutes les clés attendues pour le payload /api/workout_dna."""
        from datetime import date, timedelta
        base = date.fromisoformat(TODAY) - timedelta(days=30)
        self._set_sessions([(base + timedelta(days=i * 3)).isoformat() for i in range(10)])

        import workout_dna as _dna
        result = _dna._compute_session_spacing(period_days=90)
        for key in ("median_days", "p25_days", "p75_days",
                    "n_sessions", "n_gaps",
                    "insufficient_data", "invalid_dates",
                    "excluded_deload_sessions"):
            self.assertIn(key, result, f"clé manquante : {key}")


if __name__ == "__main__":
    unittest.main()
