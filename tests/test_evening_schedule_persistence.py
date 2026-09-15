import os
import sys
from types import SimpleNamespace
from unittest.mock import patch

from flask import Flask

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

import db_programs
from routes.workout_schedule import workout_schedule_bp


class _Query:
    def __init__(self, client, table_name):
        self.client = client
        self.table_name = table_name
        self.operation = None
        self.payload = None
        self.on_conflict = None
        self.filters = []

    def select(self, *_columns):
        self.operation = "select"
        return self

    def delete(self):
        self.operation = "delete"
        return self

    def upsert(self, payload, on_conflict=None):
        self.operation = "upsert"
        self.payload = dict(payload)
        self.on_conflict = on_conflict
        return self

    def eq(self, column, value):
        self.filters.append((column, value))
        return self

    def execute(self):
        rows = self.client.store[self.table_name]
        matching = [
            row for row in rows
            if all(row.get(column) == value for column, value in self.filters)
        ]

        if self.operation == "select":
            if self.table_name == "weekly_schedule":
                data = []
                sessions = {row["id"]: row for row in self.client.store["program_sessions"]}
                for row in matching:
                    result = dict(row)
                    session = sessions.get(row.get("session_id"))
                    result["program_sessions"] = (
                        {"name": session["name"]} if session is not None else None
                    )
                    data.append(result)
            else:
                data = [dict(row) for row in matching]
            return SimpleNamespace(data=data)

        if self.operation == "delete":
            self.client.store[self.table_name] = [
                row for row in rows
                if not all(row.get(column) == value for column, value in self.filters)
            ]
            return SimpleNamespace(data=[])

        if self.operation == "upsert":
            keys = self.on_conflict.split(",") if self.on_conflict else []
            match = tuple(self.payload.get(key) for key in keys)
            for index, row in enumerate(rows):
                if tuple(row.get(key) for key in keys) == match:
                    rows[index] = dict(self.payload)
                    return SimpleNamespace(data=[dict(self.payload)])
            rows.append(dict(self.payload))
            return SimpleNamespace(data=[dict(self.payload)])

        raise AssertionError(f"Unsupported operation: {self.operation}")


class _Client:
    def __init__(self):
        self.store = {
            "program_sessions": [
                {"id": "push", "name": "Push B", "program_id": "program-1"},
                {"id": "pull", "name": "Pull B", "program_id": "program-1"},
                {"id": "legs", "name": "Jambes B", "program_id": "program-1"},
            ],
            "weekly_schedule": [],
        }

    def table(self, table_name):
        return _Query(self, table_name)


def _schedule_row(day, slot, session_id):
    return {"day_name": day, "slot": slot, "session_id": session_id}


def _save(client, snapshot):
    with patch.object(db_programs.db_core, "_client", client), \
         patch.object(db_programs.db_core, "MODE", "ONLINE"), \
         patch.object(db_programs, "get_active_program_id", return_value="program-1"):
        assert db_programs.set_evening_week_schedule(snapshot) is True


def _fetch(client):
    with patch.object(db_programs.db_core, "_client", client), \
         patch.object(db_programs.db_core, "MODE", "ONLINE"):
        return db_programs.get_evening_week_schedule()


def test_create_and_modify_evening_assignment():
    client = _Client()

    _save(client, {"Sam": "Pull B"})
    assert _fetch(client) == {"Sam": "Pull B"}

    _save(client, {"Sam": "Jambes B"})
    assert _fetch(client) == {"Sam": "Jambes B"}


def test_partial_snapshot_removes_missing_day_and_preserves_present_days():
    client = _Client()
    client.store["weekly_schedule"] = [
        _schedule_row("Ven", "evening", "push"),
        _schedule_row("Sam", "evening", "pull"),
        _schedule_row("Dim", "evening", "legs"),
    ]

    _save(client, {"Ven": "Push B", "Dim": "Jambes B"})

    assert _fetch(client) == {"Ven": "Push B", "Dim": "Jambes B"}
    assert not any(
        row["day_name"] == "Sam" and row["slot"] == "evening"
        for row in client.store["weekly_schedule"]
    )


def test_empty_snapshot_removes_all_evening_assignments():
    client = _Client()
    client.store["weekly_schedule"] = [
        _schedule_row("Ven", "evening", "push"),
        _schedule_row("Sam", "evening", "pull"),
    ]

    _save(client, {})

    assert _fetch(client) == {}
    assert not any(row["slot"] == "evening" for row in client.store["weekly_schedule"])


def test_evening_clear_does_not_touch_morning_assignment():
    client = _Client()
    client.store["weekly_schedule"] = [
        _schedule_row("Sam", "morning", "pull"),
        _schedule_row("Sam", "evening", "pull"),
    ]

    _save(client, {})

    assert client.store["weekly_schedule"] == [
        _schedule_row("Sam", "morning", "pull")
    ]
    assert _fetch(client) == {}


def test_evening_schedule_endpoint_returns_500_when_persistence_fails():
    app = Flask(__name__)
    app.register_blueprint(workout_schedule_bp)
    failing_db = SimpleNamespace(set_evening_week_schedule=lambda _schedule: False)

    with patch.dict(sys.modules, {"db": failing_db}):
        response = app.test_client().post("/api/evening_schedule", json={})

    assert response.status_code == 500
    assert response.get_json() == {
        "success": False,
        "error": "evening_schedule_persistence_failed",
    }
