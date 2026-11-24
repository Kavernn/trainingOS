"""Incident 2026-11-24 : programme_data?program_id=<consulté> renvoyait le planning de l'actif."""
import sys
from unittest.mock import patch
from conftest import BaseRouteTest


class TestProgrammeDataSchedule(BaseRouteTest):
    def test_schedule_is_the_loaded_programs_own(self):
        db = sys.modules["db"]
        calls = []
        def sched(*, strict=False, program_id=None):
            calls.append(program_id)
            return {"Mar": "Mardi AM — Pull A"} if program_id == "v4" else {"Mar": "Mardi Pull A"}
        with patch.object(db, "get_relational_week_schedule", side_effect=sched), \
             patch.object(db, "get_active_program_id", return_value="hiver"):
            r = self.get("/api/programme_data?program_id=v4")
        self.assertEqual(200, r.status_code)
        self.assertEqual({"Mar": "Mardi AM — Pull A"}, self.json(r)["schedule"])
        self.assertIn("v4", calls)
