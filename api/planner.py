from __future__ import annotations
from db import get_json, set_json
from datetime import datetime
from typing import Dict, List
from blocks import make_strength_block, get_strength_exercises, sorted_blocks
from progression import suggest_next_weight


# ---------------------------------------------------------------------------
# Default program (new block format)
# ---------------------------------------------------------------------------

DEFAULT_PROGRAM = {
    "Push A": {
        "blocks": [
            make_strength_block({
                "Bench Press":       "4x5-7",
                "Overhead Press":    "3x6-8",
                "Incline DB Press":  "3x8-10",
                "Lateral Raises":    "3x12-15",
                "Triceps Extension": "3x10-12",
            }, order=0)
        ]
    },
    "Pull A": {
        "blocks": [
            make_strength_block({
                "Barbell Row":  "4x6-8",
                "Lat Pulldown": "3x8-10",
                "Seated Row":   "3x10-12",
                "Face Pull":    "3x15",
                "Hammer Curl":  "3x10-12",
            }, order=0)
        ]
    },
    "Legs": {
        "blocks": [
            make_strength_block({
                "Back Squat":        "4x5-7",
                "Leg Press":         "3x10-12",
                "Leg Curl":          "3x10-12",
                "Romanian Deadlift": "3x8-10",
                "Calf Raise":        "3x12-15",
                "Abs":               "3x12-15",
            }, order=0)
        ]
    },
    "Push B": {
        "blocks": [
            make_strength_block({
                "Incline DB Press":  "4x8-10",
                "DB Bench Press":    "3x10-12",
                "Overhead Press":    "3x8-10",
                "Lateral Raises":    "4x12-15",
                "Triceps Extension": "3x12-15",
            }, order=0)
        ]
    },
    "Pull B + Full Body": {
        "blocks": [
            make_strength_block({
                "Deadlift":     "3x5",
                "T-Bar Row":    "4x8-10",
                "Lat Pulldown": "3x10-12",
                "Face Pull":    "3x15",
                "Hammer Curl":  "3x12-15",
            }, order=0)
        ]
    },
}

SCHEDULE = {
    0: "Push A",
    1: "Pull A",
    2: "Legs",
    3: "Push B",
    4: "Pull B + Full Body",
    5: "Yoga / Tai Chi",
    6: "Recovery",
}


# ---------------------------------------------------------------------------
# Migration
# ---------------------------------------------------------------------------

def _migrate_session(data) -> dict:
    """Convert a legacy flat {exercise: scheme} session to the block format.

    Already-migrated sessions (containing "blocks") are returned unchanged.
    """
    if isinstance(data, dict) and "blocks" in data:
        return data
    if isinstance(data, dict):
        return {"blocks": [make_strength_block(data, order=0)]}
    return {"blocks": []}


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

def load_program() -> dict:
    """Load the program from KV, auto-migrating legacy sessions and seeding missing ones."""
    raw = get_json("program", {})
    program = {name: _migrate_session(session) for name, session in raw.items()}

    # Seed any new sessions that don't exist yet in KV
    changed = False
    for name, session_def in DEFAULT_PROGRAM.items():
        if name not in program:
            program[name] = session_def
            changed = True
    if changed:
        save_program(program)

    return program


def save_program(program: dict):
    set_json("program", program)


# ---------------------------------------------------------------------------
# Timezone helpers (Montreal / Eastern)
# ---------------------------------------------------------------------------

def _eastern_offset_hours(utc_dt: datetime) -> int:
    """Return -4 (EDT) or -5 (EST) based on Canadian Eastern DST rules."""
    from datetime import timedelta as td

    def nth_sunday(year: int, month: int, n: int) -> datetime:
        first = datetime(year, month, 1)
        days_to_sunday = (6 - first.weekday()) % 7
        return first + td(days=days_to_sunday + 7 * (n - 1))

    y = utc_dt.year
    from datetime import timezone
    utc = timezone.utc
    dst_start = nth_sunday(y, 3,  2).replace(hour=7,  tzinfo=utc)
    dst_end   = nth_sunday(y, 11, 1).replace(hour=6,  tzinfo=utc)
    return -4 if dst_start <= utc_dt < dst_end else -5


def _montreal_now() -> datetime:
    try:
        from zoneinfo import ZoneInfo
        return datetime.now(ZoneInfo("America/Montreal"))
    except Exception:
        pass
    try:
        import pytz
        return datetime.now(pytz.timezone("America/Montreal"))
    except Exception:
        pass
    from datetime import timezone, timedelta
    utc_now = datetime.now(timezone.utc)
    offset  = _eastern_offset_hours(utc_now)
    return utc_now.astimezone(timezone(timedelta(hours=offset)))


def get_today() -> str:
    return SCHEDULE[_montreal_now().weekday()]


def get_today_date() -> str:
    return _montreal_now().strftime("%Y-%m-%d")


def get_week_schedule() -> Dict[str, str]:
    days = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]
    return {days[i]: SCHEDULE[i] for i in range(7)}


# ---------------------------------------------------------------------------
# Weight suggestions
# ---------------------------------------------------------------------------

def get_suggested_weights_for_today(weights: dict) -> List[dict]:
    today_session = get_today()
    program = load_program()
    if today_session not in program:
        return []

    exercises = get_strength_exercises(program[today_session])
    result: List[dict] = []
    for exercise in exercises:
        data       = weights.get(exercise, {})
        current    = data.get("current_weight", data.get("weight", 0.0))
        last_reps  = data.get("last_reps", "")
        input_type = data.get("input_type", "total")

        # Use last logged RPE from history for autoregulation
        last_history = data.get("history", [])
        last_rpe: float | None = None
        if last_history and isinstance(last_history[0], dict):
            rpe_val = last_history[0].get("rpe")
            if rpe_val is not None:
                try:
                    last_rpe = float(rpe_val)
                except (TypeError, ValueError):
                    pass

        suggested, _ = suggest_next_weight(exercise, current, last_reps, last_rpe)
        if input_type == "barbell":
            side    = (suggested - 45) / 2 if suggested >= 45 else 0
            display = f"{side:.1f} par cote (total {suggested:.1f} lbs)"
        elif input_type == "dumbbell":
            display = f"{suggested/2:.1f} par haltere"
        else:
            display = f"{suggested:.1f} lbs total"
        result.append({"exercise": exercise, "display": display})
    return result
