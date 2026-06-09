"""
rupture_engine.py — Rupture Risk Detection.

Finds historical deviation episodes (2+ consecutive days: no workout + no nutrition logged).
Extracts 7-day pre-episode context (sleep, PSS, workout frequency).
Scores current 7-day context against each historical episode profile.

Signals:
  sommeil_court        — 3-night avg sleep < 6.5h
  stress_croissant     — 7-day PSS avg > 18
  entrainements_manques — 0 sessions in last 5 days
  nutrition_absente    — 0 nutrition days in last 3 days

Score 0-100: signal_count × 18 + similar_episode_count × 14 (+ 10 if ≥3 signals).

Data read only. No writes.
"""
from __future__ import annotations
import logging
from datetime import date, timedelta

import db
from utils import _today_mtl as _today_iso

logger = logging.getLogger("trainingos.rupture")

_LOOKBACK = 120


def _date_range(start: str, end: str) -> list[str]:
    s = date.fromisoformat(start)
    e = date.fromisoformat(end)
    return [(s + timedelta(days=i)).isoformat() for i in range((e - s).days + 1)]


def _find_episodes(sessions: list[dict], nutrition: list[dict], today_str: str) -> list[dict]:
    start_limit = (date.fromisoformat(today_str) - timedelta(days=_LOOKBACK)).isoformat()
    workout_dates = {s["date"] for s in sessions if s.get("completed") and s.get("date")}
    nutrition_dates = {e["date"] for e in nutrition if e.get("date")}
    all_dates = _date_range(start_limit, today_str)
    deviation_set = {d for d in all_dates if d not in workout_dates and d not in nutrition_dates}

    episodes: list[dict] = []
    run: list[str] = []
    for d in all_dates:
        if d in deviation_set:
            run.append(d)
        else:
            if len(run) >= 2:
                episodes.append({"start": run[0], "end": run[-1], "length": len(run)})
            run = []
    if len(run) >= 2:
        episodes.append({"start": run[0], "end": run[-1], "length": len(run)})
    return episodes


def _extract_context(episode_start: str, sessions: list[dict],
                     recovery: list[dict], pss: list[dict]) -> dict:
    ep_date   = date.fromisoformat(episode_start)
    pre_end   = (ep_date - timedelta(days=1)).isoformat()
    pre_start = (ep_date - timedelta(days=7)).isoformat()

    workout_dates = {s["date"] for s in sessions if s.get("completed") and s.get("date")}
    workout_count = sum(1 for d in _date_range(pre_start, pre_end) if d in workout_dates)

    sleep_vals = [float(r["sleep_hours"]) for r in recovery
                  if pre_start <= r.get("date", "") <= pre_end and r.get("sleep_hours")]
    avg_sleep = sum(sleep_vals) / len(sleep_vals) if sleep_vals else None

    pss_vals = [float(r.get("pss_score") or r.get("score") or 0)
                for r in pss if pre_start <= r.get("date", "") <= pre_end]
    avg_pss = sum(pss_vals) / len(pss_vals) if pss_vals else None

    return {"workout_count": workout_count, "avg_sleep": avg_sleep, "avg_pss": avg_pss}


def _current_context(today_str: str, sessions: list[dict],
                     recovery: list[dict], pss: list[dict]) -> dict:
    start7 = (date.fromisoformat(today_str) - timedelta(days=6)).isoformat()
    start3 = (date.fromisoformat(today_str) - timedelta(days=2)).isoformat()

    workout_dates = {s["date"] for s in sessions if s.get("completed") and s.get("date")}
    workout_count = sum(1 for d in _date_range(start7, today_str) if d in workout_dates)

    sleep_vals = [float(r["sleep_hours"]) for r in recovery
                  if start7 <= r.get("date", "") <= today_str and r.get("sleep_hours")]
    avg_sleep = sum(sleep_vals) / len(sleep_vals) if sleep_vals else None

    sleep_3d = [float(r["sleep_hours"]) for r in recovery
                if start3 <= r.get("date", "") <= today_str and r.get("sleep_hours")]
    avg_sleep_3d = sum(sleep_3d) / len(sleep_3d) if sleep_3d else avg_sleep

    pss_vals = [float(r.get("pss_score") or r.get("score") or 0)
                for r in pss if start7 <= r.get("date", "") <= today_str]
    avg_pss = sum(pss_vals) / len(pss_vals) if pss_vals else None

    return {
        "workout_count": workout_count,
        "avg_sleep":     avg_sleep,
        "avg_sleep_3d":  avg_sleep_3d,
        "avg_pss":       avg_pss,
    }


def _active_signals(ctx: dict, nutrition: list[dict], today_str: str) -> list[str]:
    signals: list[str] = []

    if ctx.get("avg_sleep_3d") is not None and ctx["avg_sleep_3d"] < 6.5:
        signals.append("sommeil_court")

    if ctx.get("avg_pss") is not None and ctx["avg_pss"] > 18:
        signals.append("stress_croissant")

    start5 = (date.fromisoformat(today_str) - timedelta(days=4)).isoformat()
    if ctx["workout_count"] == 0 and start5 <= today_str:
        signals.append("entrainements_manques")

    start3 = (date.fromisoformat(today_str) - timedelta(days=2)).isoformat()
    if not any(e.get("date", "") >= start3 for e in nutrition):
        signals.append("nutrition_absente")

    return signals


def _contexts_similar(current: dict, pre: dict) -> bool:
    matches = 0
    if current.get("avg_sleep") is not None and pre.get("avg_sleep") is not None:
        if current["avg_sleep"] < 7.5 and pre["avg_sleep"] < 7.5:
            matches += 1
    if current.get("avg_pss") is not None and pre.get("avg_pss") is not None:
        if current["avg_pss"] > 14 and pre["avg_pss"] > 14:
            matches += 1
    if current["workout_count"] <= 2 and pre["workout_count"] <= 2:
        matches += 1
    return matches >= 2


def compute() -> dict:
    today_str = _today_iso()
    sessions  = db.get_workout_sessions(limit=300) or []
    pss       = db.get_pss_records(limit=100) or []
    recovery  = db.get_recovery_logs(limit=200) or []
    nutrition = db.get_nutrition_entries_recent(120) or []

    episodes  = _find_episodes(sessions, nutrition, today_str)
    cur_ctx   = _current_context(today_str, sessions, recovery, pss)
    signals   = _active_signals(cur_ctx, nutrition, today_str)

    similar_count = 0
    for ep in episodes:
        pre = _extract_context(ep["start"], sessions, recovery, pss)
        if _contexts_similar(cur_ctx, pre):
            similar_count += 1

    signal_count   = len(signals)
    total_episodes = len(episodes)

    score = min(100, signal_count * 18 + similar_count * 14)
    if signal_count >= 3:
        score = min(100, score + 10)

    if score < 20:
        message = "Contexte nominal. Continue comme ça."
    elif score < 40:
        message = "Quelques signaux de vigilance. Surveille ton énergie."
    elif score < 60:
        ep_str = f"{total_episodes} épisode{'s' if total_episodes != 1 else ''} passé{'s' if total_episodes != 1 else ''}"
        message = f"Pattern connu — contexte similaire à tes précédents dérapages ({ep_str})."
    else:
        sim_str = f"{similar_count} épisode{'s' if similar_count != 1 else ''} similaire{'s' if similar_count != 1 else ''}"
        message = f"Contexte de rupture détecté — {sim_str} dans ton historique."

    return {
        "score":            score,
        "signals":          signals,
        "signal_count":     signal_count,
        "similar_episodes": similar_count,
        "total_episodes":   total_episodes,
        "message":          message,
        "has_data":         True,
        "context": {
            "workout_count": cur_ctx["workout_count"],
            "avg_sleep": round(cur_ctx["avg_sleep"], 1) if cur_ctx.get("avg_sleep") is not None else None,
            "avg_pss":   round(cur_ctx["avg_pss"],   1) if cur_ctx.get("avg_pss")   is not None else None,
        },
    }
