"""
sleep_debt_engine.py — Sleep Debt Tracker.

Target: 8h / night.
Debt = sum(target - actual) over window (positive = in debt, negative = surplus).

Computes:
  debt_7d          — hours owed over last 7 logged nights
  debt_30d         — hours owed over last 30 logged nights
  avg_sleep_7d     — actual 7-night average
  trend            — creuser / stable / rembourser (based on last 3 vs prior 4 nights)
  nights_to_recover — at current avg, nights needed to clear 7d debt

Data read only. No writes.
"""
from __future__ import annotations
import logging
from datetime import date, timedelta

import db
from utils import _today_mtl as _today_iso

logger = logging.getLogger("trainingos.sleep_debt")

_TARGET = 8.0


def _debt(recovery: list[dict], start: str, end: str) -> tuple[float, int]:
    total = 0.0
    n = 0
    for r in recovery:
        d = r.get("date", "")
        if start <= d <= end and r.get("sleep_hours") is not None:
            total += _TARGET - float(r["sleep_hours"])
            n += 1
    return round(total, 1), n


def compute() -> dict:
    today_str = _today_iso()
    today     = date.fromisoformat(today_str)
    recovery  = db.get_recovery_logs(limit=60) or []

    # Exclude today — tonight's sleep isn't logged yet
    end      = (today - timedelta(days=1)).isoformat()
    start_7  = (today - timedelta(days=7)).isoformat()
    start_30 = (today - timedelta(days=30)).isoformat()

    debt_7d,  logged_7d  = _debt(recovery, start_7,  end)
    debt_30d, logged_30d = _debt(recovery, start_30, end)

    if logged_7d < 3:
        return {"has_data": False, "debt_7d": None, "debt_30d": None,
                "trend": "stable", "nights_to_recover": None, "avg_sleep_7d": None,
                "target": _TARGET, "logged_7d": logged_7d, "logged_30d": logged_30d}

    vals_7 = [float(r["sleep_hours"]) for r in recovery
              if start_7 <= r.get("date", "") <= end and r.get("sleep_hours") is not None]
    avg_7d = round(sum(vals_7) / len(vals_7), 1) if vals_7 else None

    # Trend: last 3 nights vs preceding 4
    sorted_logs = sorted(
        [r for r in recovery if r.get("sleep_hours") and r.get("date", "") <= end],
        key=lambda r: r["date"], reverse=True
    )
    recent = [float(r["sleep_hours"]) for r in sorted_logs[:3]]
    prior  = [float(r["sleep_hours"]) for r in sorted_logs[3:7]]

    trend = "stable"
    if recent and prior:
        diff = sum(recent) / len(recent) - sum(prior) / len(prior)
        if diff > 0.3:
            trend = "rembourser"
        elif diff < -0.3:
            trend = "creuser"

    # Nights to recover
    nights_to_recover = None
    if debt_7d <= 0:
        nights_to_recover = 0
    elif avg_7d is not None and avg_7d > _TARGET:
        surplus = avg_7d - _TARGET
        nights_to_recover = round(debt_7d / surplus)

    return {
        "has_data":          True,
        "debt_7d":           debt_7d,
        "debt_30d":          debt_30d if logged_30d >= 5 else None,
        "avg_sleep_7d":      avg_7d,
        "target":            _TARGET,
        "trend":             trend,
        "nights_to_recover": nights_to_recover,
        "logged_7d":         logged_7d,
        "logged_30d":        logged_30d,
    }
