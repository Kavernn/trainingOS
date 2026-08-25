"""
wearable.py — Sync Apple Watch / HealthKit data to Supabase.

POST /api/wearable/sync
  Body: {
    "date":          "YYYY-MM-DD",   # optional, defaults to today MTL
    "steps":         int,
    "sleep_hours":   float,
    "resting_hr":    float,
    "hrv":           float,          # ms SDNN
    "active_energy": float,          # kcal
    "workouts": [
      {
        "type":         str,         # "course"|"vélo"|"natation"|"marche"|"autre"
        "duration_min": float,
        "distance_km":  float,
        "calories":     float,
        "avg_hr":       float,
        "avg_pace":     str          # "mm:ss/km"
      }
    ]
  }

  Returns: { ok: true, date: str, synced_metrics: [str], workouts_added: int }
"""
from __future__ import annotations

import logging
from datetime import date as date_cls
from flask import request, jsonify

import db

logger = logging.getLogger("trainingos.wearable")


def register_routes(app):

    @app.route("/api/wearable/sync", methods=["POST"])
    def api_wearable_sync():
        from utils import _today_mtl
        data        = request.get_json() or {}
        target_date = data.get("date", _today_mtl())
        synced      = []

        # ── Recovery metrics ─────────────────────────────────────────────────
        wearable_recovery: dict = {}
        for key in ("steps", "sleep_hours", "resting_hr", "hrv", "active_energy",
                    "hr_morning", "hr_post_workout", "hr_evening",
                    "bedtime", "wake_time"):
            if data.get(key) is not None:
                wearable_recovery[key] = data[key]

        if wearable_recovery:
            ok = db.merge_recovery_wearable(target_date, wearable_recovery)
            if ok:
                synced.extend(wearable_recovery.keys())

        # ── Body composition ─────────────────────────────────────────────────
        # Manuel > HK garanti par log_body_weight_wearable (n'insère que si aucune
        # entrée du jour existe). body_fat sans poids : ignoré + warning.
        bw = data.get("body_weight")
        bf = data.get("body_fat")
        if bw is not None:
            if db.log_body_weight_wearable(target_date, bw, bf):
                synced.append("body_weight")
                if bf is not None:
                    synced.append("body_fat")
        elif bf is not None:
            logger.warning("body_fat reçu sans body_weight pour %s, ignoré", target_date)

        # ── Smart Alarm latency calibration ──────────────────────────────────
        # When HealthKit sends bedtime (= first asleep sample HH:mm), pair it
        # with the bedtime_tap we stored the previous evening to compute latency.
        hk_sleep_start = data.get("bedtime")  # "HH:mm" — first asleep sample
        if hk_sleep_start:
            from db_smart_alarm import _latency_min
            # sleep date convention: if hour < 12 the sleep belongs to yesterday
            from datetime import timedelta
            try:
                sleep_hour = int(hk_sleep_start.split(":")[0])
            except Exception:
                sleep_hour = 0
            if sleep_hour < 12:
                sleep_date = (date_cls.fromisoformat(target_date) - timedelta(days=1)).isoformat()
            else:
                sleep_date = target_date

            existing_row = db.get_smart_alarm_sessions(since=sleep_date)
            matching = next((r for r in existing_row if r.get("date") == sleep_date), None)
            if matching and matching.get("bedtime_tap"):
                lat = _latency_min(matching["bedtime_tap"], hk_sleep_start)
                db.upsert_smart_alarm_session({
                    "date":           sleep_date,
                    "hk_sleep_start": hk_sleep_start,
                    "latency_min":    lat,
                })

        # ── Workouts / Cardio ─────────────────────────────────────────────────
        workouts   = data.get("workouts", [])
        added      = 0
        existing   = db.get_cardio_logs(limit=200) or []
        # Set updated within the loop to catch duplicates inside the same sync call
        seen_keys  = {(e.get("date"), e.get("type"), e.get("source")) for e in existing}

        for w in workouts:
            workout_type = w.get("type")
            if not workout_type:
                continue

            key = (target_date, workout_type, "healthkit")
            if key in seen_keys:
                continue
            seen_keys.add(key)

            raw_duration = w.get("duration_min")
            # Cap at 180 min — HealthKit sometimes reports multi-hour auto-detected sessions
            duration_min = min(int(raw_duration), 180) if raw_duration is not None else None
            entry = {
                "date":         target_date,
                "type":         workout_type,
                "source":       "healthkit",
                "duration_min": duration_min,
                "distance_km":  w.get("distance_km"),
                "avg_hr":       w.get("avg_hr"),
                "avg_pace":     w.get("avg_pace"),
                "calories":     w.get("calories"),
            }
            # Strip None values so Supabase doesn't choke on null constraints
            entry = {k: v for k, v in entry.items() if v is not None}

            db.insert_cardio_log(entry)
            added += 1

        return jsonify({
            "ok":             True,
            "date":           target_date,
            "synced_metrics": synced,
            "workouts_added": added,
        })
