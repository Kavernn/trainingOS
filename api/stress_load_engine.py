"""
stress_load_engine.py — Stress Load Index.

Combines two stress signals per week over the last 4 weeks:
  training_stress — weekly RPE sum normalized 0-100 (peak = 100 at all-time max)
  pss_stress      — weekly PSS avg normalized 0-100 (PSS-4 range 0-16 → × 6.25)

dominant = signal with highest current value ("training" | "pss" | "balanced")
trend    = 4-week direction of combined score ("rising" | "falling" | "stable")

Data read only. No writes.
"""
from __future__ import annotations
import logging
from datetime import date, timedelta
from typing import Optional

import db
from utils import _today_mtl as _today_iso

logger = logging.getLogger("trainingos.stress_load")

_PSS_MAX = 16.0


def _monday(d: date) -> date:
    return d - timedelta(days=d.weekday())


def _week_rpe(sessions: list[dict], monday: date) -> float:
    s, e = monday.isoformat(), (monday + timedelta(days=6)).isoformat()
    return sum(
        float(r.get("rpe") or 0)
        for r in sessions
        if r.get("completed") and s <= (r.get("date") or "") <= e
    )


def _week_pss(pss_records: list[dict], monday: date) -> Optional[float]:
    s, e = monday.isoformat(), (monday + timedelta(days=6)).isoformat()
    vals = [
        float(r.get("pss_score") or r.get("score") or 0)
        for r in pss_records
        if s <= (r.get("date") or "") <= e
    ]
    return sum(vals) / len(vals) if vals else None


def compute() -> dict:
    today_str = _today_iso()
    today     = date.fromisoformat(today_str)
    sessions  = db.get_workout_sessions(limit=400) or []
    pss       = db.get_pss_records(limit=200) or []

    cur_monday = _monday(today)

    # Collect 4 complete weeks + current partial
    weekly: list[dict] = []
    for w in range(4, 0, -1):
        wm  = cur_monday - timedelta(weeks=w)
        rpe = _week_rpe(sessions, wm)
        p   = _week_pss(pss, wm)
        weekly.append({"monday": wm, "rpe": rpe, "pss": p})
    weekly.append({"monday": cur_monday, "rpe": _week_rpe(sessions, cur_monday), "pss": _week_pss(pss, cur_monday)})

    all_rpe = [w["rpe"] for w in weekly]
    peak_rpe = max(all_rpe) if any(v > 0 for v in all_rpe) else 1.0

    weeks_out = []
    for w in weekly:
        t_stress = round(w["rpe"] / peak_rpe * 100) if peak_rpe > 0 else 0
        p_stress = round(w["pss"] / _PSS_MAX * 100) if w["pss"] is not None else None
        combined = round((t_stress + (p_stress or t_stress)) / 2)
        weeks_out.append({
            "week_start": w["monday"].isoformat(),
            "training_stress": t_stress,
            "pss_stress": p_stress,
            "combined": combined,
        })

    has_training = any(w["rpe"] > 0 for w in weekly)
    has_pss      = any(w["pss"] is not None for w in weekly)

    if not has_training and not has_pss:
        return {
            "has_data": False,
            "weeks": weeks_out,
            "current_training_stress": None,
            "current_pss_stress": None,
            "dominant": None,
            "trend": "stable",
            "message": "Pas assez de données.",
        }

    cur = weeks_out[-1]
    t_cur = cur["training_stress"]
    p_cur = cur["pss_stress"]

    if p_cur is None:
        dominant = "training"
    elif t_cur > p_cur + 15:
        dominant = "training"
    elif p_cur > t_cur + 15:
        dominant = "pss"
    else:
        dominant = "balanced"

    combined_scores = [w["combined"] for w in weeks_out]
    early = combined_scores[:2]
    late  = combined_scores[-2:]
    avg_early = sum(early) / len(early) if early else 0
    avg_late  = sum(late)  / len(late)  if late  else 0
    diff = avg_late - avg_early
    if diff >= 8:
        trend = "rising"
    elif diff <= -8:
        trend = "falling"
    else:
        trend = "stable"

    if dominant == "training":
        message = "Charge d'entraînement dominante — assure une récupération suffisante."
    elif dominant == "pss":
        message = "Stress perçu élevé — la charge mentale dépasse la charge physique."
    else:
        message = "Charge équilibrée entre entraînement et stress perçu."

    return {
        "has_data": True,
        "weeks": weeks_out,
        "current_training_stress": t_cur,
        "current_pss_stress": p_cur,
        "dominant": dominant,
        "trend": trend,
        "message": message,
    }
