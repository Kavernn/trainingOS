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
import logging
from datetime import datetime

logger = logging.getLogger("trainingos.progression")

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

# Rep ranges par load_profile — utilisées en fallback dans get_rep_range()
_REP_RANGE_BY_PROFILE: dict[str, dict] = {
    "compound_heavy":       {"min": 5,  "max": 7},
    "compound_hypertrophy": {"min": 8,  "max": 12},
    "isolation":            {"min": 12, "max": 15},
    "endurance_strength":   {"min": 15, "max": 20},
}


def get_rep_range(exercise: str, load_profile: str | None = None) -> dict:
    """Source unique pour les plages de reps.

    Priorité :
      1. Override par exercice dans REPS_RULES
      2. Fallback par load_profile (_REP_RANGE_BY_PROFILE)
      3. DEFAULT_REP_RANGE (8-12)
    """
    if exercise in REPS_RULES:
        return REPS_RULES[exercise]
    if load_profile:
        return _REP_RANGE_BY_PROFILE.get(load_profile.lower(), DEFAULT_REP_RANGE)
    return DEFAULT_REP_RANGE


# Unified increment matrix: (load_profile, equipment_type) → lbs
# Source unique de vérité — utilisée par get_increment() ci-dessous.
# Remplace l'ancienne INCREMENT_RULES et _increment_for_profile dans smart_progression.
_INCREMENT_MATRIX: dict[tuple[str, str], float] = {
    ("compound_heavy",       "barbell"):  5.0,
    ("compound_heavy",       "dumbbell"): 5.0,
    ("compound_heavy",       "machine"):  5.0,
    ("compound_heavy",       "cable"):         5.0,
    ("compound_heavy",       "cable_double"):  5.0,
    ("compound_hypertrophy", "barbell"):  5.0,
    ("compound_hypertrophy", "dumbbell"): 5.0,
    ("compound_hypertrophy", "machine"):  5.0,
    ("compound_hypertrophy", "cable"):    2.5,
    ("compound_hypertrophy", "cable_double"): 2.5,
    ("isolation",            "barbell"):  2.5,
    ("isolation",            "dumbbell"): 2.5,
    ("isolation",            "machine"):  2.5,
    ("isolation",            "cable"):    2.5,
    ("isolation",            "cable_double"):  2.5,
    ("endurance_strength",   "barbell"):  2.5,
    ("endurance_strength",   "dumbbell"): 2.5,
    ("endurance_strength",   "machine"):  2.5,
    ("endurance_strength",   "cable"):    2.5,
    ("endurance_strength",   "cable_double"):  2.5,
}
_DEFAULT_INCREMENT = 2.5


def get_increment(
    exercise: str,
    load_profile: str | None = None,
    equipment_type: str | None = None,
    inventory: dict | None = None,
) -> float:
    """Source unique de vérité pour les incréments de poids.

    Priorité :
      1. Override per-exercice dans inventory (champ 'increment')
      2. Matrice (load_profile × equipment_type)
      3. load_profile seul (equipment inconnu) → compound: 5 lbs, reste: 2.5 lbs
      4. Default conservateur : 2.5 lbs
    """
    if inventory:
        inc = (inventory.get(exercise) or {}).get("increment")
        if inc is not None:
            return float(inc)

    if load_profile and equipment_type:
        key = (load_profile.lower(), equipment_type.lower())
        if key in _INCREMENT_MATRIX:
            return _INCREMENT_MATRIX[key]

    if load_profile:
        lp = load_profile.lower()
        if lp in ("compound_heavy", "compound_hypertrophy"):
            return 5.0
        return _DEFAULT_INCREMENT

    return _DEFAULT_INCREMENT


def _get_increment(exercise: str, inventory: dict | None = None) -> float:
    """Shim interne — appelle get_increment avec les métadonnées de l'inventaire si disponibles."""
    if inventory:
        entry = inventory.get(exercise) or {}
        inc = entry.get("increment")
        if inc is not None:
            return float(inc)
        lp = entry.get("load_profile")
        eq = entry.get("type")
        if lp or eq:
            return get_increment(exercise, load_profile=lp, equipment_type=eq)
    return _DEFAULT_INCREMENT


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
        except Exception as e:
            logger.exception("compute_progression_rate entry failed: %s", e)
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
    except Exception as e:
        logger.exception("_suggest_uncapped reps parse failed: %s", e)
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
    hrv_zone: str | None = None,
) -> tuple[float, str]:
    """
    Returns (suggested_weight, action) where action ∈ {increase, maintain, decrease}.

    Priority order for caps (highest wins) :
      1. hrv_zone == 'red'   → block any increase (HRV override)
      2. fatigue_score >= 70 → block any increase
      3. fatigue_score >= 50 → cap to half increment
    """
    inc = _get_increment(exercise, inventory)
    new_w, action = _suggest_uncapped(exercise, current_weight, last_reps, rpe, inc, history, avg_rir)

    # HRV red zone — block weight increase regardless of RPE
    if hrv_zone == "red" and action == "increase":
        return (current_weight, "maintain")

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
    hrv_zone: str | None = None,
) -> dict:
    """
    Prescribe sets × rep range for next session, adjusting for fatigue, HRV, and trend.

    Returns {sets, rep_min, rep_max, note}.
    base_sets comes from the programme scheme (e.g. "3x8-10" → 3).

    HRV override (applied before fatigue cap) :
      hrv_zone == 'red' → -1 set (≈ 20% volume reduction), message contextuel
    """
    MAX_SETS = 4
    sets  = min(base_sets, MAX_SETS)
    notes: list[str] = []

    # HRV red zone — volume réduit ~20% (1 set)
    if hrv_zone == "red":
        sets = max(2, sets - 1)
        notes.append("HRV rouge → volume -20%")

    # Fatigue adjustment: reduce volume when fatigued
    if fatigue_score is not None:
        if fatigue_score >= 70:
            sets = max(2, sets - 2)
            notes.append(f"fatigue élevée → {sets} sets")
        elif fatigue_score >= 50:
            sets = max(2, sets - 1)
            notes.append(f"fatigue modérée → {sets} sets")

    # Trend: ride a wave of positive progression → add a set (max 4)
    # Skip if HRV is red — ne pas augmenter le volume en récupération compromise
    rate = compute_progression_rate(history) if history else None
    if rate is not None and rate >= 1.0 and hrv_zone != "red":
        if fatigue_score is None or fatigue_score < 50:
            sets = min(MAX_SETS, sets + 1)
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
    except Exception as e:
        logger.exception("should_increase failed: %s", e)
        return False


def next_weight(exercise: str, current_weight: float) -> float:
    return round(current_weight + _get_increment(exercise), 1)


def estimate_1rm(weight: float, reps_str: str) -> float | None:
    """Estime le 1RM avec sélection de formule selon le range de reps.

    ≤10 reps → Epley  (weight × (1 + reps/30))       — précis dans ce range
    >10 reps → Brzycki (weight × (36 / (37 - reps)))  — conservateur, sous-estime
                                                          plutôt que surestime (plus sûr)
    >20 reps → None   — trop imprécis pour programmer des charges; ne pas afficher

    Référence : Epley (1985), Brzycki (1993).
    """
    try:
        reps = parse_reps(reps_str)
        if not reps:
            return 0.0
        avg_reps = sum(reps) / len(reps)
        if avg_reps > 15:
            return None
        if avg_reps > 10:
            return round(weight * (36 / (37 - avg_reps)), 1)
        return round(weight * (1 + avg_reps / 30), 1)
    except Exception as e:
        logger.exception("estimate_1rm failed: %s", e)
        return 0.0


def estimate_1rm_confidence(avg_reps: float) -> str:
    """Niveau de confiance de l'estimation 1RM.

    "high"   : ≤10 reps  — Epley précis, utiliser pour programmer les charges
    "medium" : 11-15 reps — Brzycki, afficher avec avertissement
    "low"    : >15 reps  — ne pas utiliser pour programmer les charges
    """
    if avg_reps <= 10:
        return "high"
    if avg_reps <= 15:
        return "medium"
    return "low"


def progression_status(reps_str: str, exercise: str) -> str:
    rule = REPS_RULES.get(exercise, DEFAULT_REP_RANGE)
    try:
        reps = parse_reps(reps_str)
        hit = sum(1 for r in reps if r >= rule["min"])
        return f"{hit}/{len(reps)} séries au target ({rule['min']}-{rule['max']} reps)"
    except Exception:
        return "Erreur format reps"
