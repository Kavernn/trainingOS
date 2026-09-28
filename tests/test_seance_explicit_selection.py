"""Explicit reads must not relabel the dated override's exercise body."""
import copy
import json
from pathlib import Path
import sys
from types import SimpleNamespace
from unittest.mock import patch

from conftest import BaseRouteTest


class TestSeanceExplicitSelection(BaseRouteTest):
    def setUp(self):
        super().setUp()
        self.db = sys.modules["db"]
        self.program = {"A": {"A1": "3x10", "A2": "3x10"},
                        "B": {"B1": "3x10", "B2": "3x10", "B3": "3x10"},
                        "PM": {"P1": "3x10"}}
        for name, value in {
            "get_full_program": self.program,
            "get_relational_week_schedule": {"Dim": "B"},
            "get_evening_week_schedule": {"Dim": "PM"},
            "get_session_override": {"date": "2088-09-26", "session": "A"},
            "get_session_plan_overrides": [],
        }.items():
            p = patch.object(self.db, name, return_value=value)
            p.start()
            self.addCleanup(p.stop)

    def read(self, selector=""):
        return self.get("/api/seance_data?date=2088-09-26" + selector)

    def assert_body(self, response, name, exercises):
        self.assertEqual(200, response.status_code)
        data = self.json(response)
        self.assertEqual(name, data["today"])
        self.assertEqual(sorted(exercises), sorted(data["full_program"][name]))
        self.assertEqual(exercises, data["exercise_order"][name])
        return data

    def test_explicit_b_contract_shared_with_swift(self):
        before = copy.deepcopy(self.store)
        with patch("weights.load_weights", return_value={}) as load_weights:
            data = self.assert_body(self.read("&session_name=B"), "B", ["B1", "B2", "B3"])
            self.assertTrue({"B1", "B2", "B3"}.issubset(load_weights.call_args.args[0]))
        self.assertTrue({"B1", "B2", "B3"}.issubset(data["prescriptions"]))
        fixture = json.loads((Path(__file__).parent / "fixtures/seance_explicit_selection.json").read_text())
        for key in ("today", "today_date", "already_logged", "full_program", "exercise_order", "session_type"):
            self.assertEqual(fixture[key], data[key], key)
        self.assertEqual(["B1", "B2", "B3"], [s["exercise"] for s in data["suggestions"]])
        self.assertEqual(before, self.store, "A GET must not change stored user data")

    def test_no_selector_preserves_override(self):
        self.assert_body(self.read(), "A", ["A1", "A2"])

    def test_equal_selector_preserves_override(self):
        self.assert_body(self.read("&session_name=A"), "A", ["A1", "A2"])

    def test_invalid_selector_does_not_fall_back(self):
        self.assertEqual(404, self.read("&session_name=Missing").status_code)

    def test_explicit_evening_uses_real_moved_exercises(self):
        self.db.get_session_plan_overrides.return_value = [
            {"exercise_id": "a2", "from_session_type": "morning", "to_session_type": "evening"}]
        self.db._client.table.return_value.select.return_value.in_.return_value.execute.return_value = SimpleNamespace(
            data=[{"id": "a2", "name": "A2"}])
        self.assert_body(self.read(), "A", ["A1"])
        self.assert_body(self.read("&session_name=A"), "A", ["A1"])
        data = self.assert_body(self.read("&session_name=PM"), "PM", ["P1", "A2"])
        self.assertEqual("evening", data["session_type"])
        self.assertEqual({"A2", "P1"}, {s["exercise"] for s in data["suggestions"]})

    def test_explicit_morning_preserves_reverse_move_without_contaminating_b(self):
        self.db.get_session_plan_overrides.return_value = [
            {"exercise_id": "p1", "from_session_type": "evening", "to_session_type": "morning"}]
        self.db._client.table.return_value.select.return_value.in_.return_value.execute.return_value = SimpleNamespace(
            data=[{"id": "p1", "name": "P1"}])
        self.assert_body(self.read("&session_name=A"), "A", ["A1", "A2", "P1"])
        self.assert_body(self.read("&session_name=PM"), "PM", [])
        self.assert_body(self.read("&session_name=B"), "B", ["B1", "B2", "B3"])
