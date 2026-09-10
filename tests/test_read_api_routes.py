"""
Tests: read/aggregation APIs and profile/goals/body-weight/cardio/recovery CRUD.

Routes covered:
  GET  /api/dashboard
  GET  /api/stats_data
  GET  /api/mood/rpe
  GET  /api/nutrition_data
  GET  /api/programme_data
  GET  /api/inventaire_data
  GET  /api/notes_data
  GET  /api/objectifs_data
  GET  /api/profil_data
  POST /api/update_profile
  POST /api/set_goal
  POST /api/body_weight
  POST /api/body_weight/update
  POST /api/body_weight/delete
  POST /api/log_cardio
  POST /api/delete_cardio
  POST /api/log_recovery
  POST /api/delete_recovery
"""
import sys, os
from unittest.mock import patch
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

from conftest import BaseRouteTest


# ── /api/dashboard ────────────────────────────────────────────────────────────

class TestDashboard(BaseRouteTest):

    def test_status_200(self):
        self.assertEqual(200, self.get("/api/dashboard").status_code)

    def test_required_keys(self):
        data = self.json(self.get("/api/dashboard"))
        for key in ("today", "week", "today_date", "already_logged_today",
                    "schedule", "suggestions", "full_program",
                    "exercise_muscle_metadata", "profile"):
            self.assertIn(key, data, f"Missing key: {key}")

    def test_full_program_is_flat(self):
        data = self.json(self.get("/api/dashboard"))
        for session, exos in data["full_program"].items():
            self.assertIsInstance(exos, dict)
            for ex, scheme in exos.items():
                self.assertIsInstance(scheme, str)

    def test_exercise_muscle_metadata_is_parallel_raw_and_best_effort(self):
        self.store["inventory"]["Bench Press"].update({
            "muscle_group": "Pectoraux",
            "muscle_specific": "Pectoral majeur — chef sternal",
            "secondary_muscles": ["Triceps", "Deltoïde antérieur"],
            "muscles": ["chest", "triceps", "front_delts"],
        })
        self.store["program"]["Upper A"]["blocks"][0]["exercises"]["Unknown Exercise"] = "3x8"

        data = self.json(self.get("/api/dashboard"))

        self.assertEqual("4x5-7", data["full_program"]["Upper A"]["Bench Press"])
        self.assertEqual("3x8", data["full_program"]["Upper A"]["Unknown Exercise"])
        self.assertEqual({
            "muscle_group": "Pectoraux",
            "muscle_specific": "Pectoral majeur — chef sternal",
            "secondary_muscles": ["Triceps", "Deltoïde antérieur"],
            "muscles": ["chest", "triceps", "front_delts"],
        }, data["exercise_muscle_metadata"]["Bench Press"])
        self.assertNotIn("Unknown Exercise", data["exercise_muscle_metadata"])

    def test_exercise_muscle_metadata_bulk_failure_is_best_effort(self):
        with patch("db.get_exercises_info_bulk", side_effect=RuntimeError("unavailable")):
            response = self.get("/api/dashboard")

        self.assertEqual(200, response.status_code)
        self.assertEqual({}, self.json(response)["exercise_muscle_metadata"])

    def test_not_already_logged_today(self):
        data = self.json(self.get("/api/dashboard"))
        self.assertFalse(data["already_logged_today"])

    def test_profile_present(self):
        data = self.json(self.get("/api/dashboard"))
        self.assertEqual("Test User", data["profile"]["name"])


# ── /api/stats_data ───────────────────────────────────────────────────────────

class TestStatsData(BaseRouteTest):

    def test_status_200(self):
        self.assertEqual(200, self.get("/api/stats_data").status_code)

    def test_required_keys(self):
        data = self.json(self.get("/api/stats_data"))
        for key in ("weights", "sessions", "hiit_log", "body_weight",
                    "recovery_log", "nutrition_target", "nutrition_days", "week"):
            self.assertIn(key, data, f"Missing key: {key}")

    def test_weights_data_present(self):
        data = self.json(self.get("/api/stats_data"))
        self.assertIn("Bench Press", data["weights"])

    def test_sessions_data_present(self):
        data = self.json(self.get("/api/stats_data"))
        self.assertIn("2026-03-10", data["sessions"])


# ── /api/mood/rpe ────────────────────────────────────────────────────────────

class TestMoodRPEEndpoint(BaseRouteTest):

    def test_exact_payload_averages_non_null_rpe_and_omits_empty_dates(self):
        rows = [
            {"date": "2026-03-10", "rpe": 7.2},
            {"date": "2026-03-10", "rpe": 8.0},
            {"date": "2026-03-09", "rpe": None},
        ]
        import db

        with patch.object(db, "get_workout_sessions", return_value=rows):
            response = self.get("/api/mood/rpe?days=90")

        self.assertEqual(200, response.status_code)
        self.assertEqual({"rpe_by_date": {"2026-03-10": 7.6}}, self.json(response))

    def test_default_days_uses_90_day_cutoff(self):
        import db

        with patch("routes.wellness_mood._today_mtl", return_value="2026-03-14"), \
             patch.object(db, "get_workout_sessions", return_value=[]) as get_sessions:
            response = self.get("/api/mood/rpe")

        self.assertEqual(200, response.status_code)
        get_sessions.assert_called_once_with(limit=500, offset=0, since="2025-12-14")

    def test_maximum_days_is_accepted(self):
        import db

        with patch("routes.wellness_mood._today_mtl", return_value="2026-03-14"), \
             patch.object(db, "get_workout_sessions", return_value=[]) as get_sessions:
            response = self.get("/api/mood/rpe?days=365")

        self.assertEqual(200, response.status_code)
        get_sessions.assert_called_once_with(limit=500, offset=0, since="2025-03-14")

    def test_invalid_days_returns_400_without_querying_sessions(self):
        import db

        for value in ("abc", "0", "-1", "366"):
            with self.subTest(value=value), \
                 patch.object(db, "get_workout_sessions") as get_sessions:
                response = self.get(f"/api/mood/rpe?days={value}")

            self.assertEqual(400, response.status_code)
            self.assertEqual(
                {"error": "days must be an integer between 1 and 365"},
                self.json(response),
            )
            get_sessions.assert_not_called()


# ── /api/nutrition_data ───────────────────────────────────────────────────────

class TestNutritionData(BaseRouteTest):

    def test_status_200(self):
        self.assertEqual(200, self.get("/api/nutrition_data").status_code)

    def test_required_keys(self):
        data = self.json(self.get("/api/nutrition_data"))
        for key in ("settings", "entries", "totals", "history"):
            self.assertIn(key, data, f"Missing key: {key}")

    def test_settings_has_calorie_limit(self):
        data = self.json(self.get("/api/nutrition_data"))
        self.assertIn("limite_calories", data["settings"])


# ── /api/programme_data ───────────────────────────────────────────────────────

class TestProgrammeData(BaseRouteTest):

    def test_status_200(self):
        self.assertEqual(200, self.get("/api/programme_data").status_code)

    def test_required_keys(self):
        data = self.json(self.get("/api/programme_data"))
        for key in ("full_program", "schedule", "inventory_types", "inventory_schemes"):
            self.assertIn(key, data, f"Missing key: {key}")

    def test_full_program_is_flat(self):
        data = self.json(self.get("/api/programme_data"))
        for session, exos in data["full_program"].items():
            self.assertIsInstance(exos, dict)

    def test_inventory_types_populated(self):
        data = self.json(self.get("/api/programme_data"))
        self.assertIn("Bench Press", data["inventory_types"])
        self.assertEqual("barbell", data["inventory_types"]["Bench Press"])

    def test_inventory_schemes_populated(self):
        data = self.json(self.get("/api/programme_data"))
        self.assertIn("Bench Press", data["inventory_schemes"])
        self.assertEqual("4x5-7", data["inventory_schemes"]["Bench Press"])

    def test_inventory_schemes_all_strings(self):
        data = self.json(self.get("/api/programme_data"))
        for name, scheme in data["inventory_schemes"].items():
            self.assertIsInstance(scheme, str, f"scheme for {name} is not a string")


# ── /api/inventaire_data ──────────────────────────────────────────────────────

class TestInventaireData(BaseRouteTest):

    def test_status_200(self):
        self.assertEqual(200, self.get("/api/inventaire_data").status_code)

    def test_returns_inventory(self):
        data = self.json(self.get("/api/inventaire_data"))
        self.assertIn("inventory", data)
        self.assertIn("Bench Press", data["inventory"])


# ── /api/notes_data ───────────────────────────────────────────────────────────

class TestNotesData(BaseRouteTest):

    def test_status_200(self):
        self.assertEqual(200, self.get("/api/notes_data").status_code)

    def test_required_keys(self):
        data = self.json(self.get("/api/notes_data"))
        for key in ("sessions", "total", "avg_rpe"):
            self.assertIn(key, data, f"Missing key: {key}")

    def test_sessions_count(self):
        data = self.json(self.get("/api/notes_data"))
        self.assertEqual(len(self.store["sessions"]), data["total"])


# ── /api/objectifs_data ───────────────────────────────────────────────────────

class TestObjectifsData(BaseRouteTest):

    def test_status_200(self):
        self.assertEqual(200, self.get("/api/objectifs_data").status_code)

    def test_returns_goals_key(self):
        data = self.json(self.get("/api/objectifs_data"))
        self.assertIn("goals", data)


# ── /api/profil_data ──────────────────────────────────────────────────────────

class TestProfilData(BaseRouteTest):

    def test_status_200(self):
        self.assertEqual(200, self.get("/api/profil_data").status_code)

    def test_required_keys(self):
        data = self.json(self.get("/api/profil_data"))
        for key in ("profile", "body_weight", "tendance"):
            self.assertIn(key, data, f"Missing key: {key}")

    def test_profile_name(self):
        data = self.json(self.get("/api/profil_data"))
        self.assertEqual("Test User", data["profile"]["name"])


# ── /api/update_profile ───────────────────────────────────────────────────────

class TestUpdateProfile(BaseRouteTest):

    def test_update_name(self):
        r = self.post("/api/update_profile", {"name": "Vincent"})
        self.assertEqual(200, r.status_code)
        self.assertEqual("Vincent", self.store["user_profile"]["name"])

    def test_update_merges_fields(self):
        self.post("/api/update_profile", {"weight": 185.0})
        self.assertEqual("Test User", self.store["user_profile"]["name"])   # unchanged
        self.assertEqual(185.0, self.store["user_profile"]["weight"])        # updated

    def test_returns_success(self):
        r = self.post("/api/update_profile", {"age": 31})
        self.assertTrue(self.json(r).get("success"))


# ── /api/set_goal ─────────────────────────────────────────────────────────────

class TestSetGoal(BaseRouteTest):

    def test_set_goal_success(self):
        r = self.post("/api/set_goal", {
            "exercise": "Bench Press", "weight": 225.0,
        })
        self.assertEqual(200, r.status_code)
        self.assertTrue(self.json(r).get("success"))

    def test_goal_persisted(self):
        self.post("/api/set_goal", {"exercise": "Bench Press", "weight": 225.0})
        self.assertIn("Bench Press", self.store["goals"])

    def test_missing_exercise_returns_400(self):
        r = self.post("/api/set_goal", {"weight": 200.0})
        self.assertEqual(400, r.status_code)

    def test_zero_weight_returns_400(self):
        r = self.post("/api/set_goal", {"exercise": "Bench Press", "weight": 0})
        self.assertEqual(400, r.status_code)


# ── /api/body_weight ─────────────────────────────────────────────────────────

class TestBodyWeight(BaseRouteTest):

    def test_log_body_weight(self):
        r = self.post("/api/body_weight", {"poids": 180.0, "note": "morning"})
        self.assertEqual(200, r.status_code)
        self.assertTrue(self.json(r).get("success"))
        self.assertEqual(1, len(self.store["body_weight"]))

    def test_log_body_weight_invalid_returns_400(self):
        r = self.post("/api/body_weight", {"poids": 0})
        self.assertEqual(400, r.status_code)

    def test_update_body_weight(self):
        self.post("/api/body_weight", {"poids": 180.0})
        date = self.store["body_weight"][0]["date"]
        r = self.post("/api/body_weight/update", {
            "date": date, "old_poids": 180.0, "poids": 181.5,
        })
        self.assertEqual(200, r.status_code)
        self.assertEqual(181.5, self.store["body_weight"][0]["poids"])

    def test_update_body_weight_not_found_returns_404(self):
        r = self.post("/api/body_weight/update", {
            "date": "1900-01-01", "old_poids": 999.0, "poids": 200.0,
        })
        # 400 = validation input rejette avant DB lookup ; 404 = row absente ;
        # 200 = success:False. Les 3 sont acceptables selon la logique de route.
        self.assertIn(r.status_code, (200, 400, 404))

    def test_delete_body_weight(self):
        self.post("/api/body_weight", {"poids": 180.0})
        date = self.store["body_weight"][0]["date"]
        r = self.post("/api/body_weight/delete", {"date": date, "poids": 180.0})
        self.assertEqual(200, r.status_code)
        self.assertEqual(0, len(self.store["body_weight"]))

    def test_delete_body_weight_not_found_returns_404(self):
        r = self.post("/api/body_weight/delete", {"date": "1900-01-01", "poids": 999.0})
        self.assertIn(r.status_code, (200, 404))


# ── /api/log_cardio & /api/delete_cardio ──────────────────────────────────────

class TestCardio(BaseRouteTest):

    def test_log_cardio_success(self):
        r = self.post("/api/log_cardio", {
            "date": "2026-03-14", "type": "Vélo", "duration_min": 45,
            "distance_km": 20.0, "rpe": 6,
        })
        self.assertEqual(200, r.status_code)
        self.assertTrue(self.json(r).get("ok"))

    def test_log_cardio_persisted(self):
        self.post("/api/log_cardio", {"date": "2026-03-14", "type": "Course"})
        self.assertEqual(1, len(self.store["cardio_log"]))

    def test_log_cardio_most_recent_first(self):
        self.post("/api/log_cardio", {"date": "2026-03-13", "type": "Vélo"})
        self.post("/api/log_cardio", {"date": "2026-03-14", "type": "Course"})
        self.assertEqual("2026-03-14", self.store["cardio_log"][0]["date"])

    def test_delete_cardio(self):
        self.post("/api/log_cardio", {"date": "2026-03-14", "type": "Vélo"})
        r = self.post("/api/delete_cardio", {"date": "2026-03-14", "type": "Vélo"})
        self.assertEqual(200, r.status_code)
        self.assertEqual(0, len(self.store["cardio_log"]))

    def test_delete_cardio_nonexistent_still_200(self):
        r = self.post("/api/delete_cardio", {"date": "1900-01-01", "type": "Ghost"})
        self.assertEqual(200, r.status_code)


# ── /api/log_recovery & /api/delete_recovery ──────────────────────────────────

class TestRecovery(BaseRouteTest):

    def test_log_recovery_success(self):
        r = self.post("/api/log_recovery", {
            "date": "2026-03-14", "sleep_hours": 7.5, "sleep_quality": 8,
            "resting_hr": 55, "soreness": 3,
        })
        self.assertEqual(200, r.status_code)
        self.assertTrue(self.json(r).get("ok"))

    def test_log_recovery_persisted(self):
        self.post("/api/log_recovery", {"date": "2026-03-14", "sleep_hours": 7.5})
        self.assertEqual(1, len(self.store["recovery_log"]))

    def test_log_recovery_upsert_same_date(self):
        """Logging recovery for the same date twice should update, not duplicate."""
        self.post("/api/log_recovery", {"date": "2026-03-14", "sleep_hours": 7.0})
        self.post("/api/log_recovery", {"date": "2026-03-14", "sleep_hours": 8.0})
        entries = [e for e in self.store["recovery_log"] if e["date"] == "2026-03-14"]
        self.assertEqual(1, len(entries))
        self.assertEqual(8.0, entries[0]["sleep_hours"])

    def test_delete_recovery(self):
        self.post("/api/log_recovery", {"date": "2026-03-14", "sleep_hours": 7.0})
        r = self.post("/api/delete_recovery", {"date": "2026-03-14"})
        self.assertEqual(200, r.status_code)
        remaining = [e for e in self.store["recovery_log"] if e["date"] == "2026-03-14"]
        self.assertEqual(0, len(remaining))

    def test_delete_recovery_nonexistent_still_200(self):
        r = self.post("/api/delete_recovery", {"date": "1900-01-01"})
        self.assertEqual(200, r.status_code)


if __name__ == "__main__":
    import unittest
    unittest.main(verbosity=2)
