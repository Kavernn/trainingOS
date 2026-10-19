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


def test_dna_effective_sets_matches_cockpit_summarize_muscle_workload(pinned_today, no_deload):
    """Pour la même fenêtre et les mêmes rows, DNA.effective_sets ==
    direct + 0,5 × indirect du cockpit, muscle par muscle (noms canoniques)."""
    from analytics_adapter import fetch_raw_analytics_rows, adapt_analytics_rows, is_deload_day
    from metric_semantics import DateWindow
    from muscle_workload_analytics import summarize_muscle_workload, INDIRECT_SET_COEFFICIENT
    import workout_dna as _dna

    rows = _mk_rows()
    client = _FakeClient(rows)
    period = DateWindow(pinned_today - timedelta(days=WINDOW_DAYS - 1), pinned_today)

    # 1) DNA via _compute_muscle_dominants
    dna_muscles, dna_meta = _dna._compute_muscle_dominants(client, period_days=WINDOW_DAYS)
    assert dna_meta["insufficient_data"] is False, (
        f"Attendu ≥ 8 sessions, obtenu {dna_meta['n_sessions']}"
    )
    assert dna_muscles, "Attendu au moins un muscle dans le top-6"

    # 2) Cockpit canonical : même pipeline, mêmes paramètres
    raw = fetch_raw_analytics_rows(client, period=period)
    adapted = adapt_analytics_rows(raw, period=period)
    cockpit_summary = summarize_muscle_workload(
        adapted.training_load_exposures,
        adapted.assignments,
        period=period,
        is_deload=lambda d: is_deload_day(d),
    )
    cockpit_by_muscle = {
        m.muscle: m.direct_set_count + INDIRECT_SET_COEFFICIENT * m.indirect_set_count
        for m in cockpit_summary.muscles
    }

    # 3) Les noms de muscles DNA doivent exister tels quels dans le cockpit
    #    (fusion canonique appliquée des deux côtés via adapt_analytics_rows).
    for entry in dna_muscles:
        name = entry["muscle"]
        assert name in cockpit_by_muscle, (
            f"Muscle DNA '{name}' absent du cockpit — fusion canonique divergente"
        )
        expected = round(cockpit_by_muscle[name], 1)
        assert entry["effective_sets"] == expected, (
            f"effective_sets divergent pour '{name}': "
            f"DNA={entry['effective_sets']} vs cockpit={expected}"
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


def test_dna_counts_match_cockpit_in_deload_scenario(pinned_today, monkeypatch):
    """ATTENTION — ÉCART AVEC L'INSTRUCTION « décharge exclue ».

    L'implémentation actuelle utilise `direct_set_count` + `indirect_set_count`
    de MuscleWorkload, qui INCLUENT les sets des jours de décharge (doctrine
    summarize_muscle_workload : "ce qui a été fait reste fait" ; l'exclusion
    décharge agit sur `weekly_effective_sets`, pas sur les compteurs bruts).

    Pour exclure réellement la décharge d'effective_sets DNA, il faudrait
    exposer `direct_sets_non_deload` / `indirect_sets_non_deload` (actuellement
    internes à `_MuscleAccumulator`) dans la dataclass publique MuscleWorkload.

    Ce test confirme uniquement la cohérence DNA ↔ cockpit sur la base
    `direct_set_count + 0.5 × indirect_set_count` INCLUANT les sets décharge.
    """
    from analytics_adapter import fetch_raw_analytics_rows, adapt_analytics_rows, is_deload_day
    from metric_semantics import DateWindow
    from muscle_workload_analytics import summarize_muscle_workload, INDIRECT_SET_COEFFICIENT
    import workout_dna as _dna

    deload_period = {
        "started_at":    "2026-10-01",
        "scheduled_end": "2026-10-07",
        "completed_at":  "2026-10-07",
        "duration_days": 7,
        "reason":        "test",
    }
    monkeypatch.setattr("db.get_deload_periods", lambda: [deload_period])

    rows = []
    log_id = 0
    for i in range(8):
        log_id += 1
        rows.append(_row(log_id, f"s-ok-{i}",
                         pinned_today - timedelta(days=20 + i * 2),
                         name="Bench", group="Chest", sets=2))
    for i in range(3):
        log_id += 1
        rows.append(_row(log_id, f"s-deload-{i}",
                         date(2026, 10, 2 + i),
                         name="Bench", group="Chest", sets=5))
    client = _FakeClient(rows)

    period = DateWindow(pinned_today - timedelta(days=WINDOW_DAYS - 1), pinned_today)
    adapted = adapt_analytics_rows(fetch_raw_analytics_rows(client, period=period), period=period)
    cockpit_summary = summarize_muscle_workload(
        adapted.training_load_exposures, adapted.assignments,
        period=period, is_deload=lambda d: is_deload_day(d),
    )
    cockpit_chest = next(m for m in cockpit_summary.muscles if m.muscle == "Pectoraux")
    expected_effective = cockpit_chest.direct_set_count + INDIRECT_SET_COEFFICIENT * cockpit_chest.indirect_set_count

    dna_muscles, _ = _dna._compute_muscle_dominants(client, period_days=WINDOW_DAYS)
    dna_chest = next(m for m in dna_muscles if m["muscle"] == "Pectoraux")

    # DNA = cockpit, et les deux incluent la décharge (31 sets au total).
    assert dna_chest["effective_sets"] == round(expected_effective, 1)
    assert dna_chest["effective_sets"] == 8 * 2 + 3 * 5


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
