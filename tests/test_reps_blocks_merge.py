"""Tests fusion REPS_BLOCKS pour get_strength_exercises / get_strength_exercise_ids."""
from blocks import get_strength_exercises, get_strength_exercise_ids, REPS_BLOCKS
import db_programs


def test_T1_v4_multi_blocks_ordered():
    session_def = {"blocks": [
        {"type": "isolation", "order": 0, "exercises": {
            "Leg Curl": "3x10", "Leg Extension": "3x12",
            "Adductor Machine": "3x15", "Abductor Machine": "3x15"}},
        {"type": "core", "order": 1, "exercises": {
            "Plank": "3x60s", "Hanging Leg Raise": "3x12",
            "Cable Crunch": "3x15", "Russian Twist": "3x20", "Dead Bug": "3x10"}},
    ]}
    result = get_strength_exercises(session_def)
    assert len(result) == 9
    keys = list(result.keys())
    assert keys[:4] == ["Leg Curl", "Leg Extension", "Adductor Machine", "Abductor Machine"]
    assert keys[4:] == ["Plank", "Hanging Leg Raise", "Cable Crunch", "Russian Twist", "Dead Bug"]


def test_T1b_order_respected_when_blocks_unsorted():
    # blocs volontairement dans le desordre : le tri par 'order' doit re-ordonner
    session_def = {"blocks": [
        {"type": "core", "order": 1, "exercises": {"Plank": "3x60s"}},
        {"type": "mobility", "order": 0, "exercises": {"Stretch": "2x30s"}},
    ]}
    keys = list(get_strength_exercises(session_def).keys())
    assert keys == ["Stretch", "Plank"], f"tri par order casse: {keys}"


def test_T2_ids_same_keys():
    session_def = {"blocks": [
        {"type": "isolation", "order": 0,
         "exercises": {"Leg Curl": "3x10", "Leg Extension": "3x12"},
         "exercise_ids": {"Leg Curl": "id-1", "Leg Extension": "id-2"}},
        {"type": "core", "order": 1,
         "exercises": {"Plank": "3x60s"},
         "exercise_ids": {"Plank": "id-5"}},
    ]}
    exos = get_strength_exercises(session_def)
    ids = get_strength_exercise_ids(session_def)
    assert set(exos.keys()) == set(ids.keys())
    assert all(v for v in ids.values())


def test_T3_LI2027_mono_strength_unchanged():
    session_def = {"blocks": [
        {"type": "strength", "order": 0,
         "exercises": {"Squat": "3x5", "Bench": "3x5", "Row": "3x8-12"}},
    ]}
    result = get_strength_exercises(session_def)
    assert result == {"Squat": "3x5", "Bench": "3x5", "Row": "3x8-12"}
    assert list(result.keys()) == ["Squat", "Bench", "Row"]


def test_T4_legacy_flat_unchanged():
    session_def = {"Squat": "3x8-12", "Bench": "3x5"}
    assert get_strength_exercises(session_def) == session_def
    assert get_strength_exercise_ids(session_def) == {}


def test_T5_reps_blocks_reference_intact():
    assert db_programs.REPS_BLOCKS is REPS_BLOCKS
    assert REPS_BLOCKS == frozenset({
        "strength", "force", "isolation", "core",
        "mobility", "explosive", "finisher"})


def test_T6_no_circular_import():
    import blocks as _blocks
    import db_programs as _dbp
    assert _blocks.REPS_BLOCKS is _dbp.REPS_BLOCKS
