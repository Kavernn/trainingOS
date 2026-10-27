"""
Tests: session and HIIT mutation routes.

Routes covered:
  POST /api/session/edit
  POST /api/session/delete
  POST /api/log_session
  POST /api/log_hiit
  POST /api/delete_hiit
  POST /api/hiit/edit
"""
import copy
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

from unittest.mock import patch
from conftest import BaseRouteTest, TODAY


# ── /api/session/edit ─────────────────────────────────────────────────────────

class TestSessionEdit(BaseRouteTest):

    def test_edit_rpe(self):
        r = self.post("/api/session/edit", {"date": "2026-03-10", "rpe": 9})
        self.assertEqual(200, r.status_code)
        self.assertTrue(self.json(r).get("success"))
        self.assertEqual(9, self.store["sessions"]["2026-03-10"]["rpe"])

    def test_edit_comment(self):
        self.post("/api/session/edit", {"date": "2026-03-10", "comment": "felt great"})
        self.assertEqual("felt great", self.store["sessions"]["2026-03-10"]["comment"])

    def test_edit_exercise_weight(self):
        r = self.post("/api/session/edit", {
            "date": "2026-03-10",
            "exercises": [{"exercise": "Bench Press", "weight": 190.0, "reps": "7,6,6,5"}],
        })
        self.assertEqual(200, r.status_code)
        entry = next(
            e for e in self.store["weights"]["Bench Press"]["history"]
            if e["date"] == "2026-03-10"
        )
        self.assertEqual(190.0, entry["weight"])
        self.assertEqual("7,6,6,5", entry["reps"])

    def test_edit_recalculates_1rm(self):
        self.post("/api/session/edit", {
            "date": "2026-03-10",
            "exercises": [{"exercise": "Bench Press", "weight": 190.0, "reps": "5,5,5,5"}],
        })
        entry = next(
            e for e in self.store["weights"]["Bench Press"]["history"]
            if e["date"] == "2026-03-10"
        )
        self.assertIn("1rm", entry)
        self.assertGreater(entry["1rm"], 190.0)

    def test_edit_missing_date_returns_400(self):
        r = self.post("/api/session/edit", {"rpe": 7})
        self.assertEqual(400, r.status_code)

    def test_edit_session_absente_returns_404_no_write(self):
        """Date sans workout_session → 404 'session_absente', aucune écriture.
        Doctrine : pas de success menteur, pas d'édition partielle."""
        self.assertNotIn("2026-01-01", self.store["sessions"])
        snapshot = copy.deepcopy(self.store["weights"])
        r = self.post("/api/session/edit", {
            "date": "2026-01-01",
            "exercises": [{"exercise": "Bench Press", "weight": 170.0, "reps": "8,8,8"}],
        })
        self.assertEqual(404, r.status_code)
        self.assertEqual("session_absente", self.json(r).get("error"))
        self.assertEqual(snapshot, self.store["weights"],
                         "aucune mutation attendue en cas de 404")

    def test_edit_rpe_on_absent_session_returns_404(self):
        """Rpe sur date sans session → 404, pas de touch sur sessions."""
        snapshot = copy.deepcopy(self.store["sessions"])
        r = self.post("/api/session/edit", {"date": "2026-01-01", "rpe": 8})
        self.assertEqual(404, r.status_code)
        self.assertEqual(snapshot, self.store["sessions"])

    def test_edit_unknown_exercise_returns_422_no_write(self):
        """Exercice qui ne résout pas via get_exercise_id → 422 immédiat,
        aucune écriture (ni rpe ni exercise_log)."""
        from unittest.mock import MagicMock
        db_mod = sys.modules["db"]
        orig = db_mod.get_exercise_id
        db_mod.get_exercise_id = MagicMock(side_effect=lambda n: None if n == "Unknown Exercise" else n)
        try:
            snapshot_sessions = copy.deepcopy(self.store["sessions"])
            snapshot_weights  = copy.deepcopy(self.store["weights"])
            r = self.post("/api/session/edit", {
                "date": "2026-03-10", "rpe": 11,
                "exercises": [{"exercise": "Unknown Exercise", "weight": 100.0, "reps": "5,5"}],
            })
            self.assertEqual(422, r.status_code)
            self.assertEqual("exercise_unknown", self.json(r).get("error"))
            self.assertEqual(snapshot_sessions, self.store["sessions"],
                             "rpe ne doit pas s'écrire si un exo plante en validation")
            self.assertEqual(snapshot_weights, self.store["weights"])
        finally:
            db_mod.get_exercise_id = orig

    def test_edit_exercise_without_recent_history_still_persists(self):
        """Un exercice qui existe dans exercises mais sans entrée dans
        store["weights"] (= pas fait depuis >180j via load_weights) peut
        toujours être édité tant que get_exercise_id le résout."""
        self.assertNotIn("Face Pull", self.store.get("weights", {}))
        r = self.post("/api/session/edit", {
            "date": "2026-03-10",
            "exercises": [{"exercise": "Face Pull", "weight": 60.0, "reps": "15,15,15"}],
        })
        self.assertEqual(200, r.status_code)
        self.assertIn("Face Pull", self.store["weights"])
        entry = next(e for e in self.store["weights"]["Face Pull"]["history"]
                     if e["date"] == "2026-03-10")
        self.assertEqual(60.0, entry["weight"])

    def test_edit_no_kv_salve(self):
        """Anti-régression Volet H-bis (fin du dernier vestige KV):
        éditer UN champ (rpe) = UN seul PATCH by_type ciblé.
        Aucun appel à update_workout_session (morning-only buggé, salve ~120)."""
        # Simule un historique chargé (50 dates) pour prouver l'absence de salve
        for i in range(50):
            d = f"2025-{(i // 28) + 1:02d}-{(i % 28) + 1:02d}"
            self.store["sessions"][d] = {"rpe": 6, "comment": ""}

        from unittest.mock import MagicMock as _MM
        db_mod = sys.modules["db"]
        by_type_spy = _MM(return_value=True)
        morning_spy = _MM(return_value=True)
        db_mod.update_workout_session_by_type = by_type_spy
        db_mod.update_workout_session         = morning_spy

        r = self.post("/api/session/edit", {
            "date": "2026-03-10", "session_type": "evening", "rpe": 9,
        })
        self.assertEqual(200, r.status_code)
        self.assertEqual(1, by_type_spy.call_count,
                         "PATCH ciblé unique attendu, pas de salve KV")
        self.assertEqual(0, morning_spy.call_count,
                         "update_workout_session (morning-only) ne doit plus être appelé")
        call = by_type_spy.call_args
        self.assertEqual(("2026-03-10", "evening"), (call.args[0], call.args[1]))
        self.assertEqual({"rpe": 9}, call.args[2])


# ── /api/session/delete ───────────────────────────────────────────────────────

class TestSessionDelete(BaseRouteTest):

    def test_delete_removes_session(self):
        r = self.post("/api/session/delete", {"date": "2026-03-10"})
        self.assertEqual(200, r.status_code)
        self.assertNotIn("2026-03-10", self.store["sessions"])

    def test_delete_removes_history_entries(self):
        r = self.post("/api/session/delete", {"date": "2026-03-10"})
        self.assertEqual(200, r.status_code)
        remaining = [
            e for e in self.store["weights"]["Bench Press"]["history"]
            if e["date"] == "2026-03-10"
        ]
        self.assertEqual([], remaining)

    def test_delete_preserves_other_history(self):
        """Deleting one session must not touch entries from other dates."""
        self.post("/api/session/delete", {"date": "2026-03-10"})
        dates = [e["date"] for e in self.store["weights"]["Bench Press"]["history"]]
        self.assertIn("2026-03-03", dates)

    def test_delete_updates_current_weight(self):
        """After deletion current_weight must reflect the newest remaining entry."""
        self.post("/api/session/delete", {"date": "2026-03-10"})
        self.assertEqual(180.0, self.store["weights"]["Bench Press"]["current_weight"])

    def test_delete_missing_date_returns_400(self):
        r = self.post("/api/session/delete", {})
        self.assertEqual(400, r.status_code)


# ── /api/log_session ─────────────────────────────────────────────────────────

class TestLogSession(BaseRouteTest):

    def setUp(self):
        super().setUp()
        # Local date/type-aware fake: the global historical fixture keys some
        # sessions by date only and cannot prove AM/PM isolation here.
        self.evening = {}
        self.evening_calls = []
        db = sys.modules["db"]
        self.original_update = db.update_workout_session_by_type

        def get_or_create(date):
            self.evening_calls.append("get_or_create")
            return self.evening.setdefault(date, {"id": date + "_pm", "completed": False})

        def update(date, session_type, values):
            if session_type != "evening":
                return self.original_update(date, session_type, values)
            self.evening_calls.append("update")
            if date not in self.evening:
                return False
            self.evening[date].update(values)
            return True

        db.get_or_create_workout_session_second = get_or_create
        db.update_workout_session_by_type = update

    def test_evening_existing_session_persists_exact_patch(self):
        self.evening[TODAY] = {"id": "existing-pm", "completed": False}
        self.store["sessions"][TODAY] = {"rpe": 3, "comment": "Morning"}
        values = {"rpe": 6, "comment": "", "duration_min": 42,
                  "energy_pre": 4, "session_name": "Evening plan"}
        response = self.post("/api/log_session", {"date": TODAY, "second_session": True, **values})
        self.assertEqual(200, response.status_code)
        self.assertEqual({"success": True}, self.json(response))
        self.assertEqual({"id": "existing-pm", "completed": True, **values}, self.evening[TODAY])
        self.assertEqual({"rpe": 3, "comment": "Morning"}, self.store["sessions"][TODAY])
        self.assertEqual(["get_or_create", "update"], self.evening_calls)

    def test_evening_absent_session_created_before_update(self):
        response = self.post("/api/log_session", {"date": TODAY, "second_session": True, "comment": "PM"})
        self.assertEqual(200, response.status_code)
        self.assertEqual({"success": True}, self.json(response))
        self.assertEqual(["get_or_create", "update"], self.evening_calls)
        self.assertTrue(self.evening[TODAY]["completed"])
        self.assertEqual("PM", self.evening[TODAY]["comment"])

    def test_evening_false_update_never_succeeds_existing_or_created(self):
        for existing in (False, True):
            with self.subTest(existing=existing):
                self.evening.clear()
                if existing:
                    self.evening[TODAY] = {"id": "existing-pm", "completed": False}
                with patch.object(sys.modules["db"], "update_workout_session_by_type", return_value=False) as update:
                    response = self.post("/api/log_session", {"date": TODAY, "second_session": True})
                self.assertEqual(500, response.status_code)
                self.assertIn("error", self.json(response))
                self.assertNotIn("success", self.json(response))
                update.assert_called_once_with(TODAY, "evening", {"comment": "", "completed": True})
                self.assertFalse(self.evening[TODAY]["completed"])

    def test_evening_create_failure_skips_update(self):
        with patch.object(sys.modules["db"], "get_or_create_workout_session_second", return_value={}):
            with patch.object(sys.modules["db"], "update_workout_session_by_type") as update:
                response = self.post("/api/log_session", {"date": TODAY, "second_session": True})
        self.assertEqual(500, response.status_code)
        self.assertIn("error", self.json(response))
        self.assertNotIn("success", self.json(response))
        update.assert_not_called()

    def test_evening_persistence_exception_returns_json_500(self):
        with patch.object(sys.modules["db"], "update_workout_session_by_type", side_effect=RuntimeError("DB unavailable")):
            response = self.post("/api/log_session", {"date": TODAY, "second_session": True})
        self.assertEqual(500, response.status_code)
        self.assertIn("error", self.json(response))
        self.assertNotIn("success", self.json(response))

    def test_morning_completed_keeps_previous_comment(self):
        self.store["sessions"][TODAY] = {"completed": True, "comment": "original", "rpe": 7}
        response = self.post("/api/log_session", {"date": TODAY, "comment": "new", "rpe": 9})
        self.assertEqual(200, response.status_code)
        self.assertEqual({"success": True}, self.json(response))
        self.assertEqual("original", self.store["sessions"][TODAY]["comment"])
        self.assertEqual([], self.evening_calls)

    def test_bonus_branch_does_not_call_evening_helpers(self):
        with patch("sessions.log_bonus_session") as log_bonus:
            with patch.object(sys.modules["db"], "complete_workout_session_bonus", return_value=True) as complete:
                response = self.post("/api/log_session", {"date": TODAY, "bonus_session": True, "rpe": 6, "comment": "Bonus"})
        self.assertEqual(200, response.status_code)
        self.assertEqual({"success": True}, self.json(response))
        log_bonus.assert_called_once()
        complete.assert_called_once()
        self.assertEqual([], self.evening_calls)

    def test_log_session_success(self):
        r = self.post("/api/log_session", {
            "date": TODAY, "rpe": 7, "comment": "good",
            "exos": ["Bench Press", "Back Squat"],
        })
        self.assertEqual(200, r.status_code)
        self.assertTrue(self.json(r).get("success"))

    def test_log_session_persists(self):
        self.post("/api/log_session", {"date": TODAY, "rpe": 8})
        self.assertIn(TODAY, self.store["sessions"])

    def test_log_session_duplicate_is_idempotent(self):
        """Second call for same date is idempotent (workout_logging.py:455-461).
        Doctrine actuelle : session déjà completed → 200 + success:True, pas 409.
        Les exercise_logs sont déjà écrits par /api/log ; pour éditer utiliser
        /api/session/edit ou /api/update_session. Test ancien attendait 409
        (comportement pré-idempotence)."""
        self.post("/api/log_session", {"date": TODAY, "rpe": 7})
        r = self.post("/api/log_session", {"date": TODAY, "rpe": 7})
        self.assertEqual(200, r.status_code)
        self.assertTrue(self.json(r).get("success"))

    def test_log_session_rejects_duration_above_300(self):
        """Garde-fou anti-chrono-oublié : > 300 min → 400 explicite, pas
        d'écriture. offlinePost ne queue pas les 4xx (APIError propagée)."""
        r = self.post("/api/log_session", {"date": TODAY, "rpe": 7, "duration_min": 301})
        self.assertEqual(400, r.status_code)
        body = self.json(r)
        self.assertEqual("duration_min_implausible", body.get("error"))
        self.assertIn("301", body.get("message", ""))
        self.assertNotIn(TODAY, self.store["sessions"])

    def test_log_session_rejects_extreme_duration(self):
        """Cas réel : chrono resté ouvert 24h → 1491 min, bloqué avant écriture."""
        r = self.post("/api/log_session", {"date": TODAY, "rpe": 8, "duration_min": 1491})
        self.assertEqual(400, r.status_code)
        self.assertEqual("duration_min_implausible", self.json(r).get("error"))

    def test_log_session_accepts_duration_at_threshold(self):
        """Seuil inclusif : 300 min pile → accepté."""
        r = self.post("/api/log_session", {"date": TODAY, "rpe": 7, "duration_min": 300})
        self.assertEqual(200, r.status_code)
        self.assertTrue(self.json(r).get("success"))

    def test_log_session_accepts_normal_duration(self):
        r = self.post("/api/log_session", {"date": TODAY, "rpe": 7, "duration_min": 45})
        self.assertEqual(200, r.status_code)
        self.assertEqual(45, self.store["sessions"][TODAY]["duration_min"])

    def test_log_session_accepts_null_duration(self):
        """Absence de duration_min = non envoyé → aucun check, pas de 400."""
        r = self.post("/api/log_session", {"date": TODAY, "rpe": 7})
        self.assertEqual(200, r.status_code)

    def test_log_session_second_session_allowed(self):
        self.post("/api/log_session", {"date": TODAY, "rpe": 7})
        r = self.post("/api/log_session", {"date": TODAY, "rpe": 6, "second_session": True})
        self.assertEqual(200, r.status_code)


# ── /api/update_session (metadata + exercise mutations) ──────────────────────

class TestUpdateSession(BaseRouteTest):

    def test_update_session_adds_exercise_log(self):
        r = self.post("/api/update_session", {
            "date": "2026-03-10",
            "comment": "updated",
            "exercises": [{
                "action": "add",
                "exercise": "Back Squat",
                "weight": 230.0,
                "reps": "5,5,5,5",
            }],
        })
        self.assertEqual(200, r.status_code)
        entry = next(
            e for e in self.store["weights"]["Back Squat"]["history"]
            if e["date"] == "2026-03-10"
        )
        self.assertEqual(230.0, entry["weight"])
        self.assertEqual("5,5,5,5", entry["reps"])

    def test_update_session_updates_exercise_log(self):
        r = self.post("/api/update_session", {
            "date": "2026-03-10",
            "exercises": [{
                "action": "update",
                "exercise": "Bench Press",
                "weight": 192.5,
                "reps": "6,6,6,5",
            }],
        })
        self.assertEqual(200, r.status_code)
        entry = next(
            e for e in self.store["weights"]["Bench Press"]["history"]
            if e["date"] == "2026-03-10"
        )
        self.assertEqual(192.5, entry["weight"])
        self.assertEqual("6,6,6,5", entry["reps"])

    def test_update_session_deletes_exercise_log(self):
        r = self.post("/api/update_session", {
            "date": "2026-03-10",
            "exercises": [{
                "action": "delete",
                "exercise": "Bench Press",
            }],
        })
        self.assertEqual(200, r.status_code)
        remaining = [
            e for e in self.store["weights"]["Bench Press"]["history"]
            if e["date"] == "2026-03-10"
        ]
        self.assertEqual([], remaining)

    def test_update_session_rejects_missing_weight_or_reps(self):
        r = self.post("/api/update_session", {
            "date": "2026-03-10",
            "exercises": [{
                "action": "update",
                "exercise": "Bench Press",
                "weight": 190.0,
            }],
        })
        self.assertEqual(400, r.status_code)
        data = self.json(r)
        self.assertFalse(data.get("success", True))


# ── /api/log_hiit ────────────────────────────────────────────────────────────

class TestLogHiit(BaseRouteTest):

    def test_log_hiit_success(self):
        r = self.post("/api/log_hiit", {
            "date": TODAY, "session_type": "HIIT", "rounds": 8, "rpe": 8,
        })
        self.assertEqual(200, r.status_code)
        self.assertTrue(self.json(r).get("success"))

    def test_log_hiit_persists(self):
        self.post("/api/log_hiit", {"date": TODAY, "session_type": "HIIT", "rounds": 8})
        entries = [e for e in self.store["hiit_log"] if e["date"] == TODAY]
        self.assertEqual(1, len(entries))

    def test_log_hiit_duplicate_same_type_returns_409(self):
        """Same date + same session_type → 409."""
        self.post("/api/log_hiit", {
            "date": "2026-03-11", "session_type": "Tabata",
        })
        r = self.post("/api/log_hiit", {
            "date": "2026-03-11", "session_type": "Tabata",
        })
        self.assertEqual(409, r.status_code)

    def test_log_hiit_different_type_allowed(self):
        """Same date but different session_type should be allowed."""
        r = self.post("/api/log_hiit", {
            "date": "2026-03-11", "session_type": "Vélo",
        })
        self.assertEqual(200, r.status_code)

    def test_log_hiit_second_session_flag(self):
        self.post("/api/log_hiit", {"date": "2026-03-11", "session_type": "Tabata"})
        r = self.post("/api/log_hiit", {
            "date": "2026-03-11", "session_type": "Tabata", "second_session": True,
        })
        self.assertEqual(200, r.status_code)


# ── /api/delete_hiit ─────────────────────────────────────────────────────────

class TestDeleteHiit(BaseRouteTest):

    def test_delete_by_index(self):
        before = len(self.store["hiit_log"])
        r = self.post("/api/delete_hiit", {"index": 0})
        self.assertEqual(200, r.status_code)
        self.assertEqual(before - 1, len(self.store["hiit_log"]))

    def test_delete_by_date_and_type(self):
        before = len(self.store["hiit_log"])
        r = self.post("/api/delete_hiit", {
            "date": "2026-03-11", "session_type": "Tabata",
        })
        self.assertEqual(200, r.status_code)
        self.assertEqual(before - 1, len(self.store["hiit_log"]))

    def test_delete_nonexistent_returns_400(self):
        r = self.post("/api/delete_hiit", {
            "date": "1900-01-01", "session_type": "Ghost",
        })
        self.assertEqual(400, r.status_code)

    def test_delete_out_of_bounds_index_returns_400(self):
        r = self.post("/api/delete_hiit", {"index": 999})
        self.assertEqual(400, r.status_code)


# ── /api/hiit/edit ───────────────────────────────────────────────────────────

class TestHiitEdit(BaseRouteTest):
    # La route /api/hiit/edit identifie l'entrée par date + session_type
    # et mappe : rpe→rpe, rounds→rounds_completes, notes→comment, feeling→feeling

    _PAYLOAD_BASE = {"date": "2026-03-11", "session_type": "Tabata"}

    def test_edit_rpe(self):
        r = self.post("/api/hiit/edit", {**self._PAYLOAD_BASE, "rpe": 9})
        self.assertEqual(200, r.status_code)
        self.assertEqual(9, self.store["hiit_log"][0]["rpe"])

    def test_edit_comment(self):
        self.post("/api/hiit/edit", {**self._PAYLOAD_BASE, "notes": "tough one"})
        self.assertEqual("tough one", self.store["hiit_log"][0]["comment"])

    def test_edit_feeling(self):
        self.post("/api/hiit/edit", {**self._PAYLOAD_BASE, "feeling": "great"})
        self.assertEqual("great", self.store["hiit_log"][0]["feeling"])

    def test_edit_rounds_completed(self):
        """Le field DB relational est 'rounds_completed' (schema.sql:192).
        Ancien nom KV 'rounds_completes' migré par scripts/migrate_to_relational.py."""
        self.post("/api/hiit/edit", {**self._PAYLOAD_BASE, "rounds": 6})
        self.assertEqual(6, self.store["hiit_log"][0]["rounds_completed"])

    def test_edit_invalid_index_returns_400(self):
        r = self.post("/api/hiit/edit", {"date": "1999-01-01", "session_type": "Inexistant", "rpe": 8})
        self.assertEqual(400, r.status_code)


if __name__ == "__main__":
    import unittest
    unittest.main(verbosity=2)
