"""
nutrition_performance_engine.py — Nutrition × Performance Correlation.

For each completed session with RPE, check whether nutrition was logged
the day before. Compare avg RPE between the two groups.

Minimum: 3 sessions in each group for a meaningful comparison.
Data read only. No writes.
"""
from __future__ import annotations
import logging
from datetime import date, timedelta

import db
from utils import _today_mtl as _today_iso

logger = logging.getLogger("trainingos.nutrition_performance")

_MIN_PER_GROUP = 3


def compute() -> dict:
    sessions  = db.get_workout_sessions(limit=300) or []
    nutrition = db.get_nutrition_entries_recent(365) or []

    nutr_dates = {e["date"] for e in nutrition if e.get("date")}

    completed = [
        s for s in sessions
        if s.get("completed") and s.get("date") and s.get("rpe") is not None
    ]

    with_nutr:    list[float] = []
    without_nutr: list[float] = []

    for s in completed:
        prev_day = (date.fromisoformat(s["date"]) - timedelta(days=1)).isoformat()
        rpe = float(s["rpe"])
        if prev_day in nutr_dates:
            with_nutr.append(rpe)
        else:
            without_nutr.append(rpe)

    n_with    = len(with_nutr)
    n_without = len(without_nutr)

    if n_with < _MIN_PER_GROUP or n_without < _MIN_PER_GROUP:
        return {
            "has_data":          False,
            "avg_rpe_with":      None,
            "avg_rpe_without":   None,
            "count_with":        n_with,
            "count_without":     n_without,
            "rpe_diff":          None,
            "impact_pct":        None,
            "sessions_analyzed": len(completed),
            "message":           "Pas assez de données pour établir une corrélation.",
        }

    avg_with    = round(sum(with_nutr)    / n_with,    1)
    avg_without = round(sum(without_nutr) / n_without, 1)
    rpe_diff    = round(avg_with - avg_without, 1)
    impact_pct  = round(abs(rpe_diff) / avg_without * 100) if avg_without > 0 else 0

    if rpe_diff >= 0.5:
        message = (f"Tu performes mieux quand tu manges la veille "
                   f"(+{rpe_diff} RPE en moyenne sur {n_with} séances).")
    elif rpe_diff <= -0.5:
        message = (f"Tes séances sans nutrition J-1 ont un RPE plus élevé "
                   f"({abs(rpe_diff)} points) — d'autres facteurs influencent plus.")
    else:
        message = "Impact neutre de la nutrition J-1 sur ton RPE — d'autres variables dominent."

    return {
        "has_data":          True,
        "avg_rpe_with":      avg_with,
        "avg_rpe_without":   avg_without,
        "count_with":        n_with,
        "count_without":     n_without,
        "rpe_diff":          rpe_diff,
        "impact_pct":        impact_pct,
        "sessions_analyzed": len(completed),
        "message":           message,
    }
