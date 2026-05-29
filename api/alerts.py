"""
api/alerts.py — Proactive alert detection.
Read-only: never writes to any table or KV store.
"""
from __future__ import annotations
import logging
from datetime import date, datetime, timedelta, timezone

import db
from utils import _today_mtl
from nutrition import load_settings as load_nutrition_settings
from body_weight import load_body_weight
from user_profile import load_user_profile

logger = logging.getLogger("trainingos.alerts")


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
    target = float(settings.get("objectif_proteines") or 180)
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
    target = float(settings.get("limite_calories") or 2400)
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

_COMPOUND_GROUPS = {"chest", "lats", "quads", "hamstrings", "fessiers", "shoulders"}
_MUSCLE_LABELS = {
    "chest": "Pectoraux", "lats": "Dorsaux", "quads": "Quadriceps",
    "hamstrings": "Ischio", "fessiers": "Fessiers", "shoulders": "Épaules",
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
# Detector 6 — Rapid weight loss (> 1% BW/week, rolling window)
# ---------------------------------------------------------------------------

def detect_rapid_weight_loss(body_weight: list) -> dict | None:
    entries = sorted(
        [e for e in body_weight if e.get("poids") is not None],
        key=lambda x: str(x.get("date", "")),
        reverse=True
    )
    # Need at least 14 entries spanning ~4 weeks for a reliable signal
    if len(entries) < 14:
        return None

    recent7 = entries[:7]
    older7  = entries[7:14]

    avg_recent = sum(e["poids"] for e in recent7) / len(recent7)
    avg_older  = sum(e["poids"] for e in older7)  / len(older7)

    # Compute actual elapsed weeks between window midpoints
    try:
        d_recent = date.fromisoformat(str(recent7[0].get("date", ""))[:10])
        d_older  = date.fromisoformat(str(older7[-1].get("date", ""))[:10])
        weeks = max((d_older - d_recent).days / 7, 1)
    except Exception:
        weeks = 2.0

    weekly_loss = (avg_older - avg_recent) / weeks
    if weekly_loss <= 0:
        return None

    pct_per_week = weekly_loss / avg_older * 100
    if pct_per_week <= 1.0:
        return None

    return {
        "id": "rapid_weight_loss",
        "type": "body_comp",
        "severity": "warning",
        "title": "Perte de poids trop rapide",
        "message": (
            f"Tu perds ~{weekly_loss:.1f} lbs/semaine ({pct_per_week:.1f}% de ton poids). "
            "Au-delà de 1%/semaine, tu risques de perdre du muscle en plus du gras. "
            "Réduis ton déficit de 150–200 kcal ou ajoute une séance de musculation."
        ),
        "action": "open_nutrition",
    }


# ---------------------------------------------------------------------------
# Detector 7 — Rapid weight gain (> 1 lb/week, rolling window)
# ---------------------------------------------------------------------------

def detect_rapid_weight_gain(body_weight: list) -> dict | None:
    entries = sorted(
        [e for e in body_weight if e.get("poids") is not None],
        key=lambda x: str(x.get("date", "")),
        reverse=True
    )
    if len(entries) < 14:
        return None

    recent7 = entries[:7]
    older7  = entries[7:14]

    avg_recent = sum(e["poids"] for e in recent7) / len(recent7)
    avg_older  = sum(e["poids"] for e in older7)  / len(older7)

    try:
        d_recent = date.fromisoformat(str(recent7[0].get("date", ""))[:10])
        d_older  = date.fromisoformat(str(older7[-1].get("date", ""))[:10])
        weeks = max((d_older - d_recent).days / 7, 1)
    except Exception:
        weeks = 2.0

    weekly_gain = (avg_recent - avg_older) / weeks
    if weekly_gain <= 1.0:
        return None

    return {
        "id": "rapid_weight_gain",
        "type": "body_comp",
        "severity": "warning",
        "title": "Prise de poids trop rapide",
        "message": (
            f"Tu prends ~{weekly_gain:.1f} lbs/semaine. "
            "Au-delà de 1 lb/semaine, une partie est probablement du gras. "
            "Réduis ton surplus de 100–150 kcal."
        ),
        "action": "open_nutrition",
    }


# ---------------------------------------------------------------------------
# Detector 8 — Aberrant body fat (< physiological minimum or > 45%)
# ---------------------------------------------------------------------------

def detect_aberrant_body_fat(body_weight: list, is_male: bool) -> dict | None:
    entries_with_bf = [
        e for e in body_weight
        if e.get("body_fat") is not None
    ]
    if not entries_with_bf:
        return None

    latest = sorted(entries_with_bf, key=lambda x: str(x.get("date", "")), reverse=True)[0]
    bf = float(latest["body_fat"])

    min_threshold = 5.0 if is_male else 12.0

    if bf < min_threshold:
        return {
            "id": "body_fat_too_low",
            "type": "body_comp",
            "severity": "warning",
            "title": "Body fat sous le seuil physiologique",
            "message": (
                f"Ton body fat enregistré est {bf:.1f}% — sous le minimum physiologique "
                f"({'5%' if is_male else '12%'}). Vérifie tes mesures. "
                "Si c'est correct, consulte un professionnel de santé."
            ),
            "action": "open_dashboard",
        }

    if bf > 45.0:
        return {
            "id": "body_fat_too_high",
            "type": "body_comp",
            "severity": "warning",
            "title": "Valeur body fat inhabituelle",
            "message": (
                f"Ton body fat enregistré est {bf:.1f}%. "
                "Vérifie tes mensurations (taille, cou, hanches)."
            ),
            "action": "open_dashboard",
        }

    return None


# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------

# Priority order: most actionable / critical first
_SEVERITY_ORDER = {"warning": 0, "info": 1}


def get_all_alerts() -> list[dict]:
    """Run all detectors and return alerts sorted by priority."""
    try:
        settings    = load_nutrition_settings()
        recent_days = db.get_nutrition_entries_recent(7)
        sessions    = db.get_workout_sessions(limit=20)
        inventory   = db.get_exercises() or {}
        body_weight = load_body_weight()
        profile     = load_user_profile() or {}
        sex         = (profile.get("sex") or "").upper()
        is_male     = not sex.startswith("F")

        candidates: list[dict | None] = [
            detect_high_rpe_streak(sessions),
            detect_consecutive_muscle_group(sessions, inventory),
            detect_low_protein(settings, recent_days),
            detect_under_calories(settings, recent_days),
            detect_no_log_today(recent_days),
            detect_rapid_weight_loss(body_weight),
            detect_rapid_weight_gain(body_weight),
            detect_aberrant_body_fat(body_weight, is_male),
        ]

        alerts = [a for a in candidates if a is not None]
        alerts.sort(key=lambda a: _SEVERITY_ORDER.get(a.get("severity", "info"), 99))
        return alerts

    except Exception as e:
        logger.error("get_all_alerts error: %s", e)
        return []
