"""
muscle_imbalance_engine.py — Paires agoniste/antagoniste.

Analyse les déséquilibres musculaires par paire sur 90 jours.
Source : exercise_logs JOIN exercises(muscle_group, muscle_specific, category).
Mesure : nombre de sets par muscle_group (lowercase français).

Paires analysées :
  - Pectoraux vs Dos         (push/pull — Schoenfeld 2016)
  - Quadriceps vs Ischio     (H:Q ratio ≥0.75 — Croisier 2002)
  - Biceps vs Triceps        (ratio 1:1 recommandé)
"""
from __future__ import annotations
import logging

import db

logger = logging.getLogger("trainingos.muscle_imbalance")

_MIN_LOGS = 20

# Each pair: (key, agonist_fr_names, antagonist_fr_names, agonist_label, antagonist_label,
#             ideal_ratio, warning_high, warning_low, context)
_PAIRS: list[dict] = [
    {
        "key":              "chest_back",
        "agonist_fr":       ["pectoraux"],
        "antagonist_fr":    ["dos"],
        "agonist_cat":      ["push"],
        "antagonist_cat":   ["pull"],
        "agonist_label":    "Pectoraux",
        "antagonist_label": "Dos",
        "ideal_ratio":      1.0,
        "warning_high":     1.4,
        "warning_low":      0.7,
        "source":           "Schoenfeld 2016 — ratio push:pull idéal 1:1",
    },
    {
        "key":              "quad_hamstring",
        "agonist_fr":       ["quadriceps"],
        "antagonist_fr":    ["ischio-jambiers"],
        "agonist_cat":      [],
        "antagonist_cat":   [],
        "agonist_label":    "Quadriceps",
        "antagonist_label": "Ischio-jambiers",
        "ideal_ratio":      0.75,
        "warning_high":     1.6,
        "warning_low":      0.5,
        "source":           "Croisier 2002 — H:Q ratio ≥0.75 prévient les blessures ischio",
    },
    {
        "key":              "biceps_triceps",
        "agonist_fr":       ["biceps"],
        "antagonist_fr":    ["triceps"],
        "agonist_cat":      [],
        "antagonist_cat":   [],
        "agonist_label":    "Biceps",
        "antagonist_label": "Triceps",
        "ideal_ratio":      1.0,
        "warning_high":     1.5,
        "warning_low":      0.6,
        "source":           "Ratio équilibré 1:1 recommandé",
    },
]


def compute(days: int = 90) -> dict:
    logs = db.get_exercise_logs_with_category(days=days) or []

    if len(logs) < _MIN_LOGS:
        return {
            "has_data":       False,
            "pairs":          [],
            "has_imbalance":  False,
            "total_analyzed": len(logs),
            "period_days":    days,
        }

    # Count sets per muscle_group (lowercase) — fallback to category for unclassified exercises
    sets_by_group: dict[str, int] = {}
    for log in logs:
        mg  = (log.get("muscle_group") or "").strip().lower()
        cat = (log.get("category") or "").strip().lower()
        key = mg if mg else cat
        if key:
            sets_by_group[key] = sets_by_group.get(key, 0) + 1

    pairs_result = []
    for pair in _PAIRS:
        agonist_sets = sum(sets_by_group.get(fr, 0) for fr in pair["agonist_fr"]) \
                     + sum(sets_by_group.get(c, 0)  for c  in pair["agonist_cat"])
        antagonist_sets = sum(sets_by_group.get(fr, 0) for fr in pair["antagonist_fr"]) \
                        + sum(sets_by_group.get(c, 0)  for c  in pair["antagonist_cat"])

        if agonist_sets == 0 and antagonist_sets == 0:
            continue

        ratio = round(agonist_sets / antagonist_sets, 2) if antagonist_sets > 0 else None

        if ratio is None:
            status  = "insufficient_data"
            message = f"Pas assez de données pour {pair['antagonist_label']}"
        elif ratio > pair["warning_high"]:
            status  = "imbalanced_high"
            delta   = round(ratio - pair["ideal_ratio"], 2)
            message = f"{pair['agonist_label']} sur-entraîné vs {pair['antagonist_label']} (+{delta} vs idéal {pair['ideal_ratio']})"
        elif ratio < pair["warning_low"]:
            status  = "imbalanced_low"
            delta   = round(pair["ideal_ratio"] - ratio, 2)
            message = f"{pair['antagonist_label']} sur-entraîné vs {pair['agonist_label']} (-{delta} vs idéal {pair['ideal_ratio']})"
        else:
            status  = "balanced"
            message = f"Équilibré — ratio {ratio:.2f} (idéal {pair['ideal_ratio']})"

        pairs_result.append({
            "key":               pair["key"],
            "agonist_label":     pair["agonist_label"],
            "antagonist_label":  pair["antagonist_label"],
            "agonist_sets":      agonist_sets,
            "antagonist_sets":   antagonist_sets,
            "ratio":             ratio,
            "ideal_ratio":       pair["ideal_ratio"],
            "status":            status,
            "message":           message,
            "source":            pair["source"],
        })

    has_imbalance = any(p["status"].startswith("imbalanced") for p in pairs_result)

    return {
        "has_data":       True,
        "pairs":          pairs_result,
        "has_imbalance":  has_imbalance,
        "total_analyzed": len(logs),
        "period_days":    days,
    }
