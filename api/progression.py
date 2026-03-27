# progression.py
"""
Progression logic with RPE-based autoregulation.

Graduated RPE scale:
  ≤ 5.5   → increase full increment
  5.6–6.5 → increase half increment
  6.6–7.9 → maintain (nudge based on 4-week trend magnitude)
  8.0–8.9 → decrease half increment
  ≥ 9.0   → decrease full increment

Trend-modulated maintain zone:
  rate <  0.0 lbs/week → regressing  → full increment nudge
  rate <  0.5 lbs/week → stalling    → half increment nudge
  rate >= 0.5 lbs/week → progressing → no nudge

Fatigue cap (post-processing):
  score >= 70 → block any increase (return maintain)
  score >= 50 → cap increase to half increment

RIR fallback: avg_rir provided → rpe_approx = 10 − avg_rir.
"""
from __future__ import annotations
from datetime import datetime

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
_RPE_INCREASE_FULL = 5.5
_RPE_INCREASE_HALF = 6.5
_RPE_DECREASE_HALF = 8.0
_RPE_DECREASE_FULL = 9.0

# Trend thresholds (lbs/week of 1RM gain)
_RATE_STALL     = 0.5   # below this = stalling
_RATE_REGRESS   = 0.0   # below this = regressing

# Legacy aliases
_RPE_INCREASE = _RPE_INCREASE_FULL
_RPE_DECREASE = _RPE_DECREASE_FULL


def _get_increment(exercise: str, inventory: dict | None = None) -> float:
    if inventory:
        entry = inventory.get(exercise, {})
        inc = entry.get("increment")
        if inc is not None:
            return float(inc)
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
    Weekly e1RM gain rate (lbs/week) via linear regression on last 28 days.
    Positive = gaining, negative = regressing. None if < 2 data points.
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
    x_vals = [e[0] for e in entries]
    y_vals = [e[1] for e in entries]
    x_mean = sum(x_vals) / n
    y_mean = sum(y_vals) / n
    num  = sum((x - x_mean) * (y - y_mean) for x, y in zip(x_vals, y_vals))
    den  = sum((x - x_mean) ** 2 for x in x_vals)
    if den == 0:
        return None
    return round(-num / den * 7, 2)   # positive = gaining lbs/week


def _suggest_uncapped(
    exercise: str,
    current_weight: float,
    last_reps: str,
    rpe: float | None,
    inc: float,
    history: list[dict] | None,
    avg_rir: float | None,
) -> tuple[float, str]:
    """Core suggestion logic — no fatigue cap applied here."""
    # RIR → approximate RPE fallback
    if rpe is None and avg_rir is not None:
        rpe = round(10.0 - avg_rir, 1)

    if rpe is not None:
        if rpe <= _RPE_INCREASE_FULL:
            return (round(current_weight + inc, 1), "increase")

        elif rpe <= _RPE_INCREASE_HALF:
            return (round(current_weight + inc * 0.5, 1), "increase")

        elif rpe < _RPE_DECREASE_HALF:
            # Maintain zone — use 4-week trend magnitude
            rate = compute_progression_rate(history) if history else None
            if rate is not None:
                if rate < _RATE_REGRESS:
                    # Regressing → full increment nudge
                    return (round(current_weight + inc, 1), "increase")
                elif rate < _RATE_STALL:
                    # Stalling → half increment nudge
                    return (round(current_weight + inc * 0.5, 1), "increase")
            return (current_weight, "maintain")

        elif rpe < _RPE_DECREASE_FULL:
            return (round(max(0.0, current_weight - inc * 0.5), 1), "decrease")

        else:
            return (round(max(0.0, current_weight - inc), 1), "decrease")

    # Reps-based fallback
    rule = REPS_RULES.get(exercise, DEFAULT_REP_RANGE)
    try:
        reps = parse_reps(last_reps)
        if reps and all(r >= rule["min"] for r in reps):
            return (round(current_weight + inc, 1), "increase")
    except Exception:
        pass
    return (current_weight, "maintain")


def suggest_next_weight(
    exercise: str,
    current_weight: float,
    last_reps: str,
    rpe: float | None = None,
    inventory: dict | None = None,
    history: list[dict] | None = None,
    avg_rir: float | None = None,
    fatigue_score: int | None = None,
) -> tuple[float, str]:
    """
    Returns (suggested_weight, action) where action ∈ {increase, maintain, decrease}.

    Applies fatigue cap after computing the base suggestion:
      fatigue_score >= 70 → block any increase
      fatigue_score >= 50 → cap increase to half increment
    """
    inc = _get_increment(exercise, inventory)
    new_w, action = _suggest_uncapped(exercise, current_weight, last_reps, rpe, inc, history, avg_rir)

    # Fatigue cap
    if fatigue_score is not None and action == "increase":
        if fatigue_score >= 70:
            return (current_weight, "maintain")
        if fatigue_score >= 50:
            max_w = round(current_weight + inc * 0.5, 1)
            return (min(new_w, max_w), action)

    return new_w, action


def prescribe_volume(
    exercise: str,
    base_sets: int = 3,
    rep_min: int = 8,
    rep_max: int = 12,
    fatigue_score: int | None = None,
    history: list[dict] | None = None,
) -> dict:
    """
    Prescribe sets × rep range for next session, adjusting for fatigue and trend.

    Returns {sets, rep_min, rep_max, note}.
    base_sets comes from the programme scheme (e.g. "3x8-10" → 3).
    """
    sets  = base_sets
    notes: list[str] = []

    # Fatigue adjustment: reduce volume when fatigued
    if fatigue_score is not None:
        if fatigue_score >= 70:
            sets = max(2, base_sets - 2)
            notes.append(f"fatigue élevée → {sets} sets")
        elif fatigue_score >= 50:
            sets = max(2, base_sets - 1)
            notes.append(f"fatigue modérée → {sets} sets")

    # Trend: ride a wave of positive progression → add a set
    rate = compute_progression_rate(history) if history else None
    if rate is not None and rate >= 1.0:
        if fatigue_score is None or fatigue_score < 50:
            sets = min(6, sets + 1)
            notes.append("progression ↑ +1 set")

    return {
        "sets":    sets,
        "rep_min": rep_min,
        "rep_max": rep_max,
        "note":    " · ".join(notes) if notes else None,
    }


# ── Legacy helpers ─────────────────────────────────────────────────────────

def should_increase(reps_str: str, exercise: str) -> bool:
    rule = REPS_RULES.get(exercise, DEFAULT_REP_RANGE)
    try:
        reps = parse_reps(reps_str)
        return bool(reps) and all(r >= rule["min"] for r in reps)
    except Exception:
        return False


def next_weight(exercise: str, current_weight: float) -> float:
    return round(current_weight + _get_increment(exercise), 1)


def estimate_1rm(weight: float, reps_str: str) -> float:
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
