"""
sleep_hrv_engine.py — Sleep Duration × HRV Correlation.

Groups recovery_logs entries by sleep duration bucket:
  short  — < 7 h
  optimal — 7–8 h
  long   — > 8 h

Computes average HRV per bucket (only rows with both fields present).
Min 3 data points across any buckets for has_data.
Identifies best_bucket = highest avg HRV.

Data read only. No writes.
"""
from __future__ import annotations
import logging
from typing import Optional

import db

logger = logging.getLogger("trainingos.sleep_hrv")

_BUCKETS = [
    ("short",   None, 7.0),
    ("optimal", 7.0,  8.0),
    ("long",    8.0,  None),
]

_LABELS = {
    "short":   "< 7 h",
    "optimal": "7–8 h",
    "long":    "> 8 h",
}


def _bucket(sleep_h: float) -> str:
    if sleep_h < 7.0:
        return "short"
    if sleep_h <= 8.0:
        return "optimal"
    return "long"


def compute() -> dict:
    logs = db.get_recovery_logs(limit=120) or []

    valid = [
        r for r in logs
        if r.get("sleep_hours") is not None and r.get("hrv") is not None
        and float(r.get("hrv") or 0) > 0
    ]

    if len(valid) < 3:
        return {
            "has_data": False,
            "buckets": [],
            "best_bucket": None,
            "sessions_analyzed": 0,
            "message": "Pas assez de données sommeil/HRV.",
        }

    groups: dict[str, list[float]] = {"short": [], "optimal": [], "long": []}
    for r in valid:
        b = _bucket(float(r["sleep_hours"]))
        groups[b].append(float(r["hrv"]))

    buckets_out = []
    best_bucket: Optional[str] = None
    best_hrv = -1.0

    for key, _, _ in _BUCKETS:
        vals = groups[key]
        avg_hrv = round(sum(vals) / len(vals), 1) if vals else None
        buckets_out.append({
            "bucket": key,
            "label": _LABELS[key],
            "avg_hrv": avg_hrv,
            "count": len(vals),
        })
        if avg_hrv is not None and avg_hrv > best_hrv:
            best_hrv = avg_hrv
            best_bucket = key

    if best_bucket == "optimal":
        message = "Ton HRV est optimal avec 7–8 h de sommeil."
    elif best_bucket == "long":
        message = "Ton HRV est meilleur avec plus de 8 h de sommeil."
    elif best_bucket == "short":
        message = "Les données suggèrent un HRV élevé malgré peu de sommeil — vérifie la cohérence."
    else:
        message = "Données insuffisantes pour identifier un pattern clair."

    return {
        "has_data": True,
        "buckets": buckets_out,
        "best_bucket": best_bucket,
        "sessions_analyzed": len(valid),
        "message": message,
    }
