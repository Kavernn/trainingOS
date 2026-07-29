"""Dédoublonnage central de get_all_exercise_history (chantier stats 2026-07-28).

4 cas :
- solo → inchangé
- doublon (riche + vide, même exo/date) → 1 row (la riche)
- deux vides même exo/date → 1 row (dédupliqué, reste vide)
- deux non-vides distinctes (matin+bonus réels) → 2 rows (défensif)

Invariant restoreLogResults : la row survivante d'un dédoublonnage porte le
session_type de la row la plus riche (pas la vide).
"""
from unittest.mock import MagicMock, patch


def _mock_client(rows):
    client = MagicMock()
    chain = client.table.return_value.select.return_value
    chain.gte.return_value = chain
    chain.range.return_value.execute.return_value.data = rows
    return client


def _row(name, date, session_type, weight, reps, sets_json):
    return {
        "weight": weight,
        "reps": reps,
        "sets_json": sets_json,
        "exercises": {"name": name},
        "workout_sessions": {"date": date, "session_type": session_type},
    }


def _run(rows):
    import db_core, db_sessions
    with patch.object(db_core, "_client", _mock_client(rows)), \
         patch.object(db_core, "MODE", "ONLINE"):
        return db_sessions.get_all_exercise_history(cutoff_days=180)


def test_solo_unchanged():
    result = _run([_row("Bench", "2026-07-15", "morning", 100.0, "10,10,10",
                        [{"weight": 100, "reps": 10, "set_volume": 1000}])])
    assert list(result.keys()) == ["Bench"]
    assert len(result["Bench"]) == 1
    assert result["Bench"][0]["session_type"] == "morning"


def test_dupe_rich_plus_empty_keeps_rich():
    rows = [
        _row("Bench", "2026-07-15", "bonus", 100.0, "10,10", []),
        _row("Bench", "2026-07-15", "morning", 100.0, "10,10,10",
             [{"weight": 100, "reps": 10, "set_volume": 1000}]),
    ]
    r = _run(rows)["Bench"]
    assert len(r) == 1
    assert r[0]["session_type"] == "morning"
    assert r[0]["sets"], "row survivante doit avoir les sets non-vides"


def test_dupe_both_empty_compacts_to_one():
    rows = [
        _row("Bench", "2026-07-15", "morning", 100.0, "10,10", []),
        _row("Bench", "2026-07-15", "bonus", 100.0, "10,10", []),
    ]
    r = _run(rows)["Bench"]
    assert len(r) == 1
    assert "sets" not in r[0]


def test_two_distinct_non_empty_kept_defensive():
    sets_a = [{"weight": 100, "reps": 10, "set_volume": 1000}]
    sets_b = [{"weight": 80, "reps": 12, "set_volume": 960}]
    rows = [
        _row("Bench", "2026-07-15", "morning", 100.0, "10", sets_a),
        _row("Bench", "2026-07-15", "bonus", 80.0, "12", sets_b),
    ]
    r = _run(rows)["Bench"]
    assert len(r) == 2, "matin+bonus légitimes distincts → garder les deux"
