"""
volume_progression_engine.py — Volume Progression.

Weekly training load = sum of RPE for all completed sessions in the week.
Tracks last 12 weeks. Identifies current phase:
  building   — last 3w avg > preceding 3w avg by ≥ 10%
  declining  — last 3w avg < preceding 3w avg by ≥ 10%
  maintaining — within ±10%

Also reports current_pct_of_peak (current week load vs all-time weekly peak).

Data read only. No writes.
"""
from __future__ import annotations
import logging
from datetime import date, timedelta
from typing import Optional

import db
from utils import _today_mtl as _today_iso

logger = logging.getLogger("trainingos.volume_progression")

_WEEKS = 12


def _monday(d: date) -> date:
    return d - timedelta(days=d.weekday())


def _week_load(sessions: list[dict], monday: date) -> float:
    s_str = monday.isoformat()
    e_str = (monday + timedelta(days=6)).isoformat()
    return sum(
        float(s.get("rpe") or 0)
        for s in sessions
        if s.get("completed") and s_str <= (s.get("date") or "") <= e_str
    )


def compute() -> dict:
    today_str = _today_iso()
    today     = date.fromisoformat(today_str)
    sessions  = db.get_workout_sessions(limit=400) or []

    completed = [s for s in sessions if s.get("completed") and s.get("date")]
    if len(completed) < 4:
        return {
            "has_data": False, "weekly_loads": [], "trend": "maintaining",
            "peak_load": None, "current_pct_of_peak": None,
            "message": "Pas assez de données.",
        }

    cur_monday = _monday(today)
    weekly_loads = []
    for w in range(_WEEKS, 0, -1):
        wm   = cur_monday - timedelta(weeks=w)
        load = _week_load(sessions, wm)
        weekly_loads.append({"week_start": wm.isoformat(), "load": round(load, 1)})

    # Include current (partial) week
    cur_load = _week_load(sessions, cur_monday)
    weekly_loads.append({"week_start": cur_monday.isoformat(), "load": round(cur_load, 1)})

    loads = [w["load"] for w in weekly_loads]
    non_zero = [l for l in loads if l > 0]
    if not non_zero:
        return {
            "has_data": False, "weekly_loads": weekly_loads, "trend": "maintaining",
            "peak_load": None, "current_pct_of_peak": None,
            "message": "Aucune séance avec RPE enregistrée.",
        }

    peak_load = max(non_zero)

    # Trend: compare last 3 complete weeks vs preceding 3
    complete_loads = [w["load"] for w in weekly_loads[:-1]]  # exclude current partial
    if len(complete_loads) >= 6:
        recent = complete_loads[-3:]
        prior  = complete_loads[-6:-3]
        avg_recent = sum(recent) / 3
        avg_prior  = sum(prior)  / 3
        if avg_prior > 0:
            pct_change = (avg_recent - avg_prior) / avg_prior * 100
            if pct_change >= 10:
                trend = "building"
            elif pct_change <= -10:
                trend = "declining"
            else:
                trend = "maintaining"
        else:
            trend = "building" if avg_recent > 0 else "maintaining"
    else:
        trend = "maintaining"

    current_pct: Optional[int] = None
    if peak_load > 0:
        current_pct = round(cur_load / peak_load * 100)

    if trend == "building":
        message = "Volume en hausse — tu construis ta charge progressivement."
    elif trend == "declining":
        message = "Volume en baisse — phase de récupération ou déload naturel."
    else:
        message = "Volume stable — maintien de la charge actuelle."

    return {
        "has_data":            True,
        "weekly_loads":        weekly_loads,
        "trend":               trend,
        "peak_load":           round(peak_load, 1),
        "current_pct_of_peak": current_pct,
        "message":             message,
    }
