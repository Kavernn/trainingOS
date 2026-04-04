"""
breathwork.py — Tracking des sessions de respiration guidée.

Clé KV : "breathwork_sessions" → list[dict] DESC par date

Endpoints exposés dans index.py :
  GET  /api/breathwork/techniques
  POST /api/breathwork/log
  GET  /api/breathwork/history
  GET  /api/breathwork/stats
"""
from __future__ import annotations

from datetime import date as date_cls, timedelta
import uuid

import db

# ── Techniques disponibles ────────────────────────────────────────────────────

TECHNIQUES = [
    {
        "id":          "coherence",
        "name":        "Cohérence cardiaque",
        "description": "5 min · 6 cycles/min. Régule le système nerveux autonome. Idéal matin, midi et soir.",
        "icon":        "waveform.path.ecg",
        "color":       "green",
        "phases": [
            {"phase": "inhale",  "label": "Inspirez",  "seconds": 5},
            {"phase": "exhale",  "label": "Expirez",   "seconds": 5},
        ],
        "target_cycles":  15,
        "total_sec":      150,
        "difficulty":     "facile",
    },
    {
        "id":          "box",
        "name":        "Box Breathing",
        "description": "Technique des Navy SEALs. Parfait pour calmer l'anxiété rapidement et retrouver le focus.",
        "icon":        "square",
        "color":       "blue",
        "phases": [
            {"phase": "inhale",   "label": "Inspirez", "seconds": 4},
            {"phase": "hold",     "label": "Tenez",    "seconds": 4},
            {"phase": "exhale",   "label": "Expirez",  "seconds": 4},
            {"phase": "holdOut",  "label": "Pause",    "seconds": 4},
        ],
        "target_cycles":  4,
        "total_sec":      64,
        "difficulty":     "intermédiaire",
    },
    {
        "id":          "478",
        "name":        "4-7-8",
        "description": "Technique du Dr Andrew Weil. Réduit l'anxiété et aide à s'endormir en quelques minutes.",
        "icon":        "wind",
        "color":       "purple",
        "phases": [
            {"phase": "inhale",  "label": "Inspirez", "seconds": 4},
            {"phase": "hold",    "label": "Tenez",    "seconds": 7},
            {"phase": "exhale",  "label": "Expirez",  "seconds": 8},
        ],
        "target_cycles":  4,
        "total_sec":      76,
        "difficulty":     "intermédiaire",
    },
    {
        "id":          "sigh",
        "name":        "Soupir physiologique",
        "description": "Double inspiration + longue expiration. Réduit le stress immédiatement. Étudié par Stanford.",
        "icon":        "lungs.fill",
        "color":       "cyan",
        "phases": [
            {"phase": "inhale",  "label": "Grande inspiration", "seconds": 4},
            {"phase": "hold",    "label": "Petite inspiration",  "seconds": 1},
            {"phase": "exhale",  "label": "Longue expiration",  "seconds": 8},
        ],
        "target_cycles":  5,
        "total_sec":      65,
        "difficulty":     "facile",
    },
]

_TECHNIQUE_MAP = {t["id"]: t for t in TECHNIQUES}
_TECHNIQUE_MAP_BY_NAME = {t["name"]: t for t in TECHNIQUES}


# ── CRUD ──────────────────────────────────────────────────────────────────────

def log_session(technique_id: str, duration_sec: int, cycles: int) -> dict:
    if technique_id not in _TECHNIQUE_MAP:
        raise ValueError(f"Technique inconnue : {technique_id}")

    technique_name = _TECHNIQUE_MAP[technique_id]["name"]
    session = {
        "id":           str(uuid.uuid4()),
        "date":         date_cls.today().isoformat(),
        "technique_id": technique_id,
        "technique":    technique_name,
        "duration_sec": duration_sec,
        "duration_min": duration_sec // 60,
        "cycles":       cycles,
        "logged_at":    date_cls.today().isoformat(),
    }
    db.insert_breathwork_session(session)
    return session


def get_history(days: int = 30) -> list:
    sessions = db.get_breathwork_sessions(days=days)
    # Enrichit technique_id si absent (données migrées)
    for s in sessions:
        if not s.get("technique_id") and s.get("technique"):
            tech = _TECHNIQUE_MAP_BY_NAME.get(s["technique"])
            if tech:
                s["technique_id"] = tech["id"]
    return sessions


def get_stats(days: int = 7) -> dict:
    """Statistiques hebdomadaires/mensuelles."""
    sessions = get_history(days)
    total_min = sum(
        s.get("duration_min") or (s.get("duration_sec", 0) // 60)
        for s in sessions
    )
    by_technique: dict[str, int] = {}
    for s in sessions:
        key = s.get("technique_id") or s.get("technique", "?")
        by_technique[key] = by_technique.get(key, 0) + 1

    fav = max(by_technique, key=by_technique.get) if by_technique else None
    if fav:
        fav_name = _TECHNIQUE_MAP[fav]["name"] if fav in _TECHNIQUE_MAP else fav
    else:
        fav_name = None

    return {
        "sessions_count": len(sessions),
        "total_minutes":  total_min,
        "favorite":       fav_name,
        "by_technique":   by_technique,
        "days":           days,
    }


def get_session_dates(days: int = 30) -> set[str]:
    return {s["date"] for s in get_history(days)}
