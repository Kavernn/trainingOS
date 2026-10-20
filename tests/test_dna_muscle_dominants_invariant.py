"""DNA muscle dominants = summarize_muscle_workload (source canonique).

Invariant du commit a1 : pour la même fenêtre et les mêmes données brutes,
`effective_sets` par muscle dans DNA == `direct + 0,5 × indirect` du cockpit
(summarize_muscle_workload). Mêmes noms de muscles canoniques des deux côtés
— preuve que DNA ne recalcule plus et consomme la source unique.
"""
from __future__ import annotations

import sys
from datetime import date, timedelta
from pathlib import Path
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "api"))


# ── Fakes partagés (miroir test_cockpit_muscles_previous_and_deload) ─────────

def _row(log_id, session_id, day, *, name="Bench", group="Chest", sets=1):
    return {
        "id": str(log_id),
        "session_id": session_id,
        "exercise_id": f"id-{name}",
        "weight": 100,
        "reps": "5",
        "sets_json": [{"weight": 100, "reps": 5} for _ in range(sets)],
        "workout_sessions": {"date": day.isoformat()},
        "exercises": {
            "name":              name,
            "tracking_type":     "reps",
            "muscle_group":      group,
            "muscle_specific":   None,
            "secondary_muscles": [],
        },
    }


class _FakeQuery:
    def __init__(self, rows): self.rows = rows
    def select(self, _): return self
    def gte(self, *_): return self
    def lte(self, *_): return self
    def execute(self): return type("R", (), {"data": self.rows})()


class _FakeClient:
    def __init__(self, rows): self.rows = rows
    def table(self, _): return _FakeQuery(self.rows)


TODAY = date(2026, 10, 15)
WINDOW_DAYS = 90


def _mk_rows():
    """8+ séances distinctes pour franchir le seuil MIN_SESSIONS_PER_SECTION=8.
    3 muscles : Chest (Bench), Lats (Row), Biceps (secondary de Row)."""
    rows = []
    log_id = 0
    # 5 Bench sessions (direct Chest)
    for i in range(5):
        log_id += 1
        rows.append(_row(log_id, f"s-bench-{i}", TODAY - timedelta(days=i * 3),
                         name="Bench", group="Chest", sets=3))
    # 4 Row sessions (direct Lats + indirect Biceps)
    for i in range(4):
        log_id += 1
        r = _row(log_id, f"s-row-{i}", TODAY - timedelta(days=1 + i * 3),
                 name="Row", group="Lats", sets=2)
        r["exercises"]["secondary_muscles"] = ["Biceps"]
        rows.append(r)
    return rows


@pytest.fixture
def pinned_today(monkeypatch):
    pinned = TODAY.isoformat()
    monkeypatch.setattr("utils._today_mtl", lambda: pinned)
    return TODAY


@pytest.fixture
def no_deload(monkeypatch):
    """Aucune période de décharge → is_deload_day retourne toujours False."""
    monkeypatch.setattr("db.get_deload_periods", lambda: [])


def test_dna_effective_sets_equals_cockpit_weekly_effective_sets(pinned_today, no_deload):
    """Pour la même fenêtre et les mêmes rows, DNA.effective_sets ==
    MuscleWorkload.weekly_effective_sets du cockpit (séries effectives /
    semaine, hors décharge au numérateur ET au dénominateur). Mêmes noms
    canoniques des deux côtés."""
    from analytics_adapter import fetch_raw_analytics_rows, adapt_analytics_rows, is_deload_day
    from metric_semantics import DateWindow
    from muscle_workload_analytics import summarize_muscle_workload
    import workout_dna as _dna

    rows = _mk_rows()
    client = _FakeClient(rows)
    period = DateWindow(pinned_today - timedelta(days=WINDOW_DAYS - 1), pinned_today)

    dna_muscles, dna_meta = _dna._compute_muscle_dominants(client, period_days=WINDOW_DAYS)
    assert dna_meta["insufficient_data"] is False, (
        f"Attendu ≥ 8 sessions, obtenu {dna_meta['n_sessions']}"
    )
    assert dna_muscles, "Attendu au moins un muscle dans le top-6"

    adapted = adapt_analytics_rows(fetch_raw_analytics_rows(client, period=period), period=period)
    cockpit_summary = summarize_muscle_workload(
        adapted.training_load_exposures,
        adapted.assignments,
        period=period,
        is_deload=lambda d: is_deload_day(d),
    )
    cockpit_by_muscle = {m.muscle: m.weekly_effective_sets for m in cockpit_summary.muscles}

    for entry in dna_muscles:
        name = entry["muscle"]
        assert name in cockpit_by_muscle, (
            f"Muscle DNA '{name}' absent du cockpit — fusion canonique divergente"
        )
        expected = cockpit_by_muscle[name]
        assert expected is not None, (
            f"Muscle '{name}' aurait dû être exclu (weekly_effective_sets=None)"
        )
        assert entry["effective_sets"] == round(expected, 1), (
            f"effective_sets divergent pour '{name}': "
            f"DNA={entry['effective_sets']} vs cockpit={round(expected, 1)}"
        )


def test_dna_insufficient_data_under_8_sessions(pinned_today, no_deload):
    """< 8 sessions dans la fenêtre → insufficient_data=True, muscles=[]."""
    import workout_dna as _dna

    # 5 sessions seulement
    rows = [
        _row(i + 1, f"s-{i}", pinned_today - timedelta(days=i),
             name="Bench", group="Chest")
        for i in range(5)
    ]
    client = _FakeClient(rows)

    dna_muscles, dna_meta = _dna._compute_muscle_dominants(client, period_days=WINDOW_DAYS)
    assert dna_meta["insufficient_data"] is True
    assert dna_meta["n_sessions"] == 5
    assert dna_muscles == []


def test_dna_deload_sessions_do_not_alter_numerator(pinned_today, monkeypatch):
    """À période décharge identique, ajouter des séries DANS la décharge
    ne change pas effective_sets.

    Scénario A : décharge 2026-10-01→07 enregistrée, 8 séances hors décharge,
                 ZÉRO séance pendant la décharge.
    Scénario B : même décharge enregistrée, mêmes 8 séances hors + 3 séances
                 DANS la décharge.

    Le dénominateur (non_deload_days = 83) est identique dans les deux
    scénarios parce que la fenêtre décharge est la MÊME. La seule variable
    est les séries décharge au numérateur — qui doivent être exclues par
    is_deload_day. Donc A == B."""
    import workout_dna as _dna

    deload_period = {
        "started_at":    "2026-10-01",
        "scheduled_end": "2026-10-07",
        "completed_at":  "2026-10-07",
        "duration_days": 7,
        "reason":        "test",
    }
    monkeypatch.setattr("db.get_deload_periods", lambda: [deload_period])

    rows_a = [
        _row(i + 1, f"s-ok-{i}", pinned_today - timedelta(days=20 + i * 2),
             name="Bench", group="Chest", sets=2)
        for i in range(8)
    ]
    dna_a, _ = _dna._compute_muscle_dominants(_FakeClient(rows_a), period_days=WINDOW_DAYS)
    chest_a = next(m for m in dna_a if m["muscle"] == "Pectoraux")

    rows_b = list(rows_a) + [
        _row(100 + i, f"s-deload-{i}", date(2026, 10, 2 + i),
             name="Bench", group="Chest", sets=5)
        for i in range(3)
    ]
    dna_b, _ = _dna._compute_muscle_dominants(_FakeClient(rows_b), period_days=WINDOW_DAYS)
    chest_b = next(m for m in dna_b if m["muscle"] == "Pectoraux")

    assert chest_a["effective_sets"] == chest_b["effective_sets"], (
        f"effective_sets changé par des séries décharge non exclues : "
        f"A={chest_a['effective_sets']} (0 série décharge) vs "
        f"B={chest_b['effective_sets']} (15 séries décharge ajoutées)"
    )


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
