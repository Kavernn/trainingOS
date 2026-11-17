"""
acwr.py — Acute:Chronic Workload Ratio (ACWR) — EWMA Engine
============================================================
Méthode : Exponentially Weighted Moving Average (Blanch & Gabbett, 2016)
Charge   : session_load() — sRPE × durée (Foster 2001) → RPE réel des séries × durée →
           tonnage calibré (estimation) → None (séance exclue, jamais comptée 0)

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
from utils import _today_mtl


# ─────────────────────────────────────────────────────────────
# CONFIGURATION
# ─────────────────────────────────────────────────────────────

ACUTE_DAYS   = 7
CHRONIC_DAYS = 28
FETCH_DAYS   = 90        # Historique suffisant pour que l'EWMA converge
SPIKE_SIGMA  = 3.0       # Cap outliers à mean + N×σ
CHRONIC_FLOOR = 1.0      # Plancher pour éviter division par zéro
RATIO_MAX    = 3.0       # Clamp dur — ratio > 3.0 n'a pas de sens pratique

# ── session_load : sources de données (Build H) ──────────────────────────────
# Étape 2 (RPE moyen des séries) : fiable SEULEMENT pour les séances datées à partir de ce jour.
# Avant le commit iOS 8ea233f7 (2026-11-17 18:11), chaque série non saisie partait avec
# rir=3 / rpe=7 inventés : ces RPE de séries ne doivent jamais alimenter une charge.
REAL_SET_RPE_SINCE = "2026-11-18"
# Étape 3 (tonnage) : k = médiane(sRPE×durée / tonnage) sur une fenêtre RÉCENTE (l'historique
# ancien contient des RPE 7 par défaut). Moins de K_MIN_SESSIONS paires → repli log1p (estimation).
K_WINDOW_DAYS  = 60
K_MIN_SESSIONS = 5

# λ = 2/(N+1) — formule standard EWMA
_LA = 2.0 / (ACUTE_DAYS + 1)    # 0.250  (half-life ≈ 2.4 j — fatigue neuromusculaire)
_LC = 2.0 / (CHRONIC_DAYS + 1)  # ≈0.069 (half-life ≈ 9.7 j — adaptation fitness)


# ─────────────────────────────────────────────────────────────
# CHARGE DE SÉANCE
# ─────────────────────────────────────────────────────────────

def session_load(rpe: Optional[float], duration_min: Optional[float],
                 tonnage: Optional[float], set_rpe_mean: Optional[float] = None,
                 k: Optional[float] = None) -> Optional[float]:
    """
    Charge d'une séance (AU). Données réelles d'abord, estimation explicite ensuite.
      1. sRPE × durée (Foster) — RPE de séance réel. Ex. RPE 7 × 60 min = 420 AU.
      2. RPE moyen des séries réellement saisies × durée (cf. REAL_SET_RPE_SINCE).
      3. Tonnage calibré k × tonnage (k personnel, fenêtre récente) ; sans k : log1p×10.
         ESTIMATION — sous-estime ~×3,5 sans calibration (mesure 2026-11-17).
    None = aucune donnée exploitable : la séance est exclue, jamais comptée 0.
    Seule règle de charge : utilisée par l'ACWR et stress_load_engine.
    """
    dur = float(duration_min) if duration_min else 0.0
    if rpe is not None and dur > 0:
        return float(rpe) * dur
    if set_rpe_mean is not None and dur > 0:
        return float(set_rpe_mean) * dur
    if tonnage and tonnage > 0:
        return k * float(tonnage) if k is not None else math.log1p(float(tonnage)) * 10
    return None


def real_set_rpe_mean(sets_lists: list, session_date: str) -> Optional[float]:
    """Moyenne des RPE de séries RÉELLEMENT saisies ; None avant REAL_SET_RPE_SINCE ou sans saisie."""
    if not session_date or str(session_date)[:10] < REAL_SET_RPE_SINCE:
        return None
    vals = [float(st["rpe"]) for sets in sets_lists for st in (sets or [])
            if isinstance(st, dict) and st.get("rpe") is not None]
    return sum(vals) / len(vals) if vals else None


def tonnage_k(rows: list[dict], today_iso: str) -> Optional[float]:
    """k = médiane(sRPE×durée / tonnage) sur K_WINDOW_DAYS ; None si < K_MIN_SESSIONS paires."""
    cutoff = (date_cls.fromisoformat(today_iso) - timedelta(days=K_WINDOW_DAYS)).isoformat()
    ratios = [float(r["rpe"]) * float(r["duration_min"]) / float(r["total_volume"])
              for r in rows
              if str(r.get("date") or "")[:10] >= cutoff
              and r.get("rpe") is not None and (r.get("duration_min") or 0) > 0
              and (r.get("total_volume") or 0) > 0]
    return statistics.median(ratios) if len(ratios) >= K_MIN_SESSIONS else None


def _row_load(r: dict, k: Optional[float]) -> Optional[float]:
    return session_load(r.get("rpe"), r.get("duration_min"), r.get("total_volume"),
                        r.get("set_rpe_mean"), k)


# ─────────────────────────────────────────────────────────────
# FETCH SESSIONS
# ─────────────────────────────────────────────────────────────

def _fetch_sessions(days: int = FETCH_DAYS) -> list[dict]:
    """
    Séances des N derniers jours (morning, evening, bonus) depuis v_session_volume :
    session_id, date, rpe, duration_min, total_volume. Les séances sans RPE de séance et
    postérieures à REAL_SET_RPE_SINCE reçoivent set_rpe_mean (RPE réels de leurs séries).
    """
    if db._client is None:
        return []
    try:
        cutoff = (date_cls.fromisoformat(_today_mtl()) - timedelta(days=days)).isoformat()
        rows = (
            db._client.table("v_session_volume")
            .select("session_id, date, rpe, duration_min, total_volume")
            .gte("date", cutoff)
            .order("date", desc=False)
            .execute()
        ).data or []
        need = [r["session_id"] for r in rows
                if r.get("rpe") is None and str(r.get("date") or "")[:10] >= REAL_SET_RPE_SINCE]
        if need:
            logs = (db._client.table("exercise_logs").select("session_id, sets_json")
                    .in_("session_id", need).execute()).data or []
            by_session: dict[str, list] = {}
            for lg in logs:
                by_session.setdefault(lg["session_id"], []).append(lg.get("sets_json") or [])
            for r in rows:
                if r["session_id"] in by_session:
                    r["set_rpe_mean"] = real_set_rpe_mean(by_session[r["session_id"]], r.get("date"))
        return rows
    except Exception as e:
        db.logger.warning("acwr: fetch_sessions error: %s", e)
        return []


def session_loads_by_id(days: int) -> dict[str, float]:
    """{session_id: charge} — même règle que l'ACWR (pour stress_load_engine). Séances sans
    donnée exploitable absentes du dict (exclues, jamais 0)."""
    rows = _fetch_sessions(max(days, K_WINDOW_DAYS))
    k = tonnage_k(rows, _today_mtl())
    out: dict[str, float] = {}
    for r in rows:
        load = _row_load(r, k)
        if load is not None:
            out[r["session_id"]] = load
    return out


# Proxy RPE par type de cardio (Foster 2001 — sRPE × durée applicable au cardio)
_CARDIO_RPE_PROXY: dict[str, float] = {
    "run":       7.0, "course":   7.0, "running":  7.0, "trail":    7.5,
    "hiit":      8.0,
    "bike":      6.0, "vélo":     6.0, "cycling":  6.0, "cycle":    6.0,
    "walk":      4.0, "marche":   4.0, "walking":  4.0, "hike":     5.0,
    "swim":      7.0, "natation": 7.0,
    "rowing":    7.0,
}


def _fetch_cardio(days: int = FETCH_DAYS) -> list[dict]:
    """Récupère les sessions cardio des N derniers jours."""
    if db._client is None:
        return []
    try:
        cutoff = (date_cls.fromisoformat(_today_mtl()) - timedelta(days=days)).isoformat()
        resp = (
            db._client.table("cardio_logs")
            .select("date, duration_min, type")
            .gte("date", cutoff)
            .order("date", desc=False)
            .execute()
        )
        return resp.data or []
    except Exception as e:
        db.logger.warning("acwr: fetch_cardio error: %s", e)
        return []


def _aggregate_daily_cardio(rows: list[dict]) -> dict[str, float]:
    """Cumule les charges cardio par jour via RPE proxy × durée."""
    daily: dict[str, float] = {}
    for r in rows:
        d = str(r.get("date") or "")[:10]
        if not d:
            continue
        dur = float(r.get("duration_min") or 0)
        if dur <= 0:
            continue
        rpe = _CARDIO_RPE_PROXY.get((r.get("type") or "").lower(), 6.0)
        daily[d] = daily.get(d, 0.0) + rpe * dur
    return daily


# ─────────────────────────────────────────────────────────────
# EWMA ENGINE — FONCTIONS PURES
# ─────────────────────────────────────────────────────────────

def _aggregate_daily(rows: list[dict], k: Optional[float] = None) -> dict[str, float]:
    """Cumule les charges des séances d'un même jour ; séance sans donnée = exclue (pas 0)."""
    daily: dict[str, float] = {}
    for r in rows:
        raw_date = r.get("date")
        if not raw_date:
            continue
        d = str(raw_date)[:10]
        load = _row_load(r, k)
        if load is None:
            continue
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
    end   = date_cls.fromisoformat(_today_mtl())
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

def _latest_or_empty(series: list[dict]) -> dict:
    """Extrait le dernier point EWMA ou retourne un point vide."""
    if not series:
        return {"ratio": 0.0, "acute_load": 0.0, "chronic_load": 0.0,
                "zone_code": "insufficient_data", "confidence": "low", "days_of_data": 0}
    return series[-1]


def calc_acwr() -> dict:
    """
    Calcule l'ACWR EWMA courant (total + séparés muscu/cardio).

    Champs retournés :
      ratio, acute_load, chronic_load  — ACWR total (muscu + cardio combinés)
      zone                             — {code, label, color, recommendation}
      trend                            — 8 snapshots hebdomadaires (total)
      confidence                       — "low" | "moderate" | "high"
      days_of_data                     — nombre de jours de données
      strength_acwr                    — {ratio, acute_load, chronic_load, zone_code}
      cardio_acwr                      — {ratio, acute_load, chronic_load, zone_code}
    """
    # ── Muscu ───────────────────────────────────────────────────────────────
    strength_rows  = _fetch_sessions(FETCH_DAYS)
    strength_daily = _aggregate_daily(strength_rows, tonnage_k(strength_rows, _today_mtl()))

    # ── Cardio ──────────────────────────────────────────────────────────────
    cardio_rows  = _fetch_cardio(FETCH_DAYS)
    cardio_daily = _aggregate_daily_cardio(cardio_rows)

    # ── Total combiné ───────────────────────────────────────────────────────
    all_dates    = set(strength_daily.keys()) | set(cardio_daily.keys())
    total_daily  = {d: strength_daily.get(d, 0.0) + cardio_daily.get(d, 0.0)
                    for d in all_dates}

    strength_series = _run_ewma(strength_daily)
    cardio_series   = _run_ewma(cardio_daily)
    total_series    = _run_ewma(total_daily)

    # ── Réponse principale (total) ───────────────────────────────────────────
    latest = _latest_or_empty(total_series)
    meta   = _zone_meta(latest["zone_code"])

    # ── Sous-ACWRs ──────────────────────────────────────────────────────────
    sl = _latest_or_empty(strength_series)
    cl = _latest_or_empty(cardio_series)

    def _sub(pt: dict) -> dict:
        return {
            "ratio":        pt["ratio"],
            "acute_load":   pt["acute_load"],
            "chronic_load": pt["chronic_load"],
            "zone_code":    pt["zone_code"],
            "confidence":   pt["confidence"],
        }

    # ── Lentille deload — interprétation seulement, pas les données ────────────
    deload_active = False
    try:
        import db as _db
        deload_active = _db.get_active_deload_period() is not None
        if deload_active:
            zone_code = latest["zone_code"]
            meta = dict(meta)  # copie — ne pas muter _ZONE_META
            if zone_code == "under":
                meta["recommendation"] = (
                    "Décharge active — repos intentionnel pour adaptation. "
                    "Charge basse attendue et saine. Reprendre progressivement après."
                )
            elif zone_code in ("caution", "danger"):
                meta["recommendation"] = (
                    meta["recommendation"] +
                    " (Décharge en cours — poursuivre le repos intentionnel.)"
                )
    except Exception:
        pass

    return {
        "ratio":          latest["ratio"],
        "acute_load":     latest["acute_load"],
        "chronic_load":   latest["chronic_load"],
        "zone":           meta,
        "trend":          _weekly_snapshots(total_series),
        "confidence":     latest["confidence"],
        "days_of_data":   latest["days_of_data"],
        "strength_acwr":  _sub(sl),
        "cardio_acwr":    _sub(cl),
        "deload_context": deload_active,
    }
