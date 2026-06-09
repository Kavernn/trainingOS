"""
training_heatmap_engine.py — Training Heatmap (12-week grid).

Builds a 12 × 7 grid (weeks × days Mon–Sun) of session counts for
completed sessions. Also returns total_by_day[7] and best_day_index.

Callers can render a GitHub-style contribution heatmap to show which
days the athlete actually trains across the last 12 weeks.

Data read only. No writes.
"""
from __future__ import annotations
import logging
from datetime import date, timedelta

import db
from utils import _today_mtl as _today_iso

logger = logging.getLogger("trainingos.training_heatmap")

_WEEKS = 12
DAY_LABELS = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]


def _monday(d: date) -> date:
    return d - timedelta(days=d.weekday())


def compute() -> dict:
    today_str  = _today_iso()
    today      = date.fromisoformat(today_str)
    cur_monday = _monday(today)
    cutoff     = (cur_monday - timedelta(weeks=_WEEKS)).isoformat()

    sessions = db.get_workout_sessions(limit=500) or []
    completed = {
        s["date"] for s in sessions
        if s.get("completed") and s.get("date") and s["date"] >= cutoff
    }

    if len(completed) < 3:
        return {
            "has_data": False,
            "weeks": [],
            "total_by_day": [0] * 7,
            "best_day_index": None,
            "sessions_tracked": 0,
            "message": "Pas assez de données.",
        }

    total_by_day = [0] * 7
    weeks_out = []

    for w in range(_WEEKS, 0, -1):
        wm   = cur_monday - timedelta(weeks=w)
        days = []
        for d_offset in range(7):
            day  = wm + timedelta(days=d_offset)
            cnt  = 1 if day.isoformat() in completed else 0
            days.append(cnt)
            total_by_day[d_offset] += cnt
        weeks_out.append({"week_start": wm.isoformat(), "days": days})

    # Also include current (partial) week
    cur_days = []
    for d_offset in range(7):
        day = cur_monday + timedelta(days=d_offset)
        cnt = 1 if day.isoformat() in completed else 0
        cur_days.append(cnt)
        total_by_day[d_offset] += cnt
    weeks_out.append({"week_start": cur_monday.isoformat(), "days": cur_days})

    best_day_index = total_by_day.index(max(total_by_day))

    sessions_tracked = len(completed)

    if total_by_day[best_day_index] > 0:
        message = f"Tu t'entraînes le plus souvent le {DAY_LABELS[best_day_index]}."
    else:
        message = "Aucune session complétée sur la période."

    return {
        "has_data":         True,
        "weeks":            weeks_out,
        "total_by_day":     total_by_day,
        "best_day_index":   best_day_index,
        "sessions_tracked": sessions_tracked,
        "message":          message,
    }
