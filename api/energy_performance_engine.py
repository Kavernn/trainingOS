"""
energy_performance_engine.py — Energy × Performance Correlation.

Groups completed sessions by pre-session energy level (energy_pre field):
  low    — 1–3
  medium — 4–6
  high   — 7–10

Computes avg RPE per bucket. Min 3 sessions per bucket for has_data.
best_energy: bucket with highest avg RPE (you perform better when…).

Data read only. No writes.
"""
from __future__ import annotations
import logging
from typing import Optional

import db

logger = logging.getLogger("trainingos.energy_performance")

_BUCKETS = [
    ("low",    1,  3),
    ("medium", 4,  6),
    ("high",   7, 10),
]

_LABELS = {"low": "Bas (1–3)", "medium": "Moyen (4–6)", "high": "Élevé (7–10)"}


def _bucket(energy: int) -> str:
    if energy <= 3:
        return "low"
    if energy <= 6:
        return "medium"
    return "high"


def compute() -> dict:
    sessions = db.get_workout_sessions(limit=400) or []

    valid = [
        s for s in sessions
        if s.get("completed")
        and s.get("rpe") is not None and float(s.get("rpe") or 0) > 0
        and s.get("energy_pre") is not None
    ]

    if len(valid) < 6:
        return {
            "has_data": False,
            "buckets": [],
            "best_energy": None,
            "sessions_analyzed": 0,
            "rpe_diff": None,
            "message": "Pas assez de données énergie/performance.",
        }

    groups: dict[str, list[float]] = {"low": [], "medium": [], "high": []}
    for s in valid:
        b = _bucket(int(s["energy_pre"]))
        groups[b].append(float(s["rpe"]))

    buckets_out = []
    best_energy: Optional[str] = None
    best_rpe = -1.0

    for key, _, _ in _BUCKETS:
        vals = groups[key]
        avg_rpe = round(sum(vals) / len(vals), 1) if vals else None
        buckets_out.append({
            "bucket":  key,
            "label":   _LABELS[key],
            "avg_rpe": avg_rpe,
            "count":   len(vals),
        })
        if avg_rpe is not None and avg_rpe > best_rpe:
            best_rpe    = avg_rpe
            best_energy = key

    # RPE diff: high vs low (if both have data)
    high_avg = next((b["avg_rpe"] for b in buckets_out if b["bucket"] == "high" and b["avg_rpe"]), None)
    low_avg  = next((b["avg_rpe"] for b in buckets_out if b["bucket"] == "low"  and b["avg_rpe"]), None)
    rpe_diff = round(high_avg - low_avg, 1) if high_avg is not None and low_avg is not None else None

    has_enough = any(b["count"] >= 3 for b in buckets_out)
    if not has_enough:
        return {
            "has_data": False,
            "buckets": buckets_out,
            "best_energy": None,
            "sessions_analyzed": len(valid),
            "rpe_diff": None,
            "message": "Pas assez de données par niveau d'énergie.",
        }

    if best_energy == "high":
        message = "Tu performes mieux quand ton énergie pré-séance est élevée."
    elif best_energy == "medium":
        message = "Ton RPE est optimal à énergie modérée — tu t'autorégules bien."
    elif best_energy == "low":
        message = "Tu t'entraînes fort même avec peu d'énergie — surveille la fatigue chronique."
    else:
        message = "Corrélation énergie/performance non concluante."

    return {
        "has_data":          True,
        "buckets":           buckets_out,
        "best_energy":       best_energy,
        "sessions_analyzed": len(valid),
        "rpe_diff":          rpe_diff,
        "message":           message,
    }
