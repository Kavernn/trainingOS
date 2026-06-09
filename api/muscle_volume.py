"""muscle_volume.py — Hard sets par groupe musculaire par semaine.

Gold standard hypertrophie : Schoenfeld & Krieger 2017.
Ranges recommandés : 10-20 sets/muscle/semaine.

Un "hard set" = tout set exécuté à RPE ≥ 7, ou RPE absent (conservateur).
"""
from __future__ import annotations
from datetime import date, timedelta

import db
from utils import _today_mtl

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
    cutoff = (date.fromisoformat(_today_mtl()) - timedelta(days=days)).isoformat()
    logs   = db.get_exercise_logs_since(cutoff)

    counts: dict[str, int] = {}

    for log in logs:
        # Prefer enriched catalog fields; fall back to legacy muscles[] array
        muscle_group    = (log.get("muscle_group") or "").strip()
        muscle_specific = (log.get("muscle_specific") or "").strip()
        if muscle_group and muscle_specific:
            muscles = [muscle_specific]
        elif muscle_group:
            muscles = [muscle_group]
        else:
            muscles = log.get("muscles") or []

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


def compute_volume_full(days_current: int = 7, days_trend: int = 28) -> dict:
    """Full muscle volume report: current week + 4-week rolling avg + MEV status + neglected.

    neglected = muscles with 4-week avg < MEV (10 sets/week, Schoenfeld & Krieger 2017).
    """
    current_raw = compute_weekly_hard_sets(days=days_current)
    trend_raw   = compute_weekly_hard_sets(days=days_trend)

    weeks = days_trend / 7.0
    avg_per_week: dict[str, float] = {
        m: round(d["sets"] / weeks, 1)
        for m, d in trend_raw.items()
    }

    neglected = sorted(
        [
            {
                "muscle":             m,
                "label":              MUSCLE_LABELS.get(m, m.capitalize()),
                "avg_sets_per_week":  avg_per_week[m],
                "mev":                VOLUME_RANGES["optimal_min"],
                "deficit":            round(VOLUME_RANGES["optimal_min"] - avg_per_week[m], 1),
            }
            for m in avg_per_week
            if avg_per_week[m] < VOLUME_RANGES["optimal_min"]
        ],
        key=lambda x: x["avg_sets_per_week"],
    )

    weekly_avg_enriched = {
        m: {
            "avg_sets_per_week": avg_per_week[m],
            "label":             MUSCLE_LABELS.get(m, m.capitalize()),
            "status":            (
                "low"     if avg_per_week[m] < VOLUME_RANGES["optimal_min"] else
                "optimal" if avg_per_week[m] <= VOLUME_RANGES["optimal_max"] else
                "high"
            ),
        }
        for m in avg_per_week
    }

    return {
        "current_week":   current_raw,
        "weekly_avg":     weekly_avg_enriched,
        "neglected":      neglected,
        "mev":            VOLUME_RANGES["optimal_min"],
        "mav":            VOLUME_RANGES["optimal_max"],
        "trend_days":     days_trend,
    }
