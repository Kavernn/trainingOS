"""
Tests: compute_snapshot écrit body_fat_pct avec un garde-fou de 14 jours.

Contexte : season_snapshots.body_fat_pct peut être écrit par compute_snapshot
pour les saisons futures. Si la dernière mesure body_fat non-null date de
plus de 14 jours avant la date du snapshot, on NE l'écrit PAS (laisse null) :
une valeur périmée étiquetée comme "début/fin de saison" ferait un
"souvenir fantôme" côté UI.

Couvre :
  - body_fat_pct = dernière mesure non-null si ≤ 14j avant snap date
  - absent si la seule mesure non-null date de 30 jours
  - itère pour trouver un non-null si le top-1 est null
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

from unittest.mock import patch
from conftest import BaseRouteTest


SNAP_DATE = "2026-10-17"


def _run_snapshot(logs):
    """Patch les deps de compute_snapshot et retourne le snapshot."""
    import season_engine
    with patch("season_engine.db.get_body_weight_logs", return_value=logs), \
         patch("season_engine.db.get_pss_records",      return_value=[]), \
         patch("season_engine.db.get_war_room_battles", return_value=[]), \
         patch("season_engine.db.get_exercise_prs",     return_value=[]), \
         patch("season_engine.db.get_ritual_history",   return_value=[]), \
         patch("season_engine.db.get_recovery_logs",    return_value=[]), \
         patch("phoenix_engine.compute",                return_value={"score": 60, "axes": {}}):
        return season_engine.compute_snapshot(as_of_date=SNAP_DATE)


class TestComputeSnapshotBodyFat(BaseRouteTest):

    def test_recent_measurement_written(self):
        """Mesure body_fat 3 jours avant snap → body_fat_pct populé."""
        logs = [
            {"date": "2026-10-14", "weight": 185.3, "body_fat": 17.0},  # 3 jours avant
        ]
        snap = _run_snapshot(logs)
        self.assertEqual(17.0, snap.get("body_fat_pct"))

    def test_stale_measurement_rejected(self):
        """Mesure body_fat 30 jours avant snap → body_fat_pct absent (pas périmé)."""
        logs = [
            {"date": "2026-09-17", "weight": 185.3, "body_fat": 17.0},  # 30 jours avant
        ]
        snap = _run_snapshot(logs)
        self.assertNotIn("body_fat_pct", snap, "une mesure de 30j ne doit pas être écrite comme snapshot")

    def test_scans_past_null_within_window(self):
        """Top-1 avec body_fat=null, 2e à 5 jours avec non-null → prend le 2e."""
        logs = [
            {"date": "2026-10-16", "weight": 186.0, "body_fat": None},   # 1j, null
            {"date": "2026-10-12", "weight": 185.3, "body_fat": 17.0},   # 5j, cible
        ]
        snap = _run_snapshot(logs)
        self.assertEqual(17.0, snap.get("body_fat_pct"))

    def test_scans_past_null_rejects_stale(self):
        """Top-1 null + 2e non-null mais à 30j → body_fat_pct absent."""
        logs = [
            {"date": "2026-10-16", "weight": 186.0, "body_fat": None},    # 1j, null
            {"date": "2026-09-17", "weight": 184.0, "body_fat": 18.0},    # 30j, rejeté
        ]
        snap = _run_snapshot(logs)
        self.assertNotIn("body_fat_pct", snap)

    def test_boundary_14_days(self):
        """Pile 14 jours avant → accepté (cutoff inclusif)."""
        logs = [{"date": "2026-10-03", "weight": 185.3, "body_fat": 17.5}]
        snap = _run_snapshot(logs)
        self.assertEqual(17.5, snap.get("body_fat_pct"))

    def test_boundary_15_days(self):
        """15 jours avant → rejeté."""
        logs = [{"date": "2026-10-02", "weight": 185.3, "body_fat": 17.5}]
        snap = _run_snapshot(logs)
        self.assertNotIn("body_fat_pct", snap)


if __name__ == "__main__":
    import unittest
    unittest.main()
