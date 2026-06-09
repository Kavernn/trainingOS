"""
optimal_day_engine.py — Jour Optimal d'Entraînement.

For each day of week (0=Mon … 6=Sun), compute:
  - number of completed sessions
  - avg RPE
  - completion rate (completed / total scheduled that day)

Identifies best_day (highest avg RPE with ≥2 sessions) and
worst_day (lowest completion or lowest RPE, min 2 sessions).

Data read only. No writes.
"""
from __future__ import annotations
import logging
from collections import defaultdict

import db
from utils import _today_mtl as _today_iso

logger = logging.getLogger("trainingos.optimal_day")

_DAY_LABELS = ["Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi", "Dimanche"]
_DAY_SHORT  = ["Lun",   "Mar",   "Mer",     "Jeu",   "Ven",      "Sam",    "Dim"]
_MIN_SESSIONS = 2   # minimum sessions per day to include in analysis


def compute() -> dict:
    sessions = db.get_workout_sessions(limit=400) or []

    completed = [s for s in sessions if s.get("completed") and s.get("date") and s.get("rpe") is not None]
    all_with_date = [s for s in sessions if s.get("date")]

    if len(completed) < 7:
        return {
            "has_data": False, "best_day": None, "worst_day": None,
            "by_day": [], "sessions_analyzed": len(completed),
        }

    from datetime import date as _date
    rpe_by_day: dict[int, list[float]] = defaultdict(list)
    count_by_day: dict[int, int] = defaultdict(int)
    total_by_day: dict[int, int] = defaultdict(int)

    for s in completed:
        dow = _date.fromisoformat(s["date"]).weekday()
        rpe_by_day[dow].append(float(s["rpe"]))
        count_by_day[dow] += 1

    for s in all_with_date:
        dow = _date.fromisoformat(s["date"]).weekday()
        total_by_day[dow] += 1

    by_day = []
    for dow in range(7):
        cnt = count_by_day[dow]
        if cnt < 1:
            by_day.append({
                "dow": dow, "label": _DAY_LABELS[dow], "short": _DAY_SHORT[dow],
                "session_count": 0, "avg_rpe": None, "completion_rate": None,
            })
            continue
        avg_rpe = round(sum(rpe_by_day[dow]) / cnt, 1)
        total   = total_by_day[dow] or cnt
        completion_rate = round(cnt / total * 100)
        by_day.append({
            "dow": dow,
            "label": _DAY_LABELS[dow],
            "short": _DAY_SHORT[dow],
            "session_count": cnt,
            "avg_rpe": avg_rpe,
            "completion_rate": completion_rate,
        })

    # Best: highest avg RPE among days with ≥ _MIN_SESSIONS
    eligible = [d for d in by_day if (d["session_count"] or 0) >= _MIN_SESSIONS and d["avg_rpe"] is not None]
    if not eligible:
        return {
            "has_data": False, "best_day": None, "worst_day": None,
            "by_day": by_day, "sessions_analyzed": len(completed),
        }

    best  = max(eligible, key=lambda d: d["avg_rpe"])
    worst = min(eligible, key=lambda d: d["avg_rpe"])

    return {
        "has_data":          True,
        "best_day":          best["dow"],
        "worst_day":         worst["dow"],
        "by_day":            by_day,
        "sessions_analyzed": len(completed),
    }
