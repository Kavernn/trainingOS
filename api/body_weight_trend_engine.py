"""
body_weight_trend_engine.py — Body Weight Trend.

Uses body_weight_logs (weight in lbs). Computes:
  - 4-week simple moving average (last 28 days vs preceding 28 days)
  - % change and trend direction: gaining/losing/stable (±1 % threshold)
  - current_pct_of_range: position within 90-day high/low window
  - last 12 weekly averages for sparkline

Data read only. No writes.
"""
from __future__ import annotations
import logging
from datetime import date, timedelta
from typing import Optional

import db
from utils import _today_mtl as _today_iso

logger = logging.getLogger("trainingos.body_weight_trend")

_STABLE_PCT  = 1.0   # within ±1 % = stable
_MIN_ENTRIES = 4


def _monday(d: date) -> date:
    return d - timedelta(days=d.weekday())


def compute() -> dict:
    today_str = _today_iso()
    today     = date.fromisoformat(today_str)

    logs = db.get_body_weight_logs(limit=200) or []
    valid = [l for l in logs if l.get("weight") and l.get("date")]

    if len(valid) < _MIN_ENTRIES:
        return {
            "has_data": False,
            "weekly_avgs": [],
            "trend": "stable",
            "current_weight": None,
            "change_pct": None,
            "current_pct_of_range": None,
            "range_high": None,
            "range_low": None,
            "message": "Pas assez de données de poids.",
        }

    # Sort ascending by date
    valid.sort(key=lambda l: l["date"])
    by_date = {l["date"]: float(l["weight"]) for l in valid}

    # 4-week windows
    recent_start = (today - timedelta(days=28)).isoformat()
    prior_start  = (today - timedelta(days=56)).isoformat()
    recent_end   = today_str
    prior_end    = (today - timedelta(days=29)).isoformat()

    recent_vals = [v for d_str, v in by_date.items() if recent_start <= d_str <= recent_end]
    prior_vals  = [v for d_str, v in by_date.items() if prior_start  <= d_str <= prior_end]

    avg_recent = sum(recent_vals) / len(recent_vals) if recent_vals else None
    avg_prior  = sum(prior_vals)  / len(prior_vals)  if prior_vals  else None

    trend = "stable"
    change_pct: Optional[float] = None
    if avg_recent is not None and avg_prior and avg_prior > 0:
        change_pct = (avg_recent - avg_prior) / avg_prior * 100
        if change_pct >= _STABLE_PCT:
            trend = "gaining"
        elif change_pct <= -_STABLE_PCT:
            trend = "losing"

    # 90-day range
    range_start = (today - timedelta(days=90)).isoformat()
    range_vals  = [v for d_str, v in by_date.items() if d_str >= range_start]
    range_high  = max(range_vals) if range_vals else None
    range_low   = min(range_vals) if range_vals else None

    current_weight = by_date[max(by_date.keys())]

    current_pct: Optional[int] = None
    if range_high and range_low and range_high > range_low:
        current_pct = round((current_weight - range_low) / (range_high - range_low) * 100)

    # Weekly averages (last 12 weeks)
    cur_monday = _monday(today)
    weekly_avgs = []
    for w in range(12, 0, -1):
        wm  = cur_monday - timedelta(weeks=w)
        we  = wm + timedelta(days=6)
        wv  = [v for d_str, v in by_date.items() if wm.isoformat() <= d_str <= we.isoformat()]
        avg = round(sum(wv) / len(wv), 1) if wv else None
        weekly_avgs.append({"week_start": wm.isoformat(), "avg": avg})
    # current partial week
    cur_wv  = [v for d_str, v in by_date.items() if cur_monday.isoformat() <= d_str <= today_str]
    cur_avg = round(sum(cur_wv) / len(cur_wv), 1) if cur_wv else None
    weekly_avgs.append({"week_start": cur_monday.isoformat(), "avg": cur_avg})

    if trend == "gaining":
        message = f"Poids en hausse (+{abs(round(change_pct or 0, 1))} % sur 4 sem.)."
    elif trend == "losing":
        message = f"Poids en baisse ({round(change_pct or 0, 1)} % sur 4 sem.)."
    else:
        message = "Poids stable sur les 4 dernières semaines."

    return {
        "has_data":             True,
        "weekly_avgs":          weekly_avgs,
        "trend":                trend,
        "current_weight":       round(current_weight, 1),
        "change_pct":           round(change_pct, 1) if change_pct is not None else None,
        "current_pct_of_range": current_pct,
        "range_high":           round(range_high, 1) if range_high else None,
        "range_low":            round(range_low, 1)  if range_low  else None,
        "message":              message,
    }
