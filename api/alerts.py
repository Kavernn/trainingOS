"""
api/alerts.py — Proactive alert detection.
Read-only: never writes to any table or KV store.
"""
from __future__ import annotations
import logging
from datetime import date, datetime, timedelta, timezone

import db
from nutrition import load_settings as load_nutrition_settings

logger = logging.getLogger("trainingos.alerts")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _today_mtl() -> str:
    try:
        from zoneinfo import ZoneInfo
        return datetime.now(ZoneInfo("America/Montreal")).strftime("%Y-%m-%d")
    except Exception:
        return datetime.now().strftime("%Y-%m-%d")


def _hour_mtl() -> int:
    try:
        from zoneinfo import ZoneInfo
        return datetime.now(ZoneInfo("America/Montreal")).hour
    except Exception:
        return datetime.now().hour


def _time_str_mtl() -> str:
    try:
        from zoneinfo import ZoneInfo
        return datetime.now(ZoneInfo("America/Montreal")).strftime("%H:%M")
    except Exception:
        return datetime.now().strftime("%H:%M")


# ---------------------------------------------------------------------------
# Detector 1 — Low protein (< 70 % target, 2+ consecutive past days)
# ---------------------------------------------------------------------------

def detect_low_protein(settings: dict, recent_days: list[dict]) -> dict | None:
    target = float(settings.get("objectif_proteines") or 160)
    threshold = target * 0.70
    today = _today_mtl()

    past = [d for d in recent_days if d["date"] < today and d.get("nb", 0) > 0]
    if len(past) < 2:
        return None

    last2 = sorted(past, key=lambda x: x["date"], reverse=True)[:2]
    low = [d for d in last2 if d["proteines"] < threshold]
    if len(low) < 2:
        return None

    avg = round(sum(d["proteines"] for d in low) / len(low))
    return {
        "id": "low_protein_2d",
        "type": "nutrition",
        "severity": "warning",
        "title": "Protéines insuffisantes",
        "message": (
            f"{int(avg)}g de protéines en moyenne sur les 2 derniers jours "
            f"(objectif {int(target)}g). Ce soir : viande, œufs, cottage ou shake."
        ),
        "action": "open_nutrition",
    }


# ---------------------------------------------------------------------------
# Detector 2 — Under calories (< 75 % target, 2+ consecutive past days with entries)
# ---------------------------------------------------------------------------

def detect_under_calories(settings: dict, recent_days: list[dict]) -> dict | None:
    target = float(settings.get("limite_calories") or 2200)
    threshold = target * 0.75
    today = _today_mtl()

    past = [d for d in recent_days if d["date"] < today and d.get("nb", 0) > 0]
    if len(past) < 2:
        return None

    last2 = sorted(past, key=lambda x: x["date"], reverse=True)[:2]
    low = [d for d in last2 if d["calories"] < threshold]
    if len(low) < 2:
        return None

    avg = round(sum(d["calories"] for d in low) / len(low))
    deficit = int(target - avg)
    return {
        "id": "under_calories_2d",
        "type": "nutrition",
        "severity": "warning",
        "title": "Déficit calorique prolongé",
        "message": (
            f"~{int(avg)} kcal/jour en moyenne sur les 2 derniers jours "
            f"(objectif {int(target)} kcal, déficit ~{deficit} kcal). "
            "Risque de perte musculaire — mange plus ce soir."
        ),
        "action": "open_nutrition",
    }


# ---------------------------------------------------------------------------
# Detector 3 — No log today (past 18:00, zero entries)
# ---------------------------------------------------------------------------

def detect_no_log_today(recent_days: list[dict]) -> dict | None:
    if _hour_mtl() < 18:
        return None

    today = _today_mtl()
    today_data = next((d for d in recent_days if d["date"] == today), None)
    if today_data and today_data.get("nb", 0) > 0:
        return None

    return {
        "id": "no_log_today",
        "type": "nutrition",
        "severity": "info",
        "title": "Aucun repas enregistré",
        "message": (
            f"Il est {_time_str_mtl()} et tu n'as rien loggé aujourd'hui. "
            "Quelques minutes pour enregistrer tes repas — ton suivi en dépend."
        ),
        "action": "open_nutrition",
    }


# ---------------------------------------------------------------------------
# Detector 4 — Consecutive muscle group (same primary group, 2 days in a row)
# ---------------------------------------------------------------------------

_COMPOUND_GROUPS = {"chest", "lats", "quads", "hamstrings", "glutes", "shoulders"}
_MUSCLE_LABELS = {
    "chest": "Pectoraux", "lats": "Dorsaux", "quads": "Quadriceps",
    "hamstrings": "Ischio", "glutes": "Fessiers", "shoulders": "Épaules",
}


def _primary_muscles(exercise_name: str, inventory: dict) -> set[str]:
    entry = inventory.get(exercise_name, {})
    muscles = entry.get("muscles") or []
    return {m for m in muscles if m in _COMPOUND_GROUPS}


def detect_consecutive_muscle_group(sessions: list[dict], inventory: dict) -> dict | None:
    today = _today_mtl()
    yesterday = (date.fromisoformat(today) - timedelta(days=1)).isoformat()

    today_sessions = [s for s in sessions if str(s.get("date", "")) == today]
    yesterday_sessions = [s for s in sessions if str(s.get("date", "")) == yesterday]

    if not today_sessions or not yesterday_sessions:
        return None

    try:
        today_logs = db.get_session_exercise_logs(today)
        yesterday_logs = db.get_session_exercise_logs(yesterday)
    except Exception as e:
        logger.warning("detect_consecutive_muscle_group: error fetching logs: %s", e)
        return None

    if not today_logs or not yesterday_logs:
        return None

    today_muscles: set[str] = set()
    for log in today_logs:
        today_muscles |= _primary_muscles(log["exercise_name"], inventory)

    yesterday_muscles: set[str] = set()
    for log in yesterday_logs:
        yesterday_muscles |= _primary_muscles(log["exercise_name"], inventory)

    overlap = today_muscles & yesterday_muscles
    if not overlap:
        return None

    names = ", ".join(_MUSCLE_LABELS.get(m, m.capitalize()) for m in sorted(overlap))
    return {
        "id": f"consecutive_muscle",
        "type": "training",
        "severity": "warning",
        "title": "Groupe musculaire consécutif",
        "message": (
            f"{names} entraîné(s) hier et aujourd'hui. "
            "Pense à gérer l'intensité ou à cibler des groupes différents demain."
        ),
        "action": "open_dashboard",
    }


# ---------------------------------------------------------------------------
# Detector 5 — High RPE streak (avg > 8.5 on last 3 sessions)
# ---------------------------------------------------------------------------

def detect_high_rpe_streak(sessions: list[dict]) -> dict | None:
    with_rpe = [
        s for s in sessions
        if s.get("rpe") is not None and s.get("date")
    ]
    with_rpe.sort(key=lambda x: x["date"], reverse=True)

    if len(with_rpe) < 3:
        return None

    last3_rpe = [float(s["rpe"]) for s in with_rpe[:3]]
    if not all(r > 8.5 for r in last3_rpe):
        return None

    avg = round(sum(last3_rpe) / 3, 1)
    return {
        "id": "high_rpe_streak",
        "type": "recovery",
        "severity": "warning",
        "title": "Intensité maximale 3 séances de suite",
        "message": (
            f"RPE moyen {avg}/10 sur les 3 dernières séances. "
            "Ton système nerveux est sous pression — allège demain ou prends un jour de repos."
        ),
        "action": "open_dashboard",
    }


# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------

# Priority order: most actionable / critical first
_SEVERITY_ORDER = {"warning": 0, "info": 1}


def get_all_alerts() -> list[dict]:
    """Run all detectors and return alerts sorted by priority."""
    try:
        settings = load_nutrition_settings()
        recent_days = db.get_nutrition_entries_recent(7)
        sessions = db.get_workout_sessions(limit=20)
        inventory = db.get_exercises() or {}

        candidates: list[dict | None] = [
            detect_high_rpe_streak(sessions),
            detect_consecutive_muscle_group(sessions, inventory),
            detect_low_protein(settings, recent_days),
            detect_under_calories(settings, recent_days),
            detect_no_log_today(recent_days),
        ]

        alerts = [a for a in candidates if a is not None]
        alerts.sort(key=lambda a: _SEVERITY_ORDER.get(a.get("severity", "info"), 99))
        return alerts

    except Exception as e:
        logger.error("get_all_alerts error: %s", e)
        return []
