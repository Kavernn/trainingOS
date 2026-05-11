"""
acwr.py — Acute:Chronic Workload Ratio (ACWR) — EWMA Engine
============================================================
Méthode : Exponentially Weighted Moving Average (Blanch & Gabbett, 2016)
Charge   : sRPE × durée (Foster 2001) ; fallback tonnage log-normalisé

Pourquoi EWMA > rolling average :
  - Pas de couplage mathématique entre acute et chronic (fenêtres indépendantes)
  - Pas d'effet falaise au bord des fenêtres
  - Décroissance naturelle les jours de repos via (1-λ)
  - Pondération exponentielle : données récentes plus pertinentes physiologiquement

Zones (Hulin et al. 2016) :
  < 0.8   → Sous-charge   (blue)
  0.8-1.3 → Optimal       (green)
  1.3-1.5 → Attention     (orange)
  > 1.5   → Surcharge     (red)
"""
from __future__ import annotations

import math
import statistics
from datetime import date as date_cls, timedelta
from typing import Optional

import db


# ─────────────────────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────────────────────

ACUTE_DAYS   = 7
CHRONIC_DAYS = 28
FETCH_DAYS   = 90        # Historique suffisant pour que l'EWMA converge
SPIKE_SIGMA  = 3.0       # Cap outliers à mean + N×σ
CHRONIC_FLOOR = 1.0      # Plancher pour éviter division par zéro
RATIO_MAX    = 3.0       # Clamp dur — ratio > 3.0 n'a pas de sens pratique

# λ = 2/(N+1) — formule standard EWMA
_LA = 2.0 / (ACUTE_DAYS + 1)    # 0.250  (half-life ≈ 2.4 j — fatigue neuromusculaire)
_LC = 2.0 / (CHRONIC_DAYS + 1)  # ≈0.069 (half-life ≈ 9.7 j — adaptation fitness)


# ─────────────────────────────────────────────────────────────
# CHARGE DE SÉANCE
# ─────────────────────────────────────────────────────────────

def _session_load(rpe: Optional[float], duration_min: Optional[float],
                  tonnage: Optional[float]) -> float:
    """
    Méthode primaire : Foster sRPE × durée (AU = Arbitrary Units).
    Validée en musculation (Day et al. 2004), agnostique de modalité.
    Exemples : RPE 7 × 60 min = 420 AU, RPE 9 × 45 min = 405 AU.

    Fallback : tonnage log-normalisé si sRPE/durée absents.
    """
    if rpe is not None and duration_min is not None and duration_min > 0:
        return float(rpe) * float(duration_min)
    if tonnage and tonnage > 0:
        return math.log1p(tonnage) * 10  # même ordre de grandeur que sRPE×durée
    return 0.0


# ─────────────────────────────────────────────────────────────
# FETCH SESSIONS
# ─────────────────────────────────────────────────────────────

def _fetch_sessions(days: int = FETCH_DAYS) -> list[dict]:
    """
    Récupère les séances des N derniers jours avec rpe, duration_min, session_volume.
    Inclut séances morning ET evening (is_second=True) pour ne rien manquer.
    """
    if db._client is None:
        return []
    try:
        cutoff = (date_cls.today() - timedelta(days=days)).isoformat()
        resp = (
            db._client.table("workout_sessions")
            .select("date, rpe, duration_min, session_volume")
            .gte("date", cutoff)
            .order("date", desc=False)
            .execute()
        )
        return resp.data or []
    except Exception as e:
        db.logger.warning("acwr: fetch_sessions error: %s", e)
        return []


# ─────────────────────────────────────────────────────────────
# EWMA ENGINE — FONCTIONS PURES
# ─────────────────────────────────────────────────────────────

def _aggregate_daily(rows: list[dict]) -> dict[str, float]:
    """Cumule les charges de toutes les séances d'un même jour."""
    daily: dict[str, float] = {}
    for r in rows:
        raw_date = r.get("date")
        if not raw_date:
            continue
        d = str(raw_date)[:10]
        load = _session_load(r.get("rpe"), r.get("duration_min"), r.get("session_volume"))
        daily[d] = daily.get(d, 0.0) + load
    return daily


def _spike_cap(loads: list[float]) -> Optional[float]:
    """
    Plafond anti-spike : mean + N×σ sur les charges non-nulles.
    Nécessite 5+ points pour ne pas sur-contraindre les débuts d'historique.
    """
    non_zero = [l for l in loads if l > 0]
    if len(non_zero) < 5:
        return None
    mu = statistics.mean(non_zero)
    sigma = statistics.stdev(non_zero)
    return mu + SPIKE_SIGMA * sigma


def _run_ewma(daily: dict[str, float]) -> list[dict]:
    """
    Calcule la série EWMA complète jour par jour.

    Règle de mise à jour :
        EWMA_t = λ × load_t + (1 − λ) × EWMA_{t−1}

    Jour de repos (load_t = 0) → décroissance naturelle : EWMA_t = (1−λ) × EWMA_{t−1}
    Les deux EWMAs (acute, chronic) sont entièrement indépendants — pas de couplage.
    """
    if not daily:
        return []

    sorted_dates = sorted(daily.keys())
    all_loads = list(daily.values())
    cap = _spike_cap(all_loads)

    ewma_a = ewma_c = 0.0
    results = []
    day_count = 0

    # Itère sur tous les jours calendaires (repos = 0)
    start = date_cls.fromisoformat(sorted_dates[0])
    end   = date_cls.today()
    current = start

    while current <= end:
        d_str = current.isoformat()
        raw_load = daily.get(d_str, 0.0)
        load = min(raw_load, cap) if cap and raw_load > 0 else raw_load
        day_count += 1

        # Mise à jour EWMA (Blanch & Gabbett 2016, Eq. 2)
        ewma_a = _LA * load + (1 - _LA) * ewma_a
        ewma_c = _LC * load + (1 - _LC) * ewma_c

        # Confiance selon l'historique disponible
        if day_count < ACUTE_DAYS:
            confidence = "low"
        elif day_count < CHRONIC_DAYS:
            confidence = "moderate"
        else:
            confidence = "high"

        # Ratio — neutre si base chronique insuffisante
        if ewma_c < CHRONIC_FLOOR or confidence == "low":
            ratio = 1.0
            zone_code = "insufficient_data"
        else:
            ratio = max(0.0, min(ewma_a / ewma_c, RATIO_MAX))
            zone_code = _zone_code(ratio)

        results.append({
            "date":        d_str,
            "acute_load":  round(ewma_a, 2),
            "chronic_load": round(ewma_c, 2),
            "ratio":       round(ratio, 3),
            "zone_code":   zone_code,
            "confidence":  confidence,
            "days_of_data": day_count,
        })

        current += timedelta(days=1)

    return results


# ─────────────────────────────────────────────────────────────
# ZONES
# ─────────────────────────────────────────────────────────────

_ZONE_META = {
    "insufficient_data": {
        "code": "insufficient_data", "label": "Données insuffisantes", "color": "#6B7280",
        "recommendation": "Continue à logger RPE + durée pour obtenir ton ratio ACWR.",
    },
    "under": {
        "code": "under", "label": "Sous-charge", "color": "#3B82F6",
        "recommendation": "Charge aiguë inférieure à la base chronique. Augmente progressivement volume ou intensité.",
    },
    "optimal": {
        "code": "optimal", "label": "Zone optimale", "color": "#10B981",
        "recommendation": "Équilibre charge aiguë/chronique idéal. Maintiens cette progression.",
    },
    "caution": {
        "code": "caution", "label": "Attention", "color": "#F59E0B",
        "recommendation": "Charge élevée. Priorise sommeil et récupération cette semaine.",
    },
    "danger": {
        "code": "danger", "label": "Surcharge", "color": "#EF4444",
        "recommendation": "Risque de surmenage. Réduis la charge ou planifie une semaine de décharge.",
    },
}


def _zone_code(ratio: float) -> str:
    if ratio < 0.8:   return "under"
    if ratio <= 1.3:  return "optimal"
    if ratio <= 1.5:  return "caution"
    return "danger"


def _zone_meta(code: str) -> dict:
    return _ZONE_META.get(code, _ZONE_META["insufficient_data"])


# ─────────────────────────────────────────────────────────────
# SNAPSHOTS HEBDOMADAIRES (sparkline)
# ─────────────────────────────────────────────────────────────

def _weekly_snapshots(series: list[dict], n_weeks: int = 8) -> list[dict]:
    """
    Dernier point EWMA de chaque semaine ISO → trend sparkline stable.
    Un seul point bruité ne déforme pas la tendance.
    """
    by_week: dict[str, dict] = {}
    for pt in series:
        d = date_cls.fromisoformat(pt["date"])
        iso = d.isocalendar()
        key = f"{iso[0]}-W{iso[1]:02d}"
        by_week[key] = pt  # Garde le dernier jour de la semaine

    last_n = sorted(by_week.items())[-n_weeks:]
    return [
        {
            "week":    f"W{i + 1}",
            "ratio":   pt["ratio"],
            "acute":   round(pt["acute_load"]),
            "chronic": round(pt["chronic_load"]),
        }
        for i, (_, pt) in enumerate(last_n)
    ]


# ─────────────────────────────────────────────────────────────
# POINT D'ENTRÉE PUBLIC
# ─────────────────────────────────────────────────────────────

def calc_acwr() -> dict:
    """
    Calcule l'ACWR EWMA courant et retourne la réponse API complète.

    Champs retournés :
      ratio, acute_load, chronic_load  — valeurs EWMA du jour
      zone                             — {code, label, color, recommendation}
      trend                            — 8 snapshots hebdomadaires
      confidence                       — "low" | "moderate" | "high"
      days_of_data                     — nombre de jours de données
    """
    rows  = _fetch_sessions(FETCH_DAYS)
    daily = _aggregate_daily(rows)
    series = _run_ewma(daily)

    if not series:
        meta = _zone_meta("insufficient_data")
        return {
            "ratio": 0.0, "acute_load": 0.0, "chronic_load": 0.0,
            "zone": meta, "trend": [],
            "confidence": "low", "days_of_data": 0,
        }

    latest = series[-1]
    meta   = _zone_meta(latest["zone_code"])

    return {
        "ratio":        latest["ratio"],
        "acute_load":   latest["acute_load"],
        "chronic_load": latest["chronic_load"],
        "zone":         meta,
        "trend":        _weekly_snapshots(series),
        "confidence":   latest["confidence"],
        "days_of_data": latest["days_of_data"],
    }
