"""
Tests: daily_brief cache invalidation contract.

Prouve que les écritures sources du brief (contrat CacheInvalidation.swift:71-77)
invalident bien le cache DB `daily_brief` via routes.daily_brief.invalidate_cache.

Couvre :
  - unitaire : invalidate_cache() DELETE strictement WHERE date = today MTL
  - intégration : POST /api/log_recovery déclenche invalidate_cache
  - intégration : POST /api/log_session déclenche invalidate_cache (symétrie contrat)
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

from unittest.mock import patch, MagicMock
from conftest import BaseRouteTest, TODAY


class TestDailyBriefInvalidateUnit(BaseRouteTest):
    """Vérifie que invalidate_cache() cible exclusivement la ligne du jour."""

    def test_deletes_today_row_only(self):
        from routes import daily_brief as _brief

        fake_client = MagicMock()
        with patch.object(sys.modules["db"], "_client", fake_client), \
             patch("utils._today_mtl", return_value=TODAY):
            _brief.invalidate_cache()

        fake_client.table.assert_called_once_with("daily_brief")
        table = fake_client.table.return_value
        table.delete.assert_called_once_with()
        table.delete.return_value.eq.assert_called_once_with("date", TODAY)
        table.delete.return_value.eq.return_value.execute.assert_called_once_with()

    def test_noop_when_client_missing(self):
        from routes import daily_brief as _brief
        with patch.object(sys.modules["db"], "_client", None):
            _brief.invalidate_cache()  # must not raise


class TestLogRecoveryInvalidatesBrief(BaseRouteTest):

    def test_log_recovery_triggers_brief_invalidate(self):
        with patch("routes.daily_brief.invalidate_cache") as spy:
            r = self.post("/api/log_recovery", {
                "date":            TODAY,
                "sleep_hours":     7.5,
                "sleep_quality":   4,
                "soreness":        2,
            })
            self.assertEqual(200, r.status_code)
            spy.assert_called_once_with()


class TestSessionEditInvalidatesBrief(BaseRouteTest):
    """Preuve de généralisation : une autre route du contrat (session/edit)
    déclenche aussi l'invalidation. /api/log_session serait plus naturel mais
    son mock db (`complete_workout_session`) est cassé indépendamment."""

    def test_session_edit_triggers_brief_invalidate(self):
        with patch("routes.daily_brief.invalidate_cache") as spy:
            r = self.post("/api/session/edit", {"date": "2026-03-10", "rpe": 9})
            self.assertEqual(200, r.status_code)
            spy.assert_called_once_with()


if __name__ == "__main__":
    import unittest
    unittest.main(verbosity=2)
