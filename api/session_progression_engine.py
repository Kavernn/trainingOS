"""
session_progression_engine.py — Per-session-type progression.

For each session type (Push A, Pull B, Full Body, etc.), compares the
last occurrence against the previous baseline (up to 4 prior sessions)
on volume (kg×reps) and duration.

This replaces day-of-week temporal comparisons with comparisons that
are actually meaningful: same session type vs its own history.

Data read only. No writes.
"""
from __future__ import annotations
import logging
from datetime import date, timedelta

import db
from utils import _today_mtl as _today_iso

logger = logging.getLogger("trainingos.session_progression")

_MIN_OCCURRENCES = 2   # need at least 1 baseline + last
_BASELINE_WINDOW = 4   # number of prior occurrences for baseline average
_MAX_SESSIONS    = 200


def _mean(vals: list[float]) -> float:
    return sum(vals) / len(vals) if vals else 0.0


def _pct_delta(last: float, baseline: float) -> float | None:
    if baseline <= 0:
        return None
    return round((last - baseline) / baseline * 100, 1)


def _trend(delta: float | None) -> str:
    if delta is None:
        return "stable"
    if delta > 5:
        return "up"
    if delta < -5:
        return "down"
    return "stable"


def compute() -> dict:
    today_str = _today_iso()
    cutoff    = (date.fromisoformat(today_str) - timedelta(days=_MAX_SESSIONS)).isoformat()

    sessions = db.get_workout_sessions(limit=_MAX_SESSIONS) or []
    completed = [
        s for s in sessions
        if s.get("completed")
        and s.get("session_name")
        and s.get("date", "") >= cutoff
    ]

    if not completed:
        return {"has_data": False, "sessions": []}

    # Volume map: {date: total_volume} from v_session_volume view
    vol_map = db.get_session_volume_map(days=_MAX_SESSIONS)

    # Group by session name, sorted date DESC
    by_name: dict[str, list[dict]] = {}
    for s in sorted(completed, key=lambda x: x["date"], reverse=True):
        name = s["session_name"]
        by_name.setdefault(name, []).append(s)

    results: list[dict] = []
    for name, occurrences in by_name.items():
        if len(occurrences) < _MIN_OCCURRENCES:
            continue

        last   = occurrences[0]
        prior  = occurrences[1:_BASELINE_WINDOW + 1]

        last_vol  = vol_map.get(last["date"])
        prior_vols = [vol_map[s["date"]] for s in prior if s["date"] in vol_map]

        last_dur   = last.get("duration_min")
        prior_durs = [s["duration_min"] for s in prior if s.get("duration_min")]

        baseline_vol = _mean(prior_vols) if prior_vols else None
        baseline_dur = _mean([float(d) for d in prior_durs]) if prior_durs else None

        vol_delta = _pct_delta(last_vol, baseline_vol) if last_vol and baseline_vol else None
        dur_delta = _pct_delta(
            float(last_dur), baseline_dur
        ) if last_dur and baseline_dur else None

        results.append({
            "session_name":      name,
            "last_date":         last["date"],
            "last_volume":       round(last_vol, 1) if last_vol else None,
            "last_duration":     last_dur,
            "last_rpe":          last.get("rpe"),
            "baseline_volume":   round(baseline_vol, 1) if baseline_vol else None,
            "baseline_duration": round(baseline_dur, 0) if baseline_dur else None,
            "volume_delta_pct":  vol_delta,
            "duration_delta_pct": dur_delta,
            "trend":             _trend(vol_delta),
            "occurrences":       len(occurrences),
        })

    # Sort by last_date DESC so most recently trained session appears first
    results.sort(key=lambda x: x["last_date"], reverse=True)

    return {"has_data": bool(results), "sessions": results}
