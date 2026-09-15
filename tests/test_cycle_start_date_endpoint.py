"""Test endpoint /api/cycle_start_date — source serveur du mésocycle.

Contrats couverts :
 - GET → renvoie la date serveur (ou None si pas encore set)
 - GET/POST avec program_id → cible strictement ce programme
 - programme_data → contenu et cycle utilisent le même program_id
 - POST avec date valide → set réussi, retour success:True
 - POST sans date → 400 date_required (garde d'entrée)
 - program_id explicite invalide → aucun fallback arbitraire
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

import json
from unittest.mock import MagicMock
from conftest import BaseRouteTest


class TestCycleStartDateEndpoint(BaseRouteTest):

    def test_get_returns_current_cycle_start_date(self):
        db_mod = sys.modules["db"]
        db_mod.get_cycle_start_date = MagicMock(return_value="2026-04-25")

        r = self.get("/api/cycle_start_date")
        self.assertEqual(200, r.status_code)
        self.assertEqual({"date": "2026-04-25"}, self.json(r))

    def test_get_returns_null_when_no_cycle(self):
        db_mod = sys.modules["db"]
        db_mod.get_cycle_start_date = MagicMock(return_value=None)

        r = self.get("/api/cycle_start_date")
        self.assertEqual(200, r.status_code)
        self.assertIsNone(self.json(r)["date"])

    def test_get_returns_each_program_cycle(self):
        self.store["cycle_start_dates"] = {
            "program-a": "2026-01-05",
            "program-b": "2026-06-15",
        }

        cycle_a = self.json(self.get("/api/cycle_start_date?program_id=program-a"))
        cycle_b = self.json(self.get("/api/cycle_start_date?program_id=program-b"))

        self.assertEqual("2026-01-05", cycle_a["date"])
        self.assertEqual("2026-06-15", cycle_b["date"])

    def test_post_sets_cycle_start_date(self):
        db_mod = sys.modules["db"]
        db_mod.set_cycle_start_date = MagicMock(return_value=True)

        r = self.client.post(
            "/api/cycle_start_date",
            data=json.dumps({"date": "2026-07-20"}),
            content_type="application/json",
        )
        self.assertEqual(200, r.status_code)
        self.assertTrue(self.json(r)["success"])
        db_mod.set_cycle_start_date.assert_called_once_with("2026-07-20")

    def test_post_updates_only_explicit_program(self):
        self.store["cycle_start_dates"] = {
            "program-a": "2026-01-05",
            "program-b": "2026-06-15",
        }

        r = self.post("/api/cycle_start_date", {
            "date": "2026-09-01",
            "program_id": "program-b",
        })

        self.assertEqual(200, r.status_code)
        self.assertEqual("2026-01-05", self.store["cycle_start_dates"]["program-a"])
        self.assertEqual("2026-09-01", self.store["cycle_start_dates"]["program-b"])

    def test_programme_data_returns_selected_program_cycle(self):
        self.store["cycle_start_dates"] = {
            "program-a": "2026-01-05",
            "program-b": "2026-06-15",
        }

        r = self.get("/api/programme_data?program_id=program-b")

        self.assertEqual(200, r.status_code)
        self.assertEqual("program-b", self.json(r)["current_program_id"])
        self.assertEqual("2026-06-15", self.json(r)["cycle_start_date"])

    def test_invalid_program_get_does_not_return_default_cycle(self):
        self.store["cycle_start_date"] = "2026-01-05"

        r = self.get("/api/cycle_start_date?program_id=missing-program")

        self.assertEqual(200, r.status_code)
        self.assertIsNone(self.json(r)["date"])

    def test_invalid_program_post_does_not_modify_any_cycle(self):
        self.store["cycle_start_dates"] = {
            "program-a": "2026-01-05",
            "program-b": "2026-06-15",
        }
        before = dict(self.store["cycle_start_dates"])

        r = self.post("/api/cycle_start_date", {
            "date": "2026-09-01",
            "program_id": "missing-program",
        })

        self.assertEqual(500, r.status_code)
        self.assertEqual("cycle_start_date_persistence_failed", self.json(r)["error"])
        self.assertEqual(before, self.store["cycle_start_dates"])

    def test_post_without_date_returns_400(self):
        r = self.client.post(
            "/api/cycle_start_date",
            data=json.dumps({}),
            content_type="application/json",
        )
        self.assertEqual(400, r.status_code)
        self.assertEqual("date_required", self.json(r)["error"])
