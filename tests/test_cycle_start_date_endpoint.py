"""Test endpoint /api/cycle_start_date — source serveur du mésocycle.

3 cas :
 - GET → renvoie la date serveur (ou None si pas encore set)
 - POST avec date valide → set réussi, retour success:True
 - POST sans date → 400 date_required (garde d'entrée)
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

    def test_post_without_date_returns_400(self):
        r = self.client.post(
            "/api/cycle_start_date",
            data=json.dumps({}),
            content_type="application/json",
        )
        self.assertEqual(400, r.status_code)
        self.assertEqual("date_required", self.json(r)["error"])
