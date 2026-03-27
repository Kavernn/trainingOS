# progression.py
"""
Progression logic with RPE-based autoregulation.

RPE rules (graduated scale):
  ≤ 5.5   → increase full increment
  5.6–6.5 → increase half increment
  6.6–7.9 → maintain (or +half if 4-week trend stalled)
  8.0–8.9 → decrease half increment
  ≥ 9.0   → decrease full increment

RIR fallback (when RPE absent): RIR → RPE ≈ 10 − RIR
Falls back to reps-based for exercises with no RPE/RIR history.
"""
from __future__ import annotations
from datetime import datetime

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

# Graduated RPE thresholds
_RPE_INCREASE_FULL = 5.5   # ≤ 5.5  → increase full increment
_RPE_INCREASE_HALF = 6.5   # 5.6–6.5 → increase half increment
_RPE_DECREASE_HALF = 8.0   # 8.0–8.9 → decrease half increment
_RPE_DECREASE_FULL = 9.0   # ≥ 9.0  → decrease full increment

# Legacy aliases kept for backward-compat
_RPE_INCREASE = _RPE_INCREASE_FULL
_RPE_DECREASE = _RPE_DECREASE_FULL


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


def compute_progression_rate(history: list[dict]) -> float | None:
    """
    Compute weekly e1RM gain rate over last 4 weeks.

    Returns lbs/week (positive = gaining, negative = regressing).
    Returns None if < 2 data points in the 28-day window.
    """
    if not history or len(history) < 2:
        return None
    now = datetime.now()
    entries: list[tuple[float, float]] = []
    for e in history:
        try:
            d = datetime.fromisoformat(e.get("date", ""))
            age_days = (now - d).days
            if age_days <= 28 and e.get("1rm"):
                entries.append((age_days, float(e["1rm"])))
        except Exception:
            pass
    if len(entries) < 2:
        return None
    n = len(entries)
    x_vals = [e[0] for e in entries]   # days_ago (0 = today)
    y_vals = [e[1] for e in entries]   # 1RM in lbs
    x_mean = sum(x_vals) / n
    y_mean = sum(y_vals) / n
    numerator   = sum((x - x_mean) * (y - y_mean) for x, y in zip(x_vals, y_vals))
    denominator = sum((x - x_mean) ** 2 for x in x_vals)
    if denominator == 0:
        return None
    # slope: Δ1RM per day, negative when days_ago↑ and 1RM↑ (improving over time)
    slope = numerator / denominator
    return round(-slope * 7, 2)   # positive = gaining lbs/week


def suggest_next_weight(
    exercise: str,
    current_weight: float,
    last_reps: str,
    rpe: float | None = None,
    inventory: dict | None = None,
    history: list[dict] | None = None,
    avg_rir: float | None = None,
) -> tuple[float, str]:
    """
    Returns (suggested_weight, action) where action ∈ {increase, maintain, decrease}.

    Priority: RPE → RIR (converted to approximate RPE) → reps-based fallback.

    Graduated scale:
      ≤ 5.5  → +full increment
      5.6–6.5 → +half increment
      6.6–7.9 → maintain (or +half if 4-week trend is stalled/regressing)
      8.0–8.9 → -half increment
      ≥ 9.0  → -full increment
    """
    inc = _get_increment(exercise, inventory)

    # RIR → approximate RPE fallback: RIR 0 ≈ RPE 10, RIR 4 ≈ RPE 6
    if rpe is None and avg_rir is not None:
        rpe = round(10.0 - avg_rir, 1)

    if rpe is not None:
        if rpe <= _RPE_INCREASE_FULL:
            return (round(current_weight + inc, 1), "increase")
        elif rpe <= _RPE_INCREASE_HALF:
            return (round(current_weight + inc * 0.5, 1), "increase")
        elif rpe < _RPE_DECREASE_HALF:
            # Maintain zone — nudge up with half increment if stalled ≥ 4 weeks
            rate = compute_progression_rate(history) if history else None
            if rate is not None and rate <= 0.0:
                return (round(current_weight + inc * 0.5, 1), "increase")
            return (current_weight, "maintain")
        elif rpe < _RPE_DECREASE_FULL:
            return (round(max(0.0, current_weight - inc * 0.5), 1), "decrease")
        else:
            return (round(max(0.0, current_weight - inc), 1), "decrease")

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
