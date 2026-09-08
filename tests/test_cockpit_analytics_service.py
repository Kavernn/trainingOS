from datetime import date, datetime

import pytest

from cockpit_analytics_service import CockpitAnalyticsConfig, CockpitAnalyticsResponse, build_cockpit_analytics
from metric_semantics import DateWindow
from progression_comparison import ProgressionStatus


def row(log_id, session_id, day, *, name="Bench", tracking_type="reps", sets_json=None, weight=100, reps="5", group="Chest", secondary=None):
    return {
        "id": log_id, "session_id": session_id, "exercise_id": f"id-{name}",
        "weight": weight, "reps": reps, "sets_json": sets_json,
        "workout_sessions": {"date": day.isoformat()},
        "exercises": {"name": name, "tracking_type": tracking_type, "muscle_group": group,
                       "muscle_specific": None, "secondary_muscles": secondary or []},
    }


class FakeClient:
    def __init__(self, rows):
        self.rows = rows
        self.requested_period = None

    def table(self, name):
        assert name == "exercise_logs"
        return FakeQuery(self)


class FakeQuery:
    def __init__(self, client):
        self.client = client

    def select(self, value):
        return self

    def gte(self, field, value):
        self.client.requested_period = [value, None]
        return self

    def lte(self, field, value):
        self.client.requested_period[1] = value
        return self

    def execute(self):
        return type("Response", (), {"data": self.client.rows})()


def config(*, as_of=date(2026, 9, 30), progression_days=30, weekly=None, muscle=None):
    return CockpitAnalyticsConfig(
        as_of=as_of, progression_days=progression_days,
        weekly_period=weekly or DateWindow(date(2026, 9, 1), as_of),
        muscle_period=muscle or DateWindow(date(2026, 9, 1), as_of),
    )


def test_config_validates_supported_windows_dates_and_periods():
    assert config(progression_days=30).progression_days == 30
    assert config(progression_days=90).progression_days == 90
    with pytest.raises(TypeError):
        config(as_of=datetime(2026, 9, 30))
    with pytest.raises(ValueError):
        config(progression_days=28)
    with pytest.raises(ValueError):
        CockpitAnalyticsConfig(date(2026, 9, 30), 30, DateWindow(date(2026, 9, 2), date(2026, 9, 1)), DateWindow(date(2026, 9, 1), date(2026, 9, 1)))


def test_periods_cannot_extend_beyond_as_of_but_historical_periods_are_valid():
    as_of = date(2026, 9, 30)
    assert config(
        as_of=as_of,
        weekly=DateWindow(date(2026, 9, 1), as_of),
        muscle=DateWindow(date(2026, 9, 1), as_of),
    ).raw_period.end == as_of
    assert config(
        as_of=as_of,
        weekly=DateWindow(date(2026, 7, 1), date(2026, 8, 31)),
        muscle=DateWindow(date(2026, 7, 1), date(2026, 8, 31)),
    ).raw_period.end == as_of
    with pytest.raises(ValueError):
        config(weekly=DateWindow(date(2026, 9, 1), date(2026, 10, 1)))
    with pytest.raises(ValueError):
        config(muscle=DateWindow(date(2026, 9, 1), date(2026, 10, 1)))


def test_raw_period_is_union_and_90_day_progression_is_exactly_180_dates():
    cfg = config(progression_days=90, weekly=DateWindow(date(2026, 1, 1), date(2026, 2, 1)), muscle=DateWindow(date(2026, 5, 1), date(2026, 9, 20)))
    assert cfg.raw_period == DateWindow(date(2026, 1, 1), date(2026, 9, 30))
    nine = config(progression_days=90, weekly=DateWindow(date(2026, 9, 1), date(2026, 9, 30)), muscle=DateWindow(date(2026, 9, 1), date(2026, 9, 30)))
    assert nine.progression_windows.baseline.start == date(2026, 4, 4)
    assert nine.raw_period == DateWindow(date(2026, 4, 4), date(2026, 9, 30))
    assert nine.raw_period.day_count == 180


def test_empty_input_returns_valid_contract_and_continuous_weeks():
    response = build_cockpit_analytics(FakeClient([]), config(weekly=DateWindow(date(2026, 8, 31), date(2026, 9, 20))))
    assert isinstance(response, CockpitAnalyticsResponse)
    assert response.progression.comparisons == ()
    assert response.progression.status_counts == type(response.progression.status_counts)(0, 0, 0, 0)
    assert response.progression.top_movers == () and response.progression.attention == ()
    assert len(response.training_load.weekly) == 3
    assert response.training_load.summary.tonnage.value is None
    assert response.muscles.workloads == ()


def test_service_assembles_all_sections_and_preserves_tonnage_and_mappings():
    rows = [
        row("base-a", "s1", date(2026, 4, 10), sets_json=[{"weight": 100, "reps": 5}], secondary=["Triceps"]),
        row("base-b", "s2", date(2026, 5, 10), sets_json=[{"weight": 100, "reps": 5}], secondary=["Triceps"]),
        row("recent-a", "s3", date(2026, 9, 1), sets_json=[{"weight": 110, "reps": 5}], secondary=["Triceps"]),
        row("recent-b", "s4", date(2026, 9, 20), sets_json=[{"weight": 110, "reps": 5}], secondary=["Triceps"]),
        row("time", "s5", date(2026, 9, 21), name="Timed Bench", tracking_type="time", sets_json=[{"weight": 999, "reps": 30}], secondary=["Triceps"]),
    ]
    response = build_cockpit_analytics(FakeClient(rows), config(progression_days=90))
    assert response.progression.status_counts.improving == 1
    assert response.progression.top_movers[0].exercise_name == "Bench"
    assert response.training_load.summary.exposure_count == 3
    assert response.training_load.summary.tonnage.value == pytest.approx(1100)
    assert response.muscles.coverage.mapped_exposure_count == 3
    assert response.muscles.workloads[0].direct_set_count == 2


def test_result_is_order_invariant_and_preserves_partial_tonnage_and_mapping_gaps():
    rows = [
        row("missing", "s2", date(2026, 9, 2), sets_json=None),
        row("known", "s1", date(2026, 9, 1), sets_json=[{"weight": 100, "reps": 5}]),
        row("unmapped", "s3", date(2026, 9, 3), name="Mystery", group=None),
    ]
    first = build_cockpit_analytics(FakeClient(rows), config())
    second = build_cockpit_analytics(FakeClient(reversed(rows)), config())
    assert first == second
    assert first.training_load.summary.tonnage.coverage.value == "partial"
    assert first.muscles.coverage.unmapped_exposure_count == 1


def test_status_counts_and_empty_attention_are_factually_forwarded():
    response = build_cockpit_analytics(FakeClient([row("one", "s1", date(2026, 9, 1))]), config())
    assert all(item.status is ProgressionStatus.INSUFFICIENT_DATA for item in response.progression.comparisons)
    assert response.progression.top_movers == () and response.progression.attention == ()
