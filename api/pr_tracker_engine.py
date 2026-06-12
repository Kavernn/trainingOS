"""
pr_tracker_engine.py — Personal Record Tracker.

For each exercise in the last 180 days, finds:
  - all_time_max: highest estimated 1RM (Epley: w × (1 + reps/30)) ever recorded
  - recent_max:   highest estimated 1RM in the last 30 days

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

logger = logging.getLogger("trainingos.pr_tracker")

_LOOKBACK_DAYS  = 180
_RECENT_DAYS    = 30
_MAX_RESULTS    = 5


def _epley(weight: float, reps: int) -> float:
    if reps <= 0 or reps > 15:
        return weight
    if reps <= 10:
        return round(weight * (1.0 + reps / 30.0), 1)    # Epley (1985)
    return round(weight * (36.0 / (37.0 - reps)), 1)     # Brzycki (1993)


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
            est = _epley(sw, sr)
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
    today_str    = _today_iso()
    today        = date.fromisoformat(today_str)
    recent_start = (today - timedelta(days=_RECENT_DAYS)).isoformat()

    history = db.get_all_exercise_history(cutoff_days=_LOOKBACK_DAYS) or {}

    if not history:
        return {
            "has_data": False,
            "recent_prs": [],
            "total_prs": 0,
            "exercises_tracked": 0,
            "message": "Pas assez de données d'exercices.",
        }

    prs = []
    for name, entries in history.items():
        if len(entries) < 2:
            continue

        all_best    = _max_1rm(entries)
        recent_entries = [e for e in entries if (e.get("date") or "") >= recent_start]
        recent_best = _max_1rm(recent_entries) if recent_entries else None

        if all_best is None or recent_best is None:
            continue

        # A PR if recent best ≥ all-time best (achieved within last 30 days)
        if recent_best[0] >= all_best[0] * 0.999:  # float tolerance
            prs.append({
                "name":       name,
                "est_1rm":    round(recent_best[0], 1),
                "date":       recent_best[1],
                "prev_best":  round(all_best[0], 1) if len(entries) > len(recent_entries) else None,
            })

    prs.sort(key=lambda x: x["date"], reverse=True)
    total_prs = len(prs)

    if total_prs == 0:
        message = "Aucun nouveau record personnel sur les 30 derniers jours."
    elif total_prs == 1:
        message = "1 nouveau record personnel ce mois-ci — continue."
    else:
        message = f"{total_prs} nouveaux records personnels ce mois-ci — progression validée."

    return {
        "has_data":          total_prs > 0 or len(history) >= 3,
        "recent_prs":        prs[:_MAX_RESULTS],
        "total_prs":         total_prs,
        "exercises_tracked": len(history),
        "message":           message,
    }
