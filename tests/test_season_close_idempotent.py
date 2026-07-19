"""
Tests: closeSeason idempotence — anti-replay destructif.

Contexte : POST /api/seasons/<id>/close (season_engine.close_season) écrivait
un snapshot "end" + UPDATE seasons SET status='completed', ended_at, title,
arc à chaque appel, sans vérifier le status. Un replay (offlinePost iOS
reconnect OU chapterCard SeasonView L187 sur saison passée) écrasait le
rapport original figé.

Fix : head guard status == 'completed' → _report_from_completed(), zéro
écriture, zéro recompute snapshot. Rapport recomposé depuis les données
stockées.

Couvre :
  - close nominal : status pending → 200, snapshot end écrit, seasons UPDATE
  - double close  : 2e appel sur status='completed' → 200 avec le rapport
                    ORIGINAL, aucun nouveau snapshot, aucun UPDATE seasons
  - 404 propre    : id inexistant → 404, message explicite
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

from unittest.mock import patch, MagicMock
from conftest import BaseRouteTest


SEASON_PENDING = {
    "id":               "s-1",
    "number":           3,
    "status":           "active",
    "started_at":       "2026-05-01",
    "ended_at":         None,
    "generated_title":  None,
    "dominant_arc":     None,
    "custom_title":     None,
    "personal_note":    None,
}

SEASON_COMPLETED = {
    "id":               "s-1",
    "number":           3,
    "status":           "completed",
    "started_at":       "2026-05-01",
    "ended_at":         "2026-06-15",           # date figée du close original
    "generated_title":  "SEASON 3 — THE JOURNEY",  # figé
    "dominant_arc":     "steady_grind",         # figé
    "custom_title":     None,
    "personal_note":    None,
}

START_SNAPSHOT = {
    "type":       "start",
    "top_prs":    [],
    "phoenix_avg": 60,
    "weight_lbs": 180.0,
}

END_SNAPSHOT_ORIGINAL = {
    "type":                    "end",
    "phoenix_avg":             68,
    "weight_lbs":              182.5,
    "ritual_completion_rate":  0.72,
}


# Fixtures partagées pour isoler la logique du guard : compute_season_stats,
# build_narrative et generate_headline_delta sont patchés pour ne pas dépendre
# du mock db exhaustif de conftest (get_all_exercise_history & co).
_FAKE_STATS     = {"total_sessions": 42, "total_prs": 3}
_FAKE_NARRATIVE = "Tu as tenu ta parole."
_FAKE_HEADLINE  = "42 séances · +3 PR"


class TestCloseNominal(BaseRouteTest):
    """Premier close d'une saison active : snapshot end + UPDATE seasons."""

    def test_nominal_writes_snapshot_and_updates_status(self):
        with patch("season_engine.db.get_season_by_id",         return_value=SEASON_PENDING), \
             patch("season_engine.db.get_season_snapshots",     return_value=[START_SNAPSHOT]), \
             patch("season_engine.db.save_season_snapshot")     as mock_save_snap, \
             patch("season_engine.db.get_prev_season_had_reset", return_value=False), \
             patch("season_engine.db.close_season",             return_value={**SEASON_PENDING, "status": "completed"}) as mock_update, \
             patch("season_engine.compute_snapshot",            return_value=END_SNAPSHOT_ORIGINAL), \
             patch("season_engine.compute_season_stats",        return_value=dict(_FAKE_STATS)), \
             patch("season_engine.detect_arc",                  return_value="steady_grind"), \
             patch("season_engine.build_narrative",             return_value=_FAKE_NARRATIVE), \
             patch("season_engine.generate_headline_delta",     return_value=_FAKE_HEADLINE):
            r = self.post("/api/seasons/s-1/close", {})

        self.assertEqual(200, r.status_code)
        # Snapshot end écrit UNE fois
        mock_save_snap.assert_called_once()
        args, _ = mock_save_snap.call_args
        self.assertEqual("s-1", args[0])
        self.assertEqual("end", args[1])
        # UPDATE seasons appelé UNE fois avec les bons champs figés
        mock_update.assert_called_once()
        _, kwargs = mock_update.call_args
        self.assertIn("ended_at",        kwargs)
        self.assertIn("generated_title", kwargs)
        self.assertIn("dominant_arc",    kwargs)


class TestDoubleCloseIdempotent(BaseRouteTest):
    """Cœur du fix : 2e close sur une saison completed → NO-OP écriture,
    retourne le rapport original figé (title/arc/ended_at intacts)."""

    def test_double_close_no_writes_and_preserves_original(self):
        # get_season_by_id retourne la saison DÉJÀ fermée. Le guard doit
        # court-circuiter avant tout appel à save_season_snapshot ou
        # db.close_season (UPDATE seasons).
        snapshots = [START_SNAPSHOT, END_SNAPSHOT_ORIGINAL]
        with patch("season_engine.db.get_season_by_id",     return_value=SEASON_COMPLETED), \
             patch("season_engine.db.get_season_snapshots", return_value=snapshots), \
             patch("season_engine.db.save_season_snapshot") as mock_save_snap, \
             patch("season_engine.db.close_season")         as mock_update, \
             patch("season_engine.compute_snapshot")        as mock_recompute, \
             patch("season_engine.compute_season_stats",    return_value=dict(_FAKE_STATS)), \
             patch("season_engine.build_narrative",         return_value=_FAKE_NARRATIVE), \
             patch("season_engine.generate_headline_delta", return_value=_FAKE_HEADLINE):
            r = self.post("/api/seasons/s-1/close", {})

        self.assertEqual(200, r.status_code)
        payload = self.json(r)

        # PREUVE ANTI-DESTRUCTION : aucune écriture, aucun recompute snapshot.
        mock_save_snap.assert_not_called()
        mock_update.assert_not_called()
        mock_recompute.assert_not_called()

        # PREUVE PRÉSERVATION : title/arc/ended_at du rapport = valeurs figées
        # en base, pas des recalculs.
        self.assertEqual("SEASON 3 — THE JOURNEY", payload["title"])
        self.assertEqual("steady_grind",           payload["arc"])
        self.assertEqual("2026-06-15",             payload["season"]["ended_at"])


class TestCloseMissingSeason(BaseRouteTest):
    """ID inexistant → 404 propre, pas un 500."""

    def test_missing_season_returns_404(self):
        with patch("season_engine.db.get_season_by_id", return_value=None):
            r = self.post("/api/seasons/does-not-exist/close", {})

        self.assertEqual(404, r.status_code)
        self.assertIn("introuvable", self.json(r).get("error", "").lower())


if __name__ == "__main__":
    import unittest
    unittest.main(verbosity=2)
