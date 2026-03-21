"""
mood.py — Suivi de l'humeur quotidienne.

Clé KV : "mood_log" → list[dict] DESC par date

Endpoints exposés dans index.py :
  GET  /api/mood/emotions
  POST /api/mood/log
  GET  /api/mood/history
  GET  /api/mood/check_due
  GET  /api/mood/insights
"""
from __future__ import annotations

from datetime import date as date_cls, timedelta
from typing import Optional
import uuid

from db  import get_json, set_json
from pss import get_latest_pss_score

_KV_KEY = "mood_log"

# ── Émotions disponibles ──────────────────────────────────────────────────────

EMOTIONS = [
    {"id": "joyeux",       "label": "Joyeux",       "emoji": "😄", "valence":  1},
    {"id": "reconnaissant","label": "Reconnaissant", "emoji": "🙏", "valence":  1},
    {"id": "calme",        "label": "Calme",         "emoji": "😌", "valence":  1},
    {"id": "motive",       "label": "Motivé",        "emoji": "💪", "valence":  1},
    {"id": "confiant",     "label": "Confiant",      "emoji": "😎", "valence":  1},
    {"id": "neutre",       "label": "Neutre",        "emoji": "😐", "valence":  0},
    {"id": "anxieux",      "label": "Anxieux",       "emoji": "😰", "valence": -1},
    {"id": "fatigue",      "label": "Fatigué",       "emoji": "😴", "valence": -1},
    {"id": "irritable",    "label": "Irritable",     "emoji": "😤", "valence": -1},
    {"id": "triste",       "label": "Triste",        "emoji": "😢", "valence": -1},
    {"id": "depasse",      "label": "Dépassé",       "emoji": "😵", "valence": -1},
    {"id": "stresse",      "label": "Stressé",       "emoji": "😓", "valence": -1},
]

_EMOTION_MAP = {e["id"]: e for e in EMOTIONS}


# ── Stockage ──────────────────────────────────────────────────────────────────

def _load() -> list:
    return get_json(_KV_KEY) or []

def _save(records: list) -> None:
    set_json(_KV_KEY, records)


# ── CRUD ──────────────────────────────────────────────────────────────────────

def save_mood_entry(
    score: int,
    emotions: list[str],
    notes: str | None = None,
    triggers: list[str] | None = None,
) -> dict:
    """
    Enregistre une entrée d'humeur.
    score : 1-10
    emotions : liste d'IDs (voir EMOTIONS)
    """
    if not (1 <= score <= 10):
        raise ValueError("Le score doit être entre 1 et 10.")

    valid_ids = {e["id"] for e in EMOTIONS}
    emotions = [e for e in (emotions or []) if e in valid_ids]

    # Contexte PSS du jour si disponible
    pss = get_latest_pss_score("full") or get_latest_pss_score("short")
    pss_score_linked = None
    if pss and pss.get("date") == date_cls.today().isoformat():
        pss_score_linked = pss.get("score")

    records = _load()

    entry = {
        "id":               str(uuid.uuid4()),
        "date":             date_cls.today().isoformat(),
        "score":            score,
        "emotions":         emotions,
        "notes":            notes,
        "triggers":         triggers or [],
        "pss_score_linked": pss_score_linked,
    }
    records.insert(0, entry)
    _save(records)
    return entry


def _list_history(days: int = 30) -> list:
    """Retourne la liste brute des entrées — usage interne uniquement."""
    records = _load()
    if days:
        cutoff = (date_cls.today() - timedelta(days=days)).isoformat()
        records = [r for r in records if r.get("date", "") >= cutoff]
    return records


def get_history(days: int = 30, limit: int = 20, offset: int = 0) -> dict:
    records = _list_history(days)
    page = records[offset: offset + limit]
    return {
        "items":       page,
        "offset":      offset,
        "limit":       limit,
        "total":       len(records),
        "has_more":    offset + limit < len(records),
        "next_offset": offset + limit if offset + limit < len(records) else None,
    }


def get_today_entry() -> dict | None:
    today = date_cls.today().isoformat()
    return next((r for r in _load() if r.get("date") == today), None)


def check_due() -> dict:
    """Retourne True si aucune humeur loggée aujourd'hui."""
    today = date_cls.today().isoformat()
    records = _load()
    logged = any(r.get("date") == today for r in records)
    return {
        "is_due":  not logged,
        "message": "T'as-tu pris 30 secondes pour noter ton humeur aujourd'hui ?" if not logged else None,
    }


# ── Insights ──────────────────────────────────────────────────────────────────

def generate_insights(days: int = 30) -> list[str]:
    """Génère des textes motivants basés sur l'historique d'humeur."""
    records = _list_history(days)
    if len(records) < 3:
        return ["Continue à loguer ton humeur — les insights arrivent après quelques jours !"]

    scores = [r["score"] for r in records]
    avg    = sum(scores) / len(scores)
    recent = scores[:7]
    avg_recent = sum(recent) / len(recent) if recent else avg

    insights = []

    # Tendance
    delta = round(avg_recent - avg, 1)
    if delta >= 1:
        insights.append(f"Ton humeur a monté de {delta} pts cette semaine — beau travail ! 🚀")
    elif delta <= -1:
        insights.append(f"Humeur un peu plus basse cette semaine ({delta} pts). C'est normal d'avoir des creux.")
    else:
        insights.append(f"Humeur stable autour de {round(avg, 1)}/10 ce mois-ci.")

    # Émotions dominantes positives
    all_emotions: list[str] = []
    for r in records[:14]:
        all_emotions.extend(r.get("emotions", []))
    pos = [e for e in all_emotions if _EMOTION_MAP.get(e, {}).get("valence", 0) > 0]
    if pos:
        top = max(set(pos), key=pos.count)
        label = _EMOTION_MAP[top]["label"]
        insights.append(f"Ton émotion positive la plus fréquente : {_EMOTION_MAP[top]['emoji']} {label}.")

    # Score bas → suggestion
    if avg_recent < 5:
        insights.append("💡 Essaie 5 min de cohérence cardiaque — ça aide vraiment quand l'humeur est basse.")

    return insights


# ── Moyenne hebdo pour le dashboard ──────────────────────────────────────────

def get_weekly_avg(days: int = 7) -> Optional[float]:
    records = _list_history(days)
    scores = [r["score"] for r in records]
    return round(sum(scores) / len(scores), 1) if scores else None


def get_mood_trend(days: int = 7) -> str:
    """Retourne 'up', 'down' ou 'stable'."""
    records = _list_history(days * 2)
    if len(records) < 4:
        return "stable"
    half = len(records) // 2
    recent = [r["score"] for r in records[:half]]
    older  = [r["score"] for r in records[half:]]
    avg_r  = sum(recent) / len(recent)
    avg_o  = sum(older)  / len(older)
    delta  = avg_r - avg_o
    if delta >= 0.8:  return "up"
    if delta <= -0.8: return "down"
    return "stable"
