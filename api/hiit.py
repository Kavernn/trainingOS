from __future__ import annotations
import db


def load_hiit_log() -> list:
    result = db.get_hiit_logs()
    return result if isinstance(result, list) else []


# Phases HIIT (conservées)
HIIT_PHASES = [
    {"weeks": (1, 3),  "sprint": 30, "rest": 90, "rounds": 8,  "speed": "12-14 km/h"},
    {"weeks": (4, 6),  "sprint": 40, "rest": 80, "rounds": 9,  "speed": "13-15 km/h"},
    {"weeks": (7, 99), "sprint": 45, "rest": 75, "rounds": 10, "speed": "14-16 km/h"},
]


def get_hiit(week: int) -> dict:
    for phase in HIIT_PHASES:
        if phase["weeks"][0] <= week <= phase["weeks"][1]:
            return phase
    return HIIT_PHASES[-1]


def get_hiit_str(week: int) -> str:
    p = get_hiit(week)
    return f"{p['sprint']}s sprint / {p['rest']}s rest ×{p['rounds']} ({p['speed']})"
