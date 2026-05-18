"""muscle_volume.py — Hard sets par groupe musculaire par semaine.

Gold standard hypertrophie : Schoenfeld & Krieger 2017.
Ranges recommandés : 10-20 sets/muscle/semaine.

Un "hard set" = tout set exécuté à RPE ≥ 7, ou RPE absent (conservateur).
"""
from __future__ import annotations
from datetime import date, timedelta

import db

VOLUME_RANGES = {
    "optimal_min": 10,
    "optimal_max": 20,
}

MUSCLE_LABELS = {
    "chest":       "Pectoraux",
    "back":        "Dos",
    "shoulders":   "Épaules",
    "biceps":      "Biceps",
    "triceps":     "Triceps",
    "quads":       "Quadriceps",
    "hamstrings":  "Ischio-jambiers",
    "glutes":      "Fessiers",
    "calves":      "Mollets",
    "abs":         "Abdominaux",
    "forearms":    "Avant-bras",
    "traps":       "Trapèzes",
}


def compute_weekly_hard_sets(days: int = 7) -> dict:
    """Retourne {muscle_group: {sets, status, recommendation}} pour les N derniers jours.

    Un "hard set" = tout set logué où RPE ≥ 7 (ou RPE absent → compté conservative).
    """
    cutoff = (date.today() - timedelta(days=days)).isoformat()
    logs   = db.get_exercise_logs_since(cutoff)

    counts: dict[str, int] = {}

    for log in logs:
        muscles     = log.get("muscles") or []
        sets_json   = log.get("sets_json") or []
        session_rpe = log.get("rpe")

        if not muscles:
            continue

        hard_set_count = 0
        if sets_json:
            for s in sets_json:
                set_rpe = s.get("rpe") or session_rpe
                if set_rpe is None or float(set_rpe) >= 7:
                    hard_set_count += 1
        else:
            hard_set_count = 1

        for muscle in muscles:
            counts[muscle] = counts.get(muscle, 0) + hard_set_count

    result = {}
    for muscle, sets in counts.items():
        if sets < VOLUME_RANGES["optimal_min"]:
            status = "low"
            recommendation = (
                f"Volume bas ({sets} sets/sem) — cible 10-20 pour stimuler l'hypertrophie"
            )
        elif sets <= VOLUME_RANGES["optimal_max"]:
            status = "optimal"
            recommendation = f"Volume optimal ({sets} sets/sem)"
        else:
            status = "high"
            recommendation = (
                f"Volume élevé ({sets} sets/sem) — surveille ta récupération"
            )

        result[muscle] = {
            "sets":           sets,
            "status":         status,
            "label":          MUSCLE_LABELS.get(muscle, muscle.capitalize()),
            "recommendation": recommendation,
        }

    return result
