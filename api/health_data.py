"""
health_data.py — Agrégateur de métriques santé.

Sources supportées :
  - manual       : saisies manuelles (recovery_log, body_weight, nutrition_log, sessions)
  - healthkit    : capteurs iOS (steps, sommeil, HR, HRV, workouts via HealthKit)
  - wearable     : placeholder — Garmin Connect, Strava, Fitbit (non implémenté)

Les données sont stockées dans les clés KV existantes via db.py.
Ce module fusionne ces sources en un objet quotidien unifié sans créer de
nouvelles clés de stockage (agrégation à la volée).

Endpoints exposés dans index.py :
  GET /api/health/daily_summary?date=YYYY-MM-DD
  GET /api/health/weekly_summary?days=7
"""
from __future__ import annotations

from datetime import date as date_cls, timedelta
from typing import Optional

import db
from body_weight import load_body_weight
from sessions    import load_sessions


def _load_recovery_log() -> list:
    return db.get_recovery_logs() or []

def _load_cardio_log() -> list:
    return db.get_cardio_logs() or []


# ── Score de récupération (0 – 10) ──────────────────────────────────────────

def compute_recovery_score(entry: dict) -> Optional[float]:
    """
    Score composite basé sur les métriques de récupération disponibles.

    Composantes (pondérées) :
      - Qualité du sommeil   : 0-10          (poids 1.0)
      - Durée du sommeil     : objectif 8 h  (poids 1.0, normalisé 0-10)
      - Douleurs musculaires : inversé       (poids 1.0, 10-soreness)
      - HRV                  : réf. 60 ms   (poids 0.5, normalisé 0-10)

    Retourne None si aucune donnée.
    """
    score, weight = 0.0, 0.0

    if (sq := entry.get("sleep_quality")) is not None:
        score += float(sq) * 1.0;  weight += 1.0

    if (sh := entry.get("sleep_hours")) is not None:
        score += min(float(sh) / 8.0 * 10, 10) * 1.0;  weight += 1.0

    if (s := entry.get("soreness")) is not None:
        score += (10.0 - float(s)) * 1.0;  weight += 1.0

    if (hrv := entry.get("hrv")) is not None:
        score += min(float(hrv) / 60.0 * 10, 10) * 0.5;  weight += 0.5

    return round(score / weight, 1) if weight > 0 else None


# ── Totaux nutritionnels pour une date ───────────────────────────────────────

def _nutrition_totals(target_date: str) -> dict:
    """Calcule les macros totales du jour depuis nutrition_entries."""
    entries = db.get_nutrition_entries(target_date)
    if not entries:
        return {}
    return {
        "calories": round(sum(e.get("calories",  0) for e in entries)),
        "protein":  round(sum(e.get("proteines", 0) for e in entries), 1),
        "carbs":    round(sum(e.get("glucides",  0) for e in entries), 1),
        "fat":      round(sum(e.get("lipides",   0) for e in entries), 1),
        "meals":    len(entries),
    }


# ── Agrégation principale ─────────────────────────────────────────────────────

def merge_health_metrics(target_date: str) -> dict:
    """
    Fusionne toutes les sources de données santé pour une date donnée.

    Retourne un dict quotidien unifié. Les clés absentes sont omises
    (pas de valeur null — le client gère l'absence de clé).

    Structure de retour :
    {
      "date": "YYYY-MM-DD",
      "data_sources": ["manual", "healthkit"],

      # Capteurs / wearable
      "steps": int,
      "sleep_duration": float,       # heures
      "sleep_quality": float,        # 0-10
      "resting_heart_rate": float,   # bpm
      "hrv": float,                  # ms SDNN
      "soreness": float,             # 0-10
      "recovery_score": float,       # 0-10 composite
      "heart_rate_avg": float,       # bpm pendant cardio

      # Composition corporelle
      "body_weight": float,
      "body_fat_pct": float,
      "waist_cm": float,

      # Cardio
      "distance_km": float,
      "active_minutes": float,
      "pace": str,                   # "mm:ss/km"
      "cardio_type": str,
      "cardio_calories": float,

      # Entraînement muscu
      "training_rpe": float,
      "training_duration_min": float,
      "training_energy_pre": int,    # 1-5
      "training_exercises": [str],

      # Nutrition
      "calories": int,
      "protein": float,              # g
      "carbs": float,                # g
      "fat": float,                  # g
      "meals": int,
    }
    """
    result: dict = {"date": target_date, "data_sources": []}

    # ── Récupération ─────────────────────────────────────────────────────────
    rec_log = _load_recovery_log()
    rec = next((e for e in rec_log if e.get("date") == target_date), None)
    if rec:
        _set_if(result, "steps",              rec.get("steps"))
        _set_if(result, "sleep_duration",     rec.get("sleep_hours"))
        _set_if(result, "sleep_quality",      rec.get("sleep_quality"))
        _set_if(result, "resting_heart_rate", rec.get("resting_hr"))
        _set_if(result, "hrv",                rec.get("hrv"))
        _set_if(result, "soreness",           rec.get("soreness"))
        score = compute_recovery_score(rec)
        if score is not None:
            result["recovery_score"] = score
        _add_source(result, "manual")

    # ── Composition corporelle ────────────────────────────────────────────────
    bw_log = load_body_weight()
    bw = next((e for e in bw_log if e.get("date") == target_date), None)
    if bw:
        _set_if(result, "body_weight",  bw.get("poids"))
        _set_if(result, "body_fat_pct", bw.get("body_fat"))
        _set_if(result, "waist_cm",     bw.get("waist_cm"))
        _add_source(result, "manual")

    # ── Cardio ────────────────────────────────────────────────────────────────
    cardio_log = _load_cardio_log()
    cardio = next((e for e in cardio_log if e.get("date") == target_date), None)
    if cardio:
        _set_if(result, "distance_km",     cardio.get("distance_km"))
        _set_if(result, "active_minutes",  cardio.get("duration_min"))
        _set_if(result, "heart_rate_avg",  cardio.get("avg_hr"))
        _set_if(result, "pace",            cardio.get("avg_pace"))
        _set_if(result, "cardio_type",     cardio.get("type"))
        _set_if(result, "cardio_calories", cardio.get("calories"))
        # Les sessions importées depuis HealthKit portent source="healthkit"
        src = "healthkit" if cardio.get("source") == "healthkit" else "manual"
        _add_source(result, src)

    # ── Séance de musculation ─────────────────────────────────────────────────
    sessions = load_sessions()
    session  = sessions.get(target_date)
    if session:
        _set_if(result, "training_rpe",          session.get("rpe"))
        _set_if(result, "training_duration_min", session.get("duration_min"))
        _set_if(result, "training_energy_pre",   session.get("energy_pre"))
        _set_if(result, "training_exercises",    session.get("exos"))
        _add_source(result, "manual")

    # ── Nutrition ─────────────────────────────────────────────────────────────
    nutr = _nutrition_totals(target_date)
    if nutr:
        result.update(nutr)
        _add_source(result, "manual")

    # ── Placeholder wearables ─────────────────────────────────────────────────
    # Garmin Connect  : GET https://connectapi.garmin.com/wellness-api/wellness/dailies/{userId}/{date}
    #   → steps, distance, active_minutes, resting_hr, average_stress_level
    # Strava          : GET https://www.strava.com/api/v3/activities?after={epoch}&before={epoch}
    #   → distance, elapsed_time, average_heartrate, average_cadence
    # Fitbit          : GET https://api.fitbit.com/1/user/-/activities/date/{date}.json
    #   → steps, distance, active_minutes, calories
    # Apple Watch     : déjà couvert par HealthKit (HealthKitService.swift)
    #
    # Pour activer : implémenter WearableConnector.fetch(target_date) et décommenter :
    # wearable = WearableConnector.fetch(target_date)
    # if wearable:
    #     for k, v in wearable.items():
    #         result.setdefault(k, v)   # ne pas écraser les données manuelles
    #     _add_source(result, "wearable")

    return result


# ── API publique ──────────────────────────────────────────────────────────────

def get_daily_health_summary(target_date: str | None = None) -> dict:
    """Résumé santé unifié pour une date (défaut = aujourd'hui)."""
    if target_date is None:
        target_date = date_cls.today().isoformat()
    return merge_health_metrics(target_date)


def get_weekly_health_summary(days: int = 7) -> list[dict]:
    """Résumés des `days` derniers jours, du plus récent au plus ancien."""
    today = date_cls.today()
    return [
        merge_health_metrics((today - timedelta(days=i)).isoformat())
        for i in range(days)
    ]


# ── Helpers ───────────────────────────────────────────────────────────────────

def _set_if(d: dict, key: str, value) -> None:
    """Ajoute la clé au dict seulement si value n'est pas None."""
    if value is not None:
        d[key] = value

def _add_source(d: dict, source: str) -> None:
    if source not in d["data_sources"]:
        d["data_sources"].append(source)
