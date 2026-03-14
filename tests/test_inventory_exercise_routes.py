"""
Tests: inventory and exercise CRUD routes.
Also verifies the P1/P2 audit fixes (rename propagation, delete cleanup).

Routes covered:
  POST /api/save_exercise  (create, update, rename)
  POST /api/delete_exercise
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

from conftest import BaseRouteTest


# ── /api/save_exercise ────────────────────────────────────────────────────────

class TestSaveExerciseCreate(BaseRouteTest):

    def test_create_new_exercise(self):
        r = self.post("/api/save_exercise", {
            "name": "Dumbbell Curl",
            "type": "dumbbell",
            "increment": 2.5,
            "default_scheme": "3x10-12",
        })
        self.assertEqual(200, r.status_code)
        self.assertIn("Dumbbell Curl", self.store["inventory"])

    def test_created_exercise_has_correct_type(self):
        self.post("/api/save_exercise", {
            "name": "Dumbbell Curl", "type": "dumbbell", "increment": 2.5,
        })
        self.assertEqual("dumbbell", self.store["inventory"]["Dumbbell Curl"]["type"])

    def test_create_returns_success(self):
        r = self.post("/api/save_exercise", {"name": "Push-up", "type": "bodyweight"})
        self.assertTrue(self.json(r).get("success"))

    def test_missing_name_returns_400(self):
        r = self.post("/api/save_exercise", {"type": "machine"})
        self.assertEqual(400, r.status_code)


class TestSaveExerciseUpdate(BaseRouteTest):

    def test_update_existing_exercise_type(self):
        self.post("/api/save_exercise", {
            "name": "Cable Fly", "type": "cable", "increment": 5,
            "default_scheme": "3x15",
        })
        self.assertEqual("cable", self.store["inventory"]["Cable Fly"]["type"])

    def test_update_default_scheme(self):
        self.post("/api/save_exercise", {
            "name": "Cable Fly", "type": "cable", "default_scheme": "4x12",
        })
        self.assertEqual("4x12", self.store["inventory"]["Cable Fly"]["default_scheme"])


class TestSaveExerciseRename(BaseRouteTest):
    """P1 fix: rename must propagate to program using block-format traversal."""

    def test_rename_updates_inventory_key(self):
        self.post("/api/save_exercise", {
            "original_name": "Bench Press",
            "name": "Barbell Bench Press",
            "type": "barbell",
        })
        self.assertIn("Barbell Bench Press", self.store["inventory"])
        self.assertNotIn("Bench Press", self.store["inventory"])

    def test_rename_propagates_to_program_strength_block(self):
        """P1: rename from Inventaire must update exercise in program sessions."""
        self.post("/api/save_exercise", {
            "original_name": "Bench Press",
            "name": "Barbell Bench Press",
            "type": "barbell",
        })
        # Bench Press was in Upper A strength block — should now be Barbell Bench Press
        strength = next(
            b for b in self.store["program"]["Upper A"]["blocks"]
            if b["type"] == "strength"
        )
        self.assertIn("Barbell Bench Press", strength["exercises"])
        self.assertNotIn("Bench Press", strength["exercises"])

    def test_rename_preserves_scheme_in_program(self):
        old_scheme = next(
            b for b in self.store["program"]["Upper A"]["blocks"]
            if b["type"] == "strength"
        )["exercises"]["Bench Press"]

        self.post("/api/save_exercise", {
            "original_name": "Bench Press",
            "name": "Barbell Bench Press",
            "type": "barbell",
        })
        strength = next(
            b for b in self.store["program"]["Upper A"]["blocks"]
            if b["type"] == "strength"
        )
        self.assertEqual(old_scheme, strength["exercises"]["Barbell Bench Press"])

    def test_rename_preserves_other_exercises_in_session(self):
        self.post("/api/save_exercise", {
            "original_name": "Bench Press",
            "name": "Barbell Bench Press",
            "type": "barbell",
        })
        strength = next(
            b for b in self.store["program"]["Upper A"]["blocks"]
            if b["type"] == "strength"
        )
        self.assertIn("Barbell Row", strength["exercises"])
        self.assertIn("Overhead Press", strength["exercises"])


# ── /api/delete_exercise ─────────────────────────────────────────────────────

class TestDeleteExercise(BaseRouteTest):

    def test_delete_removes_from_inventory(self):
        r = self.post("/api/delete_exercise", {"name": "Cable Fly"})
        self.assertEqual(200, r.status_code)
        self.assertNotIn("Cable Fly", self.store["inventory"])

    def test_delete_unknown_returns_404(self):
        r = self.post("/api/delete_exercise", {"name": "Does Not Exist"})
        self.assertEqual(404, r.status_code)

    def test_delete_removes_from_program_strength_block(self):
        """P2 fix: deleting from inventory must also clean up program references."""
        # Bench Press is in Upper A
        r = self.post("/api/delete_exercise", {"name": "Bench Press"})
        self.assertEqual(200, r.status_code)
        strength = next(
            b for b in self.store["program"]["Upper A"]["blocks"]
            if b["type"] == "strength"
        )
        self.assertNotIn("Bench Press", strength["exercises"])

    def test_delete_preserves_other_exercises_in_program(self):
        self.post("/api/delete_exercise", {"name": "Bench Press"})
        strength = next(
            b for b in self.store["program"]["Upper A"]["blocks"]
            if b["type"] == "strength"
        )
        self.assertIn("Barbell Row", strength["exercises"])

    def test_delete_does_not_touch_weights_history(self):
        """Deleting from inventory must NOT remove exercise history from weights."""
        self.post("/api/delete_exercise", {"name": "Bench Press"})
        self.assertIn("Bench Press", self.store["weights"])
        self.assertEqual(2, len(self.store["weights"]["Bench Press"]["history"]))

    def test_delete_exercise_not_in_program_succeeds(self):
        """Deleting Cable Fly (not in any session) should still succeed cleanly."""
        r = self.post("/api/delete_exercise", {"name": "Cable Fly"})
        self.assertEqual(200, r.status_code)


if __name__ == "__main__":
    import unittest
    unittest.main(verbosity=2)
