"""
temporal_patterns.py — Temporal Pattern Analysis (Syndrome du Dimanche).

Identifies the weakest and strongest days of the week over the last 90 days:
  workout_rate  — sessions present / total occurrences of that weekday
  stress_inv    — (40 − avg PSS) / 40, higher = less stress
  nutrition_rate — logged days / total occurrences

Composite per day = workout_rate×0.40 + nutrition_rate×0.30 + stress_inv×0.30.
When no PSS data for a day, weights shift to workout 0.55 / nutrition 0.45.

Data read: workout sessions, PSS records, nutrition entries.
No writes. No modification to historical data.
"""
from __future__ import annotations
import logging
import math
from collections import defaultdict
from datetime import date, timedelta

import db
from utils import _today_mtl as _today_iso

logger = logging.getLogger("trainingos.temporal_patterns")

_SPAN         = 90
_DAY_NAMES_FR = ["lundi", "mardi", "mercredi", "jeudi", "vendredi", "samedi", "dimanche"]


def _mean(vals: list[float]) -> float:
    return sum(vals) / len(vals) if vals else 0.0


def _std(vals: list[float], mu: float) -> float:
    if len(vals) < 2:
        return 0.0
    return math.sqrt(sum((v - mu) ** 2 for v in vals) / (len(vals) - 1))


def _top_factors(day_wd: int, wd_workout: dict, wd_pss: dict, wd_nutr: dict,
                 global_w: float, global_s: float, global_n: float) -> list[str]:
    w_rate  = _mean(wd_workout[day_wd])
    s_inv   = ((40 - _mean(wd_pss[day_wd])) / 40) if wd_pss[day_wd] else None
    n_rate  = _mean(wd_nutr[day_wd])

    deltas: dict[str, float] = {
        "workout_absent":    global_w - w_rate,
        "nutrition_absente": global_n - n_rate,
    }
    if s_inv is not None:
        deltas["stress_élevé"] = global_s - s_inv

    return [k for k, v in sorted(deltas.items(), key=lambda x: x[1], reverse=True) if v > 0.05][:2]


def _build_suggestion(day_name: str, factors: list[str],
                      w_rate: float, pss_avg: float | None, n_occ: int) -> str:
    miss_pct = round((1 - w_rate) * 100)
    parts: list[str] = []
    if "workout_absent" in factors:
        parts.append(f"tu rates {miss_pct}% de tes séances")
    if "stress_élevé" in factors and pss_avg is not None:
        parts.append(f"ton stress atteint {round(pss_avg):.0f}/40")
    if "nutrition_absente" in factors:
        parts.append("tu loggues rarement ta nutrition")

    if not parts:
        return f"Le {day_name} est globalement sous-performant ({n_occ} semaines analysées)."

    sentence = f"Le {day_name}, " + " et ".join(parts) + "."
    if "workout_absent" in factors:
        sentence += " Un entraînement de 30 min ou une session de breathwork suffirait."
    elif "stress_élevé" in factors:
        sentence += " Une routine de décompression la veille au soir aide."
    elif "nutrition_absente" in factors:
        sentence += " Logger un seul repas suffit pour maintenir l'habitude."
    return sentence


def compute() -> dict:
    today    = date.fromisoformat(_today_iso())
    all_dates = sorted((today - timedelta(days=i)).isoformat() for i in range(_SPAN))
    date_set  = set(all_dates)
    today_str = today.isoformat()

    sessions  = db.get_workout_sessions(limit=_SPAN) or []
    pss       = db.get_pss_records(limit=60) or []
    nutrition = db.get_nutrition_entries_recent(_SPAN) or []

    w_dates     = {s["date"] for s in sessions
                   if s.get("date") in date_set and s.get("completed")}
    pss_by_date = {r["date"]: float(r.get("pss_score") or r.get("score") or 0)
                   for r in pss if r.get("date") in date_set}
    n_dates     = {e["date"] for e in nutrition if e.get("date") in date_set}

    wd_workout: dict[int, list[float]] = defaultdict(list)
    wd_pss:     dict[int, list[float]] = defaultdict(list)
    wd_nutr:    dict[int, list[float]] = defaultdict(list)

    for d in all_dates:
        if d > today_str:
            continue
        wd = date.fromisoformat(d).weekday()
        wd_workout[wd].append(1.0 if d in w_dates else 0.0)
        wd_nutr[wd].append(1.0 if d in n_dates else 0.0)
        if d in pss_by_date:
            wd_pss[wd].append(pss_by_date[d])

    day_scores: dict[str, float] = {}
    day_details: dict[str, dict] = {}

    for wd in range(7):
        name   = _DAY_NAMES_FR[wd]
        n_occ  = len(wd_workout[wd])
        if n_occ == 0:
            day_scores[name]  = 0.5
            day_details[name] = {"workout_rate": 0.0, "nutrition_rate": 0.0,
                                 "pss_avg": None, "n_occurrences": 0}
            continue

        w_rate  = _mean(wd_workout[wd])
        n_rate  = _mean(wd_nutr[wd])
        pss_avg = _mean(wd_pss[wd]) if wd_pss[wd] else None
        s_inv   = ((40 - pss_avg) / 40) if pss_avg is not None else None

        if s_inv is not None:
            composite = w_rate * 0.40 + n_rate * 0.30 + s_inv * 0.30
        else:
            composite = w_rate * 0.55 + n_rate * 0.45

        day_scores[name]  = round(composite, 3)
        day_details[name] = {
            "workout_rate":   round(w_rate, 2),
            "nutrition_rate": round(n_rate, 2),
            "pss_avg":        round(pss_avg, 1) if pss_avg is not None else None,
            "n_occurrences":  n_occ,
        }

    if not day_scores:
        return {"has_baseline": False}

    vals = list(day_scores.values())
    mu   = _mean(vals)
    sd   = _std(vals, mu)
    z_scores = {d: round((s - mu) / sd, 2) if sd > 1e-9 else 0.0
                for d, s in day_scores.items()}

    weakest   = min(day_scores, key=day_scores.__getitem__)
    strongest = max(day_scores, key=day_scores.__getitem__)

    # Global averages for factor comparison
    global_w = _mean([_mean(wd_workout[i]) for i in range(7) if wd_workout[i]])
    global_s = _mean([((40 - _mean(wd_pss[i])) / 40) for i in range(7) if wd_pss[i]])
    global_n = _mean([_mean(wd_nutr[i]) for i in range(7) if wd_nutr[i]])

    weak_wd   = _DAY_NAMES_FR.index(weakest)
    factors   = _top_factors(weak_wd, wd_workout, wd_pss, wd_nutr, global_w, global_s, global_n)
    n_occ_w   = len(wd_workout[weak_wd])
    pss_avg_w = _mean(wd_pss[weak_wd]) if wd_pss[weak_wd] else None
    w_rate_w  = _mean(wd_workout[weak_wd])

    has_baseline = any(len(wd_workout[i]) >= 4 for i in range(7))

    return {
        "weakest_day":         weakest,
        "weakest_day_score":   day_scores[weakest],
        "strongest_day":       strongest,
        "strongest_day_score": day_scores[strongest],
        "day_scores":          day_scores,
        "day_details":         day_details,
        "weakest_factors":     factors,
        "suggestion":          _build_suggestion(weakest, factors, w_rate_w, pss_avg_w, n_occ_w),
        "has_baseline":        has_baseline,
        "z_scores":            z_scores,
    }
