from __future__ import annotations
import db
from datetime import datetime


def load_sessions() -> dict:
    try:
        rows = db.get_workout_sessions(limit=500)
        if isinstance(rows, list):
            result = {}
            for row in rows:
                if not isinstance(row, dict):
                    continue
                date = row.get("date")
                if date:
                    entry = {k: v for k, v in row.items() if k not in ("date", "id", "is_second", "user_id")}
                    for field in ("rpe", "duration_min", "session_volume"):
                        if field in entry and entry[field] is not None:
                            entry[field] = float(entry[field])
                    result[date] = entry
            return result
    except Exception:
        pass
    return {}


def save_sessions(sessions: dict):
    try:
        for date, entry in sessions.items():
            if isinstance(entry, dict):
                db.update_workout_session(date, entry)
    except Exception:
        pass


def log_session(
    date: str,
    rpe,
    comment: str,
    exos: list | None = None,
    duration_min=None,
    energy_pre=None,
    blocks: list | None = None,
    session_volume=None,
    total_reps=None,
    total_sets=None,
):
    """Log a workout session for the given date.

    Args:
        date:           ISO date string (YYYY-MM-DD).
        rpe:            Rate of perceived exertion.
        comment:        Free-text note.
        exos:           Legacy flat list of exercise names (strength only).
                        Ignored when *blocks* is provided.
        duration_min:   Total session duration in minutes.
        energy_pre:     Pre-workout energy level.
        blocks:         Ordered list of workout blocks (strength / hiit / cardio).
                        Each block is a dict with at least {"type": ..., "order": ...}.
        session_volume: Total volume lifted this session (lbs × reps).
        total_reps:     Total reps performed across all strength exercises.
        total_sets:     Total sets performed across all strength exercises.
    """
    patch: dict = {}
    if rpe is not None:
        patch["rpe"] = rpe
    if comment is not None:
        patch["comment"] = comment
    if duration_min is not None:
        patch["duration_min"] = duration_min
    if energy_pre is not None:
        patch["energy_pre"] = energy_pre
    if session_volume is not None:
        patch["session_volume"] = session_volume
    if total_reps is not None:
        patch["total_reps"] = total_reps
    if total_sets is not None:
        patch["total_sets"] = total_sets

    try:
        existing = db.get_workout_session(date)
        if existing:
            db.update_workout_session(date, patch)
        else:
            db.create_workout_session(
                date,
                rpe=rpe,
                comment=comment,
                duration_min=duration_min,
                energy_pre=energy_pre,
            )
    except Exception:
        pass


def log_second_session(
    date: str,
    rpe,
    comment: str,
    exos: list | None = None,
    duration_min=None,
    energy_pre=None,
    blocks: list | None = None,
    session_volume=None,
    total_reps=None,
    total_sets=None,
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
    if session_volume is not None:
        extra["session_volume"] = session_volume
    if total_reps is not None:
        extra["total_reps"] = total_reps
    if total_sets is not None:
        extra["total_sets"] = total_sets

    entry.setdefault("extra_sessions", []).append(extra)
    save_sessions(sessions)


def session_exists(date: str) -> bool:
    try:
        session = db.get_workout_session(date)
        return session is not None and session.get("completed", False)
    except Exception:
        return False


def get_last_sessions(n: int = 10) -> list:
    try:
        rows = db.get_workout_sessions(limit=n)
        if isinstance(rows, list):
            return [r for r in rows if isinstance(r, dict) and "date" in r][:n]
    except Exception:
        pass
    return []


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
