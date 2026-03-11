

from __future__ import annotations
from db import get_json, set_json
from datetime import datetime
from typing import Dict, List
from progression import should_increase, next_weight

DEFAULT_PROGRAM = {
    "Upper A": {
        "Bench Press": "4x5-7",
        "Barbell Row": "4x6-8",
        "Incline DB Press": "3x8-10",
        "Lat Pulldown": "3x8-10",
        "Overhead Press": "3x6-8"
    },
    "Upper B": {
        "Incline DB Press": "4x8-10",
        "T-Bar Row": "4x8-10",
        "DB Bench Press": "3x10-12",
        "Seated Row": "3x10-12",
        "Lateral Raises": "4x12-15",
        "Triceps Extension": "3x10-12",
        "Hammer Curl": "3x10-12",
        "Face Pull": "3x15"
    },
    "Lower": {
        "Back Squat": "4x5-7",
        "Leg Press": "3x10-12",
        "Leg Curl": "3x10-12",
        "Romanian Deadlift": "3x8-10",
        "Calf Raise": "3x12-15",
        "Abs": "3x12-15"
    }
}

SCHEDULE = {
    0: "Upper A",
    1: "HIIT 1",
    2: "Upper B",
    3: "HIIT 2",
    4: "Lower",
    5: "Yoga",
    6: "Recovery",
}


def load_program() -> dict:
    return get_json("program", {})

def save_program(program: dict):
    set_json("program", program)


def get_today() -> str:
    from datetime import timezone, timedelta
    EST = timezone(timedelta(hours=-5))
    return SCHEDULE[datetime.now(EST).weekday()]


def get_week_schedule() -> Dict[str, str]:
    days = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]
    return {days[i]: SCHEDULE[i] for i in range(7)}


# ── schedule_v2 / program_v2 (modular block model) ───────────

DEFAULT_SCHEDULE_V2: Dict[str, str] = {str(k): v for k, v in SCHEDULE.items()}


def load_schedule() -> Dict[str, str]:
    """Load the editable weekly schedule (day index str → session template name)."""
    return get_json("schedule_v2", DEFAULT_SCHEDULE_V2)


def save_schedule(schedule: Dict[str, str]):
    set_json("schedule_v2", schedule)


def _bootstrap_program_v2() -> dict:
    """
    Build an initial program_v2 from the existing program + known special sessions.
    Each old strength template becomes a session with one strength block.
    HIIT 1/2 become sessions with one hiit block.
    Yoga/Recovery become sessions with no blocks (rest markers).
    """
    from block_session import make_strength_block, make_hiit_block
    old_program = load_program()
    p2: dict = {}

    for name, exercises in old_program.items():
        p2[name] = {"blocks": [make_strength_block(exercises)]}

    for hiit_name, rounds, sprint, rest, speed in [
        ("HIIT 1", 8, 30, 90, "12-14 km/h"),
        ("HIIT 2", 8, 30, 90, "12-14 km/h"),
    ]:
        if hiit_name not in p2:
            p2[hiit_name] = {"blocks": [make_hiit_block(rounds, sprint, rest, speed)]}

    for rest_name in ["Yoga", "Recovery"]:
        if rest_name not in p2:
            p2[rest_name] = {"blocks": []}

    return p2


def load_program_v2() -> dict:
    """Load modular session templates. Bootstraps from old program on first use."""
    stored = get_json("program_v2", None)
    if stored is None:
        return _bootstrap_program_v2()
    return stored


def save_program_v2(program: dict):
    set_json("program_v2", program)


def get_today_v2() -> str:
    """Return the session template name assigned to today (uses schedule_v2)."""
    from datetime import timezone, timedelta
    EST = timezone(timedelta(hours=-5))
    weekday = datetime.now(EST).weekday()
    schedule = load_schedule()
    return schedule.get(str(weekday), SCHEDULE.get(weekday, "Recovery"))


def get_today_blocks() -> List[dict]:
    """Return the list of blocks for today's session template."""
    today_name = get_today_v2()
    program = load_program_v2()
    template = program.get(today_name, {})
    return template.get("blocks", [])


def get_week_schedule_v2() -> Dict[str, dict]:
    """
    Returns dict: day_label → {name, blocks, block_types}
    """
    days = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]
    schedule = load_schedule()
    program  = load_program_v2()
    result: Dict[str, dict] = {}
    for i, label in enumerate(days):
        name = schedule.get(str(i), "Recovery")
        template = program.get(name, {})
        blocks = template.get("blocks", [])
        block_types = [b.get("type", "") for b in blocks]
        result[label] = {"name": name, "blocks": blocks, "block_types": block_types}
    return result


def get_suggested_weights_for_today(weights: dict) -> List[dict]:
    today_session = get_today()
    program = load_program()
    if today_session not in program:
        return []
    result: List[dict] = []
    for exercise in program[today_session]:
        data = weights.get(exercise, {})
        current = data.get("current_weight", data.get("weight", 0.0))
        last_reps = data.get("last_reps", "")
        input_type = data.get("input_type", "total")
        suggested = next_weight(exercise, current) if should_increase(last_reps, exercise) else current
        if input_type == "barbell":
            side = (suggested - 45) / 2 if suggested >= 45 else 0
            display = f"{side:.1f} par cote (total {suggested:.1f} lbs)"
        elif input_type == "dumbbell":
            display = f"{suggested/2:.1f} par haltere"
        else:
            display = f"{suggested:.1f} lbs total"
        result.append({"exercise": exercise, "display": display})
    return result


