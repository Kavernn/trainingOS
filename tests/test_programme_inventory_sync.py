"""
Tests: /api/programme mutations with inventory synchronization.
Verifies P3 (replace creates inventory) and P4 (add creates inventory) audit fixes,
plus all other programme actions (scheme, rename, reorder, add_block, remove_block).

Routes covered:
  POST /api/programme
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

from conftest import BaseRouteTest


def _strength_exos(store, jour):
    for b in store["program"][jour]["blocks"]:
        if b["type"] == "strength":
            return b["exercises"]
    return {}


# ── add ───────────────────────────────────────────────────────────────────────

class TestProgrammeAdd(BaseRouteTest):

    def test_add_inserts_exercise_in_program(self):
        r = self.post("/api/programme", {
            "action": "add", "jour": "Upper A",
            "exercise": "Cable Fly", "scheme": "3x12-15",
        })
        self.assertEqual(200, r.status_code)
        self.assertIn("Cable Fly", _strength_exos(self.store, "Upper A"))

    def test_add_duplicate_returns_400(self):
        r = self.post("/api/programme", {
            "action": "add", "jour": "Upper A",
            "exercise": "Bench Press", "scheme": "4x5-7",
        })
        self.assertEqual(400, r.status_code)

    def test_add_seeds_inventory_entry(self):
        """P4: adding an exercise not in inventory must create a minimal entry."""
        self.post("/api/programme", {
            "action": "add", "jour": "Upper A",
            "exercise": "Z-New Move", "scheme": "3x10",
        })
        self.assertIn("Z-New Move", self.store["inventory"])

    def test_add_inventory_entry_has_scheme(self):
        self.post("/api/programme", {
            "action": "add", "jour": "Upper A",
            "exercise": "Z-New Move", "scheme": "3x10",
        })
        self.assertEqual("3x10", self.store["inventory"]["Z-New Move"]["default_scheme"])

    def test_add_existing_inventory_not_overwritten(self):
        """If inventory already has the exercise, add must not overwrite it."""
        original_type = self.store["inventory"]["Cable Fly"]["type"]
        self.post("/api/programme", {
            "action": "add", "jour": "Upper A",
            "exercise": "Cable Fly", "scheme": "3x12",
        })
        # Cable Fly already existed — type must not be changed to "machine"
        self.assertEqual(original_type, self.store["inventory"]["Cable Fly"]["type"])


# ── remove ───────────────────────────────────────────────────────────────────

class TestProgrammeRemove(BaseRouteTest):

    def test_remove_deletes_from_program(self):
        self.post("/api/programme", {
            "action": "remove", "jour": "Upper A", "exercise": "Bench Press",
        })
        self.assertNotIn("Bench Press", _strength_exos(self.store, "Upper A"))

    def test_remove_preserves_inventory(self):
        """Spec: removing from program must NOT delete from inventory."""
        self.post("/api/programme", {
            "action": "remove", "jour": "Upper A", "exercise": "Bench Press",
        })
        self.assertIn("Bench Press", self.store["inventory"])

    def test_remove_preserves_weights_history(self):
        self.post("/api/programme", {
            "action": "remove", "jour": "Upper A", "exercise": "Bench Press",
        })
        self.assertIn("Bench Press", self.store["weights"])


# ── scheme ────────────────────────────────────────────────────────────────────

class TestProgrammeScheme(BaseRouteTest):

    def test_scheme_updates_program(self):
        self.post("/api/programme", {
            "action": "scheme", "jour": "Upper A",
            "exercise": "Bench Press", "scheme": "5x3",
        })
        self.assertEqual("5x3", _strength_exos(self.store, "Upper A")["Bench Press"])

    def test_scheme_updates_inventory(self):
        self.post("/api/programme", {
            "action": "scheme", "jour": "Upper A",
            "exercise": "Bench Press", "scheme": "5x3",
        })
        self.assertEqual("5x3", self.store["inventory"]["Bench Press"]["default_scheme"])


# ── replace ───────────────────────────────────────────────────────────────────

class TestProgrammeReplace(BaseRouteTest):

    def test_replace_swaps_exercise_in_program(self):
        self.post("/api/programme", {
            "action": "replace", "jour": "Upper A",
            "old_exercise": "Bench Press",
            "new_exercise": "Incline DB Press",
            "scheme": "4x8-10",
        })
        exos = _strength_exos(self.store, "Upper A")
        self.assertNotIn("Bench Press", exos)
        self.assertIn("Incline DB Press", exos)

    def test_replace_creates_inventory_entry_for_new(self):
        """P3: replace must create inventory entry for the new exercise."""
        self.post("/api/programme", {
            "action": "replace", "jour": "Upper A",
            "old_exercise": "Bench Press",
            "new_exercise": "Incline DB Press",
            "scheme": "4x8-10",
        })
        self.assertIn("Incline DB Press", self.store["inventory"])

    def test_replace_new_entry_has_scheme(self):
        self.post("/api/programme", {
            "action": "replace", "jour": "Upper A",
            "old_exercise": "Bench Press",
            "new_exercise": "Incline DB Press",
            "scheme": "4x8-10",
        })
        self.assertEqual("4x8-10", self.store["inventory"]["Incline DB Press"]["default_scheme"])

    def test_replace_inherits_old_type_if_available(self):
        """New exercise inherits type from old inventory entry."""
        self.post("/api/programme", {
            "action": "replace", "jour": "Upper A",
            "old_exercise": "Bench Press",   # type=barbell in fixture
            "new_exercise": "Close Grip Bench",
            "scheme": "3x6-8",
        })
        # Should inherit "barbell" from Bench Press
        self.assertEqual("barbell", self.store["inventory"]["Close Grip Bench"]["type"])

    def test_replace_existing_inventory_not_overwritten(self):
        """If new exercise already exists in inventory, don't overwrite it."""
        self.post("/api/programme", {
            "action": "replace", "jour": "Upper A",
            "old_exercise": "Bench Press",
            "new_exercise": "Cable Fly",   # already in inventory as "cable"
            "scheme": "3x12",
        })
        self.assertEqual("cable", self.store["inventory"]["Cable Fly"]["type"])


# ── rename ────────────────────────────────────────────────────────────────────

class TestProgrammeRename(BaseRouteTest):

    def test_rename_updates_all_sessions(self):
        # Put Bench Press in Lower too
        lower_strength = next(
            b for b in self.store["program"]["Lower"]["blocks"]
            if b["type"] == "strength"
        )
        lower_strength["exercises"]["Bench Press"] = "3x10"

        self.post("/api/programme", {
            "action": "rename", "jour": "Upper A",
            "old_exercise": "Bench Press",
            "new_exercise": "BB Bench Press",
        })
        for jour in ("Upper A", "Lower"):
            exos = _strength_exos(self.store, jour)
            self.assertNotIn("Bench Press", exos)
            self.assertIn("BB Bench Press", exos)

    def test_rename_updates_inventory_key(self):
        self.post("/api/programme", {
            "action": "rename", "jour": "Upper A",
            "old_exercise": "Bench Press",
            "new_exercise": "BB Bench Press",
        })
        self.assertIn("BB Bench Press", self.store["inventory"])
        self.assertNotIn("Bench Press", self.store["inventory"])


# ── reorder ───────────────────────────────────────────────────────────────────

class TestProgrammeReorder(BaseRouteTest):

    def test_reorder_changes_exercise_order(self):
        self.post("/api/programme", {
            "action": "reorder", "jour": "Upper A",
            "ordre": ["Overhead Press", "Barbell Row", "Bench Press"],
        })
        self.assertEqual(
            ["Overhead Press", "Barbell Row", "Bench Press"],
            list(_strength_exos(self.store, "Upper A").keys()),
        )

    def test_reorder_preserves_schemes(self):
        before = dict(_strength_exos(self.store, "Upper A"))
        self.post("/api/programme", {
            "action": "reorder", "jour": "Upper A",
            "ordre": ["Overhead Press", "Barbell Row", "Bench Press"],
        })
        for ex, scheme in _strength_exos(self.store, "Upper A").items():
            self.assertEqual(before[ex], scheme)


# ── add_block / remove_block ──────────────────────────────────────────────────

class TestProgrammeBlocks(BaseRouteTest):

    def test_add_hiit_block(self):
        r = self.post("/api/programme", {
            "action": "add_block", "jour": "Upper A",
            "block_type": "hiit",
            "hiit_config": {"sprint": 30, "rest": 90, "rounds": 8},
        })
        self.assertEqual(200, r.status_code)
        hiit_blocks = [
            b for b in self.store["program"]["Upper A"]["blocks"]
            if b["type"] == "hiit"
        ]
        self.assertEqual(1, len(hiit_blocks))

    def test_remove_hiit_block(self):
        self.post("/api/programme", {
            "action": "add_block", "jour": "Upper A",
            "block_type": "hiit",
        })
        r = self.post("/api/programme", {
            "action": "remove_block", "jour": "Upper A", "block_type": "hiit",
        })
        self.assertEqual(200, r.status_code)
        hiit_blocks = [
            b for b in self.store["program"]["Upper A"]["blocks"]
            if b["type"] == "hiit"
        ]
        self.assertEqual(0, len(hiit_blocks))

    def test_invalid_jour_returns_400(self):
        r = self.post("/api/programme", {
            "action": "add", "jour": "Nonexistent Day",
            "exercise": "X", "scheme": "3x10",
        })
        self.assertEqual(400, r.status_code)


# ── Bug-fix regressions ───────────────────────────────────────────────────────

class TestAddInheritInventoryScheme(BaseRouteTest):
    """Bug fix: add without explicit scheme must use inventory default_scheme."""

    def test_add_no_scheme_uses_inventory_default(self):
        # Cable Fly is in inventory with default_scheme "3x12-15"
        self.post("/api/programme", {
            "action": "add", "jour": "Upper A",
            "exercise": "Cable Fly",
            # no "scheme" key — should inherit from inventory
        })
        self.assertEqual("3x12-15", _strength_exos(self.store, "Upper A")["Cable Fly"])

    def test_add_explicit_scheme_overrides_inventory(self):
        self.post("/api/programme", {
            "action": "add", "jour": "Upper A",
            "exercise": "Cable Fly", "scheme": "4x10",
        })
        self.assertEqual("4x10", _strength_exos(self.store, "Upper A")["Cable Fly"])

    def test_add_no_scheme_unknown_exercise_defaults_to_3x8_12(self):
        self.post("/api/programme", {
            "action": "add", "jour": "Upper A",
            "exercise": "Brand New Move",
        })
        self.assertEqual("3x8-12", _strength_exos(self.store, "Upper A")["Brand New Move"])


class TestSchemeNoFuzzyMatch(BaseRouteTest):
    """Bug fix: scheme action must use exact inventory key, not fuzzy substring match."""

    def setUp(self):
        super().setUp()
        # Add an exercise whose name contains another's name
        self.store["inventory"]["Incline Bench Press"] = {
            "type": "barbell", "default_scheme": "3x8-10", "increment": 5,
        }
        self.store["program"]["Upper A"]["blocks"][0]["exercises"]["Incline Bench Press"] = "3x8-10"

    def test_scheme_updates_exact_inventory_key(self):
        self.post("/api/programme", {
            "action": "scheme", "jour": "Upper A",
            "exercise": "Bench Press", "scheme": "5x3",
        })
        self.assertEqual("5x3", self.store["inventory"]["Bench Press"]["default_scheme"])

    def test_scheme_does_not_corrupt_similar_name(self):
        """Fuzzy match bug: updating 'Bench Press' must NOT touch 'Incline Bench Press'."""
        self.post("/api/programme", {
            "action": "scheme", "jour": "Upper A",
            "exercise": "Bench Press", "scheme": "5x3",
        })
        self.assertEqual("3x8-10", self.store["inventory"]["Incline Bench Press"]["default_scheme"])


class TestReplaceUpdatesExistingInventoryScheme(BaseRouteTest):
    """Bug fix: replace must update default_scheme in inventory even when new_ex already exists."""

    def test_replace_existing_inventory_scheme_updated(self):
        # Cable Fly already in inventory as "3x12-15"
        self.post("/api/programme", {
            "action": "replace", "jour": "Upper A",
            "old_exercise": "Bench Press",
            "new_exercise": "Cable Fly",
            "scheme": "4x10",
        })
        self.assertEqual("4x10", self.store["inventory"]["Cable Fly"]["default_scheme"])

    def test_replace_existing_inventory_type_preserved(self):
        self.post("/api/programme", {
            "action": "replace", "jour": "Upper A",
            "old_exercise": "Bench Press",
            "new_exercise": "Cable Fly",
            "scheme": "4x10",
        })
        self.assertEqual("cable", self.store["inventory"]["Cable Fly"]["type"])


class TestRenameNoFuzzyMatch(BaseRouteTest):
    """Bug fix: rename must use exact inventory key, not fuzzy substring match."""

    def setUp(self):
        super().setUp()
        # Add a second exercise whose name contains the renamed one
        self.store["inventory"]["Barbell Row Variant"] = {
            "type": "barbell", "default_scheme": "4x6-8", "increment": 5,
        }

    def test_rename_exact_key_updated(self):
        self.post("/api/programme", {
            "action": "rename", "jour": "Upper A",
            "old_exercise": "Barbell Row",
            "new_exercise": "Pendlay Row",
        })
        self.assertIn("Pendlay Row", self.store["inventory"])
        self.assertNotIn("Barbell Row", self.store["inventory"])

    def test_rename_does_not_touch_similar_name(self):
        """Fuzzy match bug: renaming 'Barbell Row' must NOT remove 'Barbell Row Variant'."""
        self.post("/api/programme", {
            "action": "rename", "jour": "Upper A",
            "old_exercise": "Barbell Row",
            "new_exercise": "Pendlay Row",
        })
        self.assertIn("Barbell Row Variant", self.store["inventory"])


if __name__ == "__main__":
    import unittest
    unittest.main(verbosity=2)
