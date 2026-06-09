"""
session_quality_engine.py — Session Quality Score.

Groups exercise_logs by date over the last 56 days (8 weeks).
Per session:
  rpe_score     = (session_rpe / 10) × 100          (40 % weight)
  breadth_score = min(exercise_count / 8, 1) × 100  (35 % weight)
  volume_score  = min(total_sets / 20, 1) × 100      (25 % weight)
  quality       = rpe_score×0.40 + breadth_score×0.35 + volume_score×0.25

Aggregates into 8 weekly averages. Trend compares last 3 complete weeks
to preceding 3 complete weeks (>8 pt = improving/declining).

Data read only. No writes.
"""
from __future__ import annotations
import logging
from datetime import date, timedelta
from typing import Optional

import db
from utils import _today_mtl as _today_iso

logger = logging.getLogger("trainingos.session_quality")

_WEEKS         = 8
_TARGET_EX     = 8   # exercises to score 100 % breadth
_TARGET_SETS   = 20  # total sets to score 100 % volume


def _monday(d: date) -> date:
    return d - timedelta(days=d.weekday())


def _session_quality(ex_count: int, total_sets: int, rpe: Optional[float]) -> float:
    breadth = min(ex_count / _TARGET_EX,   1.0) * 100
    volume  = min(total_sets / _TARGET_SETS, 1.0) * 100
    if rpe is not None and float(rpe) > 0:
        rpe_norm = (float(rpe) / 10.0) * 100
        return round(rpe_norm * 0.40 + breadth * 0.35 + volume * 0.25, 1)
    return round(breadth * 0.50 + volume * 0.50, 1)


def compute() -> dict:
    today_str  = _today_iso()
    today      = date.fromisoformat(today_str)
    cutoff     = (today - timedelta(days=_WEEKS * 7)).isoformat()

    logs = db.get_exercise_logs_since(cutoff) or []

    if not logs:
        return {
            "has_data": False,
            "weekly_quality": [],
            "trend": "stable",
            "avg_quality": None,
            "best_session": None,
            "message": "Pas assez de données de séances.",
        }

    # Group logs by date
    sessions: dict[str, dict] = {}
    for log in logs:
        d = log.get("date") or ""
        if not d or d < cutoff:
            continue
        sess = sessions.setdefault(d, {"rpe": None, "exercises": set(), "total_sets": 0})
        sess["exercises"].add(log.get("exercise_name") or "")
        sets_json = log.get("sets_json") or []
        sess["total_sets"] += len(sets_json) if sets_json else 1
        if log.get("rpe") is not None:
            sess["rpe"] = log["rpe"]

    if len(sessions) < 4:
        return {
            "has_data": False,
            "weekly_quality": [],
            "trend": "stable",
            "avg_quality": None,
            "best_session": None,
            "message": "Pas assez de séances enregistrées.",
        }

    # Compute per-session quality
    session_scores: list[tuple[str, float]] = []
    for d, s in sessions.items():
        q = _session_quality(len(s["exercises"]), s["total_sets"], s["rpe"])
        session_scores.append((d, q))

    # Group into weeks
    cur_monday = _monday(today)
    weekly_quality = []
    for w in range(_WEEKS, 0, -1):
        wm     = cur_monday - timedelta(weeks=w)
        we     = wm + timedelta(days=6)
        scores = [q for d, q in session_scores if wm.isoformat() <= d <= we.isoformat()]
        avg    = round(sum(scores) / len(scores), 1) if scores else None
        weekly_quality.append({"week_start": wm.isoformat(), "avg_quality": avg, "session_count": len(scores)})

    # Trend (complete weeks only → [:-0] = all 8)
    q_vals = [w["avg_quality"] for w in weekly_quality if w["avg_quality"] is not None]
    trend = "stable"
    if len(q_vals) >= 6:
        recent_avg = sum(q_vals[-3:]) / 3
        prior_avg  = sum(q_vals[-6:-3]) / 3
        if recent_avg - prior_avg >= 8:
            trend = "improving"
        elif prior_avg - recent_avg >= 8:
            trend = "declining"

    overall_avg = round(sum(q for _, q in session_scores) / len(session_scores), 1) if session_scores else None

    best = max(session_scores, key=lambda x: x[1]) if session_scores else None
    best_session = {"date": best[0], "score": best[1]} if best else None

    if trend == "improving":
        message = "Qualité des séances en hausse — ton engagement augmente."
    elif trend == "declining":
        message = "Qualité des séances en baisse — vérifie fatigue et motivation."
    else:
        message = "Qualité des séances stable."

    return {
        "has_data":      True,
        "weekly_quality": weekly_quality,
        "trend":          trend,
        "avg_quality":    overall_avg,
        "best_session":   best_session,
        "message":        message,
    }
