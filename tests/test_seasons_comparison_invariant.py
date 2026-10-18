"""
Tests: /api/seasons/comparison expose weight_start_lbs, weight_end_lbs,
body_fat_start, body_fat_end — invariant de cohérence avec weight_delta.

Contexte : commit "seasons: expose weight/body_fat start+end" ajoute 4 champs
par saison (courante + précédente). Vince en veut un visuel avant → après dans
l'onglet Body (commit 4 iOS). L'invariant demandé : la valeur `weight_delta`
déjà exposée doit égaler, à l'arrondi décimal 1 près,
`weight_end_lbs − weight_start_lbs`.

Si cet invariant casse, c'est que l'un des deux calculs diverge (bug backend
qui exposerait des données incohérentes au client — fantôme typique).
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

from unittest.mock import patch
from conftest import BaseRouteTest


ACTIVE = {
    "id":              "s-active",
    "number":          4,
    "status":          "active",
    "started_at":      "2026-07-01",
    "custom_title":    "SEASON 4",
    "generated_title": None,
}

PREV = {
    "id":              "s-prev",
    "number":          3,
    "status":          "completed",
    "started_at":      "2026-01-01",
    "ended_at":        "2026-06-30",
    "custom_title":    "SEASON 3",
    "generated_title": None,
}

START_SNAP_ACTIVE = {"type": "start", "weight_lbs": 180.0, "body_fat_pct": 18.5}
START_SNAP_PREV   = {"type": "start", "weight_lbs": 175.0, "body_fat_pct": 20.0}
END_SNAP_PREV     = {"type": "end",   "weight_lbs": 182.5, "body_fat_pct": 17.2, "pss_score": 42, "phoenix_avg": 68}

BW_LOGS = [
    {"date": "2026-10-15", "weight": 185.3, "body_fat": 17.0},
    {"date": "2026-09-01", "weight": 184.0, "body_fat": None},
]


def _patch_db(**overrides):
    """Patch toutes les fonctions `db.*` que get_seasons_comparison consomme."""
    defaults = {
        "get_active_season":    ACTIVE,
        "get_weekly_tonnage":   [],
        "get_pss_records":      [],
        "get_body_weight_logs": BW_LOGS,
        "get_workout_sessions": [],
        "get_all_seasons":      [ACTIVE, PREV],
    }
    defaults.update(overrides)
    stack = []
    for fname, value in defaults.items():
        stack.append(patch(f"routes.seasons.db.{fname}", return_value=value))
    return stack


class TestComparisonInvariant(BaseRouteTest):
    def _snapshots_router(self, season_id):
        if season_id == "s-active": return [START_SNAP_ACTIVE]
        if season_id == "s-prev":   return [START_SNAP_PREV, END_SNAP_PREV]
        return []

    def test_exposes_start_end_and_body_fat_fields(self):
        with patch("routes.seasons.db.get_season_snapshots", side_effect=self._snapshots_router):
            patches = _patch_db()
            for p in patches: p.start()
            try:
                r = self.get("/api/seasons/comparison")
            finally:
                for p in patches: p.stop()

        self.assertEqual(200, r.status_code)
        payload = self.json(r)
        cur = payload["current"]
        prv = payload["previous"]

        # Current
        self.assertEqual(180.0, cur["weight_start_lbs"])
        self.assertEqual(185.3, cur["weight_end_lbs"])
        self.assertEqual(18.5,  cur["body_fat_start"])
        self.assertEqual(17.0,  cur["body_fat_end"])

        # Previous
        self.assertEqual(175.0, prv["weight_start_lbs"])
        self.assertEqual(182.5, prv["weight_end_lbs"])
        self.assertEqual(20.0,  prv["body_fat_start"])
        self.assertEqual(17.2,  prv["body_fat_end"])

    def test_weight_delta_matches_end_minus_start(self):
        """Invariant demandé : weight_delta == round(end - start, 1)."""
        with patch("routes.seasons.db.get_season_snapshots", side_effect=self._snapshots_router):
            patches = _patch_db()
            for p in patches: p.start()
            try:
                r = self.get("/api/seasons/comparison")
            finally:
                for p in patches: p.stop()

        payload = self.json(r)
        for label, s in (("current", payload["current"]), ("previous", payload["previous"])):
            delta = s["weight_delta"]
            start = s["weight_start_lbs"]
            end   = s["weight_end_lbs"]
            self.assertIsNotNone(delta, f"{label}.weight_delta ne doit pas être None")
            self.assertAlmostEqual(
                delta, round(end - start, 1), places=2,
                msg=f"{label} viole l'invariant : delta={delta} vs end-start={round(end-start, 1)}",
            )

    def test_body_fat_end_scans_past_null_body_fat(self):
        """body_fat_end prend la dernière entrée body_weight_logs avec
        body_fat non-null (dans la fenêtre 14j), pas juste la plus récente.
        Anti-fantôme : si la ligne la plus récente a body_fat=null, on
        remonte la liste au lieu de retourner None sans raison."""
        logs = [
            {"date": "2026-10-20", "weight": 186.0, "body_fat": None},   # plus récent, null
            {"date": "2026-10-18", "weight": 185.3, "body_fat": 17.0},   # 2j, cible
        ]
        with patch("routes.seasons._today_mtl", return_value="2026-10-20"), \
             patch("routes.seasons.db.get_season_snapshots", side_effect=self._snapshots_router):
            patches = _patch_db(get_body_weight_logs=logs)
            for p in patches: p.start()
            try:
                r = self.get("/api/seasons/comparison")
            finally:
                for p in patches: p.stop()

        cur = self.json(r)["current"]
        self.assertEqual(186.0, cur["weight_end_lbs"], "weight_end reste la ligne la + récente")
        self.assertEqual(17.0,  cur["body_fat_end"],   "body_fat_end remonte au premier non-null dans 14j")

    def test_body_fat_end_rejects_stale(self):
        """Si la seule mesure body_fat non-null date de plus de 14 jours,
        body_fat_end doit être None (pas de valeur périmée)."""
        logs = [
            {"date": "2026-10-20", "weight": 186.0, "body_fat": None},   # today, null
            {"date": "2026-09-20", "weight": 184.0, "body_fat": 18.0},   # 30j, rejeté
        ]
        with patch("routes.seasons._today_mtl", return_value="2026-10-20"), \
             patch("routes.seasons.db.get_season_snapshots", side_effect=self._snapshots_router):
            patches = _patch_db(get_body_weight_logs=logs)
            for p in patches: p.start()
            try:
                r = self.get("/api/seasons/comparison")
            finally:
                for p in patches: p.stop()

        cur = self.json(r)["current"]
        self.assertIsNone(cur["body_fat_end"], "mesure body_fat 30j doit être rejetée (fantôme)")


if __name__ == "__main__":
    import unittest
    unittest.main()
