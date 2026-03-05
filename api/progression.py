# progression.py

REPS_RULES = {
    "Bench Press":      {"min": 5, "max": 7},
    "Back Squat":       {"min": 5, "max": 7},
    "Barbell Row":      {"min": 6, "max": 8},
    "Overhead Press":   {"min": 6, "max": 8},
    "Incline DB Press": {"min": 8, "max": 10},
    "Romanian Deadlift":{"min": 8, "max": 10},
    "Leg Press":        {"min": 10,"max": 12},
}

INCREMENT_RULES = {
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


def parse_reps(reps_str: str) -> list[int]:
    if not reps_str or reps_str.isspace():
        raise ValueError("Champ reps vide")
    cleaned = ''.join(reps_str.split())
    for sep in [',', ';']:
        if sep in cleaned:
            parts = cleaned.split(sep)
            break
    else:
        parts = [cleaned]
    try:
        return [int(p) for p in parts if p.strip()]
    except ValueError as e:
        raise ValueError(f"Format invalide '{reps_str}' → ex: 7,6,5,5")


def should_increase(reps_str: str, exercise: str) -> bool:
    if exercise not in REPS_RULES:
        return False
    try:
        reps = parse_reps(reps_str)
        min_rep = REPS_RULES[exercise]["min"]
        return all(r >= min_rep for r in reps)
    except:
        return False


def next_weight(exercise: str, current_weight: float) -> float:
    if exercise in INCREMENT_RULES:
        inc = INCREMENT_RULES[exercise]
    else:
        inc = INCREMENT_RULES.get("type:default", 2.5)
    return round(current_weight + inc, 1)


def estimate_1rm(weight: float, reps_str: str) -> float:
    """Formule Epley – très utilisée et fiable"""
    try:
        reps = parse_reps(reps_str)
        if not reps:
            return 0.0
        avg_reps = sum(reps) / len(reps)
        return round(weight * (1 + avg_reps / 30), 1)
    except:
        return 0.0


def progression_status(reps_str: str, exercise: str) -> str:
    if exercise not in REPS_RULES:
        return "Pas de règle définie."
    try:
        reps = parse_reps(reps_str)
        rule = REPS_RULES[exercise]
        hit = sum(1 for r in reps if r >= rule["min"])
        return f"{hit}/{len(reps)} séries au target ({rule['min']}-{rule['max']} reps)"
    except:
        return "Erreur format reps"