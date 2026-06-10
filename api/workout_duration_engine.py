"""
workout_duration_engine.py — Workout Duration Trend.

Uses duration_min from completed workout_sessions.
Computes weekly average duration over 12 weeks + current partial week.
Also correlates duration with RPE: groups sessions into
  short  (<45 min), medium (45–75 min), long (>75 min)
and shows avg RPE per group — answering "do longer sessions push harder?"

Min 5 sessions with duration_min logged for has_data.

Data read only. No writes.
"""
from __future__ import annotations
import logging
from datetime import date, timedelta
from typing import Optional

import db
from utils import _today_mtl as _today_iso

logger = logging.getLogger("trainingos.workout_duration")

_WEEKS      = 12
_SHORT_MAX  = 45
_LONG_MIN   = 75


def _monday(d: date) -> date:
    return d - timedelta(days=d.weekday())


def compute() -> dict:
    today_str  = _today_iso()
    today      = date.fromisoformat(today_str)

    sessions = db.get_workout_sessions(limit=500) or []
    with_dur = [
        s for s in sessions
        if s.get("completed") and s.get("duration_min") and float(s["duration_min"]) > 0
        and s.get("date")
    ]

    if len(with_dur) < 5:
        return {
            "has_data": False,
            "weekly_avgs": [],
            "avg_duration": None,
            "trend": "stable",
            "by_length": [],
            "sessions_analyzed": len(with_dur),
            "message": "Pas assez de données de durée.",
        }

    cur_monday = _monday(today)
    cutoff     = (cur_monday - timedelta(weeks=_WEEKS)).isoformat()
    recent     = [s for s in with_dur if s["date"] >= cutoff]

    # Weekly averages
    weekly_avgs = []
    for w in range(_WEEKS, 0, -1):
        wm  = cur_monday - timedelta(weeks=w)
        we  = (wm + timedelta(days=6)).isoformat()
        sw  = wm.isoformat()
        dur = [float(s["duration_min"]) for s in recent if sw <= s["date"] <= we]
        avg = round(sum(dur) / len(dur), 1) if dur else None
        weekly_avgs.append({"week_start": sw, "avg_min": avg, "count": len(dur)})
    # current partial week
    cur_dur = [float(s["duration_min"]) for s in with_dur if s["date"] >= cur_monday.isoformat()]
    weekly_avgs.append({"week_start": cur_monday.isoformat(),
                         "avg_min": round(sum(cur_dur)/len(cur_dur), 1) if cur_dur else None,
                         "count": len(cur_dur)})

    # Trend: recent 4-week avg vs prior 4-week avg
    avgs = [w["avg_min"] for w in weekly_avgs[:-1] if w["avg_min"] is not None]
    trend = "stable"
    if len(avgs) >= 8:
        r = sum(avgs[-4:]) / 4
        p = sum(avgs[-8:-4]) / 4
        if p > 0:
            pct = (r - p) / p * 100
            if pct >= 8:
                trend = "increasing"
            elif pct <= -8:
                trend = "decreasing"

    # RPE correlation by duration bucket
    groups: dict[str, list[float]] = {"short": [], "medium": [], "long": []}
    for s in with_dur:
        if s.get("rpe") is None:
            continue
        d_min = float(s["duration_min"])
        rpe   = float(s["rpe"])
        if d_min < _SHORT_MAX:
            groups["short"].append(rpe)
        elif d_min <= _LONG_MIN:
            groups["medium"].append(rpe)
        else:
            groups["long"].append(rpe)

    by_length = []
    for key, label, lo, hi in [
        ("short",  f"< {_SHORT_MAX} min",        0,         _SHORT_MAX),
        ("medium", f"{_SHORT_MAX}–{_LONG_MIN} min", _SHORT_MAX, _LONG_MIN),
        ("long",   f"> {_LONG_MIN} min",          _LONG_MIN, 999),
    ]:
        vals = groups[key]
        avg_rpe = round(sum(vals) / len(vals), 1) if vals else None
        by_length.append({"bucket": key, "label": label, "avg_rpe": avg_rpe, "count": len(vals)})

    overall_avg = round(sum(float(s["duration_min"]) for s in with_dur) / len(with_dur), 1)

    if trend == "increasing":
        message = "Séances plus longues en moyenne — assure-toi que l'intensité reste adéquate."
    elif trend == "decreasing":
        message = "Séances plus courtes — efficacité accrue ou volume réduit."
    else:
        message = f"Durée moyenne stable à {overall_avg} min par séance."

    return {
        "has_data":          True,
        "weekly_avgs":       weekly_avgs,
        "avg_duration":      overall_avg,
        "trend":             trend,
        "by_length":         by_length,
        "sessions_analyzed": len(with_dur),
        "message":           message,
    }
