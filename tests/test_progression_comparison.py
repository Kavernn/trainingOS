from datetime import date, timedelta

import pytest

import progression_comparison as engine
from metric_semantics import DateWindow, TrackingType
from progression_comparison import (
    AttentionKind,
    InsufficiencyReason,
    ProgressionComparison,
    ProgressionStatus,
    StrengthExposure,
    StrengthSet,
    compare_progression,
    no_recent_improvement,
    top_movers,
)


TODAY = date(2026, 9, 8)


def exposure(
    exposure_id,
    day,
    *,
    name="Bench Press",
    weight=100,
    reps=1,
    sets_marker=True,
    tracking_type="reps",
    is_deload=False,
):
    sets = (StrengthSet(weight, reps),) if sets_marker else None
    return StrengthExposure(
        exposure_id=exposure_id,
        exercise_name=name,
        date=day,
        tracking_type=tracking_type,
        sets=sets,
        weight=weight,
        reps=reps,
        is_deload=is_deload,
    )


def comparison_input(recent_weight, baseline_weight=100):
    return [
        exposure("b1", TODAY - timedelta(days=40), weight=baseline_weight),
        exposure("b2", TODAY - timedelta(days=35), weight=baseline_weight),
        exposure("r1", TODAY - timedelta(days=10), weight=recent_weight),
        exposure("r2", TODAY - timedelta(days=5), weight=recent_weight),
    ]


@pytest.mark.parametrize(
    ("recent_weight", "expected"),
    [
        (105, ProgressionStatus.IMPROVING),
        (106, ProgressionStatus.IMPROVING),
        (104.999999, ProgressionStatus.STABLE),
        (95, ProgressionStatus.DECLINING),
        (94, ProgressionStatus.DECLINING),
        (95.000001, ProgressionStatus.STABLE),
    ],
)
def test_progression_status_boundaries(recent_weight, expected):
    result = compare_progression(comparison_input(recent_weight), today=TODAY)[0]
    assert result.status is expected


def test_progression_returns_exact_windows_and_unrounded_deltas():
    result = compare_progression(comparison_input(105), today=TODAY)[0]
    assert result.baseline_window == DateWindow(date(2026, 7, 11), date(2026, 8, 9))
    assert result.recent_window == DateWindow(date(2026, 8, 10), date(2026, 9, 8))
    assert result.absolute_delta == pytest.approx(5.1666666667)
    assert result.relative_delta == pytest.approx(0.05)


@pytest.mark.parametrize(
    ("items", "reason", "baseline_count", "recent_count"),
    [
        (
            [
                exposure("b1", TODAY - timedelta(days=40)),
                exposure("r1", TODAY - timedelta(days=10)),
                exposure("r2", TODAY - timedelta(days=5)),
            ],
            InsufficiencyReason.INSUFFICIENT_BASELINE_EXPOSURES,
            1,
            2,
        ),
        (
            [
                exposure("b1", TODAY - timedelta(days=40)),
                exposure("b2", TODAY - timedelta(days=35)),
                exposure("r1", TODAY - timedelta(days=5)),
            ],
            InsufficiencyReason.INSUFFICIENT_RECENT_EXPOSURES,
            2,
            1,
        ),
        (
            [
                exposure("b1", TODAY - timedelta(days=40)),
                exposure("r1", TODAY - timedelta(days=5)),
            ],
            InsufficiencyReason.INSUFFICIENT_BOTH_WINDOWS,
            1,
            1,
        ),
    ],
)
def test_insufficient_window_reasons(items, reason, baseline_count, recent_count):
    result = compare_progression(items, today=TODAY)[0]
    assert result.status is ProgressionStatus.INSUFFICIENT_DATA
    assert result.insufficiency_reason is reason
    assert result.baseline_exposure_count == baseline_count
    assert result.recent_exposure_count == recent_count


def test_non_reps_exercise_is_returned_as_non_comparable():
    result = compare_progression(
        [exposure("t1", TODAY, tracking_type="time")], today=TODAY
    )[0]
    assert result.tracking_type is TrackingType.TIME
    assert result.status is ProgressionStatus.INSUFFICIENT_DATA
    assert result.insufficiency_reason is InsufficiencyReason.NON_COMPARABLE_TRACKING_TYPE


@pytest.mark.parametrize(
    "sets",
    [
        (StrengthSet(100, 16),),
        (StrengthSet(0, 5), StrengthSet(100, "invalid")),
    ],
)
def test_no_valid_strength_sets_are_reported(sets):
    item = StrengthExposure("x", "Bench Press", TODAY, "reps", sets)
    result = compare_progression([item], today=TODAY)[0]
    assert result.insufficiency_reason is InsufficiencyReason.NO_VALID_EXPOSURE


def test_valid_legacy_fallback_is_counted_and_reported_per_window():
    items = comparison_input(105)
    items[0] = exposure(
        "b1", TODAY - timedelta(days=40), weight=100, reps="1,1", sets_marker=False
    )
    result = compare_progression(items, today=TODAY)[0]
    assert result.status is ProgressionStatus.IMPROVING
    assert result.baseline_used_legacy_fallback is True
    assert result.recent_used_legacy_fallback is False


def test_deload_is_excluded_without_removing_the_exercise():
    items = comparison_input(105)
    items.append(exposure("deload", TODAY - timedelta(days=3), weight=200, is_deload=True))
    result = compare_progression(items, today=TODAY)[0]
    assert result.recent_exposure_count == 2
    assert result.recent_best_e1rm == pytest.approx(108.5)


def test_deload_exclusion_can_make_a_window_insufficient():
    items = comparison_input(105)
    items[3] = exposure(
        "r2", TODAY - timedelta(days=5), weight=105, is_deload=True
    )
    result = compare_progression(items, today=TODAY)[0]
    assert result.status is ProgressionStatus.INSUFFICIENT_DATA
    assert result.insufficiency_reason is InsufficiencyReason.INSUFFICIENT_RECENT_EXPOSURES
    assert result.recent_exposure_count == 1


def test_two_real_exposures_on_the_same_day_are_both_counted():
    items = comparison_input(105)
    items[2] = exposure("r-morning", TODAY - timedelta(days=5), weight=105)
    items[3] = exposure("r-bonus", TODAY - timedelta(days=5), weight=105)
    result = compare_progression(items, today=TODAY)[0]
    assert result.recent_exposure_count == 2


def test_duplicate_exposure_id_is_counted_once_independent_of_input_order():
    items = comparison_input(105)
    duplicate = items[-1]
    forward = compare_progression(items + [duplicate], today=TODAY)[0]
    reverse = compare_progression(list(reversed(items + [duplicate])), today=TODAY)[0]
    assert forward == reverse
    assert forward.recent_exposure_count == 2


def test_conflicting_duplicate_exposure_id_is_rejected():
    with pytest.raises(ValueError):
        compare_progression(
            [exposure("same", TODAY, weight=100), exposure("same", TODAY, weight=105)],
            today=TODAY,
        )


def test_best_per_window_uses_max_not_latest_or_average():
    items = [
        exposure("b1", TODAY - timedelta(days=45), weight=90),
        exposure("b2", TODAY - timedelta(days=40), weight=110),
        exposure("b3", TODAY - timedelta(days=35), weight=100),
        exposure("r1", TODAY - timedelta(days=15), weight=100),
        exposure("r2", TODAY - timedelta(days=10), weight=120),
        exposure("r3", TODAY - timedelta(days=5), weight=105),
    ]
    result = compare_progression(items, today=TODAY)[0]
    assert result.baseline_best_e1rm == pytest.approx(113.6666666667)
    assert result.recent_best_e1rm == pytest.approx(124)


def test_multiple_sets_remain_one_exposure_and_actual_best_set_wins():
    items = comparison_input(105)
    items[2] = StrengthExposure(
        "r1",
        "Bench Press",
        TODAY - timedelta(days=10),
        "reps",
        (StrengthSet(100, 10), StrengthSet(120, 5)),
    )
    result = compare_progression(items, today=TODAY)[0]
    assert result.recent_exposure_count == 2
    assert result.recent_best_e1rm == pytest.approx(140)


def test_invalid_zero_baseline_is_defensively_insufficient(monkeypatch):
    original = engine.best_e1rm_for_exposure

    def zero_baseline(**kwargs):
        result = original(**kwargs)
        if kwargs.get("weight") == "zero-baseline":
            return type(result)(best_e1rm=0.0, used_legacy_fallback=False)
        return result

    monkeypatch.setattr(engine, "best_e1rm_for_exposure", zero_baseline)
    items = comparison_input(105)
    items[0] = exposure(
        "b1", TODAY - timedelta(days=40), weight="zero-baseline", sets_marker=False
    )
    items[1] = exposure(
        "b2", TODAY - timedelta(days=35), weight="zero-baseline", sets_marker=False
    )
    result = compare_progression(items, today=TODAY)[0]
    assert result.status is ProgressionStatus.INSUFFICIENT_DATA
    assert result.insufficiency_reason is InsufficiencyReason.INVALID_BASELINE
    assert result.relative_delta is None


def make_comparison(name, status, relative, absolute):
    window = DateWindow(TODAY - timedelta(days=29), TODAY)
    return ProgressionComparison(
        exercise_name=name,
        tracking_type=TrackingType.REPS,
        status=status,
        baseline_window=window,
        recent_window=window,
        baseline_best_e1rm=100,
        recent_best_e1rm=100 + (absolute or 0),
        absolute_delta=absolute,
        relative_delta=relative,
        baseline_exposure_count=2,
        recent_exposure_count=2,
        baseline_used_legacy_fallback=False,
        recent_used_legacy_fallback=False,
        insufficiency_reason=(
            InsufficiencyReason.INSUFFICIENT_RECENT_EXPOSURES
            if status is ProgressionStatus.INSUFFICIENT_DATA
            else None
        ),
    )


def test_top_movers_filters_non_improving_and_insufficient():
    comparisons = [
        make_comparison("Improving", ProgressionStatus.IMPROVING, 0.06, 6),
        make_comparison("Stable", ProgressionStatus.STABLE, 0.01, 1),
        make_comparison("Declining", ProgressionStatus.DECLINING, -0.06, -6),
        make_comparison("Insufficient", ProgressionStatus.INSUFFICIENT_DATA, None, None),
    ]
    assert [item.exercise_name for item in top_movers(comparisons)] == ["Improving"]


def test_top_movers_uses_relative_absolute_and_name_tie_breakers():
    comparisons = [
        make_comparison("Zulu", ProgressionStatus.IMPROVING, 0.06, 8),
        make_comparison("Alpha", ProgressionStatus.IMPROVING, 0.06, 8),
        make_comparison("Relative", ProgressionStatus.IMPROVING, 0.07, 5),
        make_comparison("Absolute", ProgressionStatus.IMPROVING, 0.06, 10),
    ]
    assert [item.exercise_name for item in top_movers(reversed(comparisons))] == [
        "Relative", "Absolute", "Alpha", "Zulu"
    ]


ATTENTION_WINDOW = DateWindow(TODAY - timedelta(days=29), TODAY)


def attention_exposures(weights=(100, 100, 100), *, dates=None):
    dates = dates or (TODAY - timedelta(days=25), TODAY - timedelta(days=12), TODAY - timedelta(days=4))
    return [
        exposure(f"a{index}", day, weight=weight)
        for index, (day, weight) in enumerate(zip(dates, weights), start=1)
    ]


def test_no_recent_improvement_returns_factual_observation():
    observations = no_recent_improvement(
        attention_exposures(), observation_window=ATTENTION_WINDOW, as_of=TODAY
    )
    assert observations == [
        engine.AttentionObservation(
            kind=AttentionKind.NO_RECENT_IMPROVEMENT,
            exercise_name="Bench Press",
            observation_window=ATTENTION_WINDOW,
            last_exposure_date=TODAY - timedelta(days=4),
            days_since_last_exposure=4,
            valid_exposure_count=3,
            covered_days=21,
            latest_best_e1rm=pytest.approx(103.3333333333),
        )
    ]


def test_new_best_in_the_middle_suppresses_observation_for_the_supplied_window():
    assert no_recent_improvement(
        attention_exposures((100, 101, 100)),
        observation_window=ATTENTION_WINDOW,
        as_of=TODAY,
    ) == []


def test_new_best_at_end_suppresses_observation():
    assert no_recent_improvement(
        attention_exposures((100, 100, 101)),
        observation_window=ATTENTION_WINDOW,
        as_of=TODAY,
    ) == []


def test_exactly_point_one_lb_is_not_a_new_best_but_more_is():
    assert engine._is_new_best(100.1, 100, 0.1) is False
    assert engine._is_new_best(100.100001, 100, 0.1) is True


def test_attention_requires_three_valid_exposures():
    assert no_recent_improvement(
        attention_exposures()[:2], observation_window=ATTENTION_WINDOW, as_of=TODAY
    ) == []


def test_attention_requires_21_elapsed_covered_days():
    dates = (TODAY - timedelta(days=24), TODAY - timedelta(days=12), TODAY - timedelta(days=4))
    assert no_recent_improvement(
        attention_exposures(dates=dates),
        observation_window=ATTENTION_WINDOW,
        as_of=TODAY,
    ) == []


def test_attention_excludes_deload_and_can_fall_below_minimum():
    items = attention_exposures()
    items[1] = exposure(
        items[1].exposure_id, items[1].date, weight=100, is_deload=True
    )
    assert no_recent_improvement(
        items, observation_window=ATTENTION_WINDOW, as_of=TODAY
    ) == []


def test_attention_counts_distinct_same_day_exposures_and_deduplicates_ids():
    first = exposure("first", TODAY - timedelta(days=25), weight=100)
    morning = exposure("morning", TODAY - timedelta(days=4), weight=100)
    bonus = exposure("bonus", TODAY - timedelta(days=4), weight=100)
    items = [bonus, first, morning, morning]
    result = no_recent_improvement(
        items, observation_window=ATTENTION_WINDOW, as_of=TODAY
    )[0]
    assert result.valid_exposure_count == 3
    assert result.last_exposure_date == TODAY - timedelta(days=4)
    assert result.days_since_last_exposure == 4


def test_attention_is_input_order_independent():
    items = attention_exposures()
    assert no_recent_improvement(
        items, observation_window=ATTENTION_WINDOW, as_of=TODAY
    ) == no_recent_improvement(
        reversed(items), observation_window=ATTENTION_WINDOW, as_of=TODAY
    )
