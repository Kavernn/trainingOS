"""
sleep_quality_engine.py — Sleep Quality Score.

Combines two recovery_log signals per night:
  hours_score   = penalty for deviation from 7–9 h window (100 if in range, –10/h outside)
  quality_score = sleep_quality field (1–10) × 10

composite = hours_score × 0.5 + quality_score × 0.5, clamped 0–100.

Aggregates into 8-week weekly averages. Trend: last 3 vs preceding 3 weeks.
Only nights with at least one of the two fields are included.

Data read only. No writes.
"""
from __future__ import annotations
import logging
from datetime import date, timedelta
from typing import Optional

import db
from utils import _today_mtl as _today_iso

logger = logging.getLogger("trainingos.sleep_quality")

_WEEKS       = 8
_HOURS_MIN   = 7.0
_HOURS_MAX   = 9.0


def _hours_score(h: float) -> float:
    if _HOURS_MIN <= h <= _HOURS_MAX:
        return 100.0
    deficit = min(abs(h - _HOURS_MIN), abs(h - _HOURS_MAX))
    return max(0.0, 100.0 - deficit * 10.0)


def _composite(sleep_h: Optional[float], quality: Optional[float]) -> Optional[float]:
    if sleep_h is None and quality is None:
        return None
    hs = _hours_score(float(sleep_h)) if sleep_h is not None else None
    qs = float(quality) * 10.0        if quality  is not None else None
    if hs is not None and qs is not None:
        return hs * 0.5 + qs * 0.5
    return hs if hs is not None else qs


def _monday(d: date) -> date:
    return d - timedelta(days=d.weekday())


def compute() -> dict:
    today_str  = _today_iso()
    today      = date.fromisoformat(today_str)
    cutoff     = (today - timedelta(days=_WEEKS * 7)).isoformat()

    logs = db.get_recovery_logs(limit=200) or []
    valid = [
        l for l in logs
        if l.get("date") and l["date"] >= cutoff
        and (l.get("sleep_hours") is not None or l.get("sleep_quality") is not None)
    ]

    if len(valid) < 4:
        return {
            "has_data": False,
            "weekly_scores": [],
            "trend": "stable",
            "avg_score": None,
            "current_score": None,
            "message": "Pas assez de données de sommeil.",
        }

    cur_monday = _monday(today)
    weekly_scores = []

    for w in range(_WEEKS, 0, -1):
        wm = cur_monday - timedelta(weeks=w)
        we = wm + timedelta(days=6)
        sw, ew = wm.isoformat(), we.isoformat()
        scores = [
            _composite(l.get("sleep_hours"), l.get("sleep_quality"))
            for l in valid if sw <= l["date"] <= ew
        ]
        scores = [s for s in scores if s is not None]
        avg = round(sum(scores) / len(scores), 1) if scores else None
        weekly_scores.append({"week_start": wm.isoformat(), "score": avg, "count": len(scores)})

    q_vals = [w["score"] for w in weekly_scores if w["score"] is not None]
    trend = "stable"
    if len(q_vals) >= 6:
        recent = sum(q_vals[-3:]) / 3
        prior  = sum(q_vals[-6:-3]) / 3
        if recent - prior >= 6:
            trend = "improving"
        elif prior - recent >= 6:
            trend = "declining"

    overall_avg = round(sum(q_vals) / len(q_vals), 1) if q_vals else None

    latest = sorted(valid, key=lambda l: l["date"], reverse=True)[0]
    current_score_val = _composite(latest.get("sleep_hours"), latest.get("sleep_quality"))
    current_score = round(current_score_val, 1) if current_score_val is not None else None

    if trend == "improving":
        message = "Qualité du sommeil en hausse — récupération optimisée."
    elif trend == "declining":
        message = "Qualité du sommeil en baisse — surveille ton hygiène de sommeil."
    else:
        if overall_avg and overall_avg >= 75:
            message = "Sommeil de bonne qualité et stable."
        elif overall_avg and overall_avg >= 50:
            message = "Qualité du sommeil correcte mais améliorable."
        else:
            message = "Qualité du sommeil insuffisante — impacte la récupération."

    return {
        "has_data":      True,
        "weekly_scores": weekly_scores,
        "trend":         trend,
        "avg_score":     overall_avg,
        "current_score": current_score,
        "message":       message,
    }
