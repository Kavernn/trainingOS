"""
dass.py — DASS-21 (Depression Anxiety Stress Scales — 21 items).

Référence : Lovibond & Lovibond (1995). Psychology Department, UNSW.
Version française validée : Chronbach α > 0.88 pour chaque sous-échelle.

Scoring :
  Chaque item : 0 (jamais) → 3 (presque toujours)
  Sous-score  : somme des 7 items × 2
  Pro referral: si Dépression ≥ Sévère OU Anxiété ≥ Sévère OU Stress ≥ Sévère

Fréquence recommandée : 1 fois / mois.

Endpoints exposés dans wellness_stress.py :
  POST /api/dass/submit
  GET  /api/dass/history
  GET  /api/dass/check_due
"""
from __future__ import annotations

import uuid
from datetime import date as date_cls, timedelta
from typing import Optional

import db
from utils import _today_mtl

# ── Questions DASS-21 (version française validée) ────────────────────────────

DASS21_QUESTIONS = [
    {"id":  1, "text": "Il m'a été difficile de me calmer.",                                                      "subscale": "stress"},
    {"id":  2, "text": "J'ai eu la bouche sèche.",                                                                 "subscale": "anxiety"},
    {"id":  3, "text": "Je n'ai pas pu ressentir d'émotions positives.",                                           "subscale": "depression"},
    {"id":  4, "text": "J'ai eu des difficultés à respirer.",                                                      "subscale": "anxiety"},
    {"id":  5, "text": "Il m'a été difficile de prendre des initiatives.",                                         "subscale": "depression"},
    {"id":  6, "text": "J'ai eu tendance à réagir excessivement.",                                                 "subscale": "stress"},
    {"id":  7, "text": "J'ai eu des tremblements (ex: mains).",                                                    "subscale": "anxiety"},
    {"id":  8, "text": "Je me suis senti(e) très nerveux(se).",                                                    "subscale": "stress"},
    {"id":  9, "text": "Je me suis inquiété(e) de situations où je pourrais paniquer.",                           "subscale": "anxiety"},
    {"id": 10, "text": "Je n'avais rien à attendre de positif.",                                                   "subscale": "depression"},
    {"id": 11, "text": "Je me suis senti(e) agité(e).",                                                           "subscale": "stress"},
    {"id": 12, "text": "Il m'a été difficile de me relaxer.",                                                     "subscale": "stress"},
    {"id": 13, "text": "Je me suis senti(e) abattu(e) et triste.",                                                "subscale": "depression"},
    {"id": 14, "text": "Je n'ai pas toléré les obstacles qui m'empêchaient d'avancer.",                           "subscale": "stress"},
    {"id": 15, "text": "Je me suis senti(e) sur le point de paniquer.",                                           "subscale": "anxiety"},
    {"id": 16, "text": "Je n'ai pu ressentir d'enthousiasme pour rien.",                                          "subscale": "depression"},
    {"id": 17, "text": "Je me suis senti(e) sans grande valeur.",                                                 "subscale": "depression"},
    {"id": 18, "text": "Je me suis senti(e) assez susceptible.",                                                  "subscale": "stress"},
    {"id": 19, "text": "J'ai senti mon cœur battre fort sans effort physique.",                                   "subscale": "anxiety"},
    {"id": 20, "text": "J'ai eu peur sans raison valable.",                                                       "subscale": "anxiety"},
    {"id": 21, "text": "J'ai eu la sensation que la vie n'avait pas de sens.",                                    "subscale": "depression"},
]

# Indices 0-based par sous-échelle
_DEPRESSION_IDX = [i for i, q in enumerate(DASS21_QUESTIONS) if q["subscale"] == "depression"]  # [2,4,9,12,15,16,20]
_ANXIETY_IDX    = [i for i, q in enumerate(DASS21_QUESTIONS) if q["subscale"] == "anxiety"]     # [1,3,6,8,14,18,19]
_STRESS_IDX     = [i for i, q in enumerate(DASS21_QUESTIONS) if q["subscale"] == "stress"]      # [0,5,7,10,11,13,17]

_INTERVAL_DAYS = 28  # mensuel

# ── Seuils (après × 2) ────────────────────────────────────────────────────────

_DEPRESSION_THRESHOLDS = [
    (10,  "normal",   "Normal"),
    (14,  "mild",     "Léger"),
    (21,  "moderate", "Modéré"),
    (28,  "severe",   "Sévère"),
    (999, "extreme",  "Extrême"),
]

_ANXIETY_THRESHOLDS = [
    (8,   "normal",   "Normal"),
    (10,  "mild",     "Léger"),
    (15,  "moderate", "Modéré"),
    (20,  "severe",   "Sévère"),
    (999, "extreme",  "Extrême"),
]

_STRESS_THRESHOLDS = [
    (15,  "normal",   "Normal"),
    (19,  "mild",     "Léger"),
    (26,  "moderate", "Modéré"),
    (34,  "severe",   "Sévère"),
    (999, "extreme",  "Extrême"),
]


def _categorize(score: int, thresholds: list) -> tuple[str, str]:
    for ceiling, key, label in thresholds:
        if score < ceiling:
            return key, label
    return thresholds[-1][1], thresholds[-1][2]


# ── Scoring ───────────────────────────────────────────────────────────────────

def calculate_dass_score(responses: list[int]) -> dict:
    """
    Calcule les trois sous-scores DASS-21.

    Paramètres :
      responses : liste de 21 entiers [0-3].

    Retourne :
      {
        "depression_raw":      int,   # 0-21 (somme brute)
        "anxiety_raw":         int,
        "stress_raw":          int,
        "depression_score":    int,   # raw × 2 (0-42)
        "anxiety_score":       int,
        "stress_score":        int,
        "depression_category": str,   # "normal" | "mild" | "moderate" | "severe" | "extreme"
        "anxiety_category":    str,
        "stress_category":     str,
        "depression_label":    str,   # "Normal" | "Léger" | ...
        "anxiety_label":       str,
        "stress_label":        str,
        "pro_referral":        bool,
      }
    """
    if not isinstance(responses, list) or len(responses) != 21:
        raise ValueError("dass: 21 réponses requises.")
    if not all(isinstance(r, int) and 0 <= r <= 3 for r in responses):
        raise ValueError("dass: chaque réponse doit être un entier entre 0 et 3.")

    dep_raw  = sum(responses[i] for i in _DEPRESSION_IDX)
    anx_raw  = sum(responses[i] for i in _ANXIETY_IDX)
    str_raw  = sum(responses[i] for i in _STRESS_IDX)

    dep_score = dep_raw * 2
    anx_score = anx_raw * 2
    str_score = str_raw * 2

    dep_cat, dep_lbl = _categorize(dep_score, _DEPRESSION_THRESHOLDS)
    anx_cat, anx_lbl = _categorize(anx_score, _ANXIETY_THRESHOLDS)
    str_cat, str_lbl = _categorize(str_score, _STRESS_THRESHOLDS)

    pro_referral = any(c in ("severe", "extreme") for c in (dep_cat, anx_cat, str_cat))

    return {
        "depression_raw":      dep_raw,
        "anxiety_raw":         anx_raw,
        "stress_raw":          str_raw,
        "depression_score":    dep_score,
        "anxiety_score":       anx_score,
        "stress_score":        str_score,
        "depression_category": dep_cat,
        "anxiety_category":    anx_cat,
        "stress_category":     str_cat,
        "depression_label":    dep_lbl,
        "anxiety_label":       anx_lbl,
        "stress_label":        str_lbl,
        "pro_referral":        pro_referral,
    }


# ── Stockage ──────────────────────────────────────────────────────────────────

def save_dass_record(responses: list[int], notes: Optional[str] = None) -> dict:
    """Calcule et persiste un enregistrement DASS-21."""
    result = calculate_dass_score(responses)

    record = {
        "id":                   str(uuid.uuid4()),
        "date":                 _today_mtl(),
        "responses":            responses,
        "depression_raw":       result["depression_raw"],
        "anxiety_raw":          result["anxiety_raw"],
        "stress_raw":           result["stress_raw"],
        "depression_score":     result["depression_score"],
        "anxiety_score":        result["anxiety_score"],
        "stress_score":         result["stress_score"],
        "depression_category":  result["depression_category"],
        "anxiety_category":     result["anxiety_category"],
        "stress_category":      result["stress_category"],
        "pro_referral":         result["pro_referral"],
        "notes":                notes,
        "insights":             _generate_insights(result),
    }

    db.insert_dass_record(record)
    return record


# ── Fréquence ─────────────────────────────────────────────────────────────────

def check_due() -> dict:
    """Vérifie si un DASS-21 est dû (mensuel)."""
    records = db.get_dass_records(limit=1)

    if not records:
        return {
            "is_due":          True,
            "days_since_last": None,
            "next_due_date":   None,
            "message":         "Établis ton bilan psychologique de base — 5 min pour le DASS-21.",
        }

    last  = date_cls.fromisoformat(records[0]["date"])
    today = date_cls.fromisoformat(_today_mtl())
    delta = (today - last).days
    next_due = (last + timedelta(days=_INTERVAL_DAYS)).isoformat()

    return {
        "is_due":          delta >= _INTERVAL_DAYS,
        "days_since_last": delta,
        "next_due_date":   next_due,
        "message":         f"Ça fait {delta} jours — temps de refaire le bilan DASS-21 ? (5 min)" if delta >= _INTERVAL_DAYS else None,
    }


def get_history(limit: int = 12) -> list:
    return db.get_dass_records(limit=limit)


def get_latest() -> Optional[dict]:
    records = db.get_dass_records(limit=1)
    return records[0] if records else None


# ── Insights ──────────────────────────────────────────────────────────────────

def _generate_insights(result: dict) -> list[str]:
    insights = []

    dep_lbl = result["depression_label"]
    anx_lbl = result["anxiety_label"]
    str_lbl = result["stress_label"]

    insights.append(f"Dépression : {dep_lbl} ({result['depression_score']}/42) · Anxiété : {anx_lbl} ({result['anxiety_score']}/42) · Stress : {str_lbl} ({result['stress_score']}/42)")

    worst_score = max(result["depression_score"], result["anxiety_score"], result["stress_score"])
    worst_cat   = max(
        ("depression", result["depression_score"]),
        ("anxiety",    result["anxiety_score"]),
        ("stress",     result["stress_score"]),
        key=lambda x: x[1],
    )[0]

    if worst_score < 10:
        insights.append("Toutes tes dimensions sont dans la norme — maintiens tes routines de récupération.")
    elif worst_score < 20:
        insights.append(
            f"Tension légère à modérée — normal en période de charge. "
            "Entraînement modéré, sommeil et connexion sociale aident à réguler."
        )
    else:
        labels = {"depression": "l'humeur", "anxiety": "l'anxiété", "stress": "le stress"}
        insights.append(
            f"Score élevé sur {labels.get(worst_cat, 'une dimension')}. "
            "C'est un signal à prendre au sérieux — pas à ignorer."
        )

    if result["pro_referral"]:
        insights.append(
            "Score sévère ou extrême détecté. Il est recommandé de consulter un professionnel de santé "
            "(médecin, psychologue ou thérapeute) — ce score dépasse ce que les outils de bien-être seuls peuvent adresser."
        )

    return insights


# ── Questions ─────────────────────────────────────────────────────────────────

def get_questions() -> list:
    return DASS21_QUESTIONS
