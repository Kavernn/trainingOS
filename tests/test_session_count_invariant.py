"""Invariant session_count : /api/dashboard et /api/stats_data doivent
produire le même session_count par date, pour chaque entrée des deux
dicts `sessions`. Source unique = routes.analytics_stats.count_slots_by_date.

Hotfix du 2026-10-15 (régression dashboard vide après lot 1 Stats :
SessionEntry.sessionCount passé en requis côté iOS, mais /api/dashboard
n'émettait pas ce champ hors du bloc multi-slot aujourd'hui).
"""
import sys, os
import unittest
from unittest.mock import patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

from conftest import BaseRouteTest, TODAY


# Fixture : un jour passé avec AM + PM (deux rows workout_sessions), un
# autre avec AM + HIIT, un HIIT-seul, un mono-slot classique.
PAST_MULTI = "2026-03-10"   # existe déjà dans conftest SESSIONS (mono-slot)
AM_PM_DATE = "2026-03-05"   # on injecte 2 workout rows
AM_HIIT_DATE = "2026-03-06" # on injecte 1 workout row + 1 HIIT
HIIT_ONLY_DATE = "2026-03-09"

MULTI_WORKOUT_ROWS = [
    # AM_PM_DATE : AM + PM
    {"date": AM_PM_DATE, "session_type": "morning", "rpe": 7, "completed": True,
     "logged_at": "2026-03-05T07:30:00", "duration_min": 50, "session_name": "Upper A"},
    {"date": AM_PM_DATE, "session_type": "evening", "rpe": 6, "completed": True,
     "logged_at": "2026-03-05T18:30:00", "duration_min": 35, "session_name": "Pull A"},
    # AM_HIIT_DATE : AM workout + HIIT (voir EXTRA_HIIT ci-dessous)
    {"date": AM_HIIT_DATE, "session_type": "morning", "rpe": 7, "completed": True,
     "logged_at": "2026-03-06T07:30:00", "duration_min": 45, "session_name": "Upper A"},
    # Mono-slot historique conservé
    {"date": "2026-03-07", "session_type": "morning", "rpe": 8, "completed": True,
     "logged_at": "2026-03-07T07:00:00", "duration_min": 40, "session_name": "Legs"},
    {"date": "2026-03-10", "session_type": "morning", "rpe": 7, "completed": True,
     "logged_at": "2026-03-10T07:00:00", "duration_min": 55, "session_name": "Upper A"},
]

EXTRA_HIIT = [
    # HIIT_ONLY_DATE : HIIT seul
    {"date": HIIT_ONLY_DATE, "session_type": "Tabata", "rounds_planned": 8,
     "rounds_completed": 8, "rpe": 8},
    # AM_HIIT_DATE : HIIT en plus du workout
    {"date": AM_HIIT_DATE, "session_type": "Tabata", "rounds_planned": 6,
     "rounds_completed": 6, "rpe": 7},
    # 2026-03-11 déjà dans HIIT_LOG conftest — on garde ce flux.
]


class SessionCountInvariant(BaseRouteTest):

    def setUp(self):
        super().setUp()
        # Remplace les rows workout + hiit par nos fixtures multi-slot.
        self.store["sessions"] = {}  # on bypasse load_sessions pour forcer la lecture via get_workout_sessions
        for row in MULTI_WORKOUT_ROWS:
            # load_sessions() aggrège par date (last-write-wins). Pour exposer
            # le dict, on ne garde qu'une des rows ; le vrai comptage passe par
            # get_workout_sessions (patché ci-dessous).
            self.store["sessions"][row["date"]] = {k: v for k, v in row.items() if k != "date"}
        self.store["hiit_log"] = list(self.store.get("hiit_log") or []) + EXTRA_HIIT

        # Remplace get_workout_sessions sur le mock db live (sys.modules["db"]
        # est le _SpecGuardedMock installé par conftest). On passe par
        # object.__setattr__ sur l'inner MagicMock pour contourner le guard,
        # qui refuserait aussi une méthode "légale" si on tentait setattr direct.
        import sys as _sys
        _inner = _sys.modules["db"]._inner
        self._original_fn = _inner.get_workout_sessions
        _inner.get_workout_sessions = self._fake_get_workout_sessions
        # _today_mtl non patché par conftest ; les modules routes capturent la
        # référence au top-level (`from utils import _today_mtl`) → patcher
        # utils ne suffit pas. On patche aussi dans les modules consommateurs.
        self._today_patchers = [
            patch("utils._today_mtl", return_value=TODAY),
            patch("routes.analytics_stats._today_mtl", return_value=TODAY),
        ]
        for p in self._today_patchers:
            p.start()

    def tearDown(self):
        for p in self._today_patchers:
            p.stop()
        import sys as _sys
        _sys.modules["db"]._inner.get_workout_sessions = self._original_fn
        super().tearDown()

    def _fake_get_workout_sessions(self, limit=100, offset=0, since=None):
        rows = list(MULTI_WORKOUT_ROWS)
        if since:
            rows = [r for r in rows if r["date"] >= since]
        return rows[:limit]

    # ── Dashboard: toutes les entries ont session_count ──────────────────────

    def test_dashboard_every_session_entry_has_session_count(self):
        data = self.json(self.get("/api/dashboard"))
        self.assertIn("sessions", data)
        self.assertTrue(data["sessions"], "fixture vide : rien à vérifier")
        for date, entry in data["sessions"].items():
            self.assertIn("session_count", entry,
                          f"/api/dashboard {date} : session_count manquant")
            self.assertIsInstance(entry["session_count"], int)

    # ── Stats_data: toutes les entries ont session_count ─────────────────────

    def test_stats_data_every_session_entry_has_session_count(self):
        data = self.json(self.get("/api/stats_data"))
        self.assertIn("sessions", data)
        self.assertTrue(data["sessions"], "fixture vide : rien à vérifier")
        for date, entry in data["sessions"].items():
            self.assertIn("session_count", entry,
                          f"/api/stats_data {date} : session_count manquant")
            self.assertIsInstance(entry["session_count"], int)

    # ── Invariant : égalité entre les deux endpoints ─────────────────────────

    def test_same_session_count_across_endpoints(self):
        dash = self.json(self.get("/api/dashboard"))["sessions"]
        stats = self.json(self.get("/api/stats_data"))["sessions"]
        shared_dates = set(dash) & set(stats)
        self.assertTrue(shared_dates, "aucune date commune aux deux endpoints — fixture insuffisante")
        for date in shared_dates:
            self.assertEqual(dash[date]["session_count"], stats[date]["session_count"],
                             f"session_count divergent pour {date}: "
                             f"dashboard={dash[date]['session_count']} vs stats={stats[date]['session_count']}")

    # ── AM + PM = 2 (preuve que les slots multiples sont comptés) ────────────

    def test_am_plus_pm_counts_as_two_on_both_endpoints(self):
        dash = self.json(self.get("/api/dashboard"))["sessions"]
        stats = self.json(self.get("/api/stats_data"))["sessions"]
        self.assertEqual(dash[AM_PM_DATE]["session_count"], 2,
                         "/api/dashboard AM+PM doit valoir 2")
        self.assertEqual(stats[AM_PM_DATE]["session_count"], 2,
                         "/api/stats_data AM+PM doit valoir 2")

    # ── HIIT merge ne perd pas l'entry workout d'une date pré-existante ─────

    def test_hiit_on_workout_day_does_not_overwrite_entry(self):
        dash = self.json(self.get("/api/dashboard"))["sessions"]
        stats = self.json(self.get("/api/stats_data"))["sessions"]
        # AM_HIIT_DATE : 1 workout slot workout_sessions. session_count ne
        # compte QUE les slots workout (règle commune aux deux endpoints).
        # Le HIIT du même jour est tracké séparément via hiit_log — pas dans
        # sessions.session_count. L'invariant workout count tient : 1 == 1.
        self.assertEqual(dash[AM_HIIT_DATE]["session_count"], 1)
        self.assertEqual(stats[AM_HIIT_DATE]["session_count"], 1)
        # L'entry dashboard reste celle du workout (le merge HIIT ligne 142
        # est skippé parce que la date est déjà dans merged_sessions).
        self.assertNotEqual(dash[AM_HIIT_DATE].get("session_type"), "Tabata",
                            "le merge HIIT a écrasé l'entrée workout — régression")

    # ── HIIT-seul → entry minimale avec session_count=1 ──────────────────────

    def test_hiit_only_day_has_session_count_one(self):
        dash = self.json(self.get("/api/dashboard"))["sessions"]
        self.assertIn(HIIT_ONLY_DATE, dash)
        self.assertEqual(dash[HIIT_ONLY_DATE]["session_count"], 1)


if __name__ == "__main__":
    unittest.main(verbosity=2)
