from unittest.mock import MagicMock, patch
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))
import db_programs


def _mk_client_full(session_row: dict) -> MagicMock:
    """Mock supabase-py chain for a single session return from get_full_program."""
    c = MagicMock()
    c.table.return_value.select.return_value.order.return_value.execute.return_value.data = [session_row]
    c.table.return_value.select.return_value.order.return_value.eq.return_value.execute.return_value.data = [session_row]
    return c


def test_T1_get_full_program_force_block_preserves_type_and_exos():
    """Bloc type='force' avec 2 exos -> rendu en branche reps, type conservé."""
    session = {
        "id": "s1", "name": "Test Session", "order_index": 0,
        "program_blocks": [{
            "id": "b1", "type": "force", "order_index": 0, "hiit_config": {},
            "program_block_exercises": [
                {"order_index": 0, "scheme": "4x5-8",
                 "exercises": {"id": "e1", "name": "Back Squat"}},
                {"order_index": 1, "scheme": "3x8-10",
                 "exercises": {"id": "e2", "name": "Romanian Deadlift"}},
            ],
        }],
    }
    with patch.object(db_programs, "db_core") as dbc:
        dbc._client = _mk_client_full(session)
        dbc.MODE = "ONLINE"
        out = db_programs.get_full_program()
    blk = out["Test Session"]["blocks"][0]
    assert blk["type"] == "force", f"type doit etre 'force', pas {blk['type']!r}"
    assert blk["exercises"] == {"Back Squat": "4x5-8", "Romanian Deadlift": "3x8-10"}
    assert "hiit_config" not in blk


def test_T2_get_full_program_hiit_block_non_regression():
    """Bloc type='hiit' -> rendu en branche else avec hiit_config (Locked In 2027 safe)."""
    session = {
        "id": "s2", "name": "HIIT Day", "order_index": 0,
        "program_blocks": [{
            "id": "b2", "type": "hiit", "order_index": 0,
            "hiit_config": {"rounds": 5, "work": 30, "rest": 15},
            "program_block_exercises": [],
        }],
    }
    with patch.object(db_programs, "db_core") as dbc:
        dbc._client = _mk_client_full(session)
        dbc.MODE = "ONLINE"
        out = db_programs.get_full_program()
    blk = out["HIIT Day"]["blocks"][0]
    assert blk["type"] == "hiit"
    assert blk["hiit_config"] == {"rounds": 5, "work": 30, "rest": 15}
    assert "exercises" not in blk


def test_T3_get_session_supersets_filter_covers_reps_blocks():
    """Le filtre .in_ doit inclure 'force' (pas seulement 'strength')."""
    calls = {}
    c = MagicMock()
    def _in_(col, vals):
        calls["in_col"], calls["in_vals"] = col, list(vals)
        c.table.return_value.select.return_value.eq.return_value.in_.return_value.execute.return_value.data = []
        return c.table.return_value.select.return_value.eq.return_value.in_.return_value
    c.table.return_value.select.return_value.order.return_value.execute.return_value.data = [{"id": "s1", "name": "X"}]
    c.table.return_value.select.return_value.eq.return_value.in_.side_effect = _in_
    with patch.object(db_programs, "db_core") as dbc:
        dbc._client = c
        dbc.MODE = "ONLINE"
        db_programs.get_session_supersets()
    assert calls["in_col"] == "type"
    assert "force" in calls["in_vals"]
    assert "strength" in calls["in_vals"]
    assert "hiit" not in calls["in_vals"]
    assert "cardio" not in calls["in_vals"]


def test_T4_save_full_program_force_block_inserts_exercises():
    """Bloc {type:'force', exercises:{...}} → payload RPC contient l'exercice
    sous forme d'array (migration 101 : contrat jsonb array pour l'ordre)."""
    service = MagicMock()
    service.rpc.return_value.execute.return_value.data = {
        "skipped_empty_blocks": [], "renamed_exercise": None,
    }
    with patch.object(db_programs, "db_core") as dbc:
        dbc._client = MagicMock()
        dbc.MODE   = "ONLINE"
        dbc.get_service_supabase.return_value = service
        db_programs.save_full_program(
            {"Test": {"blocks": [{"type": "force", "order": 0,
                                  "exercises": {"Back Squat": "4x5-8"}}]}},
            program_id="prog1",
        )
    args = service.rpc.call_args.args
    assert args[0] == "save_full_program_atomic"
    sessions = args[1]["p_sessions"]
    assert sessions == [{
        "name": "Test",
        "blocks": [{
            "type": "force", "order": 0, "hiit_config": {},
            "exercises": [{"name": "Back Squat", "scheme": "4x5-8"}],
        }],
    }], f"Payload RPC inattendu : {sessions}"


if __name__ == "__main__":
    test_T1_get_full_program_force_block_preserves_type_and_exos()
    test_T2_get_full_program_hiit_block_non_regression()
    test_T3_get_session_supersets_filter_covers_reps_blocks()
    test_T4_save_full_program_force_block_inserts_exercises()
    print("OK T1 T2 T3 T4 pass")
