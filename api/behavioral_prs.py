"""
behavioral_prs.py — Behavioral Personal Records.

Tracks records on non-physical dimensions that matter as much as a squat PR:
  sleep_streak      — consecutive nights ≥ 7.5h sleep
  nutrition_streak  — consecutive days with nutrition logged
  stress_30d_avg    — 30-day rolling PSS average at all-time low
  sleep_quality_7d  — 7-day sleep quality average at all-time high

Each PR is marked as:
  is_active  — currently being lived (current value = best ever)
  value      — current measurement
  best_ever  — all-time record value
  set_date   — date the record was set / started

Idempotent: same data → same output.
Data read only. No writes.
"""
from __future__ import annotations
import logging
import hashlib
from datetime import date, timedelta

import db
from utils import _today_mtl as _today_iso

logger = logging.getLogger("trainingos.behavioral_prs")


def _uid(*parts) -> str:
    return hashlib.md5("_".join(str(p) for p in parts).encode()).hexdigest()[:16]


def _current_streak(active_dates: set[str], sorted_all_dates: list[str]) -> tuple[int, str | None]:
    """Return (length, start_date) of the current ongoing streak."""
    today_str = _today_iso()
    streak = 0
    start = None
    for d in reversed(sorted_all_dates):
        if d > today_str:
            continue
        if d in active_dates:
            streak += 1
            start = d
        else:
            break
    return streak, start


def _all_streaks(active_dates: set[str], sorted_all_dates: list[str]) -> list[tuple[int, str]]:
    """Return list of (length, start_date) for every streak in history."""
    streaks: list[tuple[int, str]] = []
    cur_len = 0
    cur_start = None
    today_str = _today_iso()

    for d in sorted_all_dates:
        if d > today_str:
            break
        if d in active_dates:
            cur_len += 1
            if cur_start is None:
                cur_start = d
        else:
            if cur_len > 0 and cur_start:
                streaks.append((cur_len, cur_start))
            cur_len = 0
            cur_start = None
    if cur_len > 0 and cur_start:
        streaks.append((cur_len, cur_start))
    return streaks


def _sleep_streak(recovery: list[dict]) -> dict | None:
    threshold = 7.5
    sorted_logs = sorted([r for r in recovery if r.get("sleep_hours")],
                          key=lambda r: r.get("date", ""))
    active = {r["date"] for r in sorted_logs if float(r["sleep_hours"]) >= threshold}
    all_dates = [r["date"] for r in sorted_logs]
    if not all_dates:
        return None

    streaks = _all_streaks(active, all_dates)
    if not streaks:
        return None

    best_len, best_start = max(streaks, key=lambda s: s[0])
    cur_len, cur_start = _current_streak(active, all_dates)

    return {
        "id":          _uid("sleep_streak", best_len, best_start),
        "type":        "sleep_streak",
        "label":       "Nuits ≥ 7h30 consécutives",
        "icon":        "moon.zzz.fill",
        "value":       cur_len,
        "best_ever":   best_len,
        "set_date":    best_start,
        "is_active":   cur_len >= best_len and cur_len > 0,
        "unit":        "nuits",
        "has_data":    True,
    }


def _nutrition_streak(nutrition: list[dict]) -> dict | None:
    logged_dates = sorted({e["date"] for e in nutrition if e.get("date")})
    if not logged_dates:
        return None

    logged_set = set(logged_dates)
    today = date.fromisoformat(_today_iso())
    # Generate full date range from first log to today
    first = date.fromisoformat(logged_dates[0])
    all_dates = [(first + timedelta(days=i)).isoformat()
                 for i in range((today - first).days + 1)]

    streaks = _all_streaks(logged_set, all_dates)
    if not streaks:
        return None

    best_len, best_start = max(streaks, key=lambda s: s[0])
    cur_len, cur_start = _current_streak(logged_set, all_dates)

    return {
        "id":        _uid("nutrition_streak", best_len, best_start),
        "type":      "nutrition_streak",
        "label":     "Jours nutrition loggés consécutifs",
        "icon":      "fork.knife.circle.fill",
        "value":     cur_len,
        "best_ever": best_len,
        "set_date":  best_start,
        "is_active": cur_len >= best_len and cur_len > 0,
        "unit":      "jours",
        "has_data":  True,
    }


def _stress_30d_avg(pss: list[dict]) -> dict | None:
    sorted_pss = sorted(pss, key=lambda r: r.get("date", ""))
    if len(sorted_pss) < 5:
        return None

    all_time_low = None
    all_time_low_date = None
    best_window_center = None

    for i, rec in enumerate(sorted_pss):
        rec_date = rec.get("date", "")
        rec_d = date.fromisoformat(rec_date)
        cutoff = (rec_d - timedelta(days=30)).isoformat()
        window_scores = [float(r.get("pss_score") or r.get("score") or 0)
                         for r in sorted_pss[:i + 1]
                         if r.get("date", "") >= cutoff]
        if len(window_scores) < 3:
            continue
        avg = sum(window_scores) / len(window_scores)
        if all_time_low is None or avg < all_time_low:
            all_time_low = avg
            all_time_low_date = rec_date

    if all_time_low is None:
        return None

    # Current 30d avg
    today_str = _today_iso()
    cutoff_now = (date.fromisoformat(today_str) - timedelta(days=30)).isoformat()
    recent = [float(r.get("pss_score") or r.get("score") or 0)
              for r in sorted_pss if r.get("date", "") >= cutoff_now]
    current_avg = sum(recent) / len(recent) if recent else None

    return {
        "id":        _uid("stress_30d", round(all_time_low, 1), all_time_low_date),
        "type":      "stress_30d_avg",
        "label":     "Stress moyen 30J le plus bas",
        "icon":      "brain.head.profile",
        "value":     round(current_avg, 1) if current_avg is not None else None,
        "best_ever": round(all_time_low, 1),
        "set_date":  all_time_low_date,
        "is_active": (current_avg is not None and round(current_avg, 1) <= round(all_time_low, 1)),
        "unit":      "/40",
        "has_data":  True,
    }


def _sleep_quality_7d(recovery: list[dict]) -> dict | None:
    sorted_logs = sorted([r for r in recovery if r.get("sleep_quality")],
                          key=lambda r: r.get("date", ""))
    if len(sorted_logs) < 5:
        return None

    all_time_high = None
    all_time_high_date = None

    for i, rec in enumerate(sorted_logs):
        rec_date = rec.get("date", "")
        rec_d = date.fromisoformat(rec_date)
        cutoff = (rec_d - timedelta(days=7)).isoformat()
        window = [float(r["sleep_quality"]) for r in sorted_logs[:i + 1]
                  if r.get("date", "") >= cutoff]
        if len(window) < 3:
            continue
        avg = sum(window) / len(window)
        if all_time_high is None or avg > all_time_high:
            all_time_high = avg
            all_time_high_date = rec_date

    if all_time_high is None:
        return None

    today_str = _today_iso()
    cutoff_now = (date.fromisoformat(today_str) - timedelta(days=7)).isoformat()
    recent = [float(r["sleep_quality"]) for r in sorted_logs
              if r.get("date", "") >= cutoff_now]
    current_avg = sum(recent) / len(recent) if recent else None

    return {
        "id":        _uid("sleep_quality", round(all_time_high, 2), all_time_high_date),
        "type":      "sleep_quality_7d",
        "label":     "Qualité de sommeil 7J la plus haute",
        "icon":      "star.fill",
        "value":     round(current_avg, 1) if current_avg is not None else None,
        "best_ever": round(all_time_high, 1),
        "set_date":  all_time_high_date,
        "is_active": (current_avg is not None and round(current_avg, 1) >= round(all_time_high, 1)),
        "unit":      "/10",
        "has_data":  True,
    }


def compute() -> dict:
    recovery  = db.get_recovery_logs(limit=500) or []
    pss       = db.get_pss_records(limit=500) or []
    nutrition = db.get_nutrition_entries_recent(365) or []

    results = []
    for fn in [_sleep_streak, _nutrition_streak]:
        try:
            r = fn(recovery) if fn == _sleep_streak else fn(nutrition)
            if r:
                results.append(r)
        except Exception as e:
            logger.error("%s error: %s", fn.__name__, e)

    try:
        r = _stress_30d_avg(pss)
        if r:
            results.append(r)
    except Exception as e:
        logger.error("stress_30d_avg error: %s", e)

    try:
        r = _sleep_quality_7d(recovery)
        if r:
            results.append(r)
    except Exception as e:
        logger.error("sleep_quality_7d error: %s", e)

    active_prs = [r for r in results if r.get("is_active")]

    return {
        "prs":        results,
        "total":      len(results),
        "active_prs": len(active_prs),
        "has_data":   len(results) > 0,
    }
