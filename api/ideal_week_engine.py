"""
ideal_week_engine.py — Blueprint Semaine Idéale.

Scores every complete Mon-Sun week in history:
  score = training_days × avg_rpe
        + (good_sleep_nights / 7) × 20
        + (nutrition_days    / 7) × 15
        - max(0, avg_pss - 15)   × 0.5

Returns the best week as a blueprint, current week for comparison,
match_pct, and gaps (metrics below 70% of the blueprint).

Data read only. No writes.
"""
from __future__ import annotations
import logging
from datetime import date, timedelta

import db
from utils import _today_mtl as _today_iso

logger = logging.getLogger("trainingos.ideal_week")

_SLEEP_TARGET = 7.5


def _monday(d: date) -> date:
    return d - timedelta(days=d.weekday())


def _week_profile(sessions: list[dict], recovery: list[dict],
                  nutrition: list[dict], pss: list[dict],
                  start: date) -> dict:
    end   = start + timedelta(days=6)
    s_str = start.isoformat()
    e_str = end.isoformat()

    done  = [s for s in sessions
             if s.get("completed") and s_str <= (s.get("date") or "") <= e_str]
    training_days = len(done)
    avg_rpe = (sum(float(s.get("rpe") or 7) for s in done) / len(done)
               if done else 0.0)

    sleep_vals = [float(r["sleep_hours"]) for r in recovery
                  if s_str <= (r.get("date") or "") <= e_str and r.get("sleep_hours")]
    avg_sleep = sum(sleep_vals) / len(sleep_vals) if sleep_vals else None
    good_sleep = sum(1 for h in sleep_vals if h >= _SLEEP_TARGET)

    nutr_days = len({e["date"] for e in nutrition
                     if s_str <= (e.get("date") or "") <= e_str})

    pss_vals = [float(r.get("pss_score") or r.get("score") or 0)
                for r in pss if s_str <= (r.get("date") or "") <= e_str]
    avg_pss = sum(pss_vals) / len(pss_vals) if pss_vals else None

    score = (training_days * avg_rpe
             + (good_sleep / 7) * 20
             + (nutr_days  / 7) * 15
             - max(0, (avg_pss or 15) - 15) * 0.5)

    return {
        "start":          s_str,
        "end":            e_str,
        "score":          round(score, 1),
        "training_days":  training_days,
        "avg_rpe":        round(avg_rpe, 1),
        "avg_sleep":      round(avg_sleep, 1) if avg_sleep is not None else None,
        "good_sleep":     good_sleep,
        "nutrition_days": nutr_days,
        "avg_pss":        round(avg_pss, 1) if avg_pss is not None else None,
    }


def compute() -> dict:
    today_str = _today_iso()
    today     = date.fromisoformat(today_str)
    sessions  = db.get_workout_sessions(limit=400) or []
    recovery  = db.get_recovery_logs(limit=300) or []
    nutrition = db.get_nutrition_entries_recent(365) or []
    pss       = db.get_pss_records(limit=200) or []

    completed = [s for s in sessions if s.get("completed") and s.get("date")]
    if len(completed) < 7:
        return {"has_data": False, "best_week": None, "current_week": None,
                "match_pct": None, "gaps": [], "total_weeks": 0}

    cur_monday = _monday(today)
    earliest   = _monday(min(date.fromisoformat(s["date"]) for s in completed))

    weeks = []
    w = earliest
    while w < cur_monday:
        p = _week_profile(sessions, recovery, nutrition, pss, w)
        if p["training_days"] >= 1:
            weeks.append(p)
        w += timedelta(weeks=1)

    if not weeks:
        return {"has_data": False, "best_week": None, "current_week": None,
                "match_pct": None, "gaps": [], "total_weeks": 0}

    best    = max(weeks, key=lambda w: w["score"])
    current = _week_profile(sessions, recovery, nutrition, pss, cur_monday)

    # Gaps: dimensions where current < 70% of best
    _gap_fields = [
        ("training_days",  "Séances d'entraînement",   "figure.strengthtraining.traditional"),
        ("good_sleep",     "Nuits ≥ 7h30",             "moon.zzz.fill"),
        ("nutrition_days", "Jours nutrition loggés",   "fork.knife.circle.fill"),
    ]
    gaps = []
    match_scores = []
    for key, label, icon in _gap_fields:
        best_val = best.get(key) or 0
        cur_val  = current.get(key) or 0
        if best_val > 0:
            ratio = min(1.0, cur_val / best_val)
            match_scores.append(ratio)
            if ratio < 0.7:
                gaps.append({"key": key, "label": label, "icon": icon,
                              "current": cur_val, "ideal": best_val})

    # PSS gap (lower = better — penalise if current significantly higher)
    if best.get("avg_pss") and current.get("avg_pss"):
        if current["avg_pss"] > best["avg_pss"] + 5:
            gaps.append({"key": "avg_pss", "label": "Niveau de stress",
                         "icon": "brain.head.profile",
                         "current": current["avg_pss"], "ideal": best["avg_pss"]})

    match_pct = round(sum(match_scores) / len(match_scores) * 100) if match_scores else None

    return {
        "has_data":     True,
        "best_week":    best,
        "current_week": current,
        "match_pct":    match_pct,
        "gaps":         gaps,
        "total_weeks":  len(weeks),
    }
