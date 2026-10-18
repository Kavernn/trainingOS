"""
Tests: /api/stats/cockpit expose previous_workloads + compteurs de jours de
décharge exclus sur la section muscles. Backend A du lot Charge.

Vérifie :
  - Backward-compat : config sans muscle_previous_period → previous_workloads
    vide, deload_days_excluded = 0.
  - Invariant courant : workloads de la fenêtre courante INCHANGÉS que le
    config demande ou non la fenêtre précédente (le filtrage par période
    est fait dans summarize_muscle_workload, pas en amont).
  - Previous workloads calculés par la MÊME fonction (summarize_muscle_workload)
    sur la fenêtre précédente demandée.
  - Compteurs current_deload_days_excluded / previous_deload_days_excluded
    corrects en fonction du cycle_start_date (doctrine 11ᵉ semaine).
  - Validation : previous.end doit précéder strictement muscle.start.
"""
from datetime import date, timedelta

import pytest

from cockpit_analytics_service import CockpitAnalyticsConfig, build_cockpit_analytics
from metric_semantics import DateWindow


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
    """config sans muscle_previous_period → previous_workloads=(), compteurs=0."""
    rows = [_row(1, "s1", CURRENT.end, name="Bench")]
    response = build_cockpit_analytics(_FakeClient(rows), _config(muscle_previous_period=None))
    muscles = response.muscles
    assert muscles.previous_period is None
    assert muscles.previous_workloads == ()
    assert muscles.current_deload_days_excluded == 0
    assert muscles.previous_deload_days_excluded == 0


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


def test_current_deload_days_excluded_counts_week_11_overlap():
    """cycle 11 sem (77j) commençant lundi 2026-07-20 → semaine 11
    = 2026-09-28 → 2026-10-04. CURRENT=[2026-09-01, 2026-09-30] → chevauche
    3 jours (lun-mar-mer 09-28/09-29/09-30)."""
    cycle_start = date(2026, 7, 20)
    rows = [_row(1, "s1", CURRENT.end, name="Bench")]
    response = build_cockpit_analytics(
        _FakeClient(rows), _config(muscle_previous_period=PREVIOUS),
        cycle_start_date=cycle_start,
    )
    assert response.muscles.current_deload_days_excluded == 3
    assert response.muscles.previous_deload_days_excluded == 0


def test_deload_days_zero_when_no_cycle_or_no_overlap():
    """Sans cycle_start → les deux compteurs restent à 0."""
    rows = [_row(1, "s1", CURRENT.end, name="Bench")]
    response = build_cockpit_analytics(
        _FakeClient(rows), _config(muscle_previous_period=PREVIOUS),
        cycle_start_date=None,
    )
    assert response.muscles.current_deload_days_excluded == 0
    assert response.muscles.previous_deload_days_excluded == 0


def test_previous_deload_days_counted_when_previous_covers_week_11():
    """Cycle 2026-05-25 → semaine 11 = [cycle+70, cycle+76] =
    [2026-08-03, 2026-08-09]. PREVIOUS = [2026-08-02, 2026-08-31] couvre
    les 7 jours de la semaine de décharge."""
    cycle_start = date(2026, 5, 25)
    rows = [_row(1, "s1", CURRENT.end, name="Bench")]
    response = build_cockpit_analytics(
        _FakeClient(rows), _config(muscle_previous_period=PREVIOUS),
        cycle_start_date=cycle_start,
    )
    assert response.muscles.previous_deload_days_excluded == 7


def test_weekly_effective_sets_excludes_deload_days():
    """Invariant demandé par Vince : une fenêtre contenant une semaine de
    décharge donne le même weekly_effective_sets que si ces 7 jours
    n'existaient pas. On compare :
    (a) fenêtre complète sans cycle_start → divise par 30/7
    (b) même fenêtre avec cycle_start posant une semaine 11 complète
        DANS la fenêtre, mais sans aucune séance pendant la décharge →
        divise par (30-7)/7 = 23/7 et compte les mêmes séries.
    Résultat : (b) > (a) car le dénominateur est plus petit."""
    # Fenêtre : 2026-09-01 → 2026-09-30 (30 j). On va placer la semaine 11
    # entièrement DANS la fenêtre : cycle_start = 2026-06-29 (lundi) →
    # semaine 11 = 2026-09-07 → 2026-09-13.
    cycle_start = date(2026, 6, 29)
    # Une séance HORS semaine de décharge (le 2026-09-20) :
    rows = [_row(1, "s1", date(2026, 9, 20), name="Bench")]
    # (a) sans deload : 1 série sur 30 j → 1 / (30/7) ≈ 0.233
    without = build_cockpit_analytics(
        _FakeClient(rows), _config(muscle_previous_period=PREVIOUS),
        cycle_start_date=None,
    )
    # (b) avec deload : 1 série non-décharge sur (30-7)=23 j → 1 / (23/7) ≈ 0.304
    with_deload = build_cockpit_analytics(
        _FakeClient(rows), _config(muscle_previous_period=PREVIOUS),
        cycle_start_date=cycle_start,
    )
    chest_a = [w for w in without.muscles.workloads     if w.muscle == "Chest"][0]
    chest_b = [w for w in with_deload.muscles.workloads if w.muscle == "Chest"][0]

    # Compteurs bruts inchangés (ce qui a été fait reste fait)
    assert chest_a.direct_set_count == chest_b.direct_set_count

    # weekly_effective_sets normalisé sur jours hors décharge
    assert with_deload.muscles.current_deload_days_excluded == 7
    assert chest_a.weekly_effective_sets == pytest.approx(1 / (30 / 7), abs=1e-6)
    assert chest_b.weekly_effective_sets == pytest.approx(1 / (23 / 7), abs=1e-6)
    assert chest_b.weekly_effective_sets > chest_a.weekly_effective_sets


def test_weekly_effective_sets_null_when_window_is_entirely_deload():
    """Fenêtre 100 % décharge → weekly_effective_sets = None (badge
    'Décharge' sans verdict côté iOS)."""
    # Fenêtre réduite à 7 j, cycle calibré pour que ces 7 j soient tous
    # en semaine 11. Fenêtre = [2026-09-07, 2026-09-13], cycle = 2026-06-29.
    tiny_window = DateWindow(date(2026, 9, 7), date(2026, 9, 13))
    cycle_start = date(2026, 6, 29)
    cfg = CockpitAnalyticsConfig(
        as_of=date(2026, 9, 13), progression_days=30,
        weekly_period=tiny_window, muscle_period=tiny_window,
        muscle_previous_period=None,
    )
    rows = [_row(1, "s1", date(2026, 9, 10), name="Bench")]
    response = build_cockpit_analytics(
        _FakeClient(rows), cfg, cycle_start_date=cycle_start,
    )
    assert response.muscles.current_deload_days_excluded == 7
    chest = [w for w in response.muscles.workloads if w.muscle == "Chest"][0]
    assert chest.weekly_effective_sets is None


def test_previous_period_must_end_before_muscle_start():
    """Validation : previous.end >= muscle.start → ValueError."""
    overlapping = DateWindow(CURRENT.start, CURRENT.start)  # chevauche CURRENT
    with pytest.raises(ValueError):
        _config(muscle_previous_period=overlapping)


if __name__ == "__main__":
    import unittest
    pytest.main([__file__, "-v"])
