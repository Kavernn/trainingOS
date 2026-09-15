"""Persistence contract for program-scoped mesocycle cycle dates."""

import os
import sys
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

import db_programs


class _ProgramsQuery:
    def __init__(self, rows):
        self.rows = rows
        self.operation = None
        self.payload = None
        self.filters = []

    def select(self, *_columns):
        self.operation = "select"
        return self

    def update(self, payload):
        self.operation = "update"
        self.payload = dict(payload)
        return self

    def eq(self, column, value):
        self.filters.append((column, value))
        return self

    def execute(self):
        matching = [
            row for row in self.rows
            if all(row.get(column) == value for column, value in self.filters)
        ]
        if self.operation == "select":
            return SimpleNamespace(data=[dict(row) for row in matching])
        if self.operation == "update":
            for row in matching:
                row.update(self.payload)
            return SimpleNamespace(data=[dict(row) for row in matching])
        raise AssertionError(f"Unsupported operation: {self.operation}")


class _Client:
    def __init__(self):
        self.programs = [
            {"id": "program-a", "cycle_start_date": "2026-01-05"},
            {"id": "program-b", "cycle_start_date": "2026-06-15"},
        ]

    def table(self, table_name):
        assert table_name == "programs"
        return _ProgramsQuery(self.programs)


def _program_dates(client):
    return {row["id"]: row["cycle_start_date"] for row in client.programs}


def _db_context(client):
    return (
        patch.object(db_programs.db_core, "_client", client),
        patch.object(db_programs.db_core, "MODE", "ONLINE"),
        patch.object(db_programs, "get_default_program_id", return_value="program-a"),
    )


def test_read_cycle_is_scoped_to_explicit_program():
    client = _Client()
    client_patch, mode_patch, default_patch = _db_context(client)
    with client_patch, mode_patch, default_patch:
        assert db_programs.get_cycle_start_date("program-a") == "2026-01-05"
        assert db_programs.get_cycle_start_date("program-b") == "2026-06-15"


def test_write_and_reset_are_scoped_to_explicit_program():
    client = _Client()
    client_patch, mode_patch, default_patch = _db_context(client)
    with client_patch, mode_patch, default_patch:
        assert db_programs.set_cycle_start_date("2026-02-02", "program-a") is True
        assert _program_dates(client) == {
            "program-a": "2026-02-02",
            "program-b": "2026-06-15",
        }

        assert db_programs.set_cycle_start_date("2026-09-01", "program-b") is True
        assert _program_dates(client) == {
            "program-a": "2026-02-02",
            "program-b": "2026-09-01",
        }


def test_absent_program_id_keeps_historical_default_fallback():
    client = _Client()
    client_patch, mode_patch, default_patch = _db_context(client)
    with client_patch, mode_patch, default_patch:
        assert db_programs.get_cycle_start_date() == "2026-01-05"
        assert db_programs.set_cycle_start_date("2026-03-03") is True

    assert _program_dates(client) == {
        "program-a": "2026-03-03",
        "program-b": "2026-06-15",
    }


def test_invalid_explicit_program_never_falls_back_to_default():
    client = _Client()
    before = _program_dates(client)
    client_patch, mode_patch, default_patch = _db_context(client)
    with client_patch, mode_patch, default_patch:
        assert db_programs.get_cycle_start_date("missing-program") is None
        assert db_programs.set_cycle_start_date("2026-09-01", "missing-program") is False

    assert _program_dates(client) == before
