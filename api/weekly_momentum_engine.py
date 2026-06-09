"""
weekly_momentum_engine.py — Weekly Momentum Score.

Score 0–100 built from 4 weighted pillars (current week Mon→today):
  Training   35% — sessions / weekly avg (last 4 completed weeks)
  Sleep      25% — avg_sleep / 8.0 (capped at 1.0)
  Nutrition  25% — nutrition_days / 7
  Stress     15% — (30 − avg_pss) / 30 (higher pss → lower score)

Also computes scores for the last 4 complete weeks and compares to
the rolling average so the user can see a trend.

Data read only. No writes.
"""
from __future__ import annotations
import logging
from datetime import date, timedelta
from typing import Optional

import db
from utils import _today_mtl as _today_iso

logger = logging.getLogger("trainingos.weekly_momentum")

_SLEEP_TARGET = 8.0
_PSS_MAX      = 30.0

_W_TRAINING   = 0.35
_W_SLEEP      = 0.25
_W_NUTRITION  = 0.25
_W_STRESS     = 0.15


def _monday(d: date) -> date:
    return d - timedelta(days=d.weekday())


def _week_score(
    sessions:  list[dict],
    recovery:  list[dict],
    nutrition: list[dict],
    pss:       list[dict],
    monday:    date,
    sunday:    date,
    avg_sessions_ref: Optional[float],
) -> dict:
    s_str = monday.isoformat()
    e_str = sunday.isoformat()

    done = [s for s in sessions
            if s.get("completed") and s_str <= (s.get("date") or "") <= e_str]
    training_days = len(done)

    sleep_vals = [float(r["sleep_hours"]) for r in recovery
                  if s_str <= (r.get("date") or "") <= e_str and r.get("sleep_hours")]
    avg_sleep = round(sum(sleep_vals) / len(sleep_vals), 1) if sleep_vals else None

    nutr_days = len({e["date"] for e in nutrition
                     if s_str <= (e.get("date") or "") <= e_str})

    pss_vals = [float(r.get("pss_score") or r.get("score") or 0)
                for r in pss if s_str <= (r.get("date") or "") <= e_str]
    avg_pss = round(sum(pss_vals) / len(pss_vals), 1) if pss_vals else None

    # Pillar scores (0–100)
    ref_sessions = avg_sessions_ref if avg_sessions_ref and avg_sessions_ref > 0 else 3.0
    p_training  = min(100.0, training_days / ref_sessions * 100)
    p_sleep     = min(100.0, (avg_sleep or 0) / _SLEEP_TARGET * 100) if avg_sleep else 50.0
    p_nutrition = min(100.0, nutr_days / 7 * 100)
    p_stress    = max(0.0, min(100.0, (_PSS_MAX - (avg_pss or 15)) / _PSS_MAX * 100))

    score = round(
        p_training  * _W_TRAINING +
        p_sleep     * _W_SLEEP    +
        p_nutrition * _W_NUTRITION +
        p_stress    * _W_STRESS
    )

    return {
        "week_start":     s_str,
        "score":          score,
        "training_days":  training_days,
        "avg_sleep":      avg_sleep,
        "nutrition_days": nutr_days,
        "avg_pss":        avg_pss,
        "pillars": {
            "training":   round(p_training),
            "sleep":      round(p_sleep),
            "nutrition":  round(p_nutrition),
            "stress":     round(p_stress),
        },
    }


def compute() -> dict:
    today_str = _today_iso()
    today     = date.fromisoformat(today_str)
    sessions  = db.get_workout_sessions(limit=400) or []
    recovery  = db.get_recovery_logs(limit=200) or []
    nutrition = db.get_nutrition_entries_recent(120) or []
    pss       = db.get_pss_records(limit=150) or []

    completed = [s for s in sessions if s.get("completed") and s.get("date")]
    if len(completed) < 7:
        return {
            "has_data": False, "score": None, "pillars": None,
            "prev_avg": None, "trend_pct": None,
            "week_start": None, "history": [], "message": "Pas assez de données.",
        }

    cur_monday = _monday(today)
    cur_sunday = cur_monday + timedelta(days=6)

    # Last 4 complete weeks for baseline + history
    history = []
    for w in range(4, 0, -1):
        wm = cur_monday - timedelta(weeks=w)
        ws = wm + timedelta(days=6)
        completed_past = [s for s in completed
                          if wm.isoformat() <= s["date"] <= ws.isoformat()]
        if not completed_past and w == 4:
            continue
        avg_ref = None  # use default for past weeks
        wk = _week_score(sessions, recovery, nutrition, pss, wm, ws, avg_ref)
        history.append(wk)

    avg_sessions_ref: Optional[float] = None
    if history:
        avg_sessions_ref = round(
            sum(h["training_days"] for h in history) / len(history), 1
        )

    current = _week_score(sessions, recovery, nutrition, pss,
                          cur_monday, cur_sunday, avg_sessions_ref)

    prev_avg: Optional[float] = None
    if history:
        prev_avg = round(sum(h["score"] for h in history) / len(history))

    trend_pct: Optional[int] = None
    if prev_avg and prev_avg > 0:
        trend_pct = round((current["score"] - prev_avg) / prev_avg * 100)

    score = current["score"]
    if score >= 75:
        message = "Semaine en feu — tous les piliers alignés."
    elif score >= 50:
        message = "Momentum solide — quelques axes à consolider."
    elif score >= 30:
        message = "Semaine sous ta moyenne — recentre-toi sur les fondamentaux."
    else:
        message = "Momentum en berne — reprends les bases."

    return {
        "has_data":   True,
        "score":      score,
        "pillars":    current["pillars"],
        "prev_avg":   prev_avg,
        "trend_pct":  trend_pct,
        "week_start": current["week_start"],
        "history":    [{"week_start": h["week_start"], "score": h["score"]} for h in history],
        "message":    message,
    }
