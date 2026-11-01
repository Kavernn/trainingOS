"""Tests: /api/session/delete — isolation par session_type.

Garantit que la suppression d'UNE séance (date, session_type) ne touche
jamais les autres session_types de la même date (morning / evening / bonus
indépendants), rejette explicitement les session_types inconnus, retourne
404 si la séance n'existe pas, et n'exécute aucune réinsertion silencieuse
des logs supprimés (ex-vestigial weights.history recompute block).

Mock : le conftest global stocke les sessions par date uniquement — ne
modélise pas morning/evening/bonus en parallèle. Patch local des 3 db funcs
pour tracer la vraie séparation par (date, session_type).
"""
import copy
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

from conftest import BaseRouteTest, TODAY


class _SessionTypeIsolatedMixin:
    """Setup db funcs qui modélisent sessions par (date, session_type)."""

    def _setup_isolated(self):
        self.sessions_by_type = {
            ("2026-03-14", "morning"): {"id": "morning_1"},
            ("2026-03-14", "evening"): {"id": "evening_1"},
            ("2026-03-14", "bonus"):   {"id": "bonus_1"},
        }
        self.deleted_log_session_ids: list = []
        self.deleted_sessions: list = []
        self.reinserted_logs: list = []

        db = sys.modules["db"]
        self._orig_get   = db.get_workout_session_by_type
        self._orig_del_s = db.delete_workout_session_by_type
        self._orig_del_l = db.delete_exercise_logs_for_session

        def _get(date, session_type):
            s = self.sessions_by_type.get((date, session_type))
            return dict(s, date=date, session_type=session_type) if s else None

        def _del_sess(date, session_type="morning"):
            key = (date, session_type)
            self.deleted_sessions.append(key)
            self.sessions_by_type.pop(key, None)
            return True

        def _del_logs(session_id):
            self.deleted_log_session_ids.append(session_id)
            return True

        db.get_workout_session_by_type   = _get
        db.delete_workout_session_by_type = _del_sess
        db.delete_exercise_logs_for_session = _del_logs

    def _teardown_isolated(self):
        db = sys.modules["db"]
        db.get_workout_session_by_type   = self._orig_get
        db.delete_workout_session_by_type = self._orig_del_s
        db.delete_exercise_logs_for_session = self._orig_del_l


class TestSessionDeleteIsolation(_SessionTypeIsolatedMixin, BaseRouteTest):

    def setUp(self):
        super().setUp()
        self._setup_isolated()

    def tearDown(self):
        self._teardown_isolated()
        super().tearDown()

    # ── Isolation par session_type ───────────────────────────────────────

    def test_delete_evening_does_not_touch_morning(self):
        r = self.post("/api/session/delete",
                      {"date": "2026-03-14", "session_type": "evening"})
        self.assertEqual(200, r.status_code)
        self.assertIn(("2026-03-14", "morning"), self.sessions_by_type,
                      "morning doit rester intacte")
        self.assertIn(("2026-03-14", "bonus"), self.sessions_by_type,
                      "bonus doit rester intacte")
        self.assertNotIn(("2026-03-14", "evening"), self.sessions_by_type)
        self.assertEqual(["evening_1"], self.deleted_log_session_ids,
                         "seuls les logs de evening_1 doivent être supprimés")

    def test_delete_morning_does_not_touch_evening_or_bonus(self):
        r = self.post("/api/session/delete",
                      {"date": "2026-03-14", "session_type": "morning"})
        self.assertEqual(200, r.status_code)
        self.assertIn(("2026-03-14", "evening"), self.sessions_by_type)
        self.assertIn(("2026-03-14", "bonus"), self.sessions_by_type)
        self.assertNotIn(("2026-03-14", "morning"), self.sessions_by_type)
        self.assertEqual(["morning_1"], self.deleted_log_session_ids)

    def test_delete_bonus_does_not_touch_morning_or_evening(self):
        r = self.post("/api/session/delete",
                      {"date": "2026-03-14", "session_type": "bonus"})
        self.assertEqual(200, r.status_code)
        self.assertIn(("2026-03-14", "morning"), self.sessions_by_type)
        self.assertIn(("2026-03-14", "evening"), self.sessions_by_type)
        self.assertNotIn(("2026-03-14", "bonus"), self.sessions_by_type)
        self.assertEqual(["bonus_1"], self.deleted_log_session_ids)

    # ── Validation session_type ──────────────────────────────────────────

    def test_delete_invalid_session_type_returns_400(self):
        r = self.post("/api/session/delete",
                      {"date": "2026-03-14", "session_type": "junk"})
        self.assertEqual(400, r.status_code)
        self.assertIn("session_type invalide", self.json(r).get("error", ""))
        # Rien ne doit avoir été supprimé.
        self.assertEqual([], self.deleted_log_session_ids)
        self.assertEqual([], self.deleted_sessions)
        self.assertEqual(3, len(self.sessions_by_type), "aucune suppression")

    # ── 404 explicite ────────────────────────────────────────────────────

    def test_delete_missing_session_returns_404(self):
        r = self.post("/api/session/delete",
                      {"date": "2099-01-01", "session_type": "morning"})
        self.assertEqual(404, r.status_code)
        self.assertEqual([], self.deleted_log_session_ids)
        self.assertEqual([], self.deleted_sessions)

    # ── Pas de réinsertion silencieuse ──────────────────────────────────

    def test_delete_does_not_reinsert_logs(self):
        """Après delete, aucun log de la séance supprimée ne doit être
        réinséré par un side-effect caché (ex-bloc vestigial load_weights +
        bulk_upsert_exercise_logs). L'endpoint ne doit faire QUE :
          1. delete_exercise_logs_for_session(session_id)
          2. delete_workout_session_by_type(date, session_type)
        Aucun autre appel d'écriture ne doit survenir sur exercise_logs."""
        db = sys.modules["db"]
        upsert_calls: list = []
        orig_bulk = getattr(db, "bulk_upsert_exercise_logs", None)
        orig_upsert = getattr(db, "upsert_exercise_log", None)

        def _spy_bulk(entries):
            upsert_calls.append(("bulk_upsert_exercise_logs", list(entries)))
            return True

        def _spy_single(*args, **kwargs):
            upsert_calls.append(("upsert_exercise_log", args, kwargs))
            return True

        db.bulk_upsert_exercise_logs = _spy_bulk
        if orig_upsert is not None:
            db.upsert_exercise_log = _spy_single
        try:
            r = self.post("/api/session/delete",
                          {"date": "2026-03-14", "session_type": "morning"})
            self.assertEqual(200, r.status_code)
            self.assertEqual([], upsert_calls,
                             "aucun upsert d'exercise_logs ne doit suivre un delete")
        finally:
            if orig_bulk is not None:
                db.bulk_upsert_exercise_logs = orig_bulk
            if orig_upsert is not None:
                db.upsert_exercise_log = orig_upsert
