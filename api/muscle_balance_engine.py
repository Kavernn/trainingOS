"""
muscle_balance_engine.py — Équilibre Musculaire.

Uses exercise_logs with category field (already stored in DB).
Categories: push, pull, legs, core, cardio — anything else → "other".

Computes:
  - % of exercise occurrences per category
  - imbalances: push/pull ratio > 1.4 or < 0.7, legs < 15%
  - top category

Data read only. No writes.
"""
from __future__ import annotations
import logging
from collections import Counter

import db

logger = logging.getLogger("trainingos.muscle_balance")

_KNOWN_CATS = {"push", "pull", "legs", "core", "cardio"}
_MIN_LOGS   = 20

# Keyword fallback for exercises without a category
_PUSH_KW = ("bench", "press", "dip", "pushup", "push", "overhead", "incline",
            "tricep", "shoulder", "ohp", "fly", "chest")
_PULL_KW = ("row", "pull", "chin", "lat", "curl", "bicep", "rear delt",
            "face pull", "shrug", "trap")
_LEGS_KW = ("squat", "leg", "lunge", "hip", "glute", "hamstring", "quad",
            "calf", "rdl", "deadlift", "step", "bulgarian")
_CORE_KW = ("plank", "ab", "crunch", "core", "oblique", "hanging", "hollow")
_CARD_KW = ("run", "bike", "cardio", "treadmill", "row", "assault", "sprint",
            "ellip", "stair")


def _classify(name: str | None, cat: str | None) -> str:
    if cat and cat.lower() in _KNOWN_CATS:
        return cat.lower()
    if not name:
        return "other"
    n = name.lower()
    if any(k in n for k in _PUSH_KW):  return "push"
    if any(k in n for k in _PULL_KW):  return "pull"
    if any(k in n for k in _LEGS_KW):  return "legs"
    if any(k in n for k in _CORE_KW):  return "core"
    if any(k in n for k in _CARD_KW):  return "cardio"
    return "other"


def compute() -> dict:
    logs = db.get_exercise_logs_with_category(days=120) or []

    if len(logs) < _MIN_LOGS:
        return {
            "has_data": False, "ratios": None, "imbalances": [],
            "total_analyzed": len(logs), "top_category": None,
        }

    counts: Counter[str] = Counter()
    for log in logs:
        cat = _classify(log.get("exercise"), log.get("category"))
        if cat != "other":
            counts[cat] += 1

    total = sum(counts.values())
    if total < _MIN_LOGS:
        return {
            "has_data": False, "ratios": None, "imbalances": [],
            "total_analyzed": len(logs), "top_category": None,
        }

    def pct(cat: str) -> int:
        return round(counts[cat] / total * 100)

    ratios = {
        "push":    pct("push"),
        "pull":    pct("pull"),
        "legs":    pct("legs"),
        "core":    pct("core"),
        "cardio":  pct("cardio"),
    }

    imbalances: list[dict] = []
    push_n = counts["push"] or 0
    pull_n = counts["pull"] or 0

    if pull_n > 0 and push_n / pull_n > 1.4:
        imbalances.append({
            "key":     "push_dominant",
            "label":   "Trop de push vs pull",
            "icon":    "arrow.up.circle.fill",
            "detail":  f"{ratios['push']}% push vs {ratios['pull']}% pull",
        })
    elif push_n > 0 and pull_n / push_n > 1.4:
        imbalances.append({
            "key":     "pull_dominant",
            "label":   "Trop de pull vs push",
            "icon":    "arrow.down.circle.fill",
            "detail":  f"{ratios['pull']}% pull vs {ratios['push']}% push",
        })

    if ratios["legs"] < 15 and (push_n + pull_n) > 0:
        imbalances.append({
            "key":     "legs_neglected",
            "label":   "Jambes sous-entraînées",
            "icon":    "figure.run",
            "detail":  f"Seulement {ratios['legs']}% de tes séances",
        })

    top_cat = max(ratios, key=lambda k: ratios[k]) if ratios else None

    return {
        "has_data":       True,
        "ratios":         ratios,
        "imbalances":     imbalances,
        "total_analyzed": len(logs),
        "top_category":   top_cat,
    }
