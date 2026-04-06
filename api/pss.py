"""
pss.py — PSS-10 / PSS-4 Perceived Stress Scale (version française validée).

Calcul du score, historique, vérification de fréquence, et insights narratifs.

Clé KV : "pss_records"  →  list[dict] (du plus récent au plus ancien)

Endpoints exposés dans index.py :
  POST /api/pss/submit
  GET  /api/pss/history
  GET  /api/pss/check_due
"""
from __future__ import annotations

from datetime import date as date_cls, timedelta
from typing import Optional
import uuid

import db

# ── Questions PSS-10 (version française validée) ──────────────────────────────

PSS10_QUESTIONS = [
    {"id": 1,  "text": "Ce mois-ci, un événement inattendu t'a souvent pris de court ?",                        "positive": False},
    {"id": 2,  "text": "T'es-tu souvent senti(e) hors de contrôle de ta vie ?",                                 "positive": False},
    {"id": 3,  "text": "T'es-tu souvent senti(e) nerveux(se) ou stressé(e) ?",                                  "positive": False},
    {"id": 4,  "text": "T'as souvent eu l'impression de bien gérer les choses importantes ?",                   "positive": True},
    {"id": 5,  "text": "T'es-tu souvent senti(e) débordé(e) par tout ce que tu devais faire ?",                "positive": False},
    {"id": 6,  "text": "T'as souvent réussi à faire face efficacement aux difficultés ?",                       "positive": True},
    {"id": 7,  "text": "T'as souvent eu l'impression d'avoir les choses sous contrôle ?",                       "positive": True},
    {"id": 8,  "text": "T'es-tu souvent senti(e) tellement à bout de nerfs que tu ne te contrôlais plus ?",    "positive": False},
    {"id": 9,  "text": "T'as souvent eu l'impression d'être au sommet de ta forme ?",                          "positive": True},
    {"id": 10, "text": "T'as souvent eu l'impression que les difficultés s'accumulaient trop pour t'en sortir ?", "positive": False},
]

# Indices 0-based des items positifs dans PSS-10 (inversés au scoring)
_POSITIVE_INDICES_PSS10 = [i for i, q in enumerate(PSS10_QUESTIONS) if q["positive"]]  # [3,5,6,8]

# Indices 0-based des items PSS-4 dans le tableau PSS-10 (items 2,5,6,9 → idx 1,4,5,8)
_PSS4_GLOBAL_INDICES = [1, 4, 5, 8]

# Indices positifs DANS le sous-tableau PSS-4 (items 6,9 → local idx 2,3)
_POSITIVE_INDICES_PSS4 = [
    local_i for local_i, global_i in enumerate(_PSS4_GLOBAL_INDICES)
    if global_i in _POSITIVE_INDICES_PSS10
]  # [2, 3]

_KV_KEY = "pss_records"

# Fréquences recommandées
_FULL_INTERVAL_DAYS  = 28   # 1 fois/mois
_SHORT_INTERVAL_DAYS = 7    # 1 fois/semaine


# ── Calcul du score ───────────────────────────────────────────────────────────

def calculate_pss_score(responses: list[int], is_short: bool = False) -> dict:
    """
    Calcule le score PSS-10 ou PSS-4.

    Paramètres :
      responses  : liste de 10 entiers [0-4] pour PSS-10,
                   ou 4 entiers [0-4] pour PSS-4 standalone,
                   ou 10 entiers avec is_short=True (extraction auto PSS-4).
      is_short   : True → extrait/utilise PSS-4.

    Retourne :
      {
        "score": int,              # 0-40 (PSS-10) ou 0-16 (PSS-4)
        "max_score": int,
        "category": str,           # "low" | "moderate" | "high"
        "category_label": str,     # "Stress faible" | "Stress modéré" | "Stress élevé"
        "raw_responses": [int],    # réponses brutes (sous-ensemble si PSS-4)
        "inverted_responses": [int],
        "positive_items_reversed": [int],  # indices inversés
        "type": str,               # "full" | "short"
      }
    """
    if not isinstance(responses, list) or len(responses) == 0:
        raise ValueError("pss: responses doit être une liste non vide.")
    if not all(isinstance(r, int) and 0 <= r <= 4 for r in responses):
        raise ValueError("pss: chaque réponse doit être un entier entre 0 et 4.")

    expected = [4, 10] if is_short else [10]
    if len(responses) not in expected:
        raise ValueError(f"pss: {len(responses)} réponses reçues, attendu {expected}.")

    # Extraction PSS-4 depuis PSS-10
    if is_short and len(responses) == 10:
        working = [responses[i] for i in _PSS4_GLOBAL_INDICES]
    else:
        working = list(responses)

    positive_indices = _POSITIVE_INDICES_PSS4 if is_short else _POSITIVE_INDICES_PSS10
    inverted = [4 - v if i in positive_indices else v for i, v in enumerate(working)]
    score = sum(inverted)
    max_score = 16 if is_short else 40
    category, label = _get_category(score, is_short)

    return {
        "score":                    score,
        "max_score":                max_score,
        "category":                 category,
        "category_label":           label,
        "raw_responses":            working,
        "inverted_responses":       inverted,
        "positive_items_reversed":  positive_indices,
        "type":                     "short" if is_short else "full",
    }


def _get_category(score: int, is_short: bool) -> tuple[str, str]:
    if is_short:
        if score <= 5:  return ("low",      "Stress faible")
        if score <= 10: return ("moderate", "Stress modéré")
        return              ("high",     "Stress élevé")
    else:
        if score <= 13: return ("low",      "Stress faible")
        if score <= 26: return ("moderate", "Stress modéré")
        return              ("high",     "Stress élevé")


# ── Stockage ──────────────────────────────────────────────────────────────────

def _load_records() -> list:
    return db.get_pss_records()


def save_pss_record(
    responses: list[int],
    is_short: bool = False,
    notes: str | None = None,
    triggers: list[str] | None = None,
    trigger_ratings: dict | None = None,
) -> dict:
    """Calcule, enrichit d'insights et persiste un enregistrement PSS."""
    result  = calculate_pss_score(responses, is_short)
    records = _load_records()

    # Streak (périodes consécutives avec au moins 1 entrée)
    streak = _compute_streak(records, result["type"])

    # Previous record of same type pour delta
    prev = next((r for r in records if r.get("type") == result["type"]), None)

    record = {
        "id":              str(uuid.uuid4()),
        "date":            date_cls.today().isoformat(),
        "type":            result["type"],
        "responses":       result["raw_responses"],
        "score":           result["score"],
        "max_score":       result["max_score"],
        "category":        result["category"],
        "category_label":  result["category_label"],
        "inverted_responses": result["inverted_responses"],
        "notes":           notes,
        "triggers":        triggers or [],
        "trigger_ratings": trigger_ratings or {},
        "streak":          streak,
        "insights":        generate_insights(result, prev, responses if not is_short else None),
    }

    db.insert_pss_record(record)
    return record


# ── Fréquence et rappels ──────────────────────────────────────────────────────

def check_due(pss_type: str = "full") -> dict:
    """
    Vérifie si un test PSS est dû.

    Retourne :
      {
        "is_due": bool,
        "days_since_last": int | None,
        "next_due_date": str | None,   # YYYY-MM-DD
        "message": str | None,          # message de suggestion si dû
      }
    """
    relevant = db.get_pss_records(pss_type=pss_type, limit=1)

    if not relevant:
        return {
            "is_due":          True,
            "days_since_last": None,
            "next_due_date":   None,
            "message":         "Établis ton niveau de stress de base — 3 min pour le bilan complet." if pss_type == "full"
                               else "Premier check rapide de ton stress ? (1 min)",
        }

    interval = _FULL_INTERVAL_DAYS if pss_type == "full" else _SHORT_INTERVAL_DAYS
    last     = date_cls.fromisoformat(relevant[0]["date"])
    today    = date_cls.today()
    delta    = (today - last).days
    next_due = (last + timedelta(days=interval)).isoformat()
    is_due   = delta >= interval

    return {
        "is_due":          is_due,
        "days_since_last": delta,
        "next_due_date":   next_due,
        "message":         _due_message(pss_type, delta) if is_due else None,
    }


def _due_message(pss_type: str, days: int) -> str:
    if pss_type == "full":
        return f"Ça fait {days} jours — temps de refaire le bilan stress complet ? (3 min)"
    return "Petit check rapide de ton stress cette semaine ? (1 min)"


# ── Insights narratifs ────────────────────────────────────────────────────────

def generate_insights(
    result: dict,
    previous_record: dict | None,
    full_responses: list[int] | None = None,
) -> list[str]:
    """Génère des textes motivants contextuels basés sur le score."""
    insights = []
    score    = result["score"]
    category = result["category"]
    max_s    = result["max_score"]
    is_full  = result["type"] == "full"

    # 1. Évolution vs précédent
    if previous_record:
        prev_score = previous_record.get("score", score)
        delta = prev_score - score  # positif = amélioration

        if delta >= 4:
            insights.append(
                f"Score en baisse de {delta} pts ({score}/{max_s}) — les efforts paient, continue !"
            )
        elif 0 < delta < 4:
            insights.append(f"Légère amélioration ({score} vs {prev_score}) — bonne tendance.")
        elif delta < -3:
            insights.append(
                f"Score en hausse de {abs(delta)} pts ({score}/{max_s}). "
                "Certaines périodes sont plus chargées — c'est normal."
            )
        elif delta == 0:
            insights.append(f"Score stable à {score}/{max_s}.")
    else:
        insights.append(f"Premier bilan enregistré — score de référence : {score}/{max_s}.")

    # 2. Items chauds (PSS-10 uniquement, réponses brutes disponibles)
    if is_full and full_responses and len(full_responses) == 10:
        hot = [
            PSS10_QUESTIONS[i]
            for i in range(10)
            if not PSS10_QUESTIONS[i]["positive"] and full_responses[i] >= 3
        ]
        hot.sort(key=lambda q: full_responses[q["id"] - 1], reverse=True)
        if hot and category != "low":
            nums = " et ".join(f"item {q['id']}" for q in hot[:2])
            insights.append(
                f"Tension visible à l'{nums}. Note un déclencheur concret pour agir dessus."
            )

    # 3. Message catégorie
    msgs = {
        "low":      f"Score faible ({score}/{max_s}) — ton niveau de stress est bien maîtrisé.",
        "moderate": f"Score modéré ({score}/{max_s}) — quelques zones de tension, mais gérable.",
        "high":     f"Score élevé ({score}/{max_s}) — ton corps réclame de l'attention. Petites actions > rien.",
    }
    insights.append(msgs[category])

    # 4. Suggestions features
    if category == "high":
        insights.append(
            "💡 Essaie : cohérence cardiaque (5 min), session légère de mobilité, ou note ce qui pèse le plus dans ton journal."
        )
    elif category == "moderate":
        insights.append("💡 Un entraînement modéré ou une courte marche peuvent réduire la tension résiduelle.")

    return insights


# ── Streak ────────────────────────────────────────────────────────────────────

def _compute_streak(records: list, pss_type: str) -> int:
    """Compte les périodes consécutives avec au moins 1 entrée du même type."""
    interval_days = _FULL_INTERVAL_DAYS + 4 if pss_type == "full" else _SHORT_INTERVAL_DAYS + 3
    relevant = sorted(
        [r for r in records if r.get("type") == pss_type],
        key=lambda r: r.get("date", ""), reverse=True
    )
    if not relevant:
        return 1

    streak = 1
    for i in range(len(relevant) - 1):
        d1 = date_cls.fromisoformat(relevant[i]["date"])
        d2 = date_cls.fromisoformat(relevant[i + 1]["date"])
        if (d1 - d2).days <= interval_days:
            streak += 1
        else:
            break
    return streak


# ── API publique ──────────────────────────────────────────────────────────────

def get_history(pss_type: str | None = None, limit: int = 20) -> list:
    """Retourne l'historique PSS (tous types si pss_type=None)."""
    return db.get_pss_records(pss_type=pss_type, limit=limit)


def get_latest_pss_score(pss_type: str = "full") -> dict | None:
    """Retourne le dernier enregistrement PSS du type donné, ou None."""
    records = db.get_pss_records(pss_type=pss_type, limit=1)
    return records[0] if records else None


def get_questions(is_short: bool = False) -> list:
    """Retourne les questions à afficher (PSS-10 ou PSS-4)."""
    if is_short:
        return [PSS10_QUESTIONS[i] for i in _PSS4_GLOBAL_INDICES]
    return PSS10_QUESTIONS
