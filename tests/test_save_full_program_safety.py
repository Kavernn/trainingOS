"""
Tests : save_full_program (db_programs.py) — contrat RPC atomique (migration 101).

Avant : séquence N appels PostgREST, pattern upsert-puis-delete pour éviter la
perte en cas d'échec intermédiaire. Après 2026-11 : une seule RPC plpgsql
`save_full_program_atomic` — l'atomicité est garantie par la transaction
Postgres (toute exception → rollback intégral). Les tests Python se limitent
à valider le wiring :
  - payload correctement sérialisé (dict → arrays, exercises dict → array
    d'objets {name, scheme}) pour préserver l'ordre.
  - le `rename` param est passé tel quel.
  - échec RPC → RuntimeError (pas de False silencieux, pas de repli séquentiel).
  - réponse jsonb décapsulée vers dict Python.
"""
import os
import sys
import unittest
from unittest.mock import MagicMock, patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))


class TestSaveFullProgramAtomic(unittest.TestCase):
    """Wiring Python → RPC save_full_program_atomic."""

    def setUp(self):
        import db_core
        self._orig_mode = db_core.MODE
        self._orig_client = db_core._client
        db_core.MODE = "ONLINE"
        db_core._client = MagicMock()
        self.service = MagicMock()
        self.service.rpc.return_value.execute.return_value.data = {
            "skipped_empty_blocks": [],
            "renamed_exercise":     None,
        }
        self._svc_patch = patch.object(db_core, "get_service_supabase",
                                        return_value=self.service)
        self._svc_patch.start()

    def tearDown(self):
        self._svc_patch.stop()
        import db_core
        db_core._client = self._orig_client
        db_core.MODE = self._orig_mode

    def test_sessions_serialized_as_array_preserving_order(self):
        """Python dict → JSON array pour préserver l'ordre d'insertion."""
        import db_programs
        db_programs.save_full_program(
            {"B_second": {"blocks": []}, "A_first": {"blocks": []}},
            program_id="pid-1",
        )
        args = self.service.rpc.call_args
        self.assertEqual(args.args[0], "save_full_program_atomic")
        sessions = args.args[1]["p_sessions"]
        self.assertEqual([s["name"] for s in sessions], ["B_second", "A_first"])

    def test_exercises_serialized_as_array_of_objects(self):
        """exercises dict {name: scheme} → array [{name, scheme}] pour l'ordre."""
        import db_programs
        db_programs.save_full_program(
            {"Upper": {"blocks": [{
                "type": "strength", "order": 0,
                "exercises": {"Bench": "4x5", "Squat": "3x8"},
            }]}},
            program_id="pid-1",
        )
        exos = self.service.rpc.call_args.args[1]["p_sessions"][0]["blocks"][0]["exercises"]
        self.assertEqual(exos, [{"name": "Bench", "scheme": "4x5"},
                                {"name": "Squat", "scheme": "3x8"}])

    def test_rename_param_passed_through(self):
        import db_programs
        db_programs.save_full_program(
            {"Upper": {"blocks": []}},
            program_id="pid-1",
            rename={"old_name": "Old", "new_name": "New"},
        )
        self.assertEqual(
            self.service.rpc.call_args.args[1]["p_rename"],
            {"old_name": "Old", "new_name": "New"},
        )

    def test_rpc_exception_raises_runtimeerror(self):
        """Un échec RPC lève — plus de False silencieux. Le caller traduit en 500."""
        import db_programs
        self.service.rpc.return_value.execute.side_effect = RuntimeError("supabase 503")
        with self.assertRaises(RuntimeError):
            db_programs.save_full_program(
                {"Upper": {"blocks": []}},
                program_id="pid-1",
            )

    def test_report_returned_as_dict(self):
        """Réponse jsonb → dict Python avec skipped_empty_blocks et renamed_exercise."""
        import db_programs
        self.service.rpc.return_value.execute.return_value.data = {
            "skipped_empty_blocks": [{"session_name": "X", "block_type": "strength",
                                      "block_order": 0, "existing_count": 3}],
            "renamed_exercise":     {"old_name": "A", "new_name": "B",
                                     "exercise_id": "uuid-1"},
        }
        report = db_programs.save_full_program(
            {"Upper": {"blocks": []}},
            program_id="pid-1",
        )
        self.assertEqual(len(report["skipped_empty_blocks"]), 1)
        self.assertEqual(report["renamed_exercise"]["new_name"], "B")

    def test_hiit_block_has_no_exercises_array(self):
        """Blocks hiit/cardio ne portent pas d'exercises relationnels."""
        import db_programs
        db_programs.save_full_program(
            {"HIIT": {"blocks": [{
                "type": "hiit", "order": 0,
                "hiit_config": {"rounds": 8, "sprint": 30, "rest": 30},
            }]}},
            program_id="pid-1",
        )
        block = self.service.rpc.call_args.args[1]["p_sessions"][0]["blocks"][0]
        self.assertNotIn("exercises", block)
        self.assertEqual(block["hiit_config"]["rounds"], 8)


if __name__ == "__main__":
    unittest.main()
