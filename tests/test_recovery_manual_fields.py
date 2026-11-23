"""recovery_logs.manual_fields — source par champ réellement saisi (migration 109).

Avant : tout check-in marquait la ligne « manual » et la synchro HealthKit ne réécrivait
plus aucun des 10 champs HealthKit déjà remplis (nuit coupée à la synchro de 12:05).
"""
import os
import sys
import unittest
from unittest.mock import patch

from flask import Flask

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

import db
import db_body
import sleep as sleep_mod
from routes.wellness_recovery import wellness_recovery_bp
from routes.wellness_stress import wellness_stress_bp

DAY = "2026-11-08"


class _Store:
    """recovery_logs en mémoire, branché sur le vrai upsert_recovery_log (et son invalidation)."""

    def __init__(self):
        self.rows = {}

    def get(self, limit=100):
        return [dict(r) for r in self.rows.values()]

    def raw_upsert(self, data):
        self.rows[data["date"]] = dict(data)
        return True


class ManualFieldsTests(unittest.TestCase):
    def setUp(self):
        self.store = _Store()
        self.patches = [
            patch.object(db_body, "get_recovery_logs", self.store.get),
            patch.object(db_body, "_upsert_recovery_log_raw", self.store.raw_upsert),
            patch.object(db, "get_recovery_logs", self.store.get),
            patch.object(db, "upsert_recovery_log", db_body.upsert_recovery_log),
            patch.object(sleep_mod, "_get_all_records", return_value=[]),
            patch("routes.wellness_recovery._today_mtl", return_value=DAY),
        ]
        for p in self.patches:
            p.start()
        app = Flask(__name__)
        app.register_blueprint(wellness_recovery_bp)
        app.register_blueprint(wellness_stress_bp)
        self.client = app.test_client()

    def tearDown(self):
        for p in reversed(self.patches):
            p.stop()

    def sync(self, **fields):
        self.assertTrue(db_body.merge_recovery_wearable(DAY, fields))

    def checkin(self, **payload):
        r = self.client.post("/api/log_recovery", json={"date": DAY, **payload})
        self.assertEqual(r.status_code, 200, r.get_json())

    @property
    def row(self):
        return self.store.rows[DAY]

    def test_late_sync_rewrites_full_night_after_checkin(self):
        # 12:05, encore endormi : nuit partielle + HRV / FC du moment.
        self.sync(sleep_hours=9.4, wake_time="12:05", bedtime="02:41", hrv=40.0, resting_hr=60, steps=120)
        # Check-in du matin : aucun champ HealthKit envoyé, aucune déclaration.
        self.checkin(sleep_quality=7, fatigue_perceived=3, energy_pre=6)
        self.assertEqual(self.row["source"], "manual")
        self.assertEqual(self.row["manual_fields"], [])
        # Synchro de l'après-midi : nuit complète et valeurs à jour.
        self.sync(sleep_hours=11.08, wake_time="13:46", bedtime="02:41", hrv=52.3, resting_hr=58, steps=8400)
        for key, value in {"sleep_hours": 11.08, "wake_time": "13:46", "hrv": 52.3,
                           "resting_hr": 58, "steps": 8400}.items():
            self.assertEqual(self.row[key], value, key)
        self.assertEqual(self.row["sleep_quality"], 7)   # subjectif intact

    def test_declared_manual_field_is_kept_others_advance(self):
        self.sync(hrv=40.0, resting_hr=60, sleep_hours=7.0)
        self.checkin(hrv=45, manual_fields=["hrv"])
        self.assertEqual(self.row["manual_fields"], ["hrv"])
        self.sync(hrv=52.3, resting_hr=58, sleep_hours=7.4)
        self.assertEqual(self.row["hrv"], 45)            # saisi : gardé
        self.assertEqual(self.row["resting_hr"], 58)     # non déclaré : avance
        self.assertEqual(self.row["sleep_hours"], 7.4)

    def test_old_app_without_declaration_marks_nothing_manual(self):
        # Ancienne LogRecoverySheet : renvoie toutes les valeurs pré-remplies, sans liste.
        self.checkin(sleep_hours=7.1, hrv=26, resting_hr=77, steps=416, sleep_quality=8)
        self.assertEqual(self.row["manual_fields"], [])
        self.sync(sleep_hours=7.08, hrv=29.44, resting_hr=75, steps=10993)
        self.assertEqual(self.row["hrv"], 29.44)
        self.assertEqual(self.row["sleep_hours"], 7.08)
        self.assertEqual(self.row["steps"], 10993)

    def test_declaration_ignores_unknown_and_subjective_fields_and_accumulates(self):
        self.checkin(hrv=45, manual_fields=["hrv", "soreness", "nope"])
        self.checkin(resting_hr=61, manual_fields=["resting_hr"])
        self.assertEqual(self.row["manual_fields"], ["hrv", "resting_hr"])
        self.checkin(sleep_quality=6)                    # sans déclaration : liste inchangée
        self.assertEqual(self.row["manual_fields"], ["hrv", "resting_hr"])

    def test_sleep_log_entry_is_protected_from_sync(self):
        r = self.client.post("/api/sleep/log", json={"bedtime": "23:30", "wake_time": "06:30", "quality": 4})
        self.assertEqual(r.status_code, 200, r.get_json())
        day = next(iter(self.store.rows))
        row = self.store.rows[day]
        self.assertEqual(set(row["manual_fields"]), {"sleep_hours", "bedtime", "wake_time"})
        self.assertTrue(db_body.merge_recovery_wearable(day, {"sleep_hours": 9.9, "bedtime": "22:00", "hrv": 50.0}))
        row = self.store.rows[day]
        self.assertEqual(row["sleep_hours"], 7.0)
        self.assertEqual(row["bedtime"], "23:30")
        self.assertEqual(row["hrv"], 50.0)

    def test_cumulative_fields_always_advance_even_if_declared(self):
        self.checkin(steps=500, active_energy=40, manual_fields=["steps", "active_energy"])
        self.sync(steps=9000, active_energy=600)
        self.assertEqual(self.row["steps"], 9000)
        self.assertEqual(self.row["active_energy"], 600)

    def test_first_sync_creates_healthkit_row(self):
        self.sync(steps=10, hrv=33.0)
        self.assertEqual(self.row["source"], "healthkit")
        self.assertNotIn("manual_fields", self.row)


if __name__ == "__main__":
    unittest.main()
