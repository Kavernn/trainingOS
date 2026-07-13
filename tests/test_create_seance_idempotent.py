"""
Tests: /api/programme action=create_seance idempotent + observabilité.
Vérifie que create_seance ne rappelle PAS save_full_program si la session existe déjà,
protégeant le garde-fou "refusing to save 0 exercises over N existing" contre un
double-tap iOS ou un rejeu SyncManager.

Match exact aligné sur l'index unique (program_id, name) : sensible casse/accents.
"""
import sys, os
from unittest.mock import patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

from conftest import BaseRouteTest


class TestCreateSeanceIdempotent(BaseRouteTest):

    def test_create_seance_new_name_creates_session(self):
        r = self.post("/api/programme", {"action": "create_seance", "jour": "Hôtel"})
        self.assertEqual(200, r.status_code)
        body = r.get_json()
        self.assertTrue(body["success"])
        self.assertTrue(body["created"])
        self.assertIn("Hôtel", self.store["program"])

    def test_create_seance_existing_name_is_noop(self):
        original_blocks = list(self.store["program"]["Upper A"]["blocks"])
        r = self.post("/api/programme", {"action": "create_seance", "jour": "Upper A"})
        self.assertEqual(200, r.status_code)
        body = r.get_json()
        self.assertTrue(body["success"])
        self.assertFalse(body["created"])
        self.assertEqual(original_blocks, self.store["program"]["Upper A"]["blocks"])

    def test_create_seance_existing_does_not_call_save_full_program(self):
        import db as _db
        with patch.object(_db, "save_full_program", wraps=_db.save_full_program) as spy:
            self.post("/api/programme", {"action": "create_seance", "jour": "Upper A"})
            spy.assert_not_called()

    def test_create_seance_double_call_second_is_noop(self):
        r1 = self.post("/api/programme", {"action": "create_seance", "jour": "Hôtel"})
        r2 = self.post("/api/programme", {"action": "create_seance", "jour": "Hôtel"})
        self.assertTrue(r1.get_json()["created"])
        self.assertFalse(r2.get_json()["created"])

    def test_create_seance_case_variant_creates_distinct_session(self):
        # Sémantique index Postgres TEXT par défaut : sensible casse/accents.
        # "hôtel" ≠ "Hôtel" côté DB (index unique), donc côté route aussi.
        r1 = self.post("/api/programme", {"action": "create_seance", "jour": "Hôtel"})
        r2 = self.post("/api/programme", {"action": "create_seance", "jour": "hôtel"})
        self.assertTrue(r1.get_json()["created"])
        self.assertTrue(r2.get_json()["created"])
        self.assertIn("Hôtel", self.store["program"])
        self.assertIn("hôtel", self.store["program"])
