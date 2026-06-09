"""
comeback_arc_engine.py — Comeback Arc.

Detects the most recent rupture episode (2+ consecutive inactive days —
no completed workout AND no nutrition logged) within the last 60 days.

If the episode ended within the last 21 days, the user is in a comeback
window. Measures post-rupture recovery: % of days since rupture that
had at least one active pillar (workout OR nutrition).

Data read only. No writes.
"""
from __future__ import annotations
import logging
from datetime import date, timedelta

import db
from utils import _today_mtl as _today_iso

logger = logging.getLogger("trainingos.comeback_arc")

_LOOKBACK_DAYS    = 60   # how far back to search for rupture episodes
_COMEBACK_WINDOW  = 21   # episode must have ended within this many days


def _find_rupture_episodes(
    session_dates: set[str],
    nutr_dates:    set[str],
    today:         date,
    lookback:      int,
) -> list[dict]:
    episodes: list[dict] = []
    streak_start: str | None = None
    streak_len    = 0

    for n in range(lookback):
        d = (today - timedelta(days=lookback - 1 - n)).isoformat()
        inactive = d not in session_dates and d not in nutr_dates
        if inactive:
            if streak_start is None:
                streak_start = d
            streak_len += 1
        else:
            if streak_len >= 2 and streak_start:
                ep_end = (date.fromisoformat(streak_start) + timedelta(days=streak_len - 1)).isoformat()
                episodes.append({"start": streak_start, "end": ep_end, "length": streak_len})
            streak_start = None
            streak_len   = 0

    if streak_len >= 2 and streak_start:
        ep_end = (date.fromisoformat(streak_start) + timedelta(days=streak_len - 1)).isoformat()
        episodes.append({"start": streak_start, "end": ep_end, "length": streak_len})

    return episodes


def compute() -> dict:
    today_str = _today_iso()
    today     = date.fromisoformat(today_str)

    sessions  = db.get_workout_sessions(limit=200) or []
    nutrition = db.get_nutrition_entries_recent(90) or []

    session_dates = {s["date"] for s in sessions if s.get("completed") and s.get("date")}
    nutr_dates    = {e["date"] for e in nutrition if e.get("date")}

    episodes = _find_rupture_episodes(session_dates, nutr_dates, today, _LOOKBACK_DAYS)

    _no_comeback = {
        "has_data": False, "in_comeback": False,
        "rupture_start": None, "rupture_end": None, "rupture_length": None,
        "days_since_rupture": None, "active_days": None, "active_since_pct": None,
        "message": "Aucune rupture récente détectée.",
    }

    if not episodes:
        return _no_comeback

    last_ep   = max(episodes, key=lambda e: e["end"])
    end_date  = date.fromisoformat(last_ep["end"])
    days_since = (today - end_date).days

    if days_since < 1 or days_since > _COMEBACK_WINDOW:
        return _no_comeback

    active_days = 0
    for n in range(1, days_since + 1):
        d = (end_date + timedelta(days=n)).isoformat()
        if d in session_dates or d in nutr_dates:
            active_days += 1

    active_pct = round(active_days / days_since * 100) if days_since > 0 else 0

    if active_pct >= 80:
        message = f"Comeback solide — {active_pct}% des jours actifs depuis ta rupture."
    elif active_pct >= 50:
        message = f"Remontée en cours — {active_pct}% des jours actifs depuis ta rupture."
    else:
        message = f"Comeback fragile — seulement {active_pct}% des jours actifs. Reprends le rythme."

    return {
        "has_data":          True,
        "in_comeback":       True,
        "rupture_start":     last_ep["start"],
        "rupture_end":       last_ep["end"],
        "rupture_length":    last_ep["length"],
        "days_since_rupture": days_since,
        "active_days":       active_days,
        "active_since_pct":  active_pct,
        "message":           message,
    }
