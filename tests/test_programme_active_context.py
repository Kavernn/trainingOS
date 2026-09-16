"""Contrat multi-programme : programme chargé != programme actif."""

import sys
from unittest.mock import MagicMock
from conftest import BaseRouteTest


class TestProgrammeActiveContext(BaseRouteTest):

    def setUp(self):
        super().setUp()
        self.store["active_program_id"] = "program-a"

    def test_active_program_load_reports_same_current_and_active_ids(self):
        data = self.json(self.get("/api/programme_data?program_id=program-a"))

        self.assertEqual("program-a", data["current_program_id"])
        self.assertEqual("program-a", data["active_program_id"])

    def test_non_active_program_load_keeps_active_id_separate(self):
        data = self.json(self.get("/api/programme_data?program_id=program-b"))

        self.assertEqual("program-b", data["current_program_id"])
        self.assertEqual("program-a", data["active_program_id"])

    def test_loading_non_active_program_does_not_activate_it(self):
        self.get("/api/programme_data?program_id=program-b")

        self.assertEqual("program-a", self.store["active_program_id"])

    def test_set_active_changes_future_active_program_field(self):
        response = self.post("/api/programs", {
            "action": "set_active",
            "program_id": "program-b",
        })
        self.assertEqual(200, response.status_code)

        data = self.json(self.get("/api/programme_data?program_id=program-b"))
        self.assertEqual("program-b", data["current_program_id"])
        self.assertEqual("program-b", data["active_program_id"])

    def test_selected_program_content_mutation_does_not_require_activation(self):
        db_mod = sys.modules["db"]
        db_mod.get_full_program = MagicMock(return_value={})
        db_mod.save_full_program = MagicMock(return_value=True)

        response = self.post("/api/programme", {
            "action": "create_seance",
            "jour": "Session B",
            "program_id": "program-b",
        })

        self.assertEqual(200, response.status_code)
        self.assertTrue(self.json(response)["success"])
        self.assertEqual("program-a", self.store["active_program_id"])
        self.assertEqual("program-b", db_mod.save_full_program.call_args.args[1])
