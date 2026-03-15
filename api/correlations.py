"""
Cross-Correlation Insights — api/correlations.py

Charge 4 clés KV en une seule passe (pas 60×4 appels), construit un index
par date, calcule Pearson r pour 7 paires de métriques, et retourne
uniquement les corrélations significatives (|r| >= 0.35, n >= 5).

Paires analysées :
  sleep_hours    → rpe (J+1)
  sleep_quality  → rpe (J+1)
  hrv            → rpe (J+1)
  hrv            → session_volume (J+1)
  mood_score     → rpe (même jour)
  soreness       → rpe (même jour)
  protein        → soreness (J+1)
"""

from __future__ import annotations

import math
from datetime import date as date_cls, timedelta
from typing import Optional

from db import get_json

# ── Catalogue des paires ──────────────────────────────────────────────────────
# (id, label, x_key, y_key, lag_days, sf_icon, color)
_PAIRS = [
    ("sleep_rpe",    "Sommeil → Performance",    "sleep_hours",   "rpe",            1, "moon.zzz.fill",     "blue"),
    ("sleep_q_rpe",  "Qualité Sommeil → RPE",    "sleep_quality", "rpe",            1, "bed.double.fill",   "indigo"),
    ("hrv_rpe",      "HRV → Performance",        "hrv",           "rpe",            1, "waveform.path.ecg", "green"),
    ("hrv_volume",   "HRV → Volume",             "hrv",           "session_volume", 1, "waveform.path.ecg", "teal"),
    ("mood_rpe",     "Humeur → Performance",     "mood_score",    "rpe",            0, "face.smiling",      "yellow"),
    ("soreness_rpe", "Courbatures → RPE",        "soreness",      "rpe",            0, "bolt.heart.fill",   "orange"),
    ("protein_sore", "Protéines → Récupération", "protein",       "soreness",       1, "fork.knife",        "purple"),
]

MIN_R = 0.35   # seuil de signification
MIN_N = 5      # points minimum par paire


# ── Chargement des données (4 lectures KV, pas 60×4) ─────────────────────────

def _load_by_date(days: int) -> dict[str, dict]:
    today = date_cls.today()
    date_range = {
        (today - timedelta(days=i)).isoformat()
        for i in range(days)
    }

    # 4 lectures KV
    rec_log  = get_json("recovery_log") or []
    sessions = get_json("sessions") or {}
    nutr_log = get_json("nutrition_log") or {}
    mood_log = get_json("mood_log") or []

    # Normalise mood_log au cas où ce serait un dict
    if isinstance(mood_log, dict):
        mood_log = list(mood_log.values())

    by_date: dict[str, dict] = {d: {} for d in date_range}

    # recovery_log → list[dict]
    for entry in rec_log:
        d = entry.get("date")
        if d not in by_date:
            continue
        for key in ("sleep_hours", "sleep_quality", "hrv", "soreness"):
            val = entry.get(key)
            if val is not None:
                by_date[d][key] = val

    # sessions → {date: dict}
    for d, sess in sessions.items():
        if d not in by_date:
            continue
        for key in ("rpe", "session_volume"):
            val = sess.get(key)
            if val is not None:
                by_date[d][key] = val

    # nutrition_log → {date: {entries: [...]}}
    for d, day_data in nutr_log.items():
        if d not in by_date:
            continue
        entries = (day_data or {}).get("entries", [])
        if entries:
            total_protein = sum(e.get("proteines", 0) for e in entries)
            if total_protein > 0:
                by_date[d]["protein"] = round(total_protein, 1)

    # mood_log → list[dict]
    for entry in mood_log:
        d = entry.get("date")
        if d not in by_date:
            continue
        score = entry.get("score")
        if score is not None:
            by_date[d]["mood_score"] = score

    return by_date


# ── Statistiques ──────────────────────────────────────────────────────────────

def _pearson(xs: list[float], ys: list[float]) -> Optional[float]:
    n = len(xs)
    if n < MIN_N:
        return None
    mx = sum(xs) / n
    my = sum(ys) / n
    num   = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    den_x = math.sqrt(sum((x - mx) ** 2 for x in xs))
    den_y = math.sqrt(sum((y - my) ** 2 for y in ys))
    if den_x < 1e-9 or den_y < 1e-9:
        return None
    return round(num / (den_x * den_y), 3)


def _extract_pairs(
    by_date: dict[str, dict],
    x_key: str,
    y_key: str,
    lag: int = 0,
) -> tuple[list[float], list[float]]:
    xs, ys = [], []
    for d in sorted(by_date):
        x_val = by_date[d].get(x_key)
        if x_val is None:
            continue
        if lag == 0:
            y_val = by_date[d].get(y_key)
        else:
            try:
                future = (date_cls.fromisoformat(d) + timedelta(days=lag)).isoformat()
                y_val = by_date.get(future, {}).get(y_key)
            except ValueError:
                continue
        if y_val is None:
            continue
        xs.append(float(x_val))
        ys.append(float(y_val))
    return xs, ys


# ── Génération de la description en français ──────────────────────────────────

def _strength_label(r: float) -> str:
    a = abs(r)
    if a >= 0.7:  return "très forte"
    if a >= 0.5:  return "forte"
    return "modérée"


def _describe(pair_id: str, r: float, xs: list[float], ys: list[float]) -> str:
    n = len(xs)
    if not xs or not ys:
        return f"Corrélation {'positive' if r > 0 else 'négative'} (r={r:+.2f})"

    median_x = sorted(xs)[len(xs) // 2]
    low_y    = [y for x, y in zip(xs, ys) if x <= median_x]
    high_y   = [y for x, y in zip(xs, ys) if x >  median_x]
    if not low_y or not high_y:
        return f"Corrélation {'positive' if r > 0 else 'négative'} (r={r:+.2f}, n={n})"

    avg_low  = sum(low_y)  / len(low_y)
    avg_high = sum(high_y) / len(high_y)

    if pair_id == "sleep_rpe":
        threshold = round(median_x, 1)
        delta = round(avg_low - avg_high, 1)  # peu de sommeil → RPE plus haut
        sign = "+" if delta > 0 else ""
        return (
            f"Quand tu dors < {threshold}h, ton RPE monte de "
            f"{sign}{delta} pts le lendemain (r={r:+.2f}, n={n})"
        )
    if pair_id == "sleep_q_rpe":
        threshold = round(median_x, 1)
        delta = round(avg_low - avg_high, 1)
        sign = "+" if delta > 0 else ""
        return (
            f"Qualité sommeil < {threshold}/10 → RPE {sign}{delta} pts "
            f"le lendemain (r={r:+.2f}, n={n})"
        )
    if pair_id == "hrv_rpe":
        delta = round(avg_high - avg_low, 1)
        sign = "+" if delta > 0 else ""
        return (
            f"HRV élevé → RPE {sign}{delta} pts le lendemain "
            f"(r={r:+.2f}, n={n})"
        )
    if pair_id == "hrv_volume":
        delta = round(avg_high - avg_low, 0)
        sign = "+" if delta > 0 else ""
        return (
            f"HRV élevé → volume {sign}{int(delta)} lbs de plus le lendemain "
            f"(r={r:+.2f}, n={n})"
        )
    if pair_id == "mood_rpe":
        delta = round(avg_high - avg_low, 1)
        sign = "+" if delta > 0 else ""
        return (
            f"Bonne humeur → RPE {sign}{delta} pts en séance "
            f"(r={r:+.2f}, n={n})"
        )
    if pair_id == "soreness_rpe":
        delta = round(avg_high - avg_low, 1)
        sign = "+" if delta > 0 else ""
        return (
            f"Courbatures élevées → RPE {sign}{delta} pts en séance "
            f"(r={r:+.2f}, n={n})"
        )
    if pair_id == "protein_sore":
        threshold = int(round(median_x, 0))
        delta = round(avg_low - avg_high, 1)  # peu de protéines → plus de courbatures
        sign = "+" if delta > 0 else ""
        return (
            f"< {threshold}g de protéines → courbatures {sign}{delta} pts "
            f"le lendemain (r={r:+.2f}, n={n})"
        )
    direction = "positive" if r > 0 else "négative"
    return f"Corrélation {direction} (r={r:+.2f}, n={n})"


# ── Point d'entrée public ─────────────────────────────────────────────────────

def get_correlations(days: int = 60) -> dict:
    days = max(14, min(days, 90))
    today = date_cls.today().isoformat()

    by_date = _load_by_date(days)
    data_points = sum(1 for v in by_date.values() if v)

    insights = []
    for pair_id, label, x_key, y_key, lag, icon, color in _PAIRS:
        xs, ys = _extract_pairs(by_date, x_key, y_key, lag)
        r = _pearson(xs, ys)
        if r is None or abs(r) < MIN_R:
            continue
        insights.append({
            "id":          pair_id,
            "label":       label,
            "description": _describe(pair_id, r, xs, ys),
            "correlation": r,
            "strength":    _strength_label(r),
            "x_var":       x_key,
            "y_var":       y_key,
            "n_points":    len(xs),
            "icon":        icon,
            "color":       color,
        })

    # Tri par |r| décroissant — les corrélations les plus fortes en premier
    insights.sort(key=lambda i: abs(i["correlation"]), reverse=True)

    return {
        "period_days": days,
        "data_points": data_points,
        "computed_at": today,
        "insights":    insights,
    }
