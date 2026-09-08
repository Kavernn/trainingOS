from dataclasses import dataclass
from datetime import date
from enum import Enum
import math

import pytest
from flask import Flask, jsonify

import db
from routes import analytics_stats
from metric_semantics import DateWindow


class FakeQuery:
    def __init__(self, rows):
        self.rows = rows

    def select(self, _value):
        return self

    def gte(self, _field, _value):
        return self

    def lte(self, _field, _value):
        return self

    def execute(self):
        return type("Response", (), {"data": self.rows})()


class FakeClient:
    def __init__(self, rows=None):
        self.rows = rows or []

    def table(self, name):
        assert name == "exercise_logs"
        return FakeQuery(self.rows)


@pytest.fixture
def app():
    flask_app = Flask(__name__)
    flask_app.register_blueprint(analytics_stats.analytics_stats_bp)

    @flask_app.errorhandler(Exception)
    def internal_error(_error):
        return jsonify({"error": "internal"}), 500

    flask_app.config["TESTING"] = True
    return flask_app


def raw_row(log_id, day, *, weight=100, tracking_type="reps", group="Chest", sets_json=None):
    return {
        "id": log_id,
        "session_id": f"session-{log_id}",
        "exercise_id": "exercise-bench",
        "weight": weight,
        "reps": "5",
        "sets_json": sets_json,
        "workout_sessions": {"date": day.isoformat()},
        "exercises": {
            "name": "Bench Press",
            "tracking_type": tracking_type,
            "muscle_group": group,
            "muscle_specific": None,
            "secondary_muscles": ["Triceps"],
        },
    }


def query(as_of="2026-09-30", progression_days="30", weekly_days="30", muscle_days="30"):
    return f"/api/stats/cockpit?as_of={as_of}&progression_days={progression_days}&weekly_days={weekly_days}&muscle_days={muscle_days}"


def test_serializer_handles_nested_dataclass_enum_date_tuple_none_zero_and_floats():
    class State(str, Enum):
        READY = "ready"

    @dataclass(frozen=True)
    class Sample:
        state: State
        day: date
        values: tuple
        missing: object
        zero: float
        negative: float

    result = analytics_stats._serialize_cockpit(Sample(State.READY, date(2026, 9, 30), (0, None), None, 0.0, -2.5))
    assert result == {"state": "ready", "day": "2026-09-30", "values": [0, None], "missing": None, "zero": 0.0, "negative": -2.5}
    with pytest.raises(ValueError):
        analytics_stats._serialize_cockpit(float("nan"))
    with pytest.raises(ValueError):
        analytics_stats._serialize_cockpit(float("inf"))
    with pytest.raises(ValueError):
        analytics_stats._serialize_cockpit(float("-inf"))


def test_valid_request_calls_service_once_with_exact_config_and_returns_empty_contract(app, monkeypatch):
    monkeypatch.setattr(db, "_client", FakeClient([]))
    monkeypatch.setattr(db, "get_cycle_start_date", lambda: None)
    calls = []
    real = analytics_stats.build_cockpit_analytics

    def spy(client, config, *, cycle_start_date=None):
        calls.append((client, config, cycle_start_date))
        return real(client, config, cycle_start_date=cycle_start_date)

    monkeypatch.setattr(analytics_stats, "build_cockpit_analytics", spy)
    response = app.test_client().get(query(progression_days="30", weekly_days="8", muscle_days="21"))
    assert response.status_code == 200
    assert len(calls) == 1
    assert calls[0][1].as_of == date(2026, 9, 30)
    assert calls[0][1].progression_days == 30
    assert calls[0][1].weekly_period == DateWindow(date(2026, 9, 23), date(2026, 9, 30))
    assert calls[0][1].muscle_period == DateWindow(date(2026, 9, 10), date(2026, 9, 30))
    payload = response.get_json()
    assert set(payload) == {"as_of", "progression", "training_load", "muscles", "data_quality"}
    assert payload["as_of"] == "2026-09-30"
    assert payload["progression"]["status_counts"] == {"improving": 0, "stable": 0, "declining": 0, "insufficient_data": 0}
    assert payload["training_load"]["weekly"]
    assert payload["muscles"]["workloads"] == []


@pytest.mark.parametrize("params", [
    {"as_of": "2026-9-30"},
    {"as_of": "2026-09-30T00:00:00"},
    {"progression_days": "28"},
    {"weekly_days": "0"},
    {"weekly_days": "-1"},
    {"weekly_days": "1.5"},
    {"muscle_days": "0"},
])
def test_invalid_query_parameters_return_400(app, params):
    values = {"as_of": "2026-09-30", "progression_days": "30", "weekly_days": "30", "muscle_days": "30"}
    values.update(params)
    response = app.test_client().get(query(**values))
    assert response.status_code == 400
    assert "error" in response.get_json()


def test_missing_required_query_parameter_returns_400(app):
    response = app.test_client().get("/api/stats/cockpit?as_of=2026-09-30&progression_days=30&weekly_days=30")
    assert response.status_code == 400


def test_rich_response_serializes_statuses_dates_coverage_zero_and_sections(app, monkeypatch):
    rows = [
        raw_row("b1", date(2026, 8, 10), weight=100, sets_json=[{"weight": 100, "reps": 5}]),
        raw_row("b2", date(2026, 8, 20), weight=100, sets_json=[{"weight": 100, "reps": 5}]),
        raw_row("r1", date(2026, 9, 10), weight=110, sets_json=[{"weight": 110, "reps": 5}]),
        raw_row("r2", date(2026, 9, 20), weight=110, sets_json=[{"weight": 110, "reps": 5}]),
        raw_row("zero", date(2026, 9, 21), weight=0, sets_json=[{"weight": 0, "reps": 5}]),
    ]
    monkeypatch.setattr(db, "_client", FakeClient(rows))
    monkeypatch.setattr(db, "get_cycle_start_date", lambda: None)
    response = app.test_client().get(query(progression_days="30", weekly_days="30", muscle_days="30"))
    assert response.status_code == 200
    payload = response.get_json()
    assert set(payload["progression"]) == {"comparison_window_days", "baseline_window", "recent_window", "status_counts", "comparisons", "top_movers", "attention"}
    assert payload["progression"]["status_counts"]["improving"] == 1
    assert payload["progression"]["comparisons"][0]["status"] == "improving"
    assert payload["progression"]["baseline_window"]["start"] == "2026-08-02"
    assert set(payload["training_load"]) == {"period", "summary", "weekly"}
    assert payload["training_load"]["summary"]["tonnage"]["value"] == 1100.0
    assert payload["training_load"]["summary"]["tonnage"]["coverage"] == "complete"
    assert set(payload["muscles"]) == {"period", "coverage", "workloads"}
    assert payload["muscles"]["coverage"]["mapped_exposure_count"] == 3
    assert payload["data_quality"]["requested_raw_period"]["end"] == "2026-09-30"
    assert not any(math.isnan(value) for value in [payload["training_load"]["summary"]["tonnage"]["value"]])


def test_service_error_is_not_misclassified_as_bad_query(app, monkeypatch):
    monkeypatch.setattr(db, "get_cycle_start_date", lambda: None)

    def broken(*_args, **_kwargs):
        raise ValueError("contradictory analytics data")

    monkeypatch.setattr(analytics_stats, "build_cockpit_analytics", broken)
    response = app.test_client().get(query())
    assert response.status_code == 500
