"""
block_session.py — Modular session data model (sessions_v2).

A Session is a container of workout blocks.
Each block represents one training modality: strength, hiit, or cardio.
Blocks are independent and reorderable.
"""
from __future__ import annotations
from datetime import datetime
from db import get_json, set_json

# ── Block type constants ─────────────────────────────────────
STRENGTH = "strength"
HIIT     = "hiit"
CARDIO   = "cardio"

BLOCK_TYPES = [STRENGTH, HIIT, CARDIO]


# ── Block factories ──────────────────────────────────────────

def make_strength_block(exercises: dict) -> dict:
    """
    exercises: {exercise_name: scheme_str}  e.g. {"Bench Press": "4x5-7"}
    """
    return {"type": STRENGTH, "exercises": exercises}


def make_hiit_block(rounds: int = 8, sprint: int = 30, rest: int = 90,
                    speed_target: str = "12-14 km/h") -> dict:
    return {
        "type":         HIIT,
        "rounds":       rounds,
        "sprint":       sprint,
        "rest":         rest,
        "speed_target": speed_target,
    }


def make_cardio_block(duration_min: int = 30, distance_km: float = 0.0,
                      cardio_type: str = "steady-state") -> dict:
    return {
        "type":         CARDIO,
        "duration_min": duration_min,
        "distance_km":  distance_km,
        "cardio_type":  cardio_type,
    }


# ── sessions_v2 CRUD ─────────────────────────────────────────

def load_sessions_v2() -> dict:
    return get_json("sessions_v2", {})


def save_sessions_v2(data: dict):
    set_json("sessions_v2", data)


def log_session_v2(date: str, template: str, blocks_data: list) -> dict:
    """
    Upsert a multi-block session for the given date.
    blocks_data: list of logged block payloads (type + modality-specific fields).
    Returns the stored entry.
    """
    sessions = load_sessions_v2()
    entry = {
        "template":  template,
        "logged_at": datetime.now().strftime("%Y-%m-%d %H:%M"),
        "blocks":    blocks_data,
    }
    sessions[date] = entry
    save_sessions_v2(sessions)
    return entry


def session_v2_exists(date: str) -> bool:
    return date in load_sessions_v2()


def get_session_v2(date: str) -> dict | None:
    return load_sessions_v2().get(date)


def delete_session_v2(date: str) -> bool:
    sessions = load_sessions_v2()
    if date not in sessions:
        return False
    del sessions[date]
    save_sessions_v2(sessions)
    return True


def edit_session_v2(date: str, block_index: int | None, changes: dict) -> bool:
    """
    Update a specific block (by index) or the top-level entry fields.
    changes: dict of fields to update.
    """
    sessions = load_sessions_v2()
    if date not in sessions:
        return False
    entry = sessions[date]
    if block_index is None:
        # Update top-level fields (template, etc.)
        for k, v in changes.items():
            if k != "blocks":
                entry[k] = v
    else:
        blocks = entry.get("blocks", [])
        if block_index < 0 or block_index >= len(blocks):
            return False
        blocks[block_index].update(changes)
        entry["blocks"] = blocks
    save_sessions_v2(sessions)
    return True


def get_last_sessions_v2(n: int = 10) -> list:
    sessions = load_sessions_v2()
    result = []
    for date in sorted(sessions.keys(), reverse=True)[:n]:
        entry = sessions[date].copy()
        entry["date"] = date
        result.append(entry)
    return result


def get_block_type_icon(block_type: str) -> str:
    return {STRENGTH: "🏋️", HIIT: "⚡", CARDIO: "🏃"}.get(block_type, "•")
