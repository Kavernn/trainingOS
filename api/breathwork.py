"""
breathwork.py — Tracking des sessions de respiration guidée.

Clé KV : "breathwork_sessions" → list[dict] DESC par date

Endpoints exposés dans index.py :
  GET  /api/breathwork/techniques
  POST /api/breathwork/log
  GET  /api/breathwork/history
"""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
import uuid

import db
import db_wellness as _db_wellness

# America/Montreal EDT = UTC-4 (approximation suffisante pour arrondir à un jour civil).
_MTL_OFFSET_HOURS = 4

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


# ── CRUD ──────────────────────────────────────────────────────────────────────

def _parse_started_at(raw: str) -> datetime:
    """Parse un ISO 8601 (avec ou sans suffixe Z). Lève ValueError si invalide."""
    if not isinstance(raw, str) or not raw:
        raise ValueError("started_at requis (ISO 8601)")
    return datetime.fromisoformat(raw.replace("Z", "+00:00"))


def _mtl_date_from(dt: datetime) -> str:
    """Jour civil America/Montreal (YYYY-MM-DD) d'un timestamp aware."""
    if dt.tzinfo is None:
        raise ValueError("started_at doit inclure un fuseau horaire")
    local = dt.astimezone(timezone(timedelta(hours=-_MTL_OFFSET_HOURS)))
    return local.date().isoformat()


def log_session(technique_id: str, duration_sec: int, cycles: int, started_at: str) -> dict:
    if technique_id not in _TECHNIQUE_MAP:
        raise ValueError(f"Technique inconnue : {technique_id}")
    dt = _parse_started_at(started_at)

    technique_name = _TECHNIQUE_MAP[technique_id]["name"]
    session = {
        "id":           str(uuid.uuid4()),
        "date":         _mtl_date_from(dt),
        "technique_id": technique_id,
        "technique":    technique_name,
        "duration_sec": duration_sec,
        "duration_min": duration_sec // 60,
        "cycles":       cycles,
        "started_at":   dt.isoformat(),
    }
    saved = db.insert_breathwork_session(session)
    if not saved:
        raise RuntimeError("insert_breathwork_session a échoué (DB indisponible)")
    return saved


def get_history(days: int = 30) -> list:
    return _db_wellness.get_breathwork_sessions(days=days)


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
