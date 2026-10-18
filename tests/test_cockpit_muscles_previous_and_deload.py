"""
Tests: /api/stats/cockpit expose previous_workloads + flags deload sur la
section muscles. Backend A du lot Charge.

Vérifie :
  - Backward-compat : config sans muscle_previous_period → previous_workloads
    vide, flags False.
  - Invariant courant : workloads de la fenêtre courante INCHANGÉS que le
    config demande ou non la fenêtre précédente (le filtrage par période
    est fait dans summarize_muscle_workload, pas en amont).
  - Previous workloads calculés par la MÊME fonction (summarize_muscle_workload)
    sur la fenêtre précédente demandée.
  - Flags current_includes_deload / previous_includes_deload corrects en
    fonction du cycle_start_date (doctrine 11ᵉ semaine).
  - Validation : previous.end doit précéder strictement muscle.start.
"""
from datetime import date, timedelta

import pytest

from cockpit_analytics_service import CockpitAnalyticsConfig, build_cockpit_analytics
from metric_semantics import DateWindow


def _row(log_id, session_id, day, *, name="Bench", group="Chest", reps="5"):
    return {
        "id": str(log_id),
        "session_id": session_id,
        "exercise_id": f"id-{name}",
        "weight": 100,
        "reps": reps,
        "sets_json": None,
        "workout_sessions": {"date": day.isoformat()},
        "exercises": {
            "name": name, "tracking_type": "reps", "muscle_group": group,
            "muscle_specific": None, "secondary_muscles": [],
        },
    }


class _FakeClient:
    def __init__(self, rows): self.rows = rows
    def table(self, _): return _FakeQuery(self.rows)


class _FakeQuery:
    def __init__(self, rows): self.rows = rows
    def select(self, _): return self
    def gte(self, *_): return self
    def lte(self, *_): return self
    def execute(self): return type("R", (), {"data": self.rows})()


AS_OF = date(2026, 9, 30)
CURRENT = DateWindow(AS_OF - timedelta(days=29), AS_OF)                                     # 30 j
PREVIOUS = DateWindow(CURRENT.start - timedelta(days=30), CURRENT.start - timedelta(days=1))  # 30 j collés


def _config(muscle_previous_period=None):
    return CockpitAnalyticsConfig(
        as_of=AS_OF, progression_days=30,
        weekly_period=CURRENT, muscle_period=CURRENT,
        muscle_previous_period=muscle_previous_period,
    )


def test_backward_compat_no_previous_period_leaves_fields_empty():
    """config sans muscle_previous_period → previous_workloads=(), flags=False."""
    rows = [_row(1, "s1", CURRENT.end, name="Bench")]
    response = build_cockpit_analytics(_FakeClient(rows), _config(muscle_previous_period=None))
    muscles = response.muscles
    assert muscles.previous_period is None
    assert muscles.previous_workloads == ()
    assert muscles.current_includes_deload is False
    assert muscles.previous_includes_deload is False


def test_current_workloads_identical_with_and_without_previous_period():
    """Invariant demandé par Vince : la fenêtre courante recalculée
    égale la valeur déjà exposée aujourd'hui. Ajouter previous ne doit
    JAMAIS changer les workloads courants."""
    rows = [
        _row(1, "s1", CURRENT.end, name="Bench"),
        _row(2, "s2", CURRENT.start + timedelta(days=5), name="Row", group="Lats"),
        _row(3, "s3", PREVIOUS.start + timedelta(days=10), name="Bench"),  # tombe en précédent
    ]
    without = build_cockpit_analytics(_FakeClient(rows), _config(muscle_previous_period=None))
    with_prev = build_cockpit_analytics(_FakeClient(rows), _config(muscle_previous_period=PREVIOUS))
    assert without.muscles.workloads == with_prev.muscles.workloads, "current contaminé par previous"
    assert without.muscles.coverage == with_prev.muscles.coverage, "coverage current contaminé"


def test_previous_workloads_populated_from_previous_period():
    """Les lignes qui tombent dans PREVIOUS alimentent previous_workloads,
    pas workloads. Même fonction (summarize_muscle_workload)."""
    rows = [
        _row(1, "s1", CURRENT.end, name="Bench"),                               # courant
        _row(2, "s2", PREVIOUS.start + timedelta(days=5), name="Bench"),        # précédent
    ]
    response = build_cockpit_analytics(_FakeClient(rows), _config(muscle_previous_period=PREVIOUS))
    cur_bench = [w for w in response.muscles.workloads if "chest" in w.muscle.lower() or "pecto" in w.muscle.lower()]
    prv_bench = [w for w in response.muscles.previous_workloads if "chest" in w.muscle.lower() or "pecto" in w.muscle.lower()]
    assert cur_bench, "muscle Chest/Pectoraux doit apparaître dans workloads courants"
    assert prv_bench, "même muscle doit apparaître dans previous_workloads"
    # chaque session distincte compte UNE fois
    assert cur_bench[0].session_count == 1
    assert prv_bench[0].session_count == 1


def test_current_includes_deload_true_when_window_overlaps_week_11():
    """cycle de 11 sem (77j) commençant lundi 2026-07-20 → semaine 11
    = 2026-09-28 → 2026-10-04. AS_OF=2026-09-30 → chevauchement."""
    cycle_start = date(2026, 7, 20)
    rows = [_row(1, "s1", CURRENT.end, name="Bench")]
    response = build_cockpit_analytics(
        _FakeClient(rows), _config(muscle_previous_period=PREVIOUS),
        cycle_start_date=cycle_start,
    )
    assert response.muscles.current_includes_deload is True
    assert response.muscles.previous_includes_deload is False


def test_current_includes_deload_false_when_no_cycle_or_no_overlap():
    """Sans cycle_start → flags toujours False."""
    rows = [_row(1, "s1", CURRENT.end, name="Bench")]
    response = build_cockpit_analytics(
        _FakeClient(rows), _config(muscle_previous_period=PREVIOUS),
        cycle_start_date=None,
    )
    assert response.muscles.current_includes_deload is False
    assert response.muscles.previous_includes_deload is False


def test_previous_includes_deload_true_when_previous_covers_week_11():
    """Si le cycle vient se poser pour que la semaine 11 tombe dans
    la fenêtre précédente (2026-08-01 → 2026-08-30), on l'indique.
    PREVIOUS = [2026-08-01, 2026-08-30]. Cycle de 77 j, semaine 11
    = [cycle+70, cycle+76]. On veut cycle+70 ∈ PREVIOUS → cycle = 2026-05-23."""
    cycle_start = date(2026, 5, 25)   # semaine 11 commence le 2026-08-03
    rows = [_row(1, "s1", CURRENT.end, name="Bench")]
    response = build_cockpit_analytics(
        _FakeClient(rows), _config(muscle_previous_period=PREVIOUS),
        cycle_start_date=cycle_start,
    )
    assert response.muscles.previous_includes_deload is True


def test_previous_period_must_end_before_muscle_start():
    """Validation : previous.end >= muscle.start → ValueError."""
    overlapping = DateWindow(CURRENT.start, CURRENT.start)  # chevauche CURRENT
    with pytest.raises(ValueError):
        _config(muscle_previous_period=overlapping)


if __name__ == "__main__":
    import unittest
    pytest.main([__file__, "-v"])
