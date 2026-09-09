from datetime import date

import pytest

from analytics_adapter import adapt_analytics_rows, fetch_raw_analytics_rows, unmapped_exercise_diagnostics
from metric_semantics import DateWindow
from progression_comparison import comparison_windows


PERIOD = DateWindow(date(2026, 1, 1), date(2026, 12, 31))


def row(
    log_id="log-1",
    session_id="session-1",
    day="2026-09-01",
    name="Bench Press",
    tracking_type="reps",
    sets_json=None,
    weight=100,
    reps="5",
    muscle_group="Pectoraux",
    muscle_specific=None,
    secondary_muscles=None,
    exercise_id=None,
):
    return {
        "id": log_id,
        "session_id": session_id,
        "exercise_id": exercise_id or f"exercise-{name}",
        "weight": weight,
        "reps": reps,
        "sets_json": sets_json,
        "workout_sessions": {"date": day},
        "exercises": {
            "name": name,
            "tracking_type": tracking_type,
            "muscle_group": muscle_group,
            "muscle_specific": muscle_specific,
            "secondary_muscles": secondary_muscles or [],
            "muscles": ["chest"],
        },
    }


def test_preserves_ids_sessions_dates_tracking_sets_and_builds_all_dtos():
    raw = row(sets_json=[{"weight": 100, "reps": 5}], muscle_specific="Pectoral majeur")
    result = adapt_analytics_rows([raw], period=PERIOD)
    strength = result.strength_exposures[0]
    load = result.training_load_exposures[0]
    assert strength.exposure_id == "log-1"
    assert load.exposure_id == "log-1"
    assert load.session_id == "session-1"
    assert load.date == date(2026, 9, 1)
    assert strength.tracking_type == "reps"
    assert load.sets[0].weight == 100
    assert result.assignments[0].direct_muscles == ("Pectoral majeur",)


def test_specific_precedes_group_and_secondary_is_indirect():
    result = adapt_analytics_rows(
        [row(muscle_group="Pectoraux", muscle_specific="Pectoral majeur", secondary_muscles=["Triceps"])],
        period=PERIOD,
    )
    assignment = result.assignments[0]
    assert assignment.direct_muscles == ("Pectoral majeur",)
    assert assignment.indirect_muscles == ("Triceps",)


def test_direct_duplicate_in_secondary_is_removed_by_assignment_contract():
    result = adapt_analytics_rows(
        [row(muscle_specific="Pectoraux", secondary_muscles=["Pectoraux", "Épaules"])],
        period=PERIOD,
    )
    assert result.assignments[0].direct_muscles == ("Pectoraux",)
    assert result.assignments[0].indirect_muscles == ("Épaules",)


def test_legacy_muscles_are_not_used_when_modern_metadata_is_absent_or_present():
    result = adapt_analytics_rows(
        [row(muscle_group=None, muscle_specific=None, secondary_muscles=None)], period=PERIOD
    )
    assert result.assignments == ()
    assert result.diagnostics.missing_muscle_mapping_count == 1


def test_catalogue_metadata_maps_cable_pull_over_without_name_reclassification():
    result = adapt_analytics_rows(
        [row(name="Cable Pull Over", muscle_group="Dos", muscle_specific="Grand dorsal")],
        period=PERIOD,
    )
    assert result.assignments[0].direct_muscles == ("Grand dorsal",)
    assert result.diagnostics.missing_muscle_mapping_count == 0
    assert result.diagnostics.unmapped_exercises == ()


def test_unmapped_catalogue_row_is_instrumented_with_identity_and_reason():
    result = adapt_analytics_rows(
        [row(name="Mystery Exercise", muscle_group=None, muscle_specific=None, secondary_muscles=None)],
        period=PERIOD,
    )
    assert result.assignments == ()
    assert result.diagnostics.unmapped_exercises[0].exercise_id == "exercise-Mystery Exercise"
    assert result.diagnostics.unmapped_exercises[0].exercise_name == "Mystery Exercise"
    assert result.diagnostics.unmapped_exercises[0].reason == "missing_structured_muscle_metadata"
    assert result.diagnostics.unmapped_exercises[0].unmapped_exposure_count == 1


def test_repeated_unmapped_exposures_are_aggregated():
    result = adapt_analytics_rows(
        [
            row(log_id="a", name="Mystery Exercise", muscle_group=None, muscle_specific=None),
            row(log_id="b", name="Mystery Exercise", muscle_group=None, muscle_specific=None),
        ],
        period=PERIOD,
    )
    assert result.diagnostics.unmapped_exercises[0].unmapped_exposure_count == 2


def test_same_name_different_ids_keep_mapped_and_unmapped_diagnostics_distinct():
    result = adapt_analytics_rows(
        [
            row(log_id="a", name="Cable Pull Over", exercise_id="exercise-a", muscle_group="Dos", muscle_specific="Grand dorsal"),
            row(log_id="b", name="Cable Pull Over", exercise_id="exercise-b", muscle_group=None, muscle_specific=None),
        ],
        period=PERIOD,
    )
    assert result.assignments[0].direct_muscles == ("Grand dorsal",)
    assert [(item.exercise_id, item.exercise_name) for item in result.diagnostics.unmapped_exercises] == [
        ("exercise-b", "Cable Pull Over")
    ]


def test_mixed_coverage_preserves_existing_counters_and_legacy_only_is_unmapped():
    result = adapt_analytics_rows(
        [
            row(log_id="mapped", name="Cable Pull Over", muscle_group="Dos", muscle_specific="Grand dorsal"),
            row(log_id="legacy", name="Legacy Only", muscle_group=None, muscle_specific=None, secondary_muscles=None),
        ],
        period=PERIOD,
    )
    assert result.diagnostics.missing_muscle_mapping_count == 1
    assert result.diagnostics.unmapped_exercises[0].exercise_name == "Legacy Only"


def test_muscle_window_diagnostics_exclude_raw_period_only_gap():
    rows = [
        row(log_id="inside", name="Inside Gap", day="2026-09-20", muscle_group=None),
        row(log_id="outside", name="Outside Gap", day="2026-08-01", muscle_group=None),
    ]
    diagnostics = unmapped_exercise_diagnostics(
        rows, period=DateWindow(date(2026, 9, 1), date(2026, 9, 30))
    )
    assert [item.exercise_name for item in diagnostics] == ["Inside Gap"]


def test_muscle_window_diagnostics_empty_when_fully_mapped():
    diagnostics = unmapped_exercise_diagnostics(
        [row(name="Cable Pull Over", muscle_group="Dos", muscle_specific="Grand dorsal")],
        period=DateWindow(date(2026, 9, 1), date(2026, 9, 30)),
    )
    assert diagnostics == ()


def test_muscle_window_diagnostics_aggregates_repeated_unmapped_exposures():
    diagnostics = unmapped_exercise_diagnostics(
        [
            row(log_id="a", name="Gap", muscle_group=None),
            row(log_id="b", name="Gap", muscle_group=None),
            row(log_id="c", name="Gap", muscle_group=None),
            row(log_id="d", name="Gap", muscle_group=None),
        ],
        period=DateWindow(date(2026, 9, 1), date(2026, 9, 30)),
    )
    assert len(diagnostics) == 1
    assert diagnostics[0].unmapped_exposure_count == 4


def test_muscle_window_diagnostics_keep_same_name_different_ids_distinct():
    diagnostics = unmapped_exercise_diagnostics(
        [
            row(log_id="a", name="Same Name", exercise_id="exercise-a", muscle_group=None),
            row(log_id="b", name="Same Name", exercise_id="exercise-b", muscle_group=None),
        ],
        period=DateWindow(date(2026, 9, 1), date(2026, 9, 30)),
    )
    assert [(item.exercise_id, item.exercise_name) for item in diagnostics] == [
        ("exercise-a", "Same Name"),
        ("exercise-b", "Same Name"),
    ]


def test_muscle_window_partial_coverage_matches_muscle_workload_window():
    rows = [
        row(log_id="mapped-1", name="Mapped 1", muscle_group="Dos"),
        row(log_id="mapped-2", name="Mapped 2", muscle_group="Dos"),
        row(log_id="gap", name="Gap", muscle_group=None),
    ]
    diagnostics = unmapped_exercise_diagnostics(
        rows, period=DateWindow(date(2026, 9, 1), date(2026, 9, 30))
    )
    assert len(diagnostics) == 1
    assert diagnostics[0].exercise_name == "Gap"


def test_only_proven_exact_glutes_normalization_is_applied_unknown_values_preserved():
    result = adapt_analytics_rows(
        [
            row(log_id="glutes", name="Glute Bridge", muscle_group="glutes"),
            row(log_id="unknown", name="Mystery Exercise", muscle_group="New Muscle Label"),
        ],
        period=PERIOD,
    )
    assignments = {item.exercise_name: item for item in result.assignments}
    assert assignments["Glute Bridge"].direct_muscles == ("Fessiers",)
    assert result.diagnostics.missing_muscle_mapping_count == 0


def test_two_distinct_logs_same_exercise_day_are_preserved():
    result = adapt_analytics_rows(
        [row(log_id="a"), row(log_id="b", session_id="session-2")], period=PERIOD
    )
    assert [item.exposure_id for item in result.training_load_exposures] == ["a", "b"]


def test_duplicate_id_is_deduplicated_and_contradiction_rejected():
    raw = row()
    assert adapt_analytics_rows([raw, raw], period=PERIOD).diagnostics.analytics_exposure_count == 1
    with pytest.raises(ValueError):
        adapt_analytics_rows([raw, row(weight=101)], period=PERIOD)


def test_legacy_top_level_fallback_is_observable_only_when_canonical_fallback_is_valid():
    result = adapt_analytics_rows([row(sets_json=None, weight=100, reps="5")], period=PERIOD)
    assert result.diagnostics.legacy_strength_fallback_count == 1
    invalid = adapt_analytics_rows([row(sets_json=None, weight=None, reps="bad")], period=PERIOD)
    assert invalid.diagnostics.legacy_strength_fallback_count == 0
    non_reps = adapt_analytics_rows(
        [row(sets_json=None, tracking_type="time", weight=100, reps="5")], period=PERIOD
    )
    assert non_reps.diagnostics.legacy_strength_fallback_count == 0
    sets_present = adapt_analytics_rows(
        [row(sets_json=[{"weight": 100, "reps": 0}], weight=100, reps="5")], period=PERIOD
    )
    assert sets_present.diagnostics.legacy_strength_fallback_count == 0


def test_deload_is_adapted_from_explicit_cycle_start_and_old_manual_state_is_not_invented():
    cycle_start = date(2026, 1, 1)
    result = adapt_analytics_rows(
        [row(day="2026-03-12")], period=PERIOD, cycle_start_date=cycle_start
    )
    assert result.strength_exposures[0].is_deload is True
    assert result.diagnostics.known_deload_exposure_count == 1
    without_cycle = adapt_analytics_rows([row(day="2026-03-12")], period=PERIOD)
    assert without_cycle.strength_exposures[0].is_deload is False


def test_diagnostics_track_missing_tracking_and_invalid_rows():
    result = adapt_analytics_rows(
        [row(tracking_type=None), {"id": "malformed"}], period=PERIOD
    )
    assert result.diagnostics.queried_exposure_count == 2
    assert result.diagnostics.analytics_exposure_count == 1
    assert result.diagnostics.invalid_row_count == 1
    assert result.diagnostics.missing_tracking_type_count == 1


def test_180_day_query_period_includes_the_first_required_baseline_date():
    windows = comparison_windows(today=date(2026, 9, 30), days=90)
    period = DateWindow(windows.baseline.start, windows.recent.end)
    assert period.day_count == 180
    assert period.start == date(2026, 4, 4)
    assert period.end == date(2026, 9, 30)


class _FakeQuery:
    def __init__(self, response):
        self.response = response
        self.calls = []

    def select(self, value):
        self.calls.append(("select", value))
        return self

    def gte(self, field, value):
        self.calls.append(("gte", field, value))
        return self

    def lte(self, field, value):
        self.calls.append(("lte", field, value))
        return self

    def execute(self):
        return self.response


class _FakeClient:
    def __init__(self, response):
        self.query = _FakeQuery(response)

    def table(self, name):
        assert name == "exercise_logs"
        return self.query


def test_raw_query_selects_identity_and_all_required_metadata_and_bounds():
    client = _FakeClient(type("Response", (), {"data": []})())
    rows = fetch_raw_analytics_rows(client, period=DateWindow(date(2026, 9, 1), date(2026, 9, 30)))
    assert rows == []
    select = client.query.calls[0][1]
    for field in ("id", "session_id", "exercise_id", "sets_json", "tracking_type", "muscle_group", "muscle_specific", "secondary_muscles"):
        assert field in select
    assert ("gte", "workout_sessions.date", "2026-09-01") in client.query.calls
    assert ("lte", "workout_sessions.date", "2026-09-30") in client.query.calls
