"""DNA sections d — PPL / Intensité / Patterns.

Garantit :
  1. _classify_ppl : Deadlift / RDL → legs (pas pull). Curl → pull.
  2. Les 3 fonctions excluent les séances pendant une période de décharge
     enregistrée (is_deload_day).
  3. Garde-fou MIN_SESSIONS_PER_SECTION = 8 : sous le seuil →
     insufficient_data=True, pas de verdict/score inventé.
  4. Fallback explicite : exos sans load_profile / movement_pattern comptés
     dans excluded_no_load_profile / excluded_no_pattern (plus de score=50
     silencieux ni d'ignore muet).
"""
from __future__ import annotations

import sys
from datetime import date, timedelta
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "api"))


TODAY = date(2026, 10, 15)
PERIOD_DAYS = 90


@pytest.fixture
def pinned_today(monkeypatch):
    monkeypatch.setattr("utils._today_mtl", lambda: TODAY.isoformat())
    return TODAY


@pytest.fixture
def no_deload(monkeypatch):
    monkeypatch.setattr("db.get_deload_periods", lambda: [])


def _entry(day: date, *, sets=1):
    return {"date": day.isoformat(), "weight": 100, "reps": "5",
            "sets": [{"weight": 100, "reps": 5} for _ in range(sets)]}


def _mk_8_sessions_bench():
    """8 séances de Bench Press étalées sur 56 jours — passe le seuil.

    Toutes AVANT 2026-09-25 pour laisser la décharge test (2026-10-01→07)
    inoccupée côté hors-décharge. Permet aux tests d'injecter 3 séances
    décharge en plus et vérifier que n_sessions reste à 8.
    """
    base = date(2026, 9, 20)
    return [_entry(base - timedelta(days=i * 7)) for i in range(8)]


# ── 1. Classification PPL ─────────────────────────────────────────────────────

def test_classify_ppl_deadlift_is_legs():
    import workout_dna as _dna
    assert _dna._classify_ppl("", "Conventional Deadlift") == "legs"
    assert _dna._classify_ppl("", "Romanian Deadlift") == "legs"
    assert _dna._classify_ppl("", "RDL") == "legs"
    # Par catégorie aussi
    assert _dna._classify_ppl("Deadlift", "") == "legs"


def test_classify_ppl_curl_stays_pull():
    import workout_dna as _dna
    assert _dna._classify_ppl("", "Barbell Curl") == "pull"
    assert _dna._classify_ppl("Biceps", "Hammer Curl") == "pull"


def test_classify_ppl_hip_thrust_is_legs():
    import workout_dna as _dna
    assert _dna._classify_ppl("", "Hip Thrust") == "legs"


# ── 2. Garde-fou MIN_SESSIONS_PER_SECTION pour PPL / Intensité / Patterns ────

def test_ppl_insufficient_data_under_8_sessions(pinned_today, no_deload):
    import workout_dna as _dna
    history = {"Bench Press": [_entry(TODAY - timedelta(days=i * 7)) for i in range(5)]}
    ex_info = {"Bench Press": {"category": "chest", "load_profile": "compound_heavy",
                               "movement_pattern": "push_horizontal"}}
    result = _dna._compute_ppl(history, ex_info, period_days=PERIOD_DAYS)
    assert result["insufficient_data"] is True
    assert result["n_sessions"] == 5
    assert "push_pct" not in result, "pas de verdict inventé sous le seuil"


def test_intensity_insufficient_data_under_8_sessions(pinned_today, no_deload):
    import workout_dna as _dna
    history = {"Bench Press": [_entry(TODAY - timedelta(days=i * 7)) for i in range(5)]}
    ex_info = {"Bench Press": {"load_profile": "compound_heavy"}}
    result = _dna._compute_intensity(history, ex_info, period_days=PERIOD_DAYS)
    assert result["insufficient_data"] is True
    assert "score" not in result, "pas de score fantôme à 50"


def test_patterns_insufficient_data_under_8_sessions(pinned_today, no_deload):
    import workout_dna as _dna
    history = {"Bench Press": [_entry(TODAY - timedelta(days=i * 7)) for i in range(5)]}
    ex_info = {"Bench Press": {"movement_pattern": "push_horizontal"}}
    result = _dna._compute_movement_patterns(history, ex_info, period_days=PERIOD_DAYS)
    assert result["insufficient_data"] is True
    assert result["patterns"] == []


# ── 3. Exclusion décharge ─────────────────────────────────────────────────────

def test_ppl_excludes_deload_sessions(pinned_today, monkeypatch):
    import workout_dna as _dna
    monkeypatch.setattr("db.get_deload_periods", lambda: [{
        "started_at":    "2026-10-01",
        "scheduled_end": "2026-10-07",
        "completed_at":  "2026-10-07",
        "duration_days": 7,
        "reason":        "test",
    }])
    # 8 séances hors décharge, puis 3 séances dans la décharge.
    history = {
        "Bench Press": _mk_8_sessions_bench()
                       + [_entry(date(2026, 10, 2 + i), sets=5) for i in range(3)]
    }
    ex_info = {"Bench Press": {"category": "chest", "load_profile": "compound_heavy",
                               "movement_pattern": "push_horizontal"}}
    result = _dna._compute_ppl(history, ex_info, period_days=PERIOD_DAYS)
    assert result["insufficient_data"] is False
    # n_sessions = 8 (les 3 séances décharge sont exclues)
    assert result["n_sessions"] == 8
    # push_pct devrait être 100 (bench seul) peu importe les séances décharge
    # — mais surtout, le push count ne doit PAS inclure les 3 × 5 = 15 sets décharge.
    # Les 8 séances légitimes contribuent 8 × 1 = 8 sets.
    # Si les sets décharge comptaient, le total serait 8 + 15 = 23, et core/other
    # pcts changeraient. Ici tout tombe push donc on vérifie indirect :
    assert result["push_pct"] == 100


def test_intensity_excludes_deload_sessions(pinned_today, monkeypatch):
    import workout_dna as _dna
    monkeypatch.setattr("db.get_deload_periods", lambda: [{
        "started_at":    "2026-10-01",
        "scheduled_end": "2026-10-07",
        "completed_at":  "2026-10-07",
        "duration_days": 7,
        "reason":        "test",
    }])
    history = {
        "Bench Press": _mk_8_sessions_bench()
                       + [_entry(date(2026, 10, 2 + i)) for i in range(3)]
    }
    ex_info = {"Bench Press": {"load_profile": "compound_heavy"}}
    result = _dna._compute_intensity(history, ex_info, period_days=PERIOD_DAYS)
    assert result["insufficient_data"] is False
    assert result["n_sessions"] == 8


def test_patterns_excludes_deload_sessions(pinned_today, monkeypatch):
    import workout_dna as _dna
    monkeypatch.setattr("db.get_deload_periods", lambda: [{
        "started_at":    "2026-10-01",
        "scheduled_end": "2026-10-07",
        "completed_at":  "2026-10-07",
        "duration_days": 7,
        "reason":        "test",
    }])
    history = {
        "Bench Press": _mk_8_sessions_bench()
                       + [_entry(date(2026, 10, 2 + i), sets=10) for i in range(3)]
    }
    ex_info = {"Bench Press": {"movement_pattern": "push_horizontal"}}
    result = _dna._compute_movement_patterns(history, ex_info, period_days=PERIOD_DAYS)
    assert result["insufficient_data"] is False
    assert result["n_sessions"] == 8
    assert result["total_sets"] == 8  # 8 × 1, pas 8 + 30 des sets décharge


# ── 4. Fallbacks explicites (load_profile / movement_pattern manquants) ──────

def test_intensity_excludes_exercises_without_load_profile(pinned_today, no_deload):
    import workout_dna as _dna
    history = {
        "Bench Press":  _mk_8_sessions_bench(),
        "Mystery Lift": [_entry(TODAY - timedelta(days=i * 10)) for i in range(5)],
    }
    ex_info = {
        "Bench Press":  {"load_profile": "compound_heavy"},
        "Mystery Lift": {"load_profile": None},  # catalogue manquant
    }
    result = _dna._compute_intensity(history, ex_info, period_days=PERIOD_DAYS)
    assert result["insufficient_data"] is False
    assert result["excluded_no_load_profile"] == 1, (
        "Mystery Lift sans load_profile → compté dans excluded, pas score 50 fantôme"
    )
    # Score basé uniquement sur Bench Press
    assert result["n_sessions"] == 8


def test_patterns_excludes_exercises_without_pattern(pinned_today, no_deload):
    import workout_dna as _dna
    history = {
        "Bench Press":  _mk_8_sessions_bench(),
        "Mystery Lift": [_entry(TODAY - timedelta(days=i * 10)) for i in range(5)],
    }
    ex_info = {
        "Bench Press":  {"movement_pattern": "push_horizontal"},
        "Mystery Lift": {"movement_pattern": ""},  # catalogue manquant
    }
    result = _dna._compute_movement_patterns(history, ex_info, period_days=PERIOD_DAYS)
    assert result["insufficient_data"] is False
    assert result["excluded_no_pattern"] == 1, (
        "Mystery Lift sans movement_pattern → compté dans excluded, pas ignoré silencieusement"
    )


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
