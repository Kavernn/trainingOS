"""Routes planning : ?program_id= explicite → planning de ce programme, jamais du programme actif."""
from conftest import BaseRouteTest


class TestScheduleRoutesProgramId(BaseRouteTest):
    def test_morning_and_evening_target_explicit_program(self):
        r = self.post("/api/morning_schedule?program_id=winter", {"schedule": {"Lun": "Lundi Push A", "Dim": "Repos"}})
        self.assertEqual(self.json(r), {"success": True})
        self.assertEqual(self.store["morning_schedule:winter"], {"Lun": "Lundi Push A", "Dim": None})
        self.assertNotIn("morning_schedule", self.store)          # programme actif non touché
        self.assertEqual(self.json(self.get("/api/morning_schedule?program_id=winter")), {"Lun": "Lundi Push A", "Dim": None})
        self.assertEqual(self.json(self.post("/api/evening_schedule?program_id=winter", {})), {"success": True})
        self.assertEqual(self.store["evening_schedule:winter"], {})

    def test_without_program_id_keeps_active_program(self):
        self.post("/api/morning_schedule", {"schedule": {"Lun": "Push A"}})
        self.assertEqual(self.store["morning_schedule"], {"Lun": "Push A"})

    def test_empty_program_id_is_refused_never_active_fallback(self):
        for path in ("/api/morning_schedule?program_id=", "/api/evening_schedule?program_id=%20"):
            r = self.post(path, {"schedule": {"Lun": "Push A"}})
            self.assertEqual(r.status_code, 400)
            self.assertEqual(self.json(r)["error"], "invalid_program_id")
        self.assertNotIn("morning_schedule", self.store)
        self.assertNotIn("evening_schedule", self.store)
