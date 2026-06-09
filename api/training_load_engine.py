"""
training_load_engine.py — Training Load / ACWR.

Acute load  = sum of session RPE over last 7 days.
Chronic load = average of 4 weekly RPE sums over last 28 days.
Ratio       = acute / chronic.

Zones:
  under   — ratio < 0.80  (undertrained / detraining)
  optimal — 0.80 ≤ ratio ≤ 1.30  (sweet spot)
  spike   — ratio > 1.30  (overreaching / injury risk)

trend_4w: list of 4 weekly loads, oldest first, for sparkline.

Data read only. No writes.
"""
from __future__ import annotations
import logging
from datetime import date, timedelta

import db
from utils import _today_mtl as _today_iso

logger = logging.getLogger("trainingos.training_load")


def _week_load(sessions: list[dict], start: str, end: str) -> float:
    return sum(
        float(s.get("rpe") or 7)
        for s in sessions
        if s.get("completed") and start <= (s.get("date") or "") <= end
    )


def compute() -> dict:
    today_str = _today_iso()
    today     = date.fromisoformat(today_str)
    sessions  = db.get_workout_sessions(limit=300) or []

    completed = [s for s in sessions if s.get("completed") and s.get("date")]
    if len(completed) < 3:
        return {"has_data": False, "acute": None, "chronic": None,
                "ratio": None, "zone": "optimal", "trend_4w": [], "message": ""}

    # Acute: current 7-day window
    acute = _week_load(sessions,
                       (today - timedelta(days=6)).isoformat(),
                       today_str)

    # Chronic: average of 4 rolling weekly loads (newest = week 0, oldest = week 3)
    weekly = []
    for w in range(4):
        w_end   = (today - timedelta(days=w * 7)).isoformat()
        w_start = (today - timedelta(days=w * 7 + 6)).isoformat()
        weekly.append(_week_load(sessions, w_start, w_end))
    chronic = sum(weekly) / 4

    ratio = round(acute / chronic, 2) if chronic > 0 else None

    # trend_4w oldest → newest
    trend_4w = [round(v, 1) for v in reversed(weekly)]

    if ratio is None:
        zone = "optimal"
    elif ratio < 0.8:
        zone = "under"
    elif ratio <= 1.3:
        zone = "optimal"
    else:
        zone = "spike"

    if ratio is None:
        msg = "Charge chronique insuffisante pour calculer le ratio."
    elif zone == "under":
        msg = f"Charge sous-optimale ({ratio}×). Augmente progressivement le volume."
    elif zone == "optimal":
        msg = f"Zone optimale ({ratio}×). Continue à ce rythme."
    else:
        msg = f"Risque de surentraînement ({ratio}×). Priorise la récupération."

    return {
        "has_data": True,
        "acute":    round(acute, 1),
        "chronic":  round(chronic, 1),
        "ratio":    ratio,
        "zone":     zone,
        "trend_4w": trend_4w,
        "message":  msg,
    }
