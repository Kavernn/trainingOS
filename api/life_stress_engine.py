"""
life_stress_engine.py — Moteur de score de stress de vie quotidien.

Le Life Stress Score (LSS) reflète l'état global de récupération et de stress
d'un athlète, en combinant des indicateurs physiologiques et d'entraînement.

Score : 0 = stress maximal / surmenage  →  100 = récupération optimale

Composantes pondérées :
  - Qualité du sommeil   : poids 0.30  (sleep_quality 0-10, normalisé)
  - Tendance HRV         : poids 0.25  (variation HRV sur 7 j)
  - Tendance FC repos    : poids 0.20  (variation RHR sur 7 j)
  - Stress subjectif     : poids 0.15  (soreness inversé)
  - Fatigue entraînement : poids 0.10  (RPE moyen des 3 dernières séances)

Flags de détection :
  - hrv_drop        : HRV du jour < moyenne 7 j - 1 écart type
  - sleep_deprivation : < 6 h ou qualité < 5
  - training_overload : RPE moyen 3 séances ≥ 8.5

Stockage : clé KV "life_stress_scores" → dict {date: score_entry}

Endpoints exposés dans index.py :
  GET /api/life_stress/score?date=YYYY-MM-DD
  GET /api/life_stress/trend?days=7
"""
from __future__ import annotations

import math
from datetime import date as date_cls, timedelta
from typing import Optional

import db
from health_data  import _load_recovery_log
from sessions     import load_sessions
from deload       import detect_fatigue_rpe
from pss          import get_latest_pss_score


# ── Constantes ────────────────────────────────────────────────────────────────

_KV_KEY            = "life_stress_scores"
_HRV_REFERENCE     = 60.0   # ms SDNN — référence populaire générale
_RHR_REFERENCE     = 55.0   # bpm — bonne forme cardiovasculaire
_RPE_FATIGUE_THRESH = 8.5
_SLEEP_DEPRIVATION_HOURS = 6.0
_SLEEP_DEPRIVATION_QUALITY = 5.0


# ── Helpers ───────────────────────────────────────────────────────────────────

def _clamp(value: float, lo: float = 0.0, hi: float = 100.0) -> float:
    return max(lo, min(hi, value))


def _rec_entry_for(target_date: str) -> Optional[dict]:
    """Retourne l'entrée recovery_log pour une date donnée, ou None."""
    log = _load_recovery_log()
    return next((e for e in log if e.get("date") == target_date), None)

def _recent_rec_entries(days: int) -> list[dict]:
    """Retourne les entrées recovery_log des `days` derniers jours (date DESC)."""
    today = date_cls.today()
    dates = {(today - timedelta(days=i)).isoformat() for i in range(days)}
    log   = _load_recovery_log()
    entries = [e for e in log if e.get("date") in dates]
    return sorted(entries, key=lambda e: e.get("date", ""), reverse=True)


# ── Détection de flags ─────────────────────────────────────────────────────────

def detect_hrv_drop(target_date: str) -> bool:
    """
    Vrai si la HRV du jour est inférieure à (moyenne 7 j − 1 écart type).
    Nécessite au moins 3 jours de données pour être significatif.
    """
    today     = date_cls.fromisoformat(target_date)
    window    = [(today - timedelta(days=i)).isoformat() for i in range(1, 8)]
    log       = _load_recovery_log()
    log_by_date = {e["date"]: e for e in log if "date" in e}

    past_hrvs = [
        float(log_by_date[d]["hrv"])
        for d in window
        if d in log_by_date and log_by_date[d].get("hrv") is not None
    ]
    if len(past_hrvs) < 3:
        return False

    mean = sum(past_hrvs) / len(past_hrvs)
    std  = math.sqrt(sum((x - mean) ** 2 for x in past_hrvs) / len(past_hrvs))

    today_entry = log_by_date.get(target_date)
    if not today_entry or today_entry.get("hrv") is None:
        return False

    return float(today_entry["hrv"]) < (mean - std)


def detect_sleep_deprivation(target_date: str) -> bool:
    """Vrai si la durée de sommeil < 6 h OU la qualité < 5."""
    entry = _rec_entry_for(target_date)
    if not entry:
        return False
    hours   = entry.get("sleep_hours")
    quality = entry.get("sleep_quality")
    if hours is not None and float(hours) < _SLEEP_DEPRIVATION_HOURS:
        return True
    if quality is not None and float(quality) < _SLEEP_DEPRIVATION_QUALITY:
        return True
    return False


def detect_training_overload() -> bool:
    """Vrai si le RPE moyen des 3 dernières séances ≥ 8.5 (réutilise deload.py)."""
    return detect_fatigue_rpe().get("fatigue", False)


# ── Calcul du score ───────────────────────────────────────────────────────────

def _score_sleep_quality(entry: dict) -> Optional[float]:
    """Normalise sleep_quality (0-10) → 0-100."""
    sq = entry.get("sleep_quality")
    if sq is None:
        return None
    return _clamp(float(sq) * 10.0)


def _score_hrv_trend(target_date: str) -> Optional[float]:
    """
    Compare HRV du jour à la moyenne des 7 jours précédents.
    Score 100 = au-dessus ou égal à la moyenne.
    Score 0   = HRV du jour = 0.
    """
    today     = date_cls.fromisoformat(target_date)
    window    = [(today - timedelta(days=i)).isoformat() for i in range(1, 8)]
    log_by_date = {e["date"]: e for e in _load_recovery_log() if "date" in e}

    today_entry = log_by_date.get(target_date)
    if not today_entry or today_entry.get("hrv") is None:
        return None

    today_hrv = float(today_entry["hrv"])
    past_hrvs = [
        float(log_by_date[d]["hrv"])
        for d in window
        if d in log_by_date and log_by_date[d].get("hrv") is not None
    ]
    baseline = sum(past_hrvs) / len(past_hrvs) if past_hrvs else _HRV_REFERENCE

    if baseline <= 0:
        return None
    return _clamp((today_hrv / baseline) * 100.0)


def _score_rhr_trend(target_date: str) -> Optional[float]:
    """
    Compare FC repos du jour à la moyenne des 7 jours précédents.
    FC plus basse = meilleure récupération → score plus élevé.
    Score 100 si FC ≤ baseline ; dégradation proportionnelle si FC > baseline.
    """
    today     = date_cls.fromisoformat(target_date)
    window    = [(today - timedelta(days=i)).isoformat() for i in range(1, 8)]
    log_by_date = {e["date"]: e for e in _load_recovery_log() if "date" in e}

    today_entry = log_by_date.get(target_date)
    if not today_entry or today_entry.get("resting_hr") is None:
        return None

    today_rhr = float(today_entry["resting_hr"])
    past_rhrs = [
        float(log_by_date[d]["resting_hr"])
        for d in window
        if d in log_by_date and log_by_date[d].get("resting_hr") is not None
    ]
    baseline = sum(past_rhrs) / len(past_rhrs) if past_rhrs else _RHR_REFERENCE

    if baseline <= 0:
        return None
    # Pénalité proportionnelle si RHR > baseline
    delta_pct = (today_rhr - baseline) / baseline  # positif = mauvais
    return _clamp(100.0 - delta_pct * 200.0)       # -200 % pour chaque % d'augmentation


def _score_subjective_stress(entry: dict) -> Optional[float]:
    """
    Stress subjectif → 0-100 (100 = pas de stress).

    Priorité :
      1. Score PSS récent (≤ 30 jours) : normalisé depuis 0-40 (PSS-10) ou 0-16 (PSS-4).
         PSS élevé = stress élevé → LSS component bas.
      2. Fallback : soreness inversé depuis recovery_log.
    """
    from datetime import date as date_cls, timedelta
    pss = get_latest_pss_score("full") or get_latest_pss_score("short")
    if pss:
        try:
            pss_date = date_cls.fromisoformat(pss["date"])
            if (date_cls.today() - pss_date).days <= 30:
                score  = float(pss["score"])
                max_s  = float(pss.get("max_score", 40))
                # PSS 0 = pas de stress → LSS 100 ; PSS max = stress max → LSS 0
                return _clamp((1.0 - score / max_s) * 100.0)
        except (KeyError, ValueError):
            pass

    # Fallback soreness
    soreness = entry.get("soreness")
    if soreness is None:
        return None
    return _clamp((10.0 - float(soreness)) * 10.0)


def _score_training_fatigue() -> Optional[float]:
    """RPE moyen 3 séances → 0-100. RPE 10 = score 0 ; RPE 0 = score 100."""
    result = detect_fatigue_rpe()
    rpe_moyen = result.get("rpe_moyen")
    if rpe_moyen is None:
        return None
    return _clamp((10.0 - rpe_moyen) * 10.0)


def compute_life_stress_score(target_date: str) -> dict:
    """
    Calcule le Life Stress Score composite pour une date donnée.

    Retourne un dict complet stockable et exposable via API :
    {
      "date":               "YYYY-MM-DD",
      "score":              float (0-100),
      "components": {
        "sleep_quality":      float | null,
        "hrv_trend":          float | null,
        "rhr_trend":          float | null,
        "subjective_stress":  float | null,
        "training_fatigue":   float | null,
      },
      "flags": {
        "hrv_drop":           bool,
        "sleep_deprivation":  bool,
        "training_overload":  bool,
      },
      "recommendations":    [str],
      "data_coverage":      float  (0-1, proportion de composantes disponibles)
    }
    """
    entry = _rec_entry_for(target_date)
    if entry is None:
        entry = {}

    # ── Composantes ───────────────────────────────────────────────────────────
    weights = {
        "sleep_quality":     0.30,
        "hrv_trend":         0.25,
        "rhr_trend":         0.20,
        "subjective_stress": 0.15,
        "training_fatigue":  0.10,
    }
    raw = {
        "sleep_quality":     _score_sleep_quality(entry),
        "hrv_trend":         _score_hrv_trend(target_date),
        "rhr_trend":         _score_rhr_trend(target_date),
        "subjective_stress": _score_subjective_stress(entry),
        "training_fatigue":  _score_training_fatigue(),
    }

    # Pondération normalisée sur les composantes disponibles uniquement
    available   = {k: v for k, v in raw.items() if v is not None}
    total_weight = sum(weights[k] for k in available)

    if total_weight > 0:
        score = sum(available[k] * weights[k] for k in available) / total_weight
    else:
        score = 50.0  # pas de données — score neutre

    score = round(_clamp(score), 1)

    # ── Flags ─────────────────────────────────────────────────────────────────
    flags = {
        "hrv_drop":          detect_hrv_drop(target_date),
        "sleep_deprivation": detect_sleep_deprivation(target_date),
        "training_overload": detect_training_overload(),
    }

    # ── Recommandations ───────────────────────────────────────────────────────
    recommendations: list[str] = []
    if score < 40:
        recommendations.append("Journée de repos actif recommandée — ton corps réclame de la récupération.")
    elif score < 60:
        recommendations.append("Entraînement léger conseillé — préfère mobilité ou cardio faible intensité.")
    if flags["hrv_drop"]:
        recommendations.append("Chute de HRV détectée — évite les efforts maximaux aujourd'hui.")
    if flags["sleep_deprivation"]:
        recommendations.append("Manque de sommeil — privilégie une récupération nocturne de 7-9 h.")
    if flags["training_overload"]:
        recommendations.append("RPE élevé sur les dernières séances — considère une semaine de deload.")
    if not recommendations and score >= 80:
        recommendations.append("Récupération optimale — tu peux performer à ton maximum aujourd'hui.")

    data_coverage = round(len(available) / len(weights), 2)

    return {
        "date":          target_date,
        "score":         score,
        "components":    raw,
        "flags":         flags,
        "recommendations": recommendations,
        "data_coverage": data_coverage,
    }


# ── Stockage + cache ──────────────────────────────────────────────────────────

def get_life_stress_score(target_date: str | None = None) -> dict:
    """
    Retourne le LSS pour une date (calcule et met en cache si absent).
    Par défaut : aujourd'hui.
    """
    if target_date is None:
        target_date = date_cls.today().isoformat()

    cached = db.get_life_stress_score_db(target_date)
    if cached:
        return cached

    result = compute_life_stress_score(target_date)
    db.upsert_life_stress_score(result)
    return result


def refresh_life_stress_score(target_date: str | None = None) -> dict:
    """Force le recalcul et met à jour le cache pour une date."""
    if target_date is None:
        target_date = date_cls.today().isoformat()
    result = compute_life_stress_score(target_date)
    db.upsert_life_stress_score(result)
    return result


def get_recent_life_stress_trend(days: int = 7) -> list[dict]:
    """
    Retourne les LSS des `days` derniers jours (du plus récent au plus ancien).
    Calcule les scores manquants à la volée.
    """
    today = date_cls.today()
    trend = []

    for i in range(days):
        d = (today - timedelta(days=i)).isoformat()
        entry = db.get_life_stress_score_db(d)
        if not entry:
            entry = compute_life_stress_score(d)
            db.upsert_life_stress_score(entry)
        trend.append(entry)

    return trend
