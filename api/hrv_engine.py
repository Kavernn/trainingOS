"""
hrv_engine.py — Moteur de calcul HRV professionnel.

Source de vérité unique pour tous les calculs HRV dérivés :
  - Rolling averages 7j et 30j (baseline personnelle)
  - Coefficient de variation 30j (stabilité du signal)
  - Score normalisé (today / 7j_avg × 100) — pas de référence absolue
  - Zone : green (≥110%) | orange (90–109%) | red (<90%)
  - Tendance linéaire sur 7 jours
  - Streak de jours consécutifs sous baseline
  - Message contextuel

Contrainte : aucune modification des données brutes.
Tout est calculé à partir de recovery_logs.hrv existant.
Metric : Apple Watch heartRateVariabilitySDNN = RMSSD (confirmé).
"""
from __future__ import annotations

import math
from datetime import date as date_cls, timedelta
from typing import Optional


_HRV_ZONES: dict[str, tuple[int, int]] = {
    "conservative": (115, 85),   # zones plus larges — moins d'alertes
    "standard":     (110, 90),   # défaut actuel
    "aggressive":   (120, 80),   # zones plus étroites — plus sensible
}


def compute_hrv_analysis(rows: list[dict], target_date: str, sensitivity: str = "standard") -> dict:
    """
    Analyse HRV complète pour une date cible.

    Args:
        rows: entrées recovery_log (chaque dict doit avoir 'date' et 'hrv').
              Peut contenir des entrées sans HRV — elles sont filtrées.
        target_date: date cible au format 'YYYY-MM-DD'.

    Returns dict :
        today_rmssd          float | None
        hrv_7d_avg           float | None
        hrv_30d_avg          float | None
        hrv_cv               float | None  (%, coefficient de variation 30j)
        hrv_score            float | None  (0-150+, today / 7j_avg × 100)
        hrv_zone             str   | None  'green' | 'orange' | 'red'
        hrv_trend            str   | None  'up' | 'stable' | 'down'
        consecutive_low_days int           (jours consécutifs sous 7j_avg)
        streak_alert         bool          (True si ≥3 jours consécutifs)
        contextual_message   str   | None
        history_7d           list[dict]    [{date, hrv}, ...] chronologique
        baseline_available   bool          (False si <3 jours de données)
        data_points_7d       int
        data_points_30d      int
    """
    today = date_cls.fromisoformat(target_date)

    # ── Index date → valeur HRV brute ────────────────────────────────────────
    hrv_by_date: dict[str, float] = {}
    for r in rows:
        d = str(r.get("date", ""))[:10]
        v = r.get("hrv")
        if d and v is not None:
            try:
                hrv_by_date[d] = float(v)
            except (TypeError, ValueError):
                pass

    today_rmssd = hrv_by_date.get(target_date)

    # ── Fenêtres temporelles (exclure aujourd'hui de la baseline) ─────────────
    window_7d  = [(today - timedelta(days=i)).isoformat() for i in range(1, 8)]
    window_30d = [(today - timedelta(days=i)).isoformat() for i in range(1, 31)]

    vals_7d  = [hrv_by_date[d] for d in window_7d  if d in hrv_by_date]
    vals_30d = [hrv_by_date[d] for d in window_30d if d in hrv_by_date]

    baseline_available = len(vals_7d) >= 3

    # ── Moyennes glissantes ───────────────────────────────────────────────────
    hrv_7d_avg  = round(sum(vals_7d)  / len(vals_7d),  1) if vals_7d  else None
    hrv_30d_avg = round(sum(vals_30d) / len(vals_30d), 1) if vals_30d else None

    # ── SD 30j, CV, flag_rest, deviation ────────────────────────────────────
    sd_30d: Optional[float] = None
    if len(vals_30d) >= 2 and hrv_30d_avg and hrv_30d_avg > 0:
        variance = sum((v - hrv_30d_avg) ** 2 for v in vals_30d) / len(vals_30d)
        sd_30d   = math.sqrt(variance)
    hrv_cv: Optional[float] = None
    if sd_30d is not None and len(vals_30d) >= 7 and hrv_30d_avg:
        hrv_cv = round(sd_30d / hrv_30d_avg * 100, 1)
    flag_rest = bool(
        today_rmssd is not None and hrv_30d_avg is not None and sd_30d is not None
        and today_rmssd < hrv_30d_avg - sd_30d
    )
    deviation = (
        round(today_rmssd - hrv_30d_avg, 1)
        if today_rmssd is not None and hrv_30d_avg is not None else None
    )

    # ── Score normalisé et zone ───────────────────────────────────────────────
    hrv_score: Optional[float] = None
    hrv_zone:  Optional[str]   = None

    if today_rmssd is not None and baseline_available and hrv_7d_avg:
        hrv_score = round(today_rmssd / hrv_7d_avg * 100, 1)
        green_min, orange_min = _HRV_ZONES.get(sensitivity, _HRV_ZONES["standard"])
        if hrv_score >= green_min:
            hrv_zone = "green"
        elif hrv_score >= orange_min:
            hrv_zone = "orange"
        else:
            hrv_zone = "red"

    # ── Tendance linéaire 7j (régression slope en ms/jour) ───────────────────
    hrv_trend: Optional[str] = None
    trend_dates = [(today - timedelta(days=i)).isoformat() for i in range(6, -1, -1)]
    trend_pts   = [(i, hrv_by_date[d]) for i, d in enumerate(trend_dates) if d in hrv_by_date]

    if len(trend_pts) >= 3:
        n       = len(trend_pts)
        x_vals  = [p[0] for p in trend_pts]
        y_vals  = [p[1] for p in trend_pts]
        x_mean  = sum(x_vals) / n
        y_mean  = sum(y_vals) / n
        num     = sum((x - x_mean) * (y - y_mean) for x, y in zip(x_vals, y_vals))
        den     = sum((x - x_mean) ** 2 for x in x_vals)
        if den > 0:
            slope = num / den
            if slope >= 0.5:
                hrv_trend = "up"
            elif slope <= -0.5:
                hrv_trend = "down"
            else:
                hrv_trend = "stable"

    # ── Streak : jours consécutifs sous 7j_avg (tolère 1 jour sans donnée) ─────
    consecutive_low_days = 0
    if hrv_7d_avg and today_rmssd is not None:
        gaps = 0
        MAX_GAPS = 1
        for i in range(7):
            d = (today - timedelta(days=i)).isoformat()
            v = hrv_by_date.get(d)
            if v is None:
                gaps += 1
                if gaps > MAX_GAPS:
                    break
                continue
            if v < hrv_7d_avg:
                consecutive_low_days += 1
            else:
                break

    streak_alert = consecutive_low_days >= 3

    # ── Historique 7j chronologique ──────────────────────────────────────────
    history_7d = []
    for d in reversed(window_7d):
        if d in hrv_by_date:
            history_7d.append({"date": d, "hrv": hrv_by_date[d]})
    if today_rmssd is not None:
        history_7d.append({"date": target_date, "hrv": today_rmssd})

    # ── Message contextuel ────────────────────────────────────────────────────
    contextual_message: Optional[str] = None

    if not baseline_available:
        contextual_message = "Baseline HRV en cours de calcul — encore quelques jours de données nécessaires."
    elif today_rmssd is None:
        contextual_message = "Aucune mesure HRV aujourd'hui — coaching non influencé par une valeur absente."
    elif hrv_7d_avg and hrv_score is not None:
        diff_pct = round((today_rmssd - hrv_7d_avg) / hrv_7d_avg * 100)
        if hrv_zone == "red":
            if streak_alert:
                contextual_message = (
                    f"HRV {abs(diff_pct)}% sous ta moyenne 7j depuis {consecutive_low_days} jours — "
                    "fatigue accumulée, récupération prioritaire."
                )
            else:
                contextual_message = (
                    f"Ton HRV est {abs(diff_pct)}% sous ta moyenne des 7 derniers jours — "
                    "récupération incomplète probable."
                )
        elif hrv_zone == "orange":
            sign = "+" if diff_pct >= 0 else ""
            contextual_message = (
                f"HRV dans la norme ({sign}{diff_pct}% vs ta moyenne 7j) — "
                "séance complète possible, surveille la fatigue."
            )
        else:  # green
            contextual_message = (
                f"HRV {diff_pct}% au-dessus de ta moyenne 7j — "
                "récupération optimale, tu peux performer à ton meilleur."
            )

    return {
        "today_rmssd":         today_rmssd,
        "hrv_7d_avg":          hrv_7d_avg,
        "hrv_30d_avg":         hrv_30d_avg,
        "hrv_cv":              hrv_cv,
        "hrv_score":           hrv_score,
        "hrv_zone":            hrv_zone,
        "hrv_trend":           hrv_trend,
        "consecutive_low_days": consecutive_low_days,
        "streak_alert":        streak_alert,
        "contextual_message":  contextual_message,
        "history_7d":          history_7d,
        "baseline_available":  baseline_available,
        "data_points_7d":      len(vals_7d),
        "data_points_30d":     len(vals_30d),
        "sd_30d":              round(sd_30d, 1) if sd_30d is not None else None,
        "flag_rest":           flag_rest,
        "deviation":           deviation,
    }
