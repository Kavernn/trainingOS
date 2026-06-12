"""
pr_tracker_engine.py — Personal Record Tracker.

For each exercise, finds:
  - all_time_max: pr_e1rm_lbs from exercise_prs table (maintained at write time)
  - recent_max:   highest estimated 1RM in the last 30 days (live scan)

A PR is flagged when recent_max >= all_time_max (i.e. set within last 30 days).

Returns up to 5 recent PRs sorted by recency, plus total_prs count.

Data read only. No writes.
"""
from __future__ import annotations
import logging
from datetime import date, timedelta
from typing import Optional

import db
from utils import _today_mtl as _today_iso
from progression import estimate_1rm as _estimate_1rm

logger = logging.getLogger("trainingos.pr_tracker")

_RECENT_DAYS = 30
_MAX_RESULTS = 5


def _to_float(v, default: float = 0.0) -> float:
    try:
        return float(v) if v is not None else default
    except (TypeError, ValueError):
        return default

def _to_int(v, default: int = 1) -> int:
    try:
        return int(float(v)) if v is not None else default
    except (TypeError, ValueError):
        return default


def _max_1rm(entries: list[dict]) -> Optional[tuple[float, str]]:
    """Return (best_1rm, date_of_best) or None."""
    best: Optional[tuple[float, str]] = None
    for e in entries:
        d    = e.get("date") or ""
        w    = _to_float(e.get("weight"))
        r    = _to_int(e.get("reps"))
        sets = e.get("sets") or []
        candidates = [
            (_to_float(s.get("weight"), w), _to_int(s.get("reps"), r))
            for s in sets if isinstance(s, dict)
        ] if sets else []
        if not candidates:
            candidates = [(w, r)]
        for sw, sr in candidates:
            if sw <= 0:
                continue
            est = _estimate_1rm(sw, str(sr)) or 0.0
            if best is None or est > best[0]:
                best = (est, d)
    return best


def compute() -> dict:
    try:
        return _compute()
    except Exception:
        logger.exception("pr_tracker compute error")
        return {"has_data": False, "recent_prs": [], "total_prs": 0, "exercises_tracked": 0, "message": "Erreur serveur"}


def _compute() -> dict:
    today_str = _today_iso()
    today     = date.fromisoformat(today_str)

    # All-time PRs from table — O(1), no history scan
    pr_rows = db.get_exercise_prs() or []
    pr_map  = {p["exercise_name"]: p for p in pr_rows}

    # Recent 30-day history for peak detection only
    history = db.get_all_exercise_history(cutoff_days=_RECENT_DAYS) or {}

    if not pr_map:
        return {
            "has_data": False,
            "recent_prs": [],
            "total_prs": 0,
            "exercises_tracked": 0,
            "message": "Pas assez de données d'exercices.",
        }

    prs = []
    for name, entries in history.items():
        pr_row = pr_map.get(name)
        if not pr_row or pr_row.get("baseline_count", 0) < 2:
            continue

        all_time_1rm = float(pr_row["pr_e1rm_lbs"] or 0)
        recent_best  = _max_1rm(entries)

        if recent_best is None or all_time_1rm <= 0:
            continue

        # A PR if recent best ≥ all-time best (achieved within last 30 days)
        if recent_best[0] >= all_time_1rm * 0.999:  # float tolerance
            prs.append({
                "name":      name,
                "est_1rm":   round(recent_best[0], 1),
                "date":      recent_best[1],
                "prev_best": round(all_time_1rm, 1),
            })

    prs.sort(key=lambda x: x["date"], reverse=True)
    total_prs = len(prs)
    tracked   = len(pr_map)

    if total_prs == 0:
        message = "Aucun nouveau record personnel sur les 30 derniers jours."
    elif total_prs == 1:
        message = "1 nouveau record personnel ce mois-ci — continue."
    else:
        message = f"{total_prs} nouveaux records personnels ce mois-ci — progression validée."

    return {
        "has_data":          total_prs > 0 or tracked >= 3,
        "recent_prs":        prs[:_MAX_RESULTS],
        "total_prs":         total_prs,
        "exercises_tracked": tracked,
        "message":           message,
    }
