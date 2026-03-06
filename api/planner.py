

from __future__ import annotations
from db import get_json, set_json
from datetime import datetime
from typing import Dict, List
from db import get_json, set_json
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
    return SCHEDULE[datetime.today().weekday()]


def get_week_schedule() -> Dict[str, str]:
    days = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]
    return {days[i]: SCHEDULE[i] for i in range(7)}


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


