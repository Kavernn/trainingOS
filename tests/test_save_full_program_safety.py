"""
Tests : save_full_program (db_programs.py) ne perd AUCUN exercice même si
une écriture intermédiaire échoue.

Ancien pattern dangereux : DELETE all exercises for block → INSERT 1-par-1.
Un échec au milieu laissait le bloc avec 0..N exos (les inserts qui avaient
eu le temps de passer) alors que N exos existaient avant → perte.

Nouveau pattern :
  1) UPSERT bulk (on_conflict=(block_id, exercise_id)) → si échec, rien
     n'est supprimé.
  2) DELETE sélectif des anciens (not.in nouveaux ids) → si échec, pire
     cas = lignes orphelines, jamais une perte.

Routes couvertes : fonction db_programs.save_full_program (appelée en aval
par /api/programme actions add/remove/scheme/rename/replace/reorder/...).
"""
import os
import sys
import unittest
from unittest.mock import MagicMock, patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))


def _make_mock_client():
    """Construit un mock Supabase client qui enregistre la séquence des calls
    (upsert / delete / insert) pour ce test. Chaque .table(...).*.execute()
    retourne un objet avec .data = [] par défaut (success-ish)."""
    client = MagicMock()
    # execute() default returns data=[] (ex_id not found → auto-create path).
    client.table.return_value.select.return_value.eq.return_value.execute.return_value.data = []
    return client


class TestSaveFullProgramSafety(unittest.TestCase):
    """Vérifie l'ordre upsert→delete et le fail-safe (aucun exo perdu)."""

    def setUp(self):
        # Reload db_programs with a fresh mocked db_core
        import db_core
        self._original_client = db_core._client
        self._original_mode = db_core.MODE
        db_core.MODE = "ONLINE"
        db_core._client = _make_mock_client()

    def tearDown(self):
        import db_core
        db_core._client = self._original_client
        db_core.MODE = self._original_mode

    def _mock_exercise_ids(self, client, name_to_id):
        """Configure le mock : exercises.select.eq(name=NAME).execute() → data=[{'id': ID}]."""
        def select_side_effect(*args, **kwargs):
            selector = MagicMock()
            def eq_side_effect(col, value):
                result_builder = MagicMock()
                if col == "name" and value in name_to_id:
                    result_builder.execute.return_value.data = [{"id": name_to_id[value]}]
                else:
                    result_builder.execute.return_value.data = []
                return result_builder
            selector.eq.side_effect = eq_side_effect
            return selector
        # Only override the "exercises" table .select path; keep .table() for others.
        original_table = client.table
        def table_side_effect(name):
            t = original_table(name)
            if name == "exercises":
                t.select.side_effect = select_side_effect
            return t
        client.table.side_effect = table_side_effect

    def _mock_sessions_upsert(self, client, session_id=42):
        """Mock /program_sessions/upsert → return + select single returns session_id."""
        def table_side_effect(name):
            t = MagicMock()
            if name == "program_sessions":
                # upsert().execute().data = [...]
                t.upsert.return_value.execute.return_value.data = [{"id": session_id}]
                # select("id").eq(name=...).eq(program_id=...).single().execute().data
                sel = MagicMock()
                sel.eq.return_value.eq.return_value.single.return_value.execute.return_value.data = {"id": session_id}
                sel.eq.return_value.single.return_value.execute.return_value.data = {"id": session_id}
                t.select.return_value = sel
            elif name == "program_blocks":
                # existing_block.data = [] → insert path
                sel = MagicMock()
                sel.eq.return_value.eq.return_value.eq.return_value.execute.return_value.data = []
                t.select.return_value = sel
                t.insert.return_value.execute.return_value.data = [{"id": 100}]
            return t
        client.table.side_effect = table_side_effect
        return client

    def test_upsert_called_before_delete(self):
        """Le bulk upsert doit précéder le delete sélectif pour que rien
        ne soit supprimé tant que les nouvelles lignes n'existent pas."""
        import db_programs
        client = _make_mock_client()
        self._mock_sessions_upsert(client, session_id=42)
        # Track sequence on program_block_exercises specifically.
        pbe = MagicMock()
        call_log = []
        pbe.upsert.side_effect = lambda *a, **k: (call_log.append(("upsert", a, k)), MagicMock(execute=MagicMock(return_value=MagicMock(data=[]))))[1]
        pbe.delete.side_effect = lambda *a, **k: (call_log.append(("delete", a, k)), MagicMock(eq=MagicMock(return_value=MagicMock(filter=MagicMock(return_value=MagicMock(execute=MagicMock(return_value=MagicMock(data=[])))))))) [1]

        original_side = client.table.side_effect
        def hooked(name):
            if name == "program_block_exercises":
                return pbe
            if name == "exercises":
                t = MagicMock()
                # Return existing exercise ids to avoid auto-create branch
                sel = MagicMock()
                sel.eq.return_value.execute.return_value.data = [{"id": 999}]
                t.select.return_value = sel
                return t
            return original_side(name)
        client.table.side_effect = hooked

        import db_core
        db_core._client = client

        program = {"Upper A": {"blocks": [{
            "type": "strength", "order": 0,
            "exercises": {"Bench Press": "4x5"},
        }]}}
        ok = db_programs.save_full_program(program, program_id="pid-1")
        self.assertTrue(ok)

        # Séquence attendue : upsert AVANT delete
        ops = [c[0] for c in call_log]
        self.assertIn("upsert", ops, "bulk upsert attendu sur program_block_exercises")
        self.assertIn("delete", ops, "delete sélectif attendu")
        self.assertLess(ops.index("upsert"), ops.index("delete"),
                        "upsert doit précéder delete (safety-ordered)")

    def test_upsert_failure_leaves_old_rows_intact(self):
        """Si l'upsert bulk échoue, le delete en aval NE DOIT PAS se produire
        → aucune ligne ancienne n'est supprimée."""
        import db_programs
        client = _make_mock_client()
        self._mock_sessions_upsert(client, session_id=42)
        pbe = MagicMock()
        delete_called = {"n": 0}
        # upsert raise
        pbe.upsert.return_value.execute.side_effect = RuntimeError("supabase 503")
        def delete_tracker(*a, **k):
            delete_called["n"] += 1
            return MagicMock(eq=MagicMock(return_value=MagicMock(filter=MagicMock(return_value=MagicMock(execute=MagicMock())))))
        pbe.delete.side_effect = delete_tracker

        original_side = client.table.side_effect
        def hooked(name):
            if name == "program_block_exercises":
                return pbe
            if name == "exercises":
                t = MagicMock()
                sel = MagicMock()
                sel.eq.return_value.execute.return_value.data = [{"id": 999}]
                t.select.return_value = sel
                return t
            return original_side(name)
        client.table.side_effect = hooked

        import db_core
        db_core._client = client

        program = {"Upper A": {"blocks": [{
            "type": "strength", "order": 0,
            "exercises": {"Bench Press": "4x5"},
        }]}}
        ok = db_programs.save_full_program(program, program_id="pid-1")
        # Retry path kicks in on exception → may still return False after retry failure.
        # Key assertion : le delete n'a jamais été appelé pour ce block → aucune perte.
        self.assertFalse(ok, "upsert failure doit renvoyer False")
        self.assertEqual(0, delete_called["n"],
                         "delete NE DOIT PAS être appelé quand l'upsert échoue — sinon on perd les anciens exos")


if __name__ == "__main__":
    unittest.main()
