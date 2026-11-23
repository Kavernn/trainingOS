"""Readiness — seuil de couverture et cache (build 1b).

Sans aucun signal du jour (HRV, FC repos, qualité/durée de sommeil, ressenti) :
score et verdict null, insufficient_data, aucune écriture readiness_daily, aucun cache.
Nutrition sans cible / sans repas / en erreur : module absent, jamais 50 ou 65.
Toute écriture recovery_logs (point unique db_body) invalide le cache readiness.
"""
import os
import sys
import unittest
from contextlib import ExitStack
from unittest.mock import MagicMock, patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

import db_body
import readiness as r

NONE = (None, {"data_insufficient": True})


def _patches(stack, *, hrv=NONE, rhr=NONE, sq=NONE, sd=NONE, sub=NONE,
             nutrition=(50.0, {"target_missing": True}), upsert=None):
    stack.enter_context(patch.object(r.db, "get_recovery_logs", return_value=[]))
    stack.enter_context(patch.object(r, "_score_hrv", return_value=hrv))
    stack.enter_context(patch.object(r, "_score_rhr", return_value=rhr))
    stack.enter_context(patch.object(r, "_score_acwr", return_value=(90.0, {"acwr": 1.0})))
    stack.enter_context(patch.object(r, "_score_sleep_quality", return_value=sq))
    stack.enter_context(patch.object(r, "_score_sleep_duration", return_value=sd))
    stack.enter_context(patch.object(r, "_score_subjective", return_value=sub))
    stack.enter_context(patch.object(r, "_score_muscle_recovery", return_value=(80.0, {}, {})))
    stack.enter_context(patch.object(r, "_score_nutrition", return_value=nutrition))
    stack.enter_context(patch.object(r, "_score_pattern", return_value=(70.0, {})))
    stack.enter_context(patch.object(r, "_active_energy_modifier", return_value=(1.0, False)))
    stack.enter_context(patch.object(r, "_get_personal_baseline", return_value=None))
    stack.enter_context(patch.object(r, "_today_mtl", return_value="2026-11-22"))
    stack.enter_context(patch("planner.get_today", return_value=None))
    upsert = upsert or MagicMock()
    stack.enter_context(patch.object(r.db, "upsert_readiness_daily", upsert))
    return upsert


class ReadinessCoverageTests(unittest.TestCase):
    def setUp(self):
        r.invalidate_cache()

    def tearDown(self):
        r.invalidate_cache()

    def test_no_core_signal_gives_null_score_no_persist_no_cache(self):
        with ExitStack() as s:
            upsert = _patches(s)
            data = r.compute()
        self.assertIsNone(data["score"])
        self.assertIsNone(data["verdict"])
        self.assertIsNone(data["verdict_method"])
        self.assertTrue(data["insufficient_data"])
        self.assertEqual(data["reason"], "no_core_signal")
        self.assertEqual(data["core_signals"], 0)
        self.assertIn("check-in", data["why"])
        self.assertIn("modules", data)
        upsert.assert_not_called()
        self.assertNotIn("result", r._CACHE)

    def test_one_core_signal_gives_score_and_persists(self):
        with ExitStack() as s:
            upsert = _patches(s, sq=(70.0, {"sleep_quality": 7}))
            data = r.compute()
        self.assertIsInstance(data["score"], int)
        self.assertIsNotNone(data["verdict"])
        self.assertFalse(data["insufficient_data"])
        self.assertIsNone(data["reason"])
        self.assertEqual(data["core_signals"], 1)
        upsert.assert_called_once_with("2026-11-22", data["score"])

    def test_core_signals_counts_each_present_signal(self):
        with ExitStack() as s:
            _patches(s, hrv=(90.0, {}), rhr=(80.0, {}), sq=(70.0, {}), sd=(60.0, {}), sub=(50.0, {}))
            self.assertEqual(r.compute()["core_signals"], 5)

    def _score_with_nutrition(self, nutrition):
        r.invalidate_cache()
        with ExitStack() as s:
            _patches(s, sq=(70.0, {}), nutrition=nutrition)
            return r.compute()

    def test_nutrition_without_target_is_excluded_not_50(self):
        reference = self._score_with_nutrition((None, {"target_missing": True}))  # module absent
        for phantom in [(50.0, {"target_missing": True}), (50.0, {"no_data": True}), (65.0, {"error": True})]:
            data = self._score_with_nutrition(phantom)
            self.assertIsNone(data["modules"]["nutrition"]["score"], phantom)
            self.assertEqual(data["score"], reference["score"], phantom)

    def test_real_nutrition_score_still_counts(self):
        data = self._score_with_nutrition((95.0, {"cal_pct": 100}))
        self.assertEqual(data["modules"]["nutrition"]["score"], 95)


class ReadinessCacheInvalidationTests(unittest.TestCase):
    """Point unique : db_body.upsert_recovery_log / delete_recovery_log."""

    def setUp(self):
        r.invalidate_cache()

    def tearDown(self):
        r.invalidate_cache()

    def test_null_then_checkin_then_get_recomputes(self):
        with ExitStack() as s:
            _patches(s)
            self.assertIsNone(r.compute()["score"])          # réveil : aucun signal
        with patch.object(db_body, "_upsert_recovery_log_raw", return_value=True):
            self.assertTrue(db_body.upsert_recovery_log({"date": "2026-11-22", "sleep_quality": 7}))
        with ExitStack() as s:
            _patches(s, sq=(70.0, {"sleep_quality": 7}))       # le check-in est arrivé
            data = r.compute()
        self.assertIsNotNone(data["score"])
        self.assertEqual(data["core_signals"], 1)

    def test_recovery_write_invalidates_a_cached_score(self):
        with ExitStack() as s:
            _patches(s, sq=(70.0, {}))
            r.compute()
        self.assertIn("result", r._CACHE)
        with patch.object(db_body, "_upsert_recovery_log_raw", return_value=True):
            db_body.upsert_recovery_log({"date": "2026-11-22", "hrv": 60})
        self.assertNotIn("result", r._CACHE)

    def test_recovery_delete_invalidates_cache(self):
        r._CACHE["result"] = {"data": {"score": 1}, "ts": 0}
        with patch.object(db_body, "_delete_recovery_log_raw", return_value=True):
            db_body.delete_recovery_log("2026-11-22")
        self.assertNotIn("result", r._CACHE)

    def test_failed_write_keeps_cache(self):
        r._CACHE["result"] = {"data": {"score": 1}, "ts": 0}
        with patch.object(db_body, "_upsert_recovery_log_raw", return_value=False):
            self.assertFalse(db_body.upsert_recovery_log({"date": "2026-11-22"}))
        self.assertIn("result", r._CACHE)

    def test_wearable_merge_goes_through_invalidation(self):
        r._CACHE["result"] = {"data": {"score": 1}, "ts": 0}
        with patch.object(db_body, "get_recovery_logs", return_value=[]), \
             patch.object(db_body, "_upsert_recovery_log_raw", return_value=True):
            db_body.merge_recovery_wearable("2026-11-22", {"hrv": 55})
        self.assertNotIn("result", r._CACHE)


if __name__ == "__main__":
    unittest.main()
