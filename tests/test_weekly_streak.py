"""Streak hebdomadaire — /api/stats/streaks.

Semaine = ISO lundi→dimanche. Jour actif = workout completed/rpe OR HIIT OR
cardio OR exercise_logs du jour (même règle qu'analytics_stats.py:256-279).
Semaine réussie = ≥ weekly_target jours DISTINCTS. Semaine en cours ne casse
jamais le streak tant qu'elle n'est pas finie.
"""
import sys, os
import unittest
from unittest.mock import patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

from conftest import BaseRouteTest


# Fixture TODAY : lundi 2026-10-19 (lundi par convention — streak hebdo
# testé indépendamment du jour de la semaine courant).
TODAY = "2026-10-19"  # lundi
WEEKS_BACK_MONDAYS = {
    "w0":  "2026-10-19",  # semaine courante (lundi)
    "w-1": "2026-10-12",
    "w-2": "2026-10-05",
    "w-3": "2026-09-28",
}


def _dates(*iso_strings):
    """Factory : rows workout_sessions à partir de dates ISO."""
    return [{"date": d, "completed": True, "rpe": 7} for d in iso_strings]


class WeeklyStreak(BaseRouteTest):

    def setUp(self):
        super().setUp()
        # Aligne _today_mtl + planner.get_today_date avec TODAY.
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
        """Remplace store['sessions'] par un dict date→entry."""
        self.store["sessions"] = {d: {"completed": True, "rpe": 7} for d in dates}

    def _set_hiit(self, dates):
        self.store["hiit_log"] = [{"date": d, "session_type": "Tabata"} for d in dates]

    def _get(self):
        return self.json(self.get(f"/api/stats/streaks?date={TODAY}"))

    # ── Scénarios demandés ───────────────────────────────────────────────────

    def test_rest_days_rotate_across_weeks_both_successful(self):
        """Repos sur des jours différents chaque semaine → les deux réussissent.
        Prouve que le streak hebdo n'utilise PAS le schedule hebdo fixe."""
        # Semaine w-1 (2026-10-12 Lun → 2026-10-18 Dim) : repos jeudi 15.
        # Jours actifs : L M M V S D = 6 → success (>=5).
        w1 = ["2026-10-12", "2026-10-13", "2026-10-14",
              "2026-10-16", "2026-10-17", "2026-10-18"]
        # Semaine w-2 (2026-10-05 → 2026-10-11) : repos mardi.
        # Jours actifs : L M J V S D = 6 → success.
        w2 = ["2026-10-05", "2026-10-07", "2026-10-08", "2026-10-09",
              "2026-10-10", "2026-10-11"]
        self._set_sessions(w1 + w2)
        self._set_hiit([])
        data = self._get()
        self.assertEqual(data["weekly_target"], 5)
        # Semaine courante : lundi seul → 1 jour → ne casse pas.
        self.assertEqual(data["weekly_streak_current"], 2,
                         "w-1 et w-2 réussies malgré repos sur jours différents")
        # weeks[-2] correspond à w-1, weeks[-3] à w-2
        by_start = {w["week_start"]: w for w in data["weeks"]}
        self.assertTrue(by_start[WEEKS_BACK_MONDAYS["w-1"]]["success"])
        self.assertEqual(by_start[WEEKS_BACK_MONDAYS["w-1"]]["days_active"], 6)
        self.assertTrue(by_start[WEEKS_BACK_MONDAYS["w-2"]]["success"])
        self.assertEqual(by_start[WEEKS_BACK_MONDAYS["w-2"]]["days_active"], 6)

    def test_four_day_week_breaks_streak(self):
        """Semaine à 4 jours → casse le streak hebdo."""
        # w-1 : 4 jours actifs → échec.
        w1 = ["2026-10-12", "2026-10-13", "2026-10-14", "2026-10-15"]
        # w-2 : 5 jours → succès.
        w2 = ["2026-10-05", "2026-10-06", "2026-10-07", "2026-10-08", "2026-10-09"]
        self._set_sessions(w1 + w2)
        self._set_hiit([])
        data = self._get()
        by_start = {w["week_start"]: w for w in data["weeks"]}
        self.assertFalse(by_start[WEEKS_BACK_MONDAYS["w-1"]]["success"])
        self.assertEqual(by_start[WEEKS_BACK_MONDAYS["w-1"]]["days_active"], 4)
        self.assertTrue(by_start[WEEKS_BACK_MONDAYS["w-2"]]["success"])
        # Streak courant : w-1 casse → 0 (w-2 réussie mais pas consécutive).
        self.assertEqual(data["weekly_streak_current"], 0,
                         "semaine à 4 jours doit casser le streak hebdo courant")

    def test_current_week_at_3_days_does_not_break_streak(self):
        """Semaine en cours à 3 jours → ne casse pas tant que non terminée."""
        # Current week : 3 jours (sous target).
        wc = ["2026-10-19", "2026-10-20", "2026-10-21"]
        # Les 2 semaines passées : succès à 5+.
        w1 = ["2026-10-12", "2026-10-13", "2026-10-14", "2026-10-15", "2026-10-16"]
        w2 = ["2026-10-05", "2026-10-06", "2026-10-07", "2026-10-08", "2026-10-09"]
        self._set_sessions(wc + w1 + w2)
        self._set_hiit([])
        data = self._get()
        self.assertEqual(data["current_week"]["days_active"], 3)
        # Streak courant doit valoir 2 (w-1 + w-2), la semaine en cours
        # incomplète NE casse PAS.
        self.assertEqual(data["weekly_streak_current"], 2,
                         "semaine en cours sous target ne doit pas casser le streak")

    def test_two_activities_same_day_count_as_one(self):
        """2 activités le même jour (workout + HIIT) = 1 seul jour actif."""
        # 5 dates distinctes dont une avec workout + HIIT → doit valoir 5, pas 6.
        wc = ["2026-10-12", "2026-10-13", "2026-10-14", "2026-10-15", "2026-10-16"]
        self._set_sessions(wc)
        self._set_hiit(["2026-10-12"])  # HIIT en plus sur le lundi
        data = self._get()
        by_start = {w["week_start"]: w for w in data["weeks"]}
        self.assertEqual(by_start[WEEKS_BACK_MONDAYS["w-1"]]["days_active"], 5,
                         "workout+HIIT même jour doivent compter pour 1 jour actif")
        self.assertTrue(by_start[WEEKS_BACK_MONDAYS["w-1"]]["success"])

    # ── Garde-fous payload ────────────────────────────────────────────────────

    def test_payload_shape(self):
        self._set_sessions([])
        self._set_hiit([])
        data = self._get()
        for k in ("weekly_target", "weekly_streak_current", "weekly_streak_best",
                  "current_week", "weeks",
                  "current_streak", "best_streak", "today_logged", "streak_at_risk"):
            self.assertIn(k, data, f"champ manquant : {k}")
        self.assertEqual(len(data["weeks"]), 13, "doit couvrir 13 semaines ISO")
        self.assertEqual(data["weeks"][-1]["week_start"], WEEKS_BACK_MONDAYS["w0"],
                         "weeks[-1] = semaine courante")

    def test_target_is_single_source_backend(self):
        """weekly_target renvoyé explicitement — iOS ne doit pas coder 5 en dur."""
        self._set_sessions([])
        self._set_hiit([])
        data = self._get()
        self.assertEqual(data["weekly_target"], 5)

    # ── week_at_risk (source unique serveur) ──────────────────────────────────

    def _get_at(self, day_iso: str):
        """Fetch avec today= day_iso en patchant _today_mtl au vol."""
        for p in self._today_patchers:
            p.stop()
        patchers = [
            patch("planner.get_today_date", return_value=day_iso),
            patch("utils._today_mtl", return_value=day_iso),
            patch("routes.analytics_stats._today_mtl", return_value=day_iso),
        ]
        for p in patchers:
            p.start()
        try:
            return self.json(self.get(f"/api/stats/streaks?date={day_iso}"))
        finally:
            for p in patchers:
                p.stop()
            # Restore les patches par défaut pour tearDown.
            self._today_patchers = [
                patch("planner.get_today_date", return_value=TODAY),
                patch("utils._today_mtl", return_value=TODAY),
                patch("routes.analytics_stats._today_mtl", return_value=TODAY),
            ]
            for p in self._today_patchers:
                p.start()

    def test_week_at_risk_false_when_margin_remains(self):
        """Jour de repos avec marge → week_at_risk = false."""
        # Mardi 2026-10-20, 1 jour actif (lundi). Restants = 5+1=6 (today pas actif),
        # manquants = 4. 6 > 4 → marge → false.
        self._set_sessions(["2026-10-19"])  # lundi seulement
        self._set_hiit([])
        data = self._get_at("2026-10-20")
        self.assertFalse(data["week_at_risk"],
                         "mardi 1 jour actif, 6 restants, 4 manquants : marge")

    def test_week_at_risk_true_when_no_margin(self):
        """Plus de marge → week_at_risk = true."""
        # Samedi 2026-10-24, 3 jours actifs L+M+V, today non actif.
        # Restants = 1+1=2 (sam+dim). Manquants = 2. 2 == 2 → true.
        self._set_sessions(["2026-10-19", "2026-10-20", "2026-10-23"])
        self._set_hiit([])
        data = self._get_at("2026-10-24")
        self.assertEqual(data["current_week"]["days_active"], 3)
        self.assertTrue(data["week_at_risk"],
                        "samedi 3 jours actifs, 2 restants, 2 manquants : à risque")

    def test_week_at_risk_false_when_week_already_lost(self):
        """Semaine déjà perdue (restants < manquants) → false, pas de relance."""
        # Samedi 2026-10-24, 2 jours actifs L+M. Restants = 2 (sam+dim), manquants = 3.
        # 2 < 3 → perdue → false.
        self._set_sessions(["2026-10-19", "2026-10-20"])
        self._set_hiit([])
        data = self._get_at("2026-10-24")
        self.assertFalse(data["week_at_risk"],
                         "semaine perdue : pas de relance inutile")

    def test_week_at_risk_false_when_target_already_reached(self):
        """Objectif déjà atteint → false (manquants == 0)."""
        # Jeudi 2026-10-22, 5 jours actifs L+M+M+J (today actif).
        self._set_sessions(["2026-10-19", "2026-10-20", "2026-10-21", "2026-10-22",
                            "2026-10-18"])  # dim précédent — hors ISO, pas compté
        # 4 jours cette semaine. Besoin 5. Testons avec 5 jours réels :
        self._set_sessions(["2026-10-19", "2026-10-20", "2026-10-21", "2026-10-22"])
        self._set_hiit(["2026-10-19"])  # jour déjà actif via workout → still 4
        # On veut 5 → ajoute un workout mardi additionnel ? Non, les dates sont uniques.
        # Simpler: 5 workouts sur jours distincts.
        self._set_sessions(["2026-10-19", "2026-10-20", "2026-10-21",
                             "2026-10-22", "2026-10-18"])  # 2026-10-18 est dimanche
        # 2026-10-18 est le dimanche de la semaine PRÉCÉDENTE (lundi 2026-10-19
        # commence la semaine courante). Donc 4 jours courante + 1 précédente.
        # Essayons avec 5 jours strictement courante (impossible avant jeudi, utilise samedi):
        self._set_sessions(["2026-10-19", "2026-10-20", "2026-10-21", "2026-10-22", "2026-10-23"])
        self._set_hiit([])
        data = self._get_at("2026-10-24")  # samedi, 5 jours déjà faits L-V
        self.assertGreaterEqual(data["current_week"]["days_active"], 5)
        self.assertFalse(data["week_at_risk"],
                         "objectif atteint : plus de relance")


if __name__ == "__main__":
    unittest.main(verbosity=2)
