"""
Tests: doctrine anti-fantôme — endpoints /api/mesocycle_status et /api/overtraining_risk.

Le contrat :
  - mesocycle_status : phase=null + reason ("no_cycle_start"|"error") quand aucun
    cycle réel ; JAMAIS de phase calendaire inventée.
  - overtraining_risk : data_coverage (0-4 sources évaluables) +
    insufficient_data=True SEULEMENT à coverage 0 (seul cas indistinguable
    d'un vrai "low").

Ancre : CLAUDE.md « Anti-fantôme backend », correction juillet 2026.
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

from unittest.mock import MagicMock, patch
from conftest import BaseRouteTest, TODAY


class _MtlBaseTest(BaseRouteTest):
    """conftest patches planner.get_today_date mais pas utils._today_mtl.
    Ces 2 endpoints utilisent _today_mtl → on le patche dans le namespace
    d'analytics_load (import direct)."""

    def setUp(self):
        super().setUp()
        self._mtl_patch = patch("routes.analytics_load._today_mtl", return_value=TODAY)
        self._mtl_patch.start()

    def tearDown(self):
        self._mtl_patch.stop()
        super().tearDown()


# ── /api/mesocycle_status ────────────────────────────────────────────────────

class TestMesocycleStatusNoCycle(_MtlBaseTest):
    """Absence explicite : ni active_program, ni deload historique."""

    def test_no_deload_no_active_program_returns_phase_null(self):
        db_mod = sys.modules["db"]
        db_mod.get_active_program = MagicMock(return_value=None)

        r = self.get("/api/mesocycle_status")
        self.assertEqual(200, r.status_code)
        payload = self.json(r)
        self.assertIsNone(payload["phase"])
        self.assertEqual("no_cycle_start", payload["reason"])
        self.assertIn("current_week", payload)
        # Aucun champ fantôme (phase_label, description, icon...) dans ce cas
        for ghost_key in ("phase_label", "description", "icon", "rpe_target", "vol_guidance"):
            self.assertNotIn(ghost_key, payload)


class TestMesocycleStatusActiveProgram(_MtlBaseTest):
    """Cycle réel via active_program.cycle_start_date → phase valide (chemin nominal)."""

    def test_active_program_cycle_start_returns_valid_phase(self):
        db_mod = sys.modules["db"]
        # Cycle démarré il y a 3 semaines → week_in_cycle=3 → phase "intensification"
        db_mod.get_active_program = MagicMock(return_value={
            "cycle_start_date": "2026-02-21",  # ~3 semaines avant TODAY=2026-03-14
        })

        r = self.get("/api/mesocycle_status")
        self.assertEqual(200, r.status_code)
        payload = self.json(r)
        self.assertIsNotNone(payload["phase"])
        self.assertEqual("intensification", payload["phase"])
        self.assertEqual(3, payload["weeks_since_deload"])
        self.assertIn("phase_label", payload)
        self.assertNotIn("reason", payload)


class TestMesocycleStatusDeloadFallback(_MtlBaseTest):
    """Fallback : pas d'active_program, mais séance nommée 'deload' présente."""

    def test_deload_session_fallback(self):
        db_mod = sys.modules["db"]
        db_mod.get_active_program = MagicMock(return_value=None)
        # Ajouter une séance deload il y a 2 semaines
        self.store["sessions"]["2026-02-28"] = {
            "rpe": 5, "comment": "", "session_name": "Deload semaine récup",
        }

        r = self.get("/api/mesocycle_status")
        self.assertEqual(200, r.status_code)
        payload = self.json(r)
        self.assertIsNotNone(payload["phase"])
        self.assertEqual("2026-02-28", payload["last_deload_date"])
        self.assertNotIn("reason", payload)


class TestMesocycleStatusActiveProgramError(_MtlBaseTest):
    """Exception à la lecture active_program + pas de fallback → phase=null + reason='error'."""

    def test_active_program_exception_fails_loud(self):
        db_mod = sys.modules["db"]
        db_mod.get_active_program = MagicMock(side_effect=RuntimeError("db timeout"))

        r = self.get("/api/mesocycle_status")
        self.assertEqual(200, r.status_code)
        payload = self.json(r)
        self.assertIsNone(payload["phase"])
        self.assertEqual("error", payload["reason"])


# ── /api/overtraining_risk ───────────────────────────────────────────────────

class TestOvertrainingRiskInsufficient(_MtlBaseTest):
    """coverage=0 : aucune source évaluable → insufficient_data=True."""

    def test_all_sources_absent_marks_insufficient(self):
        db_mod = sys.modules["db"]
        db_mod.get_mood_logs = MagicMock(return_value=[])
        # Fixture par défaut : recovery_log vide, sessions=2 avec RPE mais <2 dans les 7j
        # → RPE trend non évaluable, mood vide, HRV baseline sans data, recovery today absent

        r = self.get("/api/overtraining_risk")
        self.assertEqual(200, r.status_code)
        payload = self.json(r)
        self.assertEqual(0, payload["data_coverage"])
        self.assertTrue(payload["insufficient_data"])
        # Payload "low" reste présent mais l'iOS saura l'ignorer via insufficient_data
        self.assertEqual("low", payload["level"])
        self.assertEqual(0, payload["risk_score"])


class TestOvertrainingRiskPartialCoverage(_MtlBaseTest):
    """coverage>=1 : au moins une source évaluable → insufficient_data=False."""

    def test_recovery_only_marks_evaluable(self):
        db_mod = sys.modules["db"]
        db_mod.get_mood_logs = MagicMock(return_value=[])
        # Ajouter une recovery pour aujourd'hui — la source "recovery" devient évaluable.
        self.store["recovery_log"] = [{
            "date": TODAY, "sleep_hours": 7.5, "sleep_quality": 4,
            "hrv": 55, "resting_hr": 62, "soreness": 2,
        }]

        r = self.get("/api/overtraining_risk")
        self.assertEqual(200, r.status_code)
        payload = self.json(r)
        self.assertGreaterEqual(payload["data_coverage"], 1)
        self.assertFalse(payload["insufficient_data"])


if __name__ == "__main__":
    import unittest
    unittest.main(verbosity=2)
