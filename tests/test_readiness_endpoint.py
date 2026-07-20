"""
Tests: /api/readiness — doctrine anti-fantôme (CLAUDE.md).

Le catch-all L846-855 retournait {score: 65} sur toute exception au calcul —
score plausible inventé, affiché comme un vrai (bien que le decode iOS actuel
échoue sur modules:{}, le pattern crime était en place, prêt à basculer).

Test principal : compute error → HTTP 500 + {error, reason: "compute_error"},
JAMAIS 65. Prouve la fin du fantôme.

test_persist_failure_preserves_score non implémenté — conftest db mock
lacunaire (get_all_exercise_history signature, cascade de deps). À écrire
au chantier fixtures MagicMock.

La doctrine 832-836 est préservée par structure : le try/except de
persistance L838-841 est imbriqué DANS le try principal — une exception
d'écriture est attrapée et loggée localement (L840-841), elle n'atteint
jamais le catch-all L846-852 qui raise. Inspection confirmée sur
readiness.py au commit du fix : indent 8 (persist except) vs indent 4
(catch-all), aucun chemin ne relie l'un à l'autre.
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

from unittest.mock import patch
from conftest import BaseRouteTest, TODAY


class _ReadinessBaseTest(BaseRouteTest):
    """readiness._CACHE (module-level, 5 min TTL) doit être vidé entre tests
    pour éviter qu'un score caché contamine un test suivant."""

    def setUp(self):
        super().setUp()
        import readiness as _r
        _r.invalidate_cache()
        self._mtl_patch = patch("readiness._today_mtl", return_value=TODAY)
        self._mtl_patch.start()

    def tearDown(self):
        self._mtl_patch.stop()
        super().tearDown()


class TestReadinessComputeError(_ReadinessBaseTest):

    def test_compute_error_returns_500_never_score_65(self):
        # Fait planter le calcul en amont — get_recovery_logs est la 1ère lecture db.
        with patch("readiness.db.get_recovery_logs", side_effect=RuntimeError("db down")):
            r = self.get("/api/readiness")

        self.assertEqual(500, r.status_code)
        payload = self.json(r)
        self.assertEqual("compute_error", payload["reason"])
        self.assertEqual("readiness compute failed", payload["error"])
        # Assertion doctrine anti-fantôme : aucun champ score/verdict/modules ne remonte
        for ghost in ("score", "verdict", "modules", "muscle_recovery", "why"):
            self.assertNotIn(ghost, payload)


class TestReadinessRouteContract(_ReadinessBaseTest):
    """Route wrapper : transmet le payload de compute() tel quel sur succès.
    Prouve qu'aucune couche de la route ne corrompt/remplace le vrai résultat."""

    def test_nominal_passes_compute_payload_through(self):
        fake = {
            "score": 78, "verdict": "go", "why": "test",
            "adjustment": None, "progression_modifier": 1.0,
            "modules": {"hrv": {"score": 80, "label": "HRV", "detail": "ok"}},
            "muscle_recovery": {}, "today_session": None,
            "computed_at": "2026-03-14T12:00:00Z",
        }
        with patch("routes.readiness._r.compute", return_value=fake):
            r = self.get("/api/readiness")

        self.assertEqual(200, r.status_code)
        self.assertEqual(78, self.json(r)["score"])
        self.assertEqual("go", self.json(r)["verdict"])


class TestVerdictGuards(_ReadinessBaseTest):
    """Commit 3 — plancher absolu + veto HRV/RHR au mode relatif.
    Le relatif module, l'absolu protège. Défaut structurel démontré :
    la moyenne pondérée du composite ne peut pas tomber sous rest sur
    un seul module effondré → veto par module nécessaire."""

    def test_relative_go_downgraded_below_absolute_floor(self):
        import readiness as _r
        # Baseline glissée à 55 (fatigue chronique) : 58 ≥ 55-0.5×5 = 52.5 → raw="go"
        # Mais 58 < _FLOOR_ABSOLUTE (60) → downgrade moderate
        verdict, is_rel, reason = _r._verdict(58, baseline={"mean": 55, "sd": 5.0})
        self.assertEqual("moderate", verdict)
        self.assertTrue(is_rel)
        self.assertIn("plancher", reason)

    def test_relative_go_downgraded_when_hrv_module_critical(self):
        import readiness as _r
        # Cas type 19/07 : composite 74 (baseline compatible go) + HRV 30 → veto
        verdict, is_rel, reason = _r._verdict(
            74, baseline={"mean": 72, "sd": 5.0}, hrv_score=30, rhr_score=80
        )
        self.assertEqual("moderate", verdict)
        self.assertIn("HRV", reason)

    def test_relative_go_downgraded_when_rhr_module_critical(self):
        import readiness as _r
        # Même logique, canal cardiovasculaire
        verdict, is_rel, reason = _r._verdict(
            74, baseline={"mean": 72, "sd": 5.0}, hrv_score=80, rhr_score=30
        )
        self.assertEqual("moderate", verdict)
        self.assertIn("RHR", reason)

    def test_go_kept_when_all_guards_pass(self):
        import readiness as _r
        verdict, is_rel, reason = _r._verdict(
            85, baseline={"mean": 80, "sd": 5.0}, hrv_score=75, rhr_score=85
        )
        self.assertEqual("go", verdict)
        self.assertIsNone(reason)

    def test_moderate_and_rest_untouched_by_guards(self):
        import readiness as _r
        # Moderate raw : les garde-fous n'agissent que sur "go" → reason None
        v, _, r = _r._verdict(55, baseline={"mean": 65, "sd": 5.0}, hrv_score=20, rhr_score=20)
        self.assertEqual("moderate", v)
        self.assertIsNone(r)
        # Rest raw : idem
        v, _, r = _r._verdict(30, baseline={"mean": 65, "sd": 5.0})
        self.assertEqual("rest", v)
        self.assertIsNone(r)

    def test_absolute_cold_start_go_downgraded_by_hrv_veto(self):
        import readiness as _r
        # Cold start (baseline None) : score 80 = go absolu, mais HRV 25 → veto
        verdict, is_rel, reason = _r._verdict(80, baseline=None, hrv_score=25, rhr_score=90)
        self.assertEqual("moderate", verdict)
        self.assertFalse(is_rel)
        self.assertIn("HRV", reason)


class TestMessagingHonest(_ReadinessBaseTest):
    """Commit 1 — la branche verdict==go du messaging ne peut plus affirmer
    'toutes tes métriques au vert' quand un module est critique.
    Un texte qui contredit ses propres composants = mensonge d'écran."""

    def test_go_with_critical_module_names_it(self):
        import readiness as _r
        modules = {
            "hrv":  {"score": 30, "label": "HRV",      "detail": ""},
            "rhr":  {"score": 80, "label": "FC repos", "detail": ""},
            "acwr": {"score": 95, "label": "Charge",   "detail": ""},
        }
        why, adj, prog = _r._build_messaging("go", modules, {}, {})
        self.assertIn("HRV", why)
        self.assertIn("30", why)
        self.assertNotIn("au vert", why)
        self.assertEqual(1.0, prog)  # progression modifier inchangé — l'honnêteté est cosmétique

    def test_go_with_all_modules_healthy_keeps_optimistic_message(self):
        import readiness as _r
        modules = {
            "hrv": {"score": 80, "label": "HRV",      "detail": ""},
            "rhr": {"score": 85, "label": "FC repos", "detail": ""},
        }
        why, adj, prog = _r._build_messaging("go", modules, {}, {})
        self.assertIn("au vert", why)


if __name__ == "__main__":
    import unittest
    unittest.main(verbosity=2)
