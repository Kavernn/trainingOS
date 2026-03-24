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

from datetime import date as date_cls
from flask import request, jsonify

import db


def register_routes(app):

    @app.route("/api/wearable/sync", methods=["POST"])
    def api_wearable_sync():
        data        = request.get_json() or {}
        target_date = data.get("date", date_cls.today().isoformat())
        synced      = []

        # ── Recovery metrics ─────────────────────────────────────────────────
        wearable_recovery: dict = {}
        for key in ("steps", "sleep_hours", "resting_hr", "hrv", "active_energy"):
            if data.get(key) is not None:
                wearable_recovery[key] = data[key]

        if wearable_recovery:
            ok = db.merge_recovery_wearable(target_date, wearable_recovery)
            if ok:
                synced.extend(wearable_recovery.keys())

        # ── Body composition (push to body_weight log) ────────────────────────
        # DB stores weight in lbs — pass bw_lbs directly, no conversion needed
        bw_lbs = data.get("body_weight_lbs")
        bf_pct = data.get("body_fat_pct")
        if bw_lbs is not None:
            db.log_body_weight_wearable(target_date, poids=round(bw_lbs, 1), body_fat=bf_pct)
            synced.append("body_weight")

        # ── Workouts / Cardio ─────────────────────────────────────────────────
        workouts   = data.get("workouts", [])
        added      = 0
        existing   = db.get_cardio_logs(limit=200) or []

        for w in workouts:
            workout_type = w.get("type")
            if not workout_type:
                continue

            # Deduplicate: skip if same date + type + source already stored
            already = any(
                e.get("date") == target_date
                and e.get("type") == workout_type
                and e.get("source") == "healthkit"
                for e in existing
            )
            if already:
                continue

            entry = {
                "date":         target_date,
                "type":         workout_type,
                "source":       "healthkit",
                "duration_min": w.get("duration_min"),
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
