"""Local-date regression: schedule, dashboard and executable slots share a day."""
import sys
from unittest.mock import patch
from conftest import BaseRouteTest


class TestWorkoutDayContext(BaseRouteTest):
    def setUp(self):
        super().setUp()
        # Isolate planning from the R11 reference query; no applied references
        # exist in this fixture (the query has its own DatabaseContracts tests).
        references = patch("weights.coaching_references", return_value={})
        references.start()
        self.addCleanup(references.stop)
        self.store["active_program_id"] = "program-a"
        self.program = {"Jambes B": {"Squat": "3x5"}, "Thursday AM": {"Bench": "3x5"},
                        "Sunday PM": {"Carry": "3x10"}}
        self.patches = [
            patch.object(sys.modules["db"], "get_full_program", return_value=self.program),
            patch.object(sys.modules["db"], "get_relational_week_schedule",
                         return_value={"Dim": "Jambes B", "Jeu": "Thursday AM"}),
            patch.object(sys.modules["db"], "get_evening_week_schedule", return_value={"Dim": "Sunday PM"}),
            patch.object(sys.modules["db"], "get_session_override", return_value=None),
        ]
        for p in self.patches:
            p.start()
            self.addCleanup(p.stop)

    def test_sunday_dashboard_matches_schedule_and_execution(self):
        dashboard = self.json(self.get("/api/dashboard?date=2026-09-27"))
        morning = self.json(self.get("/api/seance_data?date=2026-09-27"))
        evening = self.json(self.get("/api/seance_soir_data?date=2026-09-27"))
        self.assertEqual("Jambes B", dashboard["today"])
        self.assertEqual(dashboard["schedule"]["Dim"], morning["today"])
        self.assertEqual("2026-09-27", morning["today_date"])
        self.assertEqual("Sunday PM", dashboard["evening_session_name"])
        self.assertEqual("Sunday PM", evening["today_soir"])
        self.assertEqual("2026-09-27", evening["today_date"])

    def test_explicit_thursday_is_not_sunday(self):
        dashboard = self.json(self.get("/api/dashboard?date=2026-09-24"))
        self.assertEqual("Thursday AM", dashboard["today"])

    def test_inactive_selection_does_not_change_dashboard(self):
        before = self.json(self.get("/api/dashboard?date=2026-09-27"))
        selected = self.json(self.get("/api/programme_data?program_id=program-b"))
        self.assertEqual("program-b", selected["current_program_id"])
        self.assertEqual("program-a", selected["active_program_id"])
        after = self.json(self.get("/api/dashboard?date=2026-09-27"))
        self.assertEqual(before["today"], after["today"])
        self.assertEqual(before["full_program"], after["full_program"])
        self.assertEqual("program-a", self.store["active_program_id"])

    def test_foreign_schedule_session_is_not_executable(self):
        from planner import sessions_for_date
        self.assertEqual(("Repos", None), sessions_for_date("2026-09-27", {"Other": {}}))

    def test_override_must_match_exact_date(self):
        from planner import sessions_for_date
        with patch.object(sys.modules["db"], "get_session_override",
                          return_value={"date": "2026-09-24", "session": "Thursday AM"}):
            self.assertEqual("Jambes B", sessions_for_date("2026-09-27", self.program)[0])
