"""
performance_conditions_engine.py — Conditions de Performance.

Identifies the personal "recipe" for peak training sessions.

1. Rank all completed sessions by RPE (top 20%).
2. For each top session, extract context from the 24h prior:
   sommeil_optimal  — ≥ 7.5h sleep the night before
   hrv_elevé        — HRV ≥ 60 that morning
   stress_faible    — PSS avg < 15 over the preceding 7 days
   nutrition_faite  — nutrition logged the day before
   repos_adéquat   — 1-3 rest days since previous session
3. Conditions present in ≥ 55% of top sessions → optimal profile.
4. Compare today's context to profile → alignment_score 0-100.

Data read only. No writes.
"""
from __future__ import annotations
import logging
from datetime import date, timedelta

import db
from utils import _today_mtl as _today_iso

logger = logging.getLogger("trainingos.perf_conditions")

_TOP_PCT   = 0.20
_THRESHOLD = 0.55

_LABELS = {
    "sommeil_optimal": "Sommeil ≥ 7h30 la veille",
    "hrv_elevé":       "HRV élevée",
    "stress_faible":   "Faible stress (PSS < 15)",
    "nutrition_faite": "Nutrition loggée la veille",
    "repos_adéquat":   "1–3 jours de repos avant",
}
_ICONS = {
    "sommeil_optimal": "moon.zzz.fill",
    "hrv_elevé":       "waveform.path.ecg",
    "stress_faible":   "brain.head.profile",
    "nutrition_faite": "fork.knife.circle.fill",
    "repos_adéquat":   "figure.run",
}


def _prev(d: str) -> str:
    return (date.fromisoformat(d) - timedelta(days=1)).isoformat()


def _context(target_date: str, sessions: list[dict], recovery: list[dict],
             pss: list[dict], nutrition: list[dict]) -> dict:
    prev = _prev(target_date)

    sleep_entry = next((r for r in recovery
                        if r.get("date") == prev and r.get("sleep_hours")), None)
    sleep_hours = float(sleep_entry["sleep_hours"]) if sleep_entry else None

    hrv_entry = next((r for r in recovery
                      if r.get("date") in (target_date, prev) and r.get("hrv")), None)
    hrv = float(hrv_entry["hrv"]) if hrv_entry else None

    cutoff7 = (date.fromisoformat(target_date) - timedelta(days=7)).isoformat()
    pss_vals = [float(r.get("pss_score") or r.get("score") or 0)
                for r in pss if cutoff7 <= r.get("date", "") < target_date]
    pss_avg = sum(pss_vals) / len(pss_vals) if pss_vals else None

    nutr_prev = any(e.get("date") == prev for e in nutrition)

    done = sorted([s for s in sessions if s.get("completed") and s.get("date")],
                  key=lambda s: s["date"])
    prev_done = [s for s in done if s["date"] < target_date]
    rest_days = None
    if prev_done:
        rest_days = (date.fromisoformat(target_date) -
                     date.fromisoformat(prev_done[-1]["date"])).days

    return {
        "sleep_hours":    sleep_hours,
        "hrv":            hrv,
        "pss_avg":        pss_avg,
        "nutrition_prev": nutr_prev,
        "rest_days":      rest_days,
    }


def _flags(ctx: dict) -> dict[str, bool]:
    return {
        "sommeil_optimal": ctx["sleep_hours"] is not None and ctx["sleep_hours"] >= 7.5,
        "hrv_elevé":       ctx["hrv"]         is not None and ctx["hrv"] >= 60,
        "stress_faible":   ctx["pss_avg"]     is not None and ctx["pss_avg"] < 15,
        "nutrition_faite": bool(ctx["nutrition_prev"]),
        "repos_adéquat":   ctx["rest_days"]   is not None and 1 <= ctx["rest_days"] <= 3,
    }


def compute() -> dict:
    today_str = _today_iso()
    sessions  = db.get_workout_sessions(limit=300) or []
    recovery  = db.get_recovery_logs(limit=300) or []
    pss       = db.get_pss_records(limit=100) or []
    nutrition = db.get_nutrition_entries_recent(180) or []

    completed = [s for s in sessions if s.get("completed") and s.get("date") and s.get("rpe")]
    if len(completed) < 5:
        return {"has_data": False, "conditions": [], "alignment_score": None,
                "matched": 0, "total": 0, "message": "Accumule des séances pour affiner ta recette."}

    scored  = sorted(completed, key=lambda s: float(s.get("rpe") or 0), reverse=True)
    top_n   = max(3, int(len(scored) * _TOP_PCT))
    top_s   = scored[:top_n]

    counts: dict[str, int] = {k: 0 for k in _LABELS}
    for s in top_s:
        ctx = _context(s["date"], sessions, recovery, pss, nutrition)
        for key, val in _flags(ctx).items():
            if val:
                counts[key] += 1

    optimal = []
    for key, label in _LABELS.items():
        pct = counts[key] / top_n
        if pct >= _THRESHOLD:
            optimal.append({
                "key":       key,
                "label":     label,
                "icon":      _ICONS[key],
                "frequency": round(pct * 100),
            })
    optimal.sort(key=lambda c: c["frequency"], reverse=True)

    cur_ctx   = _context(today_str, sessions, recovery, pss, nutrition)
    cur_flags = _flags(cur_ctx)
    matched   = 0
    for cond in optimal:
        hit = cur_flags.get(cond["key"], False)
        cond["match_today"] = hit
        if hit:
            matched += 1

    total     = len(optimal)
    alignment = round(matched / total * 100) if total > 0 else None

    if alignment is None:
        msg = "Accumule des séances pour affiner ta recette."
    elif alignment >= 80:
        msg = "Conditions optimales réunies — séance à fort potentiel aujourd'hui."
    elif alignment >= 50:
        msg = f"{matched}/{total} conditions optimales présentes."
    else:
        missing = [c["label"] for c in optimal if not c.get("match_today")]
        msg = f"Il manque : {missing[0]}." if missing else "Conditions sous-optimales aujourd'hui."

    return {
        "has_data":       True,
        "conditions":     optimal,
        "alignment_score": alignment,
        "matched":        matched,
        "total":          total,
        "top_sessions_n": top_n,
        "message":        msg,
        "current_context": {
            "sleep_hours":    round(cur_ctx["sleep_hours"], 1) if cur_ctx.get("sleep_hours") is not None else None,
            "hrv":            int(cur_ctx["hrv"])              if cur_ctx.get("hrv")         is not None else None,
            "pss_avg":        round(cur_ctx["pss_avg"], 1)     if cur_ctx.get("pss_avg")     is not None else None,
            "nutrition_prev": cur_ctx["nutrition_prev"],
            "rest_days":      cur_ctx["rest_days"],
        },
    }
