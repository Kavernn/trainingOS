from datetime import date

import pytest

from metric_semantics import DateWindow
from muscle_workload_analytics import (
    ExerciseMuscleAssignment,
    summarize_muscle_workload,
)
from training_load_analytics import TrainingLoadExposure, TrainingLoadSet


PERIOD = DateWindow(date(2026, 9, 1), date(2026, 9, 30))


def exposure(exposure_id, session_id, day, *, name="Bench", tracking_type="reps", sets=((100, 5),)):
    payload = None if sets is None else tuple(TrainingLoadSet(weight, reps) for weight, reps in sets)
    return TrainingLoadExposure(exposure_id, session_id, name, day, tracking_type, payload)


def assignment(name="Bench", direct=(), indirect=()):
    return ExerciseMuscleAssignment(name, tuple(direct), tuple(indirect))


def workload(result, muscle):
    return next(item for item in result.muscles if item.muscle == muscle)


def test_assignment_deduplicates_and_direct_wins_over_indirect():
    item = assignment(direct=(" chest ", "chest"), indirect=("chest", "triceps", "triceps"))
    assert item.direct_muscles == ("chest",)
    assert item.indirect_muscles == ("triceps",)


def test_assignment_rejects_empty_muscle_values_and_fuzzy_is_not_used():
    with pytest.raises(ValueError):
        assignment(direct=("",))
    result = summarize_muscle_workload(
        [exposure("1", "s1", date(2026, 9, 1), name="Bench Press")],
        [assignment("Bench", direct=("chest",))],
        period=PERIOD,
    )
    assert result.coverage.mapped_exposure_count == 0
    assert result.muscles == ()


def test_duplicate_identical_assignment_is_allowed_and_conflict_rejected():
    ex = [exposure("1", "s1", date(2026, 9, 1))]
    mapped = assignment(direct=("chest",))
    assert summarize_muscle_workload(ex, [mapped, mapped], period=PERIOD).coverage.mapped_exposure_count == 1
    with pytest.raises(ValueError):
        summarize_muscle_workload(ex, [assignment(), assignment(indirect=("triceps",))], period=PERIOD)


def test_direct_and_indirect_sets_use_only_valid_reps_sets_without_weighting():
    result = summarize_muscle_workload(
        [exposure("1", "s1", date(2026, 9, 1), sets=((100, 5), (0, 8), (100, 0), (-1, 5)))],
        [assignment(direct=("chest",), indirect=("triceps", "shoulders"))],
        period=PERIOD,
    )
    assert workload(result, "chest").direct_set_count == 2
    assert workload(result, "triceps").indirect_set_count == 2
    assert workload(result, "shoulders").indirect_set_count == 2


@pytest.mark.parametrize("tracking_type", ["time", "carry", "plyo", "cardio", "interval", "protocol", "mobility", "unknown"])
def test_non_reps_are_exposures_but_never_strength_sets(tracking_type):
    result = summarize_muscle_workload(
        [exposure("1", "s1", date(2026, 9, 1), tracking_type=tracking_type)],
        [assignment(direct=("chest",))],
        period=PERIOD,
    )
    chest = workload(result, "chest")
    assert chest.direct_set_count == 0
    assert chest.direct_exposure_count == 1
    assert result.coverage.reps_exposure_count == 0


def test_exposure_session_and_day_counts_are_distinct_facts():
    result = summarize_muscle_workload(
        [
            exposure("1", "s1", date(2026, 9, 1), name="Bench"),
            exposure("2", "s1", date(2026, 9, 1), name="Fly"),
            exposure("3", "s2", date(2026, 9, 1), name="Press"),
            exposure("4", "s3", date(2026, 9, 2), name="Bench"),
        ],
        [assignment("Bench", direct=("chest",)), assignment("Fly", indirect=("chest",)), assignment("Press", direct=("chest",))],
        period=PERIOD,
    )
    chest = workload(result, "chest")
    assert chest.direct_exposure_count == 3
    assert chest.indirect_exposure_count == 1
    assert chest.session_count == 3
    assert chest.active_day_count == 2
    assert chest.last_exposure_date == date(2026, 9, 2)


def test_coverage_tracks_mapped_and_unmapped_reps_and_ignores_out_of_period():
    result = summarize_muscle_workload(
        [
            exposure("mapped", "s1", date(2026, 9, 1), name="Bench"),
            exposure("unmapped", "s2", date(2026, 9, 2), name="Unknown"),
            exposure("outside", "s3", date(2026, 10, 1), name="Bench"),
        ],
        [assignment("Bench", direct=("chest",))],
        period=PERIOD,
    )
    assert result.coverage.total_exposure_count == 2
    assert result.coverage.mapped_exposure_count == 1
    assert result.coverage.unmapped_exposure_count == 1
    assert result.coverage.reps_exposure_count == 2
    assert result.coverage.mapped_reps_exposure_count == 1


def test_duplicate_exposure_is_counted_once_and_conflict_is_rejected():
    item = exposure("same", "s1", date(2026, 9, 1))
    result = summarize_muscle_workload([item, item], [assignment(direct=("chest",))], period=PERIOD)
    assert result.coverage.total_exposure_count == 1
    with pytest.raises(ValueError):
        summarize_muscle_workload(
            [item, exposure("same", "s1", date(2026, 9, 1), sets=((101, 5),))],
            [assignment(direct=("chest",))],
            period=PERIOD,
        )


def test_result_is_deterministic_for_shuffled_input_and_muscles_sorted():
    items = [
        exposure("2", "s2", date(2026, 9, 2), name="Fly"),
        exposure("1", "s1", date(2026, 9, 1), name="Bench"),
    ]
    assignments = [assignment("Fly", direct=("triceps",)), assignment("Bench", direct=("chest",))]
    first = summarize_muscle_workload(items, assignments, period=PERIOD)
    second = summarize_muscle_workload(reversed(items), reversed(assignments), period=PERIOD)
    assert first == second
    assert [item.muscle for item in first.muscles] == ["chest", "triceps"]


def test_assignment_without_exposure_does_not_create_muscle():
    result = summarize_muscle_workload([], [assignment(direct=("chest",))], period=PERIOD)
    assert result.muscles == ()
    assert result.coverage.total_exposure_count == 0
