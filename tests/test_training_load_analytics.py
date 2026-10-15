from datetime import date, timedelta

import pytest

from analytics_adapter import is_deload_day
from metric_semantics import DateWindow
from training_load_analytics import (
    TonnageCoverage,
    TrainingLoadExposure,
    TrainingLoadSet,
    daily_training_load,
    summarize_training_load,
    weekly_training_load,
)


def exposure(
    exposure_id,
    session_id,
    day,
    *,
    tracking_type="reps",
    sets=((100, 5),),
    exercise_name="Bench Press",
):
    payload = (
        None
        if sets is None
        else tuple(TrainingLoadSet(weight, reps) for weight, reps in sets)
    )
    return TrainingLoadExposure(
        exposure_id=exposure_id,
        session_id=session_id,
        exercise_name=exercise_name,
        date=day,
        tracking_type=tracking_type,
        sets=payload,
    )


def test_summary_counts_mixed_tracking_sessions_and_days_without_input_order_dependency():
    period = DateWindow(date(2026, 9, 1), date(2026, 9, 7))
    items = [
        exposure("reps-1", "morning", date(2026, 9, 1)),
        exposure("time-1", "morning", date(2026, 9, 1), tracking_type="time"),
        exposure("carry-1", "bonus", date(2026, 9, 1), tracking_type="carry"),
        exposure("cardio-1", "cardio", date(2026, 9, 3), tracking_type="cardio"),
    ]
    forward = summarize_training_load(items, period=period)
    reverse = summarize_training_load(reversed(items), period=period)
    assert forward == reverse
    assert forward.exposure_count == 4
    assert forward.session_count == 3
    assert forward.active_day_count == 2
    assert forward.reps_exposure_count == 1
    assert forward.valid_reps_set_count == 1


def test_two_distinct_logs_for_same_exercise_session_and_date_remain_distinct():
    period = DateWindow(date(2026, 9, 1), date(2026, 9, 1))
    items = [
        exposure("left-log", "session", period.start),
        exposure("right-log", "session", period.start),
    ]
    result = summarize_training_load(items, period=period)
    assert result.exposure_count == 2
    assert result.session_count == 1
    assert result.active_day_count == 1


def test_exact_duplicate_exposure_is_counted_once():
    period = DateWindow(date(2026, 9, 1), date(2026, 9, 1))
    item = exposure("same", "session", period.start)
    result = summarize_training_load([item, item], period=period)
    assert result.exposure_count == 1
    assert result.tonnage.value == pytest.approx(500)


def test_conflicting_duplicate_exposure_is_rejected():
    period = DateWindow(date(2026, 9, 1), date(2026, 9, 1))
    with pytest.raises(ValueError):
        summarize_training_load(
            [
                exposure("same", "session", period.start, sets=((100, 5),)),
                exposure("same", "session", period.start, sets=((105, 5),)),
            ],
            period=period,
        )


def test_exposures_outside_explicit_period_are_ignored():
    period = DateWindow(date(2026, 9, 2), date(2026, 9, 4))
    result = summarize_training_load(
        [
            exposure("before", "s1", date(2026, 9, 1)),
            exposure("inside", "s2", date(2026, 9, 3)),
            exposure("after", "s3", date(2026, 9, 5)),
        ],
        period=period,
    )
    assert result.exposure_count == 1


def test_complete_tonnage_aggregates_all_calculable_reps_exposures():
    period = DateWindow(date(2026, 9, 1), date(2026, 9, 2))
    result = summarize_training_load(
        [
            exposure("a", "s1", date(2026, 9, 1), sets=((100, 5), (80, 10))),
            exposure("b", "s2", date(2026, 9, 2), sets=((50, 10),)),
        ],
        period=period,
    )
    assert result.valid_reps_set_count == 3
    assert result.tonnage.value == pytest.approx(1800)
    assert result.tonnage.applicable_exposure_count == 2
    assert result.tonnage.calculable_exposure_count == 2
    assert result.tonnage.uncalculable_exposure_count == 0
    assert result.tonnage.coverage is TonnageCoverage.COMPLETE


def test_calculable_true_zero_is_complete_not_missing():
    period = DateWindow(date(2026, 9, 1), date(2026, 9, 1))
    result = summarize_training_load(
        [exposure("zero", "s1", period.start, sets=((0, 10),))], period=period
    )
    assert result.valid_reps_set_count == 1
    assert result.tonnage.value == pytest.approx(0)
    assert result.tonnage.coverage is TonnageCoverage.COMPLETE
    assert result.tonnage.applicable_exposure_count == 1
    assert result.tonnage.calculable_exposure_count == 1


def test_no_reps_exposure_is_unavailable_with_zero_applicable_count():
    period = DateWindow(date(2026, 9, 1), date(2026, 9, 1))
    result = summarize_training_load(
        [exposure("time", "s1", period.start, tracking_type="time", sets=((500, 30),))],
        period=period,
    )
    assert result.reps_exposure_count == 0
    assert result.tonnage.value is None
    assert result.tonnage.applicable_exposure_count == 0
    assert result.tonnage.calculable_exposure_count == 0
    assert result.tonnage.coverage is TonnageCoverage.UNAVAILABLE


@pytest.mark.parametrize("sets", [None, (), ((100, 0),), ((-100, 5),), ((100, "bad"),)])
def test_reps_present_but_not_calculable_remains_distinguishable(sets):
    period = DateWindow(date(2026, 9, 1), date(2026, 9, 1))
    result = summarize_training_load(
        [exposure("bad", "s1", period.start, sets=sets)], period=period
    )
    assert result.reps_exposure_count == 1
    assert result.valid_reps_set_count == 0
    assert result.tonnage.value is None
    assert result.tonnage.applicable_exposure_count == 1
    assert result.tonnage.calculable_exposure_count == 0
    assert result.tonnage.coverage is TonnageCoverage.UNAVAILABLE


def test_partial_tonnage_keeps_known_sum_and_reports_coverage():
    period = DateWindow(date(2026, 9, 1), date(2026, 9, 2))
    result = summarize_training_load(
        [
            exposure("known", "s1", date(2026, 9, 1), sets=((100, 5),)),
            exposure("missing", "s2", date(2026, 9, 2), sets=None),
        ],
        period=period,
    )
    assert result.tonnage.value == pytest.approx(500)
    assert result.tonnage.applicable_exposure_count == 2
    assert result.tonnage.calculable_exposure_count == 1
    assert result.tonnage.uncalculable_exposure_count == 1
    assert result.tonnage.coverage is TonnageCoverage.PARTIAL


def test_non_reps_positive_values_never_contaminate_tonnage():
    period = DateWindow(date(2026, 9, 1), date(2026, 9, 1))
    result = summarize_training_load(
        [
            exposure("reps", "s1", period.start, sets=((100, 5),)),
            exposure("carry", "s1", period.start, tracking_type="carry", sets=((999, 999),)),
        ],
        period=period,
    )
    assert result.tonnage.value == pytest.approx(500)
    assert result.tonnage.applicable_exposure_count == 1
    assert result.tonnage.coverage is TonnageCoverage.COMPLETE


def test_valid_reps_set_count_uses_canonical_tonnage_semantics_per_set():
    period = DateWindow(date(2026, 9, 1), date(2026, 9, 1))
    result = summarize_training_load(
        [
            exposure(
                "mixed",
                "s1",
                period.start,
                sets=((100, 5), (0, 8), (100, 0), (-1, 5), (100, "bad")),
            )
        ],
        period=period,
    )
    assert result.valid_reps_set_count == 2
    assert result.tonnage.value == pytest.approx(500)


def test_non_reps_sets_never_count_as_valid_reps_sets():
    period = DateWindow(date(2026, 9, 1), date(2026, 9, 1))
    result = summarize_training_load(
        [exposure("carry", "s1", period.start, tracking_type="carry", sets=((100, 5),))],
        period=period,
    )
    assert result.valid_reps_set_count == 0


def test_weekly_trajectory_is_continuous_and_keeps_empty_week_unknown():
    period = DateWindow(date(2026, 8, 31), date(2026, 9, 20))
    result = weekly_training_load(
        [
            exposure("first", "s1", date(2026, 9, 1)),
            exposure("last", "s2", date(2026, 9, 15)),
        ],
        period=period,
    )
    assert [bucket.week_start for bucket in result] == [
        date(2026, 8, 31), date(2026, 9, 7), date(2026, 9, 14)
    ]
    assert result[1].exposure_count == 0
    assert result[1].tonnage.value is None
    assert result[1].tonnage.coverage is TonnageCoverage.UNAVAILABLE
    assert result[2].exposure_count == 1


def test_weekly_buckets_cross_month_and_year_boundaries():
    period = DateWindow(date(2026, 12, 28), date(2027, 1, 10))
    result = weekly_training_load([], period=period)
    assert [(bucket.week_start, bucket.week_end) for bucket in result] == [
        (date(2026, 12, 28), date(2027, 1, 3)),
        (date(2027, 1, 4), date(2027, 1, 10)),
    ]


def test_partial_boundary_weeks_expose_full_week_and_covered_window():
    period = DateWindow(date(2026, 9, 2), date(2026, 9, 10))
    result = weekly_training_load([], period=period)
    assert result[0].week_start == date(2026, 8, 31)
    assert result[0].week_end == date(2026, 9, 6)
    assert result[0].covered_window == DateWindow(date(2026, 9, 2), date(2026, 9, 6))
    assert result[0].is_partial is True
    assert result[1].week_start == date(2026, 9, 7)
    assert result[1].week_end == date(2026, 9, 13)
    assert result[1].covered_window == DateWindow(date(2026, 9, 7), date(2026, 9, 10))
    assert result[1].is_partial is True


def test_full_week_is_not_marked_partial():
    period = DateWindow(date(2026, 9, 7), date(2026, 9, 13))
    result = weekly_training_load([], period=period)
    assert len(result) == 1
    assert result[0].is_partial is False


def test_weekly_results_are_invariant_to_input_order():
    period = DateWindow(date(2026, 8, 31), date(2026, 9, 13))
    items = [
        exposure("b", "s2", date(2026, 9, 8), sets=((80, 5),)),
        exposure("a", "s1", date(2026, 9, 1), sets=((100, 5),)),
    ]
    assert weekly_training_load(items, period=period) == weekly_training_load(
        reversed(items), period=period
    )


def test_weekly_can_omit_empty_weeks_explicitly():
    period = DateWindow(date(2026, 8, 31), date(2026, 9, 20))
    result = weekly_training_load(
        [exposure("only", "s1", date(2026, 9, 15))],
        period=period,
        include_empty=False,
    )
    assert [bucket.week_start for bucket in result] == [date(2026, 9, 14)]


# ── daily_training_load ──────────────────────────────────────────────────────

def test_daily_covers_every_day_in_period():
    period = DateWindow(date(2026, 9, 7), date(2026, 9, 13))
    result = daily_training_load(
        [exposure("a", "s1", date(2026, 9, 8), sets=((100, 5),))],
        period=period,
    )
    assert [entry.date for entry in result] == [
        date(2026, 9, 7), date(2026, 9, 8), date(2026, 9, 9),
        date(2026, 9, 10), date(2026, 9, 11), date(2026, 9, 12), date(2026, 9, 13),
    ]
    # Empty days are reported with UNAVAILABLE tonnage (not zero).
    assert result[0].tonnage.coverage is TonnageCoverage.UNAVAILABLE
    assert result[0].tonnage.value is None
    assert result[1].tonnage.value == pytest.approx(500)
    assert result[1].tonnage.coverage is TonnageCoverage.COMPLETE


def test_daily_sum_matches_weekly_tonnage_invariant():
    """Pour chaque semaine ISO complète dans ``period``, somme(daily) == weekly."""
    period = DateWindow(date(2026, 8, 31), date(2026, 9, 20))  # 3 semaines Lun→Dim
    exposures = [
        exposure("mon-a", "s1", date(2026, 8, 31), sets=((100, 5), (80, 10))),  # 1300
        exposure("mon-b", "s1", date(2026, 8, 31), sets=((60, 12),)),           # 720
        exposure("wed",   "s2", date(2026, 9, 2),  sets=((120, 3),)),           # 360
        exposure("sun",   "s3", date(2026, 9, 6),  sets=((95, 8),)),            # 760
        exposure("w2-tue","s4", date(2026, 9, 8),  sets=((110, 5),)),           # 550
        exposure("w2-fri","s5", date(2026, 9, 11), sets=((70, 10), (70, 8))),   # 1260
        exposure("w3-mon","s6", date(2026, 9, 14), sets=((100, 6),)),           # 600
        # Non-reps: must be excluded from tonnage.
        exposure("time",  "s6", date(2026, 9, 14), tracking_type="time", sets=((999, 999),)),
    ]
    weekly = weekly_training_load(exposures, period=period)
    daily  = daily_training_load(exposures, period=period)

    for week in weekly:
        if week.is_partial:
            continue
        week_daily_sum = sum(
            (entry.tonnage.value or 0.0)
            for entry in daily
            if week.week_start <= entry.date <= week.week_end
        )
        week_total = week.tonnage.value or 0.0
        assert week_daily_sum == pytest.approx(week_total), (
            f"invariant broken for week starting {week.week_start}: "
            f"daily sum {week_daily_sum} vs weekly {week_total}"
        )


def test_daily_marks_deload_days_from_predicate():
    """Les 7 jours de la 11ᵉ semaine du cycle sont flaggués is_deload=True."""
    cycle_start = date(2026, 1, 5)  # un lundi
    # Semaine 11 commence 10 × 7 = 70 jours plus tard.
    deload_monday = cycle_start + timedelta(days=70)
    deload_sunday = deload_monday + timedelta(days=6)
    # Fenêtre couvre : semaine précédente (non-deload) + semaine deload complète.
    period = DateWindow(deload_monday - timedelta(days=7), deload_sunday)

    result = daily_training_load(
        [],  # pas d'exposure nécessaire pour tester le flag
        period=period,
        is_deload=lambda d: is_deload_day(d, cycle_start),
    )
    by_date = {entry.date: entry for entry in result}

    # Semaine précédente : aucun jour en deload.
    for i in range(7):
        day = deload_monday - timedelta(days=7 - i)
        assert by_date[day].is_deload is False, f"{day} should not be deload"
    # Semaine deload : les 7 jours flaggués.
    for i in range(7):
        day = deload_monday + timedelta(days=i)
        assert by_date[day].is_deload is True, f"{day} should be deload"


def test_daily_without_predicate_marks_no_day_as_deload():
    period = DateWindow(date(2026, 9, 7), date(2026, 9, 13))
    result = daily_training_load([], period=period)
    assert all(entry.is_deload is False for entry in result)
