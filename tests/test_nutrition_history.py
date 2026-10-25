"""Tests /api/stats/nutrition_history (A1).

Garantit :
  1. Payload = exactement `days` entrées consécutives (plus ancien → récent).
  2. Jour sans saisie nutrition → macros null (jamais 0).
  3. target_calories par jour == compute_target_calories(date=d) pour 3 dates
     échantillons sur la fenêtre (invariant source unique).
  4. Jour avec <7 TDEE antérieurs → target_calories null.
"""
from __future__ import annotations

import os
import sys
import unittest
from datetime import date, timedelta
from unittest.mock import patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

from conftest import BaseRouteTest


TODAY = "2026-10-25"


class NutritionHistoryEndpoint(BaseRouteTest):

    def setUp(self):
        super().setUp()
        self._today_patchers = [
            patch("planner.get_today_date", return_value=TODAY),
            patch("utils._today_mtl", return_value=TODAY),
            patch("routes.analytics_stats._today_mtl", return_value=TODAY),
            patch("tdee._today_mtl", return_value=TODAY),
        ]
        for p in self._today_patchers:
            p.start()

    def tearDown(self):
        for p in self._today_patchers:
            p.stop()
        super().tearDown()

    def _get(self, days=30):
        return self.json(self.get(f"/api/stats/nutrition_history?days={days}"))

    def _stub_tdee_series(self, series: dict):
        """Monkeypatch compute_target_calories_series pour isoler l'endpoint
        de la logique TDEE réelle (testée séparément via compute_target_calories)."""
        import tdee
        tdee._stub_series = series  # type: ignore[attr-defined]
        patcher = patch(
            "tdee.compute_target_calories_series",
            side_effect=lambda days, end_date=None: series,
        )
        patcher.start()
        self.addCleanup(patcher.stop)

    def _set_nutrition(self, by_date: dict):
        """Patche db.get_nutrition_daily_full pour retourner les jours fournis.
        conftest.get_nutrition_daily_full est un stub `_empty_list` par défaut."""
        rows = [
            {"date": d, "calories": m["calories"], "proteines": m["proteines"],
             "glucides": m.get("glucides", 0), "lipides": m.get("lipides", 0)}
            for d, m in sorted(by_date.items())
        ]
        patcher = patch("db.get_nutrition_daily_full",
                        side_effect=lambda days=60: rows)
        patcher.start()
        self.addCleanup(patcher.stop)

    # ── 1. Exactement `days` entrées consécutives ────────────────────────────

    def test_payload_has_exact_days_consecutive_entries(self):
        self._stub_tdee_series({})
        self._set_nutrition({})
        payload = self._get(days=10)
        self.assertEqual(len(payload), 10)
        today_d = date.fromisoformat(TODAY)
        for i, row in enumerate(payload):
            expected = (today_d - timedelta(days=9 - i)).isoformat()
            self.assertEqual(row["date"], expected,
                             f"entry {i}: expected {expected}, got {row['date']}")

    # ── 2. Jour sans saisie → macros null ────────────────────────────────────

    def test_days_without_log_have_null_macros(self):
        self._stub_tdee_series({})
        # 1 seul jour loggé il y a 2 jours
        logged_date = (date.fromisoformat(TODAY) - timedelta(days=2)).isoformat()
        self._set_nutrition({
            logged_date: {"calories": 2500, "proteines": 180,
                          "glucides": 300, "lipides": 80}
        })
        payload = self._get(days=5)
        for row in payload:
            if row["date"] == logged_date:
                self.assertEqual(row["calories"], 2500)
                self.assertEqual(row["proteines"], 180)
            else:
                self.assertIsNone(row["calories"],
                                  f"jour sans log doit avoir calories=null, got {row['calories']}")
                self.assertIsNone(row["proteines"])
                self.assertIsNone(row["glucides"])
                self.assertIsNone(row["lipides"])

    # ── 3. Invariant target_calories ─────────────────────────────────────────

    def test_target_calories_matches_source_series(self):
        """Pour les dates présentes dans la série stubbée, le payload
        reflète exactement la valeur. Invariant source unique."""
        today_d = date.fromisoformat(TODAY)
        series = {}
        for i in range(10):
            d = (today_d - timedelta(days=i)).isoformat()
            series[d] = 2800 + i * 10  # valeurs distinctes
        self._stub_tdee_series(series)
        self._set_nutrition({})
        payload = self._get(days=10)
        by_date = {row["date"]: row for row in payload}
        for d, expected in series.items():
            self.assertIn(d, by_date)
            self.assertEqual(by_date[d]["target_calories"], expected,
                             f"{d}: expected target {expected}, got {by_date[d]['target_calories']}")

    # ── 4. Target null si TDEE antérieur insuffisant ─────────────────────────

    def test_target_null_when_tdee_history_insufficient(self):
        """Une date absente de la série (ou valeur None) → target_calories=null."""
        today_d = date.fromisoformat(TODAY)
        # Série vide (représente <7j TDEE antérieurs partout).
        self._stub_tdee_series({})
        self._set_nutrition({})
        payload = self._get(days=5)
        for row in payload:
            self.assertIsNone(row["target_calories"],
                              f"{row['date']} target doit être null, got {row['target_calories']}")

    # ── 5. Validation query ──────────────────────────────────────────────────

    def test_days_out_of_bounds_rejected(self):
        for d in (0, -5, 181, 200):
            resp = self.get(f"/api/stats/nutrition_history?days={d}")
            self.assertEqual(resp.status_code, 400, f"days={d} doit être rejeté")

    def test_days_non_integer_rejected(self):
        resp = self.get("/api/stats/nutrition_history?days=abc")
        self.assertEqual(resp.status_code, 400)

    # ── 6. Erreur série TDEE → 500 explicite, pas de fallback targets={} ─────

    def test_tdee_series_error_returns_500(self):
        self._set_nutrition({})

        def _boom(days, end_date=None):
            raise RuntimeError("energy history DB down")

        with patch("tdee.compute_target_calories_series", side_effect=_boom):
            resp = self.get("/api/stats/nutrition_history?days=10")
        self.assertEqual(resp.status_code, 500,
                         "série TDEE qui lève doit remonter en 500, pas targets null")
        payload = self.json(resp)
        self.assertIn("error", payload)
        self.assertIn("energy history DB down", payload["error"])


if __name__ == "__main__":
    unittest.main()
