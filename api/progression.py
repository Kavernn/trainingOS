# progression.py
"""
Progression logic with RPE-based autoregulation.

RPE rules (per-exercise, last logged RPE):
  ≤ 6.0  → increase  (trop facile)
  6.1–8.4 → maintain  (zone cible)
  ≥ 8.5  → decrease  (trop difficile)

Falls back to reps-based for exercises with no RPE history.
For reps-based, works for ALL exercises using DEFAULT_REP_RANGE when
the exercise isn't in REPS_RULES.
"""
from __future__ import annotations

# Target rep ranges — used for reps-based fallback only
REPS_RULES: dict[str, dict] = {
    "Bench Press":       {"min": 5,  "max": 7},
    "Back Squat":        {"min": 5,  "max": 7},
    "Barbell Row":       {"min": 6,  "max": 8},
    "Overhead Press":    {"min": 6,  "max": 8},
    "Incline DB Press":  {"min": 8,  "max": 10},
    "Romanian Deadlift": {"min": 8,  "max": 10},
    "Leg Press":         {"min": 10, "max": 12},
}

DEFAULT_REP_RANGE: dict = {"min": 8, "max": 12}

INCREMENT_RULES: dict[str, float] = {
    "Incline DB Press":     5.0,
    "Dumbbell Bench Press": 5.0,
    "Lateral Raises":       2.5,
    "Face Pull":            2.5,
    "Hammer Curl":          5.0,
    "type:barbell":         5.0,
    "type:dumbbell":        5.0,
    "type:machine":         10.0,
    "type:default":         2.5,
}

# RPE thresholds
_RPE_INCREASE  = 6.0
_RPE_DECREASE  = 8.5


def _get_increment(exercise: str, inventory: dict | None = None) -> float:
    # 1. Inventory (source of truth) — uses exercises.increment from Supabase
    if inventory:
        entry = inventory.get(exercise, {})
        inc = entry.get("increment")
        if inc is not None:
            return float(inc)
    # 2. Hardcoded fallback by name
    if exercise in INCREMENT_RULES:
        return INCREMENT_RULES[exercise]
    return INCREMENT_RULES["type:default"]


def parse_reps(reps_str: str) -> list[int]:
    if not reps_str or reps_str.isspace():
        raise ValueError("Champ reps vide")
    cleaned = "".join(reps_str.split())
    for sep in [",", ";"]:
        if sep in cleaned:
            parts = cleaned.split(sep)
            break
    else:
        parts = [cleaned]
    try:
        return [int(p) for p in parts if p.strip()]
    except ValueError:
        raise ValueError(f"Format invalide '{reps_str}' → ex: 7,6,5,5")


def suggest_next_weight(
    exercise: str,
    current_weight: float,
    last_reps: str,
    rpe: float | None = None,
    inventory: dict | None = None,
) -> tuple[float, str]:
    """
    Returns (suggested_weight, action) where action ∈ {increase, maintain, decrease}.

    RPE-based (preferred):
      rpe ≤ 6.0  → increase
      rpe 6.1–8.4 → maintain
      rpe ≥ 8.5  → decrease

    Reps-based fallback (when rpe is None):
      all reps ≥ min target → increase
      otherwise              → maintain
    """
    inc = _get_increment(exercise, inventory)

    if rpe is not None:
        if rpe <= _RPE_INCREASE:
            return (round(current_weight + inc, 1), "increase")
        elif rpe >= _RPE_DECREASE:
            return (round(max(0.0, current_weight - inc), 1), "decrease")
        else:
            return (current_weight, "maintain")

    # Reps-based fallback — works for ALL exercises
    rule = REPS_RULES.get(exercise, DEFAULT_REP_RANGE)
    try:
        reps = parse_reps(last_reps)
        if reps and all(r >= rule["min"] for r in reps):
            return (round(current_weight + inc, 1), "increase")
    except Exception:
        pass
    return (current_weight, "maintain")


# ── Legacy helpers (kept for backward-compat) ─────────────────────────────

def should_increase(reps_str: str, exercise: str) -> bool:
    """Legacy: reps-based only. Prefer suggest_next_weight()."""
    rule = REPS_RULES.get(exercise, DEFAULT_REP_RANGE)
    try:
        reps = parse_reps(reps_str)
        return bool(reps) and all(r >= rule["min"] for r in reps)
    except Exception:
        return False


def next_weight(exercise: str, current_weight: float) -> float:
    """Legacy linear increment. Prefer suggest_next_weight()."""
    return round(current_weight + _get_increment(exercise), 1)


def estimate_1rm(weight: float, reps_str: str) -> float:
    """Formule Epley."""
    try:
        reps = parse_reps(reps_str)
        if not reps:
            return 0.0
        avg_reps = sum(reps) / len(reps)
        return round(weight * (1 + avg_reps / 30), 1)
    except Exception:
        return 0.0


def progression_status(reps_str: str, exercise: str) -> str:
    rule = REPS_RULES.get(exercise, DEFAULT_REP_RANGE)
    try:
        reps = parse_reps(reps_str)
        hit = sum(1 for r in reps if r >= rule["min"])
        return f"{hit}/{len(reps)} séries au target ({rule['min']}-{rule['max']} reps)"
    except Exception:
        return "Erreur format reps"
