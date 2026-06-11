"""
training_heatmap_engine.py — Training Heatmap (12-week grid) + Adherence.

Builds a 12 × 7 grid (weeks × days Mon–Sun) of session counts for
completed sessions. Also returns adherence_by_day: per planned training
day, the ratio of actual sessions vs scheduled occurrences.

Rest days (from the active programme schedule) are excluded from
adherence — they appear as null in the array.

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

_DAY_NAME_TO_IDX = {"Lun": 0, "Mar": 1, "Mer": 2, "Jeu": 3, "Ven": 4, "Sam": 5, "Dim": 6}


def _monday(d: date) -> date:
    return d - timedelta(days=d.weekday())


def _training_day_indices(schedule: dict) -> set[int]:
    return {
        _DAY_NAME_TO_IDX[day]
        for day, session in schedule.items()
        if session != "Repos" and day in _DAY_NAME_TO_IDX
    }


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
            "adherence_by_day": [None] * 7,
            "sessions_tracked": 0,
            "message": "Pas assez de données.",
        }

    total_by_day    = [0] * 7
    planned_by_day  = [0] * 7
    weeks_out = []

    for w in range(_WEEKS, 0, -1):
        wm   = cur_monday - timedelta(weeks=w)
        days = []
        for d_offset in range(7):
            day  = wm + timedelta(days=d_offset)
            cnt  = 1 if day.isoformat() in completed else 0
            days.append(cnt)
            total_by_day[d_offset] += cnt
            if day <= today:
                planned_by_day[d_offset] += 1
        weeks_out.append({"week_start": wm.isoformat(), "days": days})

    # Current (partial) week
    cur_days = []
    for d_offset in range(7):
        day = cur_monday + timedelta(days=d_offset)
        cnt = 1 if day.isoformat() in completed else 0
        cur_days.append(cnt)
        total_by_day[d_offset] += cnt
        if day <= today:
            planned_by_day[d_offset] += 1
    weeks_out.append({"week_start": cur_monday.isoformat(), "days": cur_days})

    sessions_tracked = len(completed)

    # Adherence per day — only for planned training days
    schedule = db.get_relational_week_schedule()
    training_indices = _training_day_indices(schedule)

    adherence_by_day: list[dict | None] = []
    for i in range(7):
        if i in training_indices and planned_by_day[i] > 0:
            actual  = total_by_day[i]
            planned = planned_by_day[i]
            adherence_by_day.append({
                "planned": planned,
                "actual":  actual,
                "rate":    round(actual / planned, 3),
            })
        else:
            adherence_by_day.append(None)

    # Summary message based on adherence
    training_adherences = [a for a in adherence_by_day if a is not None]
    if training_adherences:
        avg_rate = sum(a["rate"] for a in training_adherences) / len(training_adherences)
        message = f"Adhérence au plan : {int(avg_rate * 100)}% sur {_WEEKS} semaines."
    elif sessions_tracked > 0:
        message = f"{sessions_tracked} séances complétées. Configure ton programme pour voir l'adhérence."
    else:
        message = "Aucune session complétée sur la période."

    return {
        "has_data":         True,
        "weeks":            weeks_out,
        "total_by_day":     total_by_day,
        "adherence_by_day": adherence_by_day,
        "sessions_tracked": sessions_tracked,
        "message":          message,
    }
