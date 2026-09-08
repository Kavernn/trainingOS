from datetime import date, datetime, timedelta

import pytest

from metric_semantics import (
    TrackingType,
    analytical_tonnage,
    best_e1rm_for_exposure,
    comparison_windows,
    estimate_e1rm,
    tracking_capabilities,
)


@pytest.mark.parametrize(
    ("reps", "expected"),
    [
        (1, 103.3333333333),
        (5, 116.6666666667),
        (10, 133.3333333333),
        (11, 138.4615384615),
        (15, 163.6363636364),
    ],
)
def test_estimate_e1rm_golden_values(reps, expected):
    assert estimate_e1rm(100, reps) == pytest.approx(expected)


@pytest.mark.parametrize(
    ("weight", "reps"),
    [
        (100, 16),
        (100, 0),
        (100, -1),
        (0, 5),
        (-100, 5),
        ("invalid", 5),
        (float("nan"), 5),
        (100, "invalid"),
        (100, 5.5),
    ],
)
def test_estimate_e1rm_rejects_values_outside_contract(weight, reps):
    assert estimate_e1rm(weight, reps) is None


def test_best_exposure_uses_the_actual_best_set_with_variable_weights():
    result = best_e1rm_for_exposure(
        tracking_type="reps",
        sets=[{"weight": 100, "reps": 10}, {"weight": 120, "reps": 5}],
        weight=100,
        reps="10,5",
    )
    assert result.best_e1rm == pytest.approx(140)
    assert result.used_legacy_fallback is False


def test_invalid_high_rep_set_does_not_cancel_a_valid_set():
    result = best_e1rm_for_exposure(
        tracking_type=TrackingType.REPS,
        sets=[{"weight": 200, "reps": 16}, {"weight": 100, "reps": 5}],
    )
    assert result.best_e1rm == pytest.approx(116.6666666667)
    assert result.used_legacy_fallback is False


def test_present_but_invalid_sets_do_not_use_legacy_fallback():
    result = best_e1rm_for_exposure(
        tracking_type="reps",
        sets=[{"weight": 100, "reps": 16}, {"weight": 0, "reps": 5}],
        weight=100,
        reps=5,
    )
    assert result.best_e1rm is None
    assert result.used_legacy_fallback is False


def test_empty_sets_are_present_and_do_not_use_legacy_fallback():
    result = best_e1rm_for_exposure(
        tracking_type="reps", sets=[], weight=100, reps=5
    )
    assert result.best_e1rm is None
    assert result.used_legacy_fallback is False


def test_absent_sets_use_legacy_fallback():
    result = best_e1rm_for_exposure(
        tracking_type="reps", sets=None, weight=100, reps="5,10"
    )
    assert result.best_e1rm == pytest.approx(133.3333333333)
    assert result.used_legacy_fallback is True


def test_non_reps_exposure_never_uses_fallback():
    result = best_e1rm_for_exposure(
        tracking_type="time", sets=None, weight=100, reps=5
    )
    assert result.best_e1rm is None
    assert result.used_legacy_fallback is False


def test_equal_best_sets_are_deterministic():
    sets = [{"weight": 100, "reps": 5}, {"weight": 100, "reps": 5}]
    first = best_e1rm_for_exposure(tracking_type="reps", sets=sets)
    second = best_e1rm_for_exposure(tracking_type="reps", sets=sets)
    assert first == second == best_e1rm_for_exposure(tracking_type="reps", sets=sets)


def test_tracking_capabilities_are_explicit_for_all_canonical_types():
    assert [tracking_type.value for tracking_type in TrackingType] == [
        "reps", "time", "carry", "plyo", "cardio", "interval", "protocol", "mobility"
    ]
    for tracking_type in TrackingType:
        capabilities = tracking_capabilities(tracking_type)
        expected = tracking_type is TrackingType.REPS
        assert capabilities.is_known is True
        assert capabilities.supports_e1rm is expected
        assert capabilities.supports_tonnage is expected


def test_unknown_tracking_type_has_no_capabilities():
    capabilities = tracking_capabilities("unknown")
    assert capabilities.is_known is False
    assert capabilities.supports_e1rm is False
    assert capabilities.supports_tonnage is False


def test_reps_tonnage_sums_variable_set_weights():
    result = analytical_tonnage(
        tracking_type="reps",
        sets=[{"weight": 100, "reps": 5}, {"weight": 80, "reps": 10}],
    )
    assert result.applicable is True
    assert result.value == pytest.approx(1300)


def test_reps_tonnage_preserves_a_real_zero():
    result = analytical_tonnage(
        tracking_type="reps", sets=[{"weight": 0, "reps": 10}]
    )
    assert result.applicable is True
    assert result.value == pytest.approx(0)


@pytest.mark.parametrize(
    "sets",
    [
        None,
        [],
        [
            {"weight": -100, "reps": 5},
            {"weight": 100, "reps": 0},
            {"weight": "invalid", "reps": "invalid"},
        ],
    ],
)
def test_reps_tonnage_is_applicable_but_not_calculable_without_valid_sets(sets):
    result = analytical_tonnage(tracking_type="reps", sets=sets)
    assert result.applicable is True
    assert result.value is None


def test_reps_tonnage_ignores_invalid_sets_when_a_valid_set_exists():
    result = analytical_tonnage(
        tracking_type="reps",
        sets=[
            {"weight": -100, "reps": 5},
            {"weight": 100, "reps": 5},
            {"weight": 100, "reps": 0},
        ],
    )
    assert result.applicable is True
    assert result.value == pytest.approx(500)


@pytest.mark.parametrize(
    "tracking_type",
    ["time", "carry", "plyo", "protocol", "interval", "cardio", "mobility", "unknown"],
)
def test_non_reps_and_unknown_tonnage_are_not_applicable(tracking_type):
    result = analytical_tonnage(
        tracking_type=tracking_type, sets=[{"weight": 100, "reps": 10}]
    )
    assert result.applicable is False
    assert result.value is None


@pytest.mark.parametrize("days", [1, 7, 30, 90])
def test_comparison_windows_have_exact_adjacent_disjoint_date_counts(days):
    windows = comparison_windows(today=date(2026, 9, 8), days=days)
    assert windows.recent.day_count == days
    assert windows.baseline.day_count == days
    assert windows.recent.end == date(2026, 9, 8)
    assert windows.baseline.end + timedelta(days=1) == windows.recent.start

    recent_dates = {
        windows.recent.start + timedelta(days=offset) for offset in range(days)
    }
    baseline_dates = {
        windows.baseline.start + timedelta(days=offset) for offset in range(days)
    }
    assert recent_dates.isdisjoint(baseline_dates)


def test_comparison_windows_cross_month_boundary():
    windows = comparison_windows(today=date(2026, 3, 2), days=5)
    assert windows.recent.start == date(2026, 2, 26)
    assert windows.baseline.start == date(2026, 2, 21)
    assert windows.baseline.end == date(2026, 2, 25)


def test_comparison_windows_cross_year_boundary():
    windows = comparison_windows(today=date(2027, 1, 2), days=5)
    assert windows.recent.start == date(2026, 12, 29)
    assert windows.baseline.start == date(2026, 12, 24)
    assert windows.baseline.end == date(2026, 12, 28)


@pytest.mark.parametrize("days", [0, -1, True, 1.5])
def test_comparison_windows_reject_invalid_lengths(days):
    with pytest.raises(ValueError):
        comparison_windows(today=date(2026, 9, 8), days=days)


def test_comparison_windows_reject_timestamps():
    with pytest.raises(TypeError):
        comparison_windows(today=datetime(2026, 9, 8, 12, 0), days=30)
