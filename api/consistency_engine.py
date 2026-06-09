"""
consistency_engine.py — Score de Consistance.

Measures training regularity independently of streak.
Computes std deviation of sessions/week over last 8 weeks.
Score 0–100: 100 = perfectly consistent, 0 = highly erratic.

score = max(0, 100 - std_dev * 25)

Trend: compare score over last 4 weeks vs previous 4 weeks.

Data read only. No writes.
"""
from __future__ import annotations
import logging
import math
from datetime import date, timedelta
from typing import Optional

import db
from utils import _today_mtl as _today_iso

logger = logging.getLogger("trainingos.consistency")

_WEEKS = 8
_TREND_SPLIT = 4   # split into two halves for trend


def _monday(d: date) -> date:
    return d - timedelta(days=d.weekday())


def _sessions_in_week(sessions: list[dict], monday: date) -> int:
    s_str = monday.isoformat()
    e_str = (monday + timedelta(days=6)).isoformat()
    return sum(1 for s in sessions
               if s.get("completed") and s_str <= (s.get("date") or "") <= e_str)


def _score_from_stddev(std: float) -> int:
    return max(0, round(100 - std * 25))


def compute() -> dict:
    today_str = _today_iso()
    today     = date.fromisoformat(today_str)
    sessions  = db.get_workout_sessions(limit=300) or []

    completed = [s for s in sessions if s.get("completed") and s.get("date")]
    if len(completed) < 4:
        return {
            "has_data": False, "score": None, "std_dev": None,
            "avg_sessions_per_week": None, "trend": "stable",
            "weekly_counts": [], "message": "Pas assez de données.",
        }

    cur_monday = _monday(today)
    weekly_counts = []
    for w in range(_WEEKS, 0, -1):
        wm = cur_monday - timedelta(weeks=w)
        cnt = _sessions_in_week(sessions, wm)
        weekly_counts.append({"week_start": wm.isoformat(), "count": cnt})

    counts = [w["count"] for w in weekly_counts]
    avg  = sum(counts) / len(counts)
    variance = sum((c - avg) ** 2 for c in counts) / len(counts)
    std  = math.sqrt(variance)

    score = _score_from_stddev(std)
    avg_sessions = round(avg, 1)

    # Trend: first half vs second half
    first_half  = counts[:_TREND_SPLIT]
    second_half = counts[_TREND_SPLIT:]
    std_first  = math.sqrt(sum((c - (sum(first_half)/len(first_half)))**2 for c in first_half) / len(first_half))
    std_second = math.sqrt(sum((c - (sum(second_half)/len(second_half)))**2 for c in second_half) / len(second_half))
    score_first  = _score_from_stddev(std_first)
    score_second = _score_from_stddev(std_second)
    diff = score_second - score_first

    if diff >= 8:
        trend = "improving"
    elif diff <= -8:
        trend = "declining"
    else:
        trend = "stable"

    if score >= 80:
        message = "Régularité exemplaire — ton rythme est très stable."
    elif score >= 60:
        message = "Bonne consistance — quelques semaines irrégulières."
    elif score >= 40:
        message = "Régularité moyenne — les écarts entre semaines s'accumulent."
    else:
        message = "Entraînement irrégulier — travaille la constance avant l'intensité."

    return {
        "has_data":              True,
        "score":                 score,
        "std_dev":               round(std, 2),
        "avg_sessions_per_week": avg_sessions,
        "trend":                 trend,
        "weekly_counts":         weekly_counts,
        "message":               message,
    }
