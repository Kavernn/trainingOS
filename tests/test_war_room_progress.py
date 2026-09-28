"""Focused read coverage and existing battle-handler regressions, no real account writes."""
import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import MagicMock, patch
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "api"))
from flask import Flask
from routes.war_room import war_room_bp


class Query:
    def __init__(self, client, table):
        self.client, self.table = client, table
        self.cursor = None
        self.end = "9999-12-31"
    def select(self, *args, **kwargs): return self
    def eq(self, *args): return self
    def limit(self, *args): return self
    def order(self, *args, **kwargs): return self
    def lt(self, column, date): self.cursor = date; return self
    def lte(self, column, date): self.end = date; return self
    def execute(self):
        if self.client.failed: raise RuntimeError("offline")
        if self.table == "war_room_config":
            self.client.config_reads += 1
            config = dict(self.client.config)
            if self.client.changed and self.client.config_reads > 1: config["updated_at"] = "new"
            return SimpleNamespace(data=[config])
        rows = sorted([r for r in self.client.rows if r["date"] <= self.end and (not self.cursor or r["date"] < self.cursor)], key=lambda r: r["date"], reverse=True)
        # Simulate a server-side row cap lower than requested: must still paginate.
        return SimpleNamespace(data=rows[:2], count=None if self.client.unknown_count else len(rows))


class WarRoomProgressTests(unittest.TestCase):
    def setUp(self):
        self.core = SimpleNamespace(MODE="ONLINE")
        self.core._client = self
        self.failed = self.changed = self.unknown_count = False
        self.config_reads = 0
        self.config = {"war_start_date": "2026-09-01", "updated_at": "original"}
        self.rows = [{"id": str(i), "date": f"2026-09-{i:02}", "status": "victory"} for i in range(1, 8)]
        self.addCleanup(patch.stopall)
        patch.dict(sys.modules, {"db_core": self.core}).start()
        patch("routes.war_room._today_mtl", return_value="2026-09-28").start()
        app = Flask(__name__); app.register_blueprint(war_room_bp)
        self.client = app.test_client()
    def table(self, name): return Query(self, name)

    def test_full_history_paginates_past_row_cap(self):
        data = self.client.get("/api/war_room/progress").get_json()
        self.assertTrue(data["complete"])
        self.assertEqual(len(data["battles"]), 7)
        self.assertEqual(data["through_date"], "2026-09-28")
    def test_safety_cap_is_explicitly_partial(self):
        from datetime import date, timedelta
        self.rows = [{"id": str(i), "date": (date(2026, 9, 28) - timedelta(days=i)).isoformat(), "status": "victory"} for i in range(50)]
        data = self.client.get("/api/war_room/progress").get_json()
        self.assertFalse(data["complete"])
        self.assertEqual(len(data["battles"]), 40)

    def test_public_routes_use_shared_progress_view(self):
        root = Path(__file__).resolve().parents[1]
        self.assertIn("WarRoomGateView()", (root / "Views/More/MoreView.swift").read_text())
        self.assertIn("WarRoomGateView()", (root / "Views/Dashboard/WarRoomStripView.swift").read_text())
        self.assertIn("WarRoomView()", (root / "Views/Intelligence/WarRoomGateView.swift").read_text())
        self.assertIn("WarRoomProgressView(store: progressStore)", (root / "Views/Intelligence/WarRoomView.swift").read_text())

    def test_empty_success_is_distinct_from_error(self):
        self.rows = []
        data = self.client.get("/api/war_room/progress").get_json()
        self.assertTrue(data["complete"]); self.assertEqual(data["battles"], [])
        self.failed = True
        self.assertEqual(self.client.get("/api/war_room/progress").status_code, 503)
    def test_offline_does_not_report_zero(self):
        self.core.MODE = "OFFLINE"
        self.assertEqual(self.client.get("/api/war_room/progress").status_code, 503)
    def test_unknown_coverage_is_not_complete(self):
        self.unknown_count = True
        self.assertEqual(self.client.get("/api/war_room/progress").status_code, 503)
    def test_config_change_rejects_old_context(self):
        self.changed = True
        self.assertEqual(self.client.get("/api/war_room/progress").status_code, 409)
    def test_new_start_does_not_erase_existing_history(self):
        self.config["war_start_date"] = "2026-09-25"
        self.rows.append({"id": "future", "date": "2026-10-01", "status": "victory"})
        self.assertEqual(len(self.client.get("/api/war_room/progress").get_json()["battles"]), 7)
    def test_existing_handler_rejects_duplicate_but_allows_correction(self):
        db = MagicMock()
        db.get_war_room_today_status.return_value = {"has_result": True}
        db.upsert_war_room_battle.return_value = True
        db.get_war_room_config.return_value = self.config
        engine = MagicMock(); engine.compute_summary.return_value = {"total_victories": 1}
        with patch.dict(sys.modules, {"db": db, "war_room_engine": engine}):
            payload = {"date": "2026-09-20", "status": "victory"}
            self.assertEqual(self.client.post("/api/war_room/battle", json=payload).status_code, 409)
            db.upsert_war_room_battle.assert_not_called()
            payload.update(force=True, status="lost")
            self.assertEqual(self.client.post("/api/war_room/battle", json=payload).status_code, 200)
            db.upsert_war_room_battle.assert_called_once_with({"date": "2026-09-20", "status": "lost", "notes": None})
    def test_mutation_failure_is_not_accepted(self):
        db = MagicMock(); db.get_war_room_today_status.return_value = {"has_result": False}
        db.upsert_war_room_battle.return_value = False
        with patch.dict(sys.modules, {"db": db}):
            self.assertEqual(self.client.post("/api/war_room/battle", json={"status": "victory"}).status_code, 500)

if __name__ == "__main__": unittest.main(verbosity=2)
