from __future__ import annotations
from db import get_json, set_json
from datetime import datetime


def load_sessions() -> dict:
    return get_json("sessions", {})


def save_sessions(sessions: dict):
    set_json("sessions", sessions)


def log_session(
    date: str,
    rpe,
    comment: str,
    exos: list | None = None,
    duration_min=None,
    energy_pre=None,
    blocks: list | None = None,
):
    """Log a workout session for the given date.

    Args:
        date:         ISO date string (YYYY-MM-DD).
        rpe:          Rate of perceived exertion.
        comment:      Free-text note.
        exos:         Legacy flat list of exercise names (strength only).
                      Ignored when *blocks* is provided.
        duration_min: Total session duration in minutes.
        energy_pre:   Pre-workout energy level.
        blocks:       Ordered list of workout blocks (strength / hiit / cardio).
                      Each block is a dict with at least {"type": ..., "order": ...}.
    """
    sessions = load_sessions()

    # Derive the legacy exos field so older readers stay compatible
    legacy_exos = exos or []
    if blocks is not None and not legacy_exos:
        strength = next((b for b in blocks if b.get("type") == "strength"), None)
        if strength:
            legacy_exos = strength.get("exos", [])

    entry: dict = {
        "rpe":       rpe,
        "comment":   comment,
        "exos":      legacy_exos,
        "logged_at": datetime.now().strftime("%Y-%m-%d %H:%M"),
    }
    if blocks is not None:
        entry["blocks"] = blocks
    if duration_min is not None:
        entry["duration_min"] = duration_min
    if energy_pre is not None:
        entry["energy_pre"] = energy_pre

    sessions[date] = entry
    save_sessions(sessions)


def log_second_session(
    date: str,
    rpe,
    comment: str,
    exos: list | None = None,
    duration_min=None,
    energy_pre=None,
    blocks: list | None = None,
):
    """Append a second session to the same day without overwriting the first."""
    sessions = load_sessions()
    entry = sessions.setdefault(date, {"exos": [], "logged_at": datetime.now().strftime("%Y-%m-%d %H:%M")})

    legacy_exos = exos or []
    if blocks is not None and not legacy_exos:
        strength = next((b for b in blocks if b.get("type") == "strength"), None)
        if strength:
            legacy_exos = strength.get("exos", [])

    extra: dict = {
        "rpe":       rpe,
        "comment":   comment,
        "exos":      legacy_exos,
        "logged_at": datetime.now().strftime("%Y-%m-%d %H:%M"),
    }
    if blocks is not None:
        extra["blocks"] = blocks
    if duration_min is not None:
        extra["duration_min"] = duration_min
    if energy_pre is not None:
        extra["energy_pre"] = energy_pre

    entry.setdefault("extra_sessions", []).append(extra)
    save_sessions(sessions)


def session_exists(date: str) -> bool:
    return date in load_sessions()


def get_last_sessions(n: int = 10) -> list:
    sessions = load_sessions()
    result = []
    for date in sorted(sessions.keys(), reverse=True)[:n]:
        entry = sessions[date].copy()
        entry["date"] = date
        result.append(entry)
    return result


def get_session_blocks(date: str) -> list:
    """Return the blocks list for a logged session.

    Falls back to a derived strength block when only the legacy flat exos list
    is present (pre-migration sessions).
    """
    sessions = load_sessions()
    entry = sessions.get(date, {})
    if "blocks" in entry:
        return entry["blocks"]
    exos = entry.get("exos", [])
    if exos:
        return [{"type": "strength", "order": 0, "exos": exos}]
    return []


def migrate_sessions_from_weights(weights: dict) -> int:
    return 0
