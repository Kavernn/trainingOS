"""
progressive_overload_engine.py — Progressive Overload Tracker.

For each exercise with data in both the recent 4-week window and the
preceding 4-week window, computes max weight lifted (or estimated 1RM).
Classifies exercises as:
  gaining  — max weight improved ≥ 5 %
  stalled  — change within ±5 %
  declining — max weight dropped ≥ 5 %

Returns top 3 gainers and up to 5 stalled exercises.

Data read only. No writes.
"""
from __future__ import annotations
import logging
from datetime import date, timedelta
from typing import Optional

import db
from utils import _today_mtl as _today_iso
from progression import estimate_1rm as _estimate_1rm

logger = logging.getLogger("trainingos.progressive_overload")

_GAIN_THRESHOLD  =  5.0  # %
_STALL_THRESHOLD = -5.0  # %
_MIN_SESSIONS    =  2    # per window to be considered

DAY_NAMES = ["Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi", "Dimanche"]


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


def _max_1rm_for_entries(entries: list[dict]) -> Optional[float]:
    """Return the highest estimated 1RM from a list of history entries."""
    best: Optional[float] = None
    for e in entries:
        w    = _to_float(e.get("weight"))
        r    = _to_int(e.get("reps"))
        sets = e.get("sets") or []
        if sets:
            for s in sets:
                if not isinstance(s, dict):
                    continue
                sw = _to_float(s.get("weight"), w)
                sr = _to_int(s.get("reps"), r)
                if sw > 0:
                    est = _estimate_1rm(sw, str(sr)) or 0.0
                    if best is None or est > best:
                        best = est
        elif w > 0:
            est = _estimate_1rm(w, str(r)) or 0.0
            if best is None or est > best:
                best = est
    return best


def compute() -> dict:
    try:
        return _compute()
    except Exception:
        logger.exception("progressive_overload compute error")
        return {"has_data": False, "top_gainers": [], "stalled": [], "exercises_tracked": 0, "message": "Erreur serveur"}


def _compute() -> dict:
    today_str = _today_iso()
    today     = date.fromisoformat(today_str)

    recent_start = today - timedelta(days=28)
    prior_start  = today - timedelta(days=56)

    history = db.get_all_exercise_history(cutoff_days=60) or {}

    if not history:
        return {
            "has_data": False,
            "top_gainers": [],
            "stalled": [],
            "exercises_tracked": 0,
            "message": "Pas assez de données d'entraînement.",
        }

    gainers  = []
    stalled  = []
    tracked  = 0

    for name, entries in history.items():
        recent = [e for e in entries if recent_start.isoformat() <= (e.get("date") or "") <= today_str]
        prior  = [e for e in entries if prior_start.isoformat()  <= (e.get("date") or "") <  recent_start.isoformat()]

        if len(recent) < _MIN_SESSIONS or len(prior) < _MIN_SESSIONS:
            continue

        max_recent = _max_1rm_for_entries(recent)
        max_prior  = _max_1rm_for_entries(prior)

        if max_recent is None or max_prior is None or max_prior == 0:
            continue

        tracked += 1
        pct = (max_recent - max_prior) / max_prior * 100

        entry = {
            "name":    name,
            "pct":     round(pct, 1),
            "recent":  round(max_recent, 1),
            "prior":   round(max_prior, 1),
        }

        if pct >= _GAIN_THRESHOLD:
            gainers.append(entry)
        elif pct > _STALL_THRESHOLD:
            stalled.append(entry)

    gainers.sort(key=lambda x: x["pct"], reverse=True)
    stalled.sort(key=lambda x: x["pct"])

    if tracked < 2:
        return {
            "has_data": False,
            "top_gainers": [],
            "stalled": [],
            "exercises_tracked": tracked,
            "message": "Pas assez d'exercices comparables sur les deux périodes.",
        }

    if gainers:
        count = len(gainers)
        message = f"{count} exercice{'s' if count > 1 else ''} en progression — la surcharge progressive fonctionne."
    elif stalled:
        message = "La plupart des exercices sont stagnants — pense à ajuster la charge ou le volume."
    else:
        message = "Signe de régression sur plusieurs exercices — vérifie la récupération."

    return {
        "has_data":          True,
        "top_gainers":       gainers[:3],
        "stalled":           stalled[:5],
        "exercises_tracked": tracked,
        "message":           message,
    }
