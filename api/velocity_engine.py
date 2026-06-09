"""
velocity_engine.py — Velocity of Change: is the transformation accelerating?

Computes a composite score for 4 consecutive 7-day windows, then derives:
  velocity    — rate of change between W1 (recent) and W2 (prior)
  acceleration — whether that rate is itself increasing vs W2→W3
  label       — accélération / stable / décélération / chute_libre

Data read: workout sessions, PSS records, nutrition entries, recovery logs.
No writes. No modification to historical data.
"""
from __future__ import annotations
import logging
import math
from datetime import date, timedelta

import db
from utils import _today_mtl as _today_iso

logger = logging.getLogger("trainingos.velocity")


def _window(offset: int, span: int = 7) -> set[str]:
    today = date.fromisoformat(_today_iso())
    return {(today - timedelta(days=offset + i)).isoformat() for i in range(span)}


def _score_window(
    window: set[str],
    sessions: list[dict],
    pss: list[dict],
    nutrition: list[dict],
    recovery: list[dict],
) -> float | None:
    """0–100 composite score for one 7-day window. None when window has no data."""
    # Workout: frequency + RPE-weighted quality
    w_sess = [s for s in sessions if s.get("date") in window and s.get("completed")]
    freq_score = min(1.0, len(w_sess) / 5.0)
    rpe_score  = min(1.0, sum(float(s.get("rpe") or 7) / 10.0 for s in w_sess) / 5.0)
    workout_score = (freq_score * 0.5 + rpe_score * 0.5) * 100

    # Mind: PSS inverted (0 = perfect, 40 = worst)
    w_pss = [float(r.get("pss_score") or r.get("score") or 0)
             for r in pss if r.get("date") in window]
    pss_score = ((40 - sum(w_pss) / len(w_pss)) / 40 * 100) if w_pss else None

    # Fuel: logged days
    n_days = len({e.get("date") for e in nutrition if e.get("date") in window})
    fuel_score = n_days / 7.0 * 100 if n_days > 0 else None

    # Recovery: sleep quality + HRV (normalised against 60 ms / 10-point scale)
    w_rec = [r for r in recovery if r.get("date") in window]
    rec_score = None
    if w_rec:
        slp = [float(r["sleep_quality"]) for r in w_rec if r.get("sleep_quality")]
        hrv = [float(r["hrv"])           for r in w_rec if r.get("hrv")]
        parts: list[float] = []
        if slp: parts.append(sum(slp) / len(slp) / 10.0 * 100)
        if hrv: parts.append(min(100.0, sum(hrv) / len(hrv) / 60.0 * 100))
        if parts: rec_score = sum(parts) / len(parts)

    # Weighted average — only over components with data
    components = [("workout", 0.40, workout_score)]
    if pss_score  is not None: components.append(("mind",     0.20, pss_score))
    if fuel_score is not None: components.append(("fuel",     0.20, fuel_score))
    if rec_score  is not None: components.append(("recovery", 0.20, rec_score))

    if workout_score == 0 and len(components) == 1:
        return None

    total_w = sum(w for _, w, _ in components)
    return round(sum(s * (w / total_w) for _, w, s in components), 1)


def _pct_change(s1: float | None, s2: float | None) -> float | None:
    if s1 is None or s2 is None:
        return None
    if abs(s2) < 1e-9:
        return 0.0
    return round((s1 - s2) / s2 * 100, 1)


def _label(velocity: float | None, acceleration: float | None) -> str:
    if velocity is None:
        return "foundation"
    if acceleration is not None:
        if acceleration >  10: return "accélération"
        if acceleration > -5:  return "stable"
        if acceleration > -25: return "décélération"
        return "chute_libre"
    if velocity >  5:  return "accélération"
    if velocity > -5:  return "stable"
    if velocity > -20: return "décélération"
    return "chute_libre"


def compute() -> dict:
    sessions  = db.get_workout_sessions(limit=90) or []
    pss       = db.get_pss_records(limit=60) or []
    nutrition = db.get_nutrition_entries_recent(90) or []
    recovery  = db.get_recovery_logs(limit=40) or []

    windows = [_window(i * 7, 7) for i in range(4)]  # W1 = most recent
    scores  = [_score_window(w, sessions, pss, nutrition, recovery) for w in windows]
    w1, w2, w3, w4 = scores

    velocity_recent = _pct_change(w1, w2)
    velocity_prior  = _pct_change(w2, w3)

    acceleration = None
    if velocity_recent is not None and velocity_prior is not None:
        acceleration = round(velocity_recent - velocity_prior, 1)

    trend_pct = _pct_change(w1, w4)

    return {
        "velocity":      velocity_recent,
        "acceleration":  acceleration,
        "label":         _label(velocity_recent, acceleration),
        "weekly_scores": scores,
        "trend_pct":     trend_pct,
        "has_baseline":  w2 is not None,
    }
