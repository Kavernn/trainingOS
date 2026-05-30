from __future__ import annotations
from flask import Blueprint, jsonify
from datetime import date as date_cls, timedelta
import logging
import math

from utils import _today_mtl

logger = logging.getLogger("trainingos")

cardio_metrics_bp = Blueprint("cardio_metrics", __name__)

# Types de course valides pour VO2max / pace / seuil
_VO2MAX_TYPES = {"course", "tempo", "endurance", "leger"}

# ─────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────

def _pace_str(seconds_per_km: float) -> str:
    m = int(seconds_per_km // 60)
    s = int(seconds_per_km % 60)
    return f"{m}:{s:02d}"


def _parse_pace_to_seconds(pace_str: str) -> float | None:
    """'5:30' → 330.0"""
    if not pace_str:
        return None
    try:
        parts = pace_str.strip().split(":")
        if len(parts) == 2:
            return int(parts[0]) * 60 + int(parts[1])
    except (ValueError, TypeError):
        pass
    return None


def _vo2max_from_session(distance_km: float, duration_min: float) -> float | None:
    """Jack Daniels VDOT estimate from one session."""
    if distance_km <= 0 or duration_min <= 0:
        return None
    vel = (distance_km * 1000) / duration_min  # m/min
    pct_vo2 = 0.8 + 0.1894393 * math.exp(-0.012778 * duration_min) \
              + 0.2989558 * math.exp(-0.1932605 * duration_min)
    vo2 = (-4.60 + 0.182258 * vel + 0.000104 * vel ** 2)
    return round(vo2 / pct_vo2, 1) if pct_vo2 > 0 else None


def _vo2max_category(vo2max: float, age: int, sex: str) -> str:
    is_female = (sex or "").lower() in ("f", "female", "femme")
    if is_female:
        if vo2max >= 52:   return "Élite"
        if vo2max >= 45:   return "Excellent"
        if vo2max >= 38:   return "Bon"
        if vo2max >= 31:   return "Moyen"
        return "Faible"
    else:
        if vo2max >= 56:   return "Élite"
        if vo2max >= 50:   return "Excellent"
        if vo2max >= 43:   return "Bon"
        if vo2max >= 36:   return "Moyen"
        return "Faible"


def _resolve_max_hr(sessions: list[dict], age: int | None) -> tuple[int, str]:
    """
    Priority:
      1. max(avg_hr) × 1.10 from sessions (observed + 10%)
      2. 220 - age
    Returns (max_hr, source).
    """
    hr_values = [float(s["avg_hr"]) for s in sessions if s.get("avg_hr")]
    if hr_values:
        observed_max = max(hr_values)
        return int(observed_max * 1.10), "observed"
    if age and age > 0:
        return max(1, 220 - age), "formula"
    return 190, "default"


def _acwr_cardio(sessions: list[dict], today: date_cls) -> dict:
    """
    ACWR cardio-only from cardio_logs.
    Volume = distance_km if available, else duration_min / 10 (normalized).
    Simple rolling average (not EWMA) — keeps it independent from acwr.py.
    """
    def _load(s: dict) -> float:
        if s.get("distance_km"):
            return float(s["distance_km"])
        if s.get("duration_min"):
            return float(s["duration_min"]) / 10.0
        return 0.0

    cutoff_7  = (today - timedelta(days=7)).isoformat()
    cutoff_28 = (today - timedelta(days=28)).isoformat()

    acute_load   = sum(_load(s) for s in sessions if str(s.get("date", ""))[:10] >= cutoff_7)
    chronic_load = sum(_load(s) for s in sessions if str(s.get("date", ""))[:10] >= cutoff_28)

    sessions_28 = [s for s in sessions if str(s.get("date", ""))[:10] >= cutoff_28]
    chronic_avg = chronic_load / 4.0 if sessions_28 else 0.0
    acute_avg   = acute_load

    ratio = round(acute_avg / chronic_avg, 2) if chronic_avg > 0 else 0.0

    if ratio == 0:
        zone = "no_data"
    elif ratio < 0.8:
        zone = "under"
    elif ratio <= 1.3:
        zone = "optimal"
    elif ratio <= 1.5:
        zone = "over"
    else:
        zone = "critical"

    return {
        "ratio":          ratio,
        "acute_load":     round(acute_avg, 2),
        "chronic_load":   round(chronic_avg, 2),
        "zone":           zone,
    }


def _pace_zones(best_pace_s: float) -> dict:
    """
    5 zones from best recent pace (seconds/km).
    Easy = best + 75s, Moderate = +45s, Tempo = +15s, Threshold = +5s, Race = best.
    """
    return {
        "easy":      f"{_pace_str(best_pace_s + 75)}–{_pace_str(best_pace_s + 90)}",
        "moderate":  f"{_pace_str(best_pace_s + 45)}–{_pace_str(best_pace_s + 75)}",
        "tempo":     f"{_pace_str(best_pace_s + 15)}–{_pace_str(best_pace_s + 45)}",
        "threshold": f"{_pace_str(best_pace_s + 5)}–{_pace_str(best_pace_s + 15)}",
        "race":      f"{_pace_str(best_pace_s - 10)}–{_pace_str(best_pace_s + 5)}",
    }


def _fc_zones(max_hr: int) -> dict:
    mhr = float(max_hr)
    return {
        "max_hr": max_hr,
        "zone1":  [int(mhr * 0.50), int(mhr * 0.60)],
        "zone2":  [int(mhr * 0.60), int(mhr * 0.70)],
        "zone3":  [int(mhr * 0.70), int(mhr * 0.80)],
        "zone4":  [int(mhr * 0.80), int(mhr * 0.90)],
        "zone5":  [int(mhr * 0.90), max_hr],
    }


def _zone_time_distribution(sessions: list[dict], max_hr: int) -> dict[str, float]:
    """% of sessions whose avg_hr falls in each zone."""
    counts = {"z1": 0, "z2": 0, "z3": 0, "z4": 0, "z5": 0}
    total = 0
    mhr = float(max_hr)
    for s in sessions:
        hr = s.get("avg_hr")
        if not hr:
            continue
        total += 1
        pct = float(hr) / mhr
        if pct < 0.60:       counts["z1"] += 1
        elif pct < 0.70:     counts["z2"] += 1
        elif pct < 0.80:     counts["z3"] += 1
        elif pct < 0.90:     counts["z4"] += 1
        else:                counts["z5"] += 1
    if total == 0:
        return {}
    return {k: round(v / total * 100, 1) for k, v in counts.items()}


# ─────────────────────────────────────────────────────────────
# GUIDES DYNAMIQUES
# ─────────────────────────────────────────────────────────────

def _guide_vo2max(vo2max: float | None, category: str | None, has_data: bool) -> str:
    if not has_data:
        return "Lance une session de 3 km à effort maximal pour estimer ton VO2max."
    if vo2max is None:
        return "Données insuffisantes — 3 sessions minimum sur 30 jours."
    if vo2max < 40:
        return (
            "Pour améliorer ton VO2max, intègre 2 sessions d'intervalles par semaine. "
            "Ex : 4×4 min à 90–95% FC max avec 3 min de récupération."
        )
    if vo2max < 50:
        return (
            "Ton VO2max est dans la bonne moyenne. "
            "Pour progresser : 1 session tempo/semaine à allure seuil "
            "(pace où tenir une conversation devient difficile)."
        )
    return (
        "Excellent VO2max. Maintiens avec 1–2 sessions longues par semaine "
        "et varie les intensités."
    )


def _guide_threshold(pace_s: float | None) -> str:
    if pace_s is None:
        return (
            "Pour trouver ton seuil lactique : cours 30 min à l'allure la plus rapide "
            "que tu peux maintenir. Pace moyen = seuil."
        )
    return (
        f"Ton seuil lactique estimé : {_pace_str(pace_s)} /km. "
        "Entraîne-toi 20% du temps dans cette zone pour repousser ton seuil."
    )


def _guide_acwr(zone: str, ratio: float) -> str:
    if zone == "no_data":
        return "Aucune session cardio récente — commence avec 2–3 sorties légères cette semaine."
    if zone == "under":
        return (
            "Tu es en sous-charge. Augmente progressivement le volume — "
            "+10%/semaine maximum pour éviter la déchéance aérobie."
        )
    if zone == "optimal":
        return "Zone optimale. Continue à progresser graduellement."
    if zone == "over":
        return (
            "Sur-charge détectée. Réduis le volume cette semaine pour éviter la blessure. "
            "ACWR > 1.5 = risque élevé."
        )
    return (
        f"⚠️ ACWR critique ({ratio}). Repos ou session très légère uniquement cette semaine."
    )


def _guide_zones(dist: dict[str, float], has_hr: bool) -> str:
    if not has_hr:
        return (
            "Connecte ton Apple Watch ou saisis ta FC manuellement "
            "pour personnaliser ces zones."
        )
    z2_pct = dist.get("z2", 0)
    z3_pct = dist.get("z3", 0)
    z4_pct = dist.get("z4", 0)
    if z2_pct >= 80:
        return "Bonne base aérobie. Ajoute des sessions Zone 4 pour progresser plus vite."
    if (z3_pct + z4_pct) >= 60:
        return (
            "Trop d'intensité moyenne — la 'zone grise'. "
            "Polarise : plus de Zone 2 et des sessions Zone 5 courtes."
        )
    return "Distribution de zones équilibrée. Continue ainsi."


def _guide_pace(best_pace_s: float | None, acwr_zone: str) -> str:
    if best_pace_s is None:
        return "Lance une session chronométrée pour calculer tes zones de pace."
    if acwr_zone in ("over", "critical"):
        easy_pace = _pace_str(best_pace_s + 82)
        return f"Session légère recommandée — reste en Zone Easy : {easy_pace} /km minimum."
    tempo_min = _pace_str(best_pace_s + 15)
    tempo_max = _pace_str(best_pace_s + 45)
    return f"Prochaine sortie recommandée : Zone Tempo — vise {tempo_min} à {tempo_max} /km."


# ─────────────────────────────────────────────────────────────
# ENDPOINT
# ─────────────────────────────────────────────────────────────

@cardio_metrics_bp.route("/api/cardio/metrics")
def api_cardio_metrics():
    import db as _db

    today = date_cls.fromisoformat(_today_mtl())
    cutoff_30 = (today - timedelta(days=30)).isoformat()

    profile   = _db.get_profile() or {}
    all_cardio = _db.get_cardio_logs(limit=200) or []
    recent    = [s for s in all_cardio if str(s.get("date", ""))[:10] >= cutoff_30]

    age  = profile.get("age")
    sex  = profile.get("sex", "")

    # ── VO2max ────────────────────────────────────────────────
    vo2_sessions = [
        s for s in recent
        if s.get("type") in _VO2MAX_TYPES
        and s.get("distance_km") and s.get("duration_min")
    ]
    has_vo2_data = len(vo2_sessions) >= 3

    vo2max_val:    float | None = None
    vo2max_cat:    str  | None = None
    vo2max_trend:  str  | None = None

    if has_vo2_data:
        estimates = []
        for s in vo2_sessions:
            v = _vo2max_from_session(float(s["distance_km"]), float(s["duration_min"]))
            if v and v > 10:
                estimates.append(v)
        if estimates:
            vo2max_val = round(sum(estimates) / len(estimates), 1)
            vo2max_cat = _vo2max_category(vo2max_val, age or 30, sex)
            if len(estimates) >= 2:
                delta = estimates[0] - estimates[-1]
                vo2max_trend = "up" if delta > 0 else ("down" if delta < 0 else "stable")

    # ── FC max & zones ────────────────────────────────────────
    max_hr, hr_source = _resolve_max_hr(recent, age)
    zones = _fc_zones(max_hr)
    has_hr = any(s.get("avg_hr") for s in recent)
    zone_dist = _zone_time_distribution(recent, max_hr)

    # ── Pace — meilleur pace sur sessions course ──────────────
    pace_sessions = [s for s in recent if s.get("type") in _VO2MAX_TYPES and s.get("pace_avg_seconds")]
    best_pace_s: float | None = None
    if pace_sessions:
        best_pace_s = float(min(s["pace_avg_seconds"] for s in pace_sessions))
    else:
        # Fallback : parser avg_pace string
        parsed = [_parse_pace_to_seconds(s.get("avg_pace") or "") for s in recent if s.get("type") in _VO2MAX_TYPES]
        parsed = [p for p in parsed if p]
        if parsed:
            best_pace_s = float(min(parsed))

    pace_zones_dict = _pace_zones(best_pace_s) if best_pace_s else {}

    # ── Seuil lactique (pace estimé à ~85% FCmax ou pace marathon) ──
    # Estimation simple : seuil ≈ best_pace + 20s/km
    threshold_pace_s: float | None = (best_pace_s + 20) if best_pace_s else None

    # ── ACWR cardio ───────────────────────────────────────────
    acwr = _acwr_cardio(all_cardio, today)

    # ── Guides dynamiques ─────────────────────────────────────
    guides = {
        "vo2max":    _guide_vo2max(vo2max_val, vo2max_cat, has_vo2_data),
        "threshold": _guide_threshold(threshold_pace_s),
        "acwr":      _guide_acwr(acwr["zone"], acwr["ratio"]),
        "zones":     _guide_zones(zone_dist, has_hr),
        "pace":      _guide_pace(best_pace_s, acwr["zone"]),
    }

    return jsonify({
        "vo2max_estimated":         vo2max_val,
        "vo2max_category":          vo2max_cat,
        "vo2max_trend":             vo2max_trend,
        "threshold_pace_min_per_km": _pace_str(threshold_pace_s) if threshold_pace_s else None,
        "fc_zones":                 zones,
        "hr_source":                hr_source,
        "zone_distribution":        zone_dist,
        "acwr_cardio":              acwr,
        "pace_zones":               pace_zones_dict,
        "best_pace_sec_per_km":     best_pace_s,
        "guides":                   guides,
        "data_coverage": {
            "has_fc":         has_hr,
            "has_pace":       best_pace_s is not None,
            "sessions_30d":   len(recent),
            "vo2max_sessions": len(vo2_sessions),
            "hr_source":      hr_source,
        },
    })
