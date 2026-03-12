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

from db import get_json, set_json

_KV_KEY = "breathwork_sessions"

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


# ── Stockage ──────────────────────────────────────────────────────────────────

def _load() -> list:
    return get_json(_KV_KEY) or []

def _save(sessions: list) -> None:
    set_json(_KV_KEY, sessions)


# ── CRUD ──────────────────────────────────────────────────────────────────────

def log_session(technique_id: str, duration_sec: int, cycles: int) -> dict:
    if technique_id not in _TECHNIQUE_MAP:
        raise ValueError(f"Technique inconnue : {technique_id}")

    sessions = _load()
    session = {
        "id":           str(uuid.uuid4()),
        "date":         date_cls.today().isoformat(),
        "technique_id": technique_id,
        "technique":    _TECHNIQUE_MAP[technique_id]["name"],
        "duration_sec": duration_sec,
        "cycles":       cycles,
    }
    sessions.insert(0, session)
    _save(sessions)
    return session


def get_history(days: int = 30) -> list:
    cutoff = (date_cls.today() - timedelta(days=days)).isoformat()
    return [s for s in _load() if s.get("date", "") >= cutoff]


def get_stats(days: int = 7) -> dict:
    """Statistiques hebdomadaires/mensuelles."""
    sessions = get_history(days)
    total_min = sum(s.get("duration_sec", 0) for s in sessions) // 60
    by_technique: dict[str, int] = {}
    for s in sessions:
        tid = s.get("technique_id", "?")
        by_technique[tid] = by_technique.get(tid, 0) + 1

    fav = max(by_technique, key=by_technique.get) if by_technique else None
    fav_name = _TECHNIQUE_MAP[fav]["name"] if fav and fav in _TECHNIQUE_MAP else None

    return {
        "sessions_count": len(sessions),
        "total_minutes":  total_min,
        "favorite":       fav_name,
        "by_technique":   by_technique,
        "days":           days,
    }


def get_session_dates(days: int = 30) -> set[str]:
    return {s["date"] for s in get_history(days)}
