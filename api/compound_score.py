"""
compound_score.py — Compound Interest Score.

Consistency score that grows non-linearly: a current streak amplifies the
base rate, while the raw base already absorbs missed days.

  base     = active_days / span_days            (workout OR nutrition logged)
  multiplier = 1 + log(1+streak) / log(31) * 0.5  (max 1.5 at 30-day streak)
  score    = base × multiplier × 100

100 = linear baseline (active every day, no streak bonus).
>100 = compounding consistency.

Comparison: recent 30 days vs prior 30 days to surface trend.

Data read: workout sessions, nutrition entries.
No writes. No modification to historical data.
"""
from __future__ import annotations
import logging
import math
from datetime import date, timedelta

import db
from utils import _today_mtl as _today_iso

logger = logging.getLogger("trainingos.compound")


def _current_streak(w_dates: set[str], sorted_dates: list[str]) -> int:
    """Count consecutive workout days backwards from today."""
    today_str = _today_iso()
    streak = 0
    for d in reversed(sorted_dates):
        if d > today_str:
            continue
        if d in w_dates:
            streak += 1
        else:
            break
    return streak


def _span_result(
    sessions: list[dict],
    nutrition: list[dict],
    span_dates: list[str],
) -> dict:
    date_set = set(span_dates)
    n = len(span_dates)
    if n == 0:
        return {"score": 0.0, "base_pct": 0.0, "active_days": 0, "streak": 0, "multiplier": 1.0}

    w_dates = {s["date"] for s in sessions
               if s.get("date") in date_set and s.get("completed")}
    n_dates = {e["date"] for e in nutrition if e.get("date") in date_set}

    active      = w_dates | n_dates
    base_pct    = len(active) / n
    streak      = _current_streak(w_dates, span_dates)
    multiplier  = 1.0 + math.log1p(streak) / math.log1p(30) * 0.5
    multiplier  = min(1.5, multiplier)
    score       = round(base_pct * multiplier * 100, 1)

    return {
        "score":       score,
        "base_pct":    round(base_pct * 100, 1),
        "active_days": len(active),
        "streak":      streak,
        "multiplier":  round(multiplier, 3),
        "workout_days":   len(w_dates),
        "nutrition_days": len(n_dates),
    }


def compute() -> dict:
    today = date.fromisoformat(_today_iso())

    # Recent 30 days (J0–29) and prior 30 days (J30–59)
    recent_dates = sorted((today - timedelta(days=i)).isoformat() for i in range(30))
    prior_dates  = sorted((today - timedelta(days=30 + i)).isoformat() for i in range(30))

    sessions  = db.get_workout_sessions(limit=90) or []
    nutrition = db.get_nutrition_entries_recent(90) or []

    recent = _span_result(sessions, nutrition, recent_dates)
    prior  = _span_result(sessions, nutrition, prior_dates)

    delta = round(recent["score"] - prior["score"], 1)
    trend = "hausse" if delta > 5 else ("baisse" if delta < -5 else "stable")

    has_baseline = prior["active_days"] > 0

    return {
        "score":            recent["score"],
        "base_consistency": recent["base_pct"],
        "current_streak":   recent["streak"],
        "multiplier":       recent["multiplier"],
        "delta_vs_30d":     delta,
        "trend":            trend,
        "has_baseline":     has_baseline,
        "breakdown": {
            "workout_days":   recent["workout_days"],
            "nutrition_days": recent["nutrition_days"],
            "active_days":    recent["active_days"],
            "total_days":     30,
        },
    }
