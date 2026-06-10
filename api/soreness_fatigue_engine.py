"""
soreness_fatigue_engine.py — Soreness & Fatigue Tracker.

Uses recovery_logs.soreness + recovery_logs.fatigue_perceived (both 1–10).
Computes 8-week weekly averages for each signal.
Flags "overreaching" weeks where both avg > 6.
Trend: last 3 weeks vs preceding 3 weeks (±10 % threshold).

Data read only. No writes.
"""
from __future__ import annotations
import logging
from datetime import date, timedelta
from typing import Optional

import db
from utils import _today_mtl as _today_iso

logger = logging.getLogger("trainingos.soreness_fatigue")

_WEEKS            = 8
_OVERREACH_THRESH = 6.0


def _monday(d: date) -> date:
    return d - timedelta(days=d.weekday())


def compute() -> dict:
    today_str  = _today_iso()
    today      = date.fromisoformat(today_str)
    cutoff     = (today - timedelta(days=_WEEKS * 7)).isoformat()

    logs = db.get_recovery_logs(limit=200) or []
    valid = [l for l in logs if l.get("date") and l["date"] >= cutoff]

    soreness_vals = [l for l in valid if l.get("soreness") is not None]
    fatigue_vals  = [l for l in valid if l.get("fatigue_perceived") is not None]

    if len(soreness_vals) < 4 and len(fatigue_vals) < 4:
        return {
            "has_data": False,
            "weekly_soreness": [],
            "weekly_fatigue": [],
            "overreaching_weeks": 0,
            "soreness_trend": "stable",
            "fatigue_trend": "stable",
            "current_soreness": None,
            "current_fatigue": None,
            "message": "Pas assez de données de récupération.",
        }

    cur_monday = _monday(today)
    weekly_soreness = []
    weekly_fatigue  = []

    for w in range(_WEEKS, 0, -1):
        wm = cur_monday - timedelta(weeks=w)
        we = wm + timedelta(days=6)
        sw = wm.isoformat(); ew = we.isoformat()

        s_vals = [float(l["soreness"]) for l in valid
                  if l.get("soreness") is not None and sw <= l["date"] <= ew]
        f_vals = [float(l["fatigue_perceived"]) for l in valid
                  if l.get("fatigue_perceived") is not None and sw <= l["date"] <= ew]

        s_avg = round(sum(s_vals) / len(s_vals), 1) if s_vals else None
        f_avg = round(sum(f_vals) / len(f_vals), 1) if f_vals else None
        weekly_soreness.append({"week_start": wm.isoformat(), "avg": s_avg})
        weekly_fatigue.append({"week_start":  wm.isoformat(), "avg": f_avg})

    overreaching = sum(
        1 for s, f in zip(weekly_soreness, weekly_fatigue)
        if (s["avg"] or 0) > _OVERREACH_THRESH and (f["avg"] or 0) > _OVERREACH_THRESH
    )

    def _trend(weekly: list[dict]) -> str:
        vals = [w["avg"] for w in weekly if w["avg"] is not None]
        if len(vals) < 6:
            return "stable"
        recent = sum(vals[-3:]) / 3
        prior  = sum(vals[-6:-3]) / 3
        if prior == 0:
            return "stable"
        pct = (recent - prior) / prior * 100
        if pct >= 10:
            return "worsening"
        if pct <= -10:
            return "improving"
        return "stable"

    soreness_trend = _trend(weekly_soreness)
    fatigue_trend  = _trend(weekly_fatigue)

    # Most recent values
    cur_soreness = next(
        (float(l["soreness"]) for l in sorted(valid, key=lambda x: x["date"], reverse=True)
         if l.get("soreness") is not None), None)
    cur_fatigue = next(
        (float(l["fatigue_perceived"]) for l in sorted(valid, key=lambda x: x["date"], reverse=True)
         if l.get("fatigue_perceived") is not None), None)

    if overreaching >= 2:
        message = f"{overreaching} semaines de surmenage détectées — réduis l'intensité."
    elif soreness_trend == "worsening" or fatigue_trend == "worsening":
        message = "Fatigue/courbatures en hausse — surveille la récupération."
    elif soreness_trend == "improving" and fatigue_trend == "improving":
        message = "Récupération en amélioration — tu gères bien la charge."
    else:
        message = "Niveau de fatigue et courbatures stable."

    return {
        "has_data":          True,
        "weekly_soreness":   weekly_soreness,
        "weekly_fatigue":    weekly_fatigue,
        "overreaching_weeks": overreaching,
        "soreness_trend":    soreness_trend,
        "fatigue_trend":     fatigue_trend,
        "current_soreness":  cur_soreness,
        "current_fatigue":   cur_fatigue,
        "message":           message,
    }
