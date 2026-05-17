"""
phoenix_engine.py — Phoenix Score: transformation velocity over last 7 vs prior 7 days.

Three axes:
  Workout   (50%) — volume + session frequency delta
  Stress    (25%) — PSS score delta (lower PSS = improvement)
  Nutrition (25%) — calorie + protein adherence delta

Score 0 = identical week. Positive = ascending. Negative = regressing.
Non-linear soft scaling: sign(x) * log(1 + |x| / 12) * 45
"""
from __future__ import annotations
import db
import math
import logging
from datetime import datetime, timezone, timedelta, date

logger = logging.getLogger("trainingos.phoenix")


# ── Date helpers ──────────────────────────────────────────────────────────────

def _today_iso() -> str:
    try:
        from zoneinfo import ZoneInfo
        return datetime.now(ZoneInfo("America/Montreal")).strftime("%Y-%m-%d")
    except Exception:
        return (datetime.now(timezone.utc) - timedelta(hours=5)).strftime("%Y-%m-%d")


def _window(offset: int, span: int = 7) -> set[str]:
    """Return set of ISO date strings. offset=0 → last span days, offset=span → prior."""
    today = date.fromisoformat(_today_iso())
    return {(today - timedelta(days=offset + i)).isoformat() for i in range(span)}


# ── Axes ──────────────────────────────────────────────────────────────────────

def _workout_axis(last7: set[str], prior7: set[str]) -> tuple[float, dict]:
    history = db.get_all_exercise_history() or {}
    sessions_raw = db.get_workout_sessions(limit=50) or []

    last_sessions  = [s for s in sessions_raw if s.get("date") in last7  and s.get("completed")]
    prior_sessions = [s for s in sessions_raw if s.get("date") in prior7 and s.get("completed")]

    last_vol = 0.0
    prior_vol = 0.0
    for ex_data in history.values():
        for entry in (ex_data.get("history") or []):
            d = entry.get("date", "")
            ev = float(entry.get("exercise_volume") or 0)
            if d in last7:
                last_vol += ev
            elif d in prior7:
                prior_vol += ev

    details = {
        "last_sessions": len(last_sessions),
        "prior_sessions": len(prior_sessions),
        "last_volume": round(last_vol),
        "prior_volume": round(prior_vol),
    }

    has_baseline = prior_vol > 0 or len(prior_sessions) > 0
    if not has_baseline:
        return 0.0, {**details, "has_baseline": False}

    vol_delta = ((last_vol - prior_vol) / prior_vol * 100) if prior_vol > 0 else 0.0
    sess_delta = ((len(last_sessions) - len(prior_sessions)) / len(prior_sessions) * 100) if prior_sessions else 0.0
    delta = vol_delta * 0.70 + sess_delta * 0.30

    return delta, {**details, "has_baseline": True}


def _stress_axis(last7: set[str], prior7: set[str]) -> tuple[float, dict]:
    records = db.get_pss_records(limit=40) or []

    last_pss  = [float(r.get("pss_score") or r.get("score") or 0) for r in records if r.get("date") in last7]
    prior_pss = [float(r.get("pss_score") or r.get("score") or 0) for r in records if r.get("date") in prior7]

    details = {
        "last_count": len(last_pss),
        "prior_count": len(prior_pss),
        "last_avg": round(sum(last_pss) / len(last_pss), 1) if last_pss else None,
        "prior_avg": round(sum(prior_pss) / len(prior_pss), 1) if prior_pss else None,
    }

    if not prior_pss or not last_pss:
        return 0.0, {**details, "has_baseline": False}

    last_avg  = sum(last_pss)  / len(last_pss)
    prior_avg = sum(prior_pss) / len(prior_pss)

    # PSS: lower = better, so improvement = prior_avg > last_avg
    delta = ((prior_avg - last_avg) / prior_avg * 100) if prior_avg > 0 else 0.0

    return delta, {**details, "has_baseline": True}


def _nutrition_axis(last7: set[str], prior7: set[str]) -> tuple[float, dict]:
    entries = db.get_nutrition_entries_recent(16) or []
    settings = db.get_nutrition_settings() or {}

    cal_target  = float(settings.get("calorie_limit")  or settings.get("limite_calories")    or 2000)
    prot_target = float(settings.get("protein_target") or settings.get("objectif_proteines") or 150)

    def _adherence(dates: set[str]) -> tuple[float, int]:
        day_entries = [e for e in entries if e.get("date") in dates]
        if not day_entries:
            return 0.0, 0
        scores = []
        for e in day_entries:
            cal  = float(e.get("calories") or 0)
            prot = float(e.get("proteines") or 0)
            cal_score  = min(1.0, cal  / cal_target)  if cal_target  else 0.0
            prot_score = min(1.0, prot / prot_target) if prot_target else 0.0
            scores.append((cal_score + prot_score) / 2)
        return sum(scores) / len(scores), len(scores)

    last_adh,  last_count  = _adherence(last7)
    prior_adh, prior_count = _adherence(prior7)

    details = {
        "last_count": last_count,
        "prior_count": prior_count,
        "last_adherence": round(last_adh, 2),
        "prior_adherence": round(prior_adh, 2),
    }

    if prior_count == 0:
        return 0.0, {**details, "has_baseline": False}

    delta = ((last_adh - prior_adh) / prior_adh * 100) if prior_adh > 0 else (last_adh * 100 if last_adh > 0 else 0.0)

    return delta, {**details, "has_baseline": True}


# ── Scaling + state ───────────────────────────────────────────────────────────

def _soft_scale(raw: float) -> float:
    return math.copysign(math.log(1 + abs(raw) / 12) * 45, raw)


def _map_state(score: float) -> str:
    if score < -25: return "cendres"
    if score < -8:  return "braises"
    if score < 5:   return "braises_chaudes"
    if score < 25:  return "flamme"
    if score < 50:  return "envol"
    return "supernova"


# ── Main entry ────────────────────────────────────────────────────────────────

def compute() -> dict:
    last7  = _window(0, 7)
    prior7 = _window(7, 7)

    workout_delta,   workout_details   = _workout_axis(last7, prior7)
    stress_delta,    stress_details    = _stress_axis(last7, prior7)
    nutrition_delta, nutrition_details = _nutrition_axis(last7, prior7)

    # Optional resilience axis (War Room integration)
    resilience_delta  = 0.0
    resilience_details: dict = {"has_baseline": False}
    use_resilience = False
    try:
        import db as _db
        config = _db.get_war_room_config() or {}
        if config.get("integration_phoenix"):
            import war_room_engine as _wr
            resilience_delta, resilience_details = _wr.resilience_axis(last7, prior7)
            use_resilience = True
    except Exception:
        pass

    # Optional spirit axis (Spirit Pillar integration)
    spirit_delta  = 0.0
    spirit_details: dict = {"has_baseline": False}
    use_spirit = False
    try:
        import db as _db2
        scfg = _db2.get_spirit_config() or {}
        if scfg.get("integration_phoenix"):
            import spirit_engine as _se
            spirit_delta, spirit_details = _se.compute_spirit_axis(last7, prior7)
            use_spirit = True
    except Exception:
        pass

    has_baseline = (
        workout_details.get("has_baseline")
        or stress_details.get("has_baseline")
        or nutrition_details.get("has_baseline")
    )

    if not has_baseline:
        axes = {
            "workout":   {"delta": 0.0, "details": workout_details},
            "stress":    {"delta": 0.0, "details": stress_details},
            "nutrition": {"delta": 0.0, "details": nutrition_details},
        }
        if use_resilience:
            axes["resilience"] = {"delta": 0.0, "details": resilience_details}
        if use_spirit:
            axes["spirit"] = {"delta": 0.0, "details": spirit_details}
        return {
            "score": 0.0, "state": "foundation",
            "axes": axes, "is_foundation": True, "raw_delta": 0.0,
        }

    # Weight distribution depends on active optional axes
    n_optional = (1 if use_resilience else 0) + (1 if use_spirit else 0)
    if n_optional == 0:
        raw_delta = workout_delta * 0.50 + stress_delta * 0.25 + nutrition_delta * 0.25
    elif n_optional == 1:
        opt_delta = resilience_delta if use_resilience else spirit_delta
        raw_delta = (
            workout_delta   * 0.43
            + stress_delta    * 0.21
            + nutrition_delta * 0.21
            + opt_delta       * 0.15
        )
    else:
        raw_delta = (
            workout_delta    * 0.38
            + stress_delta     * 0.18
            + nutrition_delta  * 0.18
            + resilience_delta * 0.13
            + spirit_delta     * 0.13
        )

    scaled = _soft_scale(raw_delta)

    axes = {
        "workout":   {"delta": round(workout_delta, 1),   "details": workout_details},
        "stress":    {"delta": round(stress_delta, 1),    "details": stress_details},
        "nutrition": {"delta": round(nutrition_delta, 1), "details": nutrition_details},
    }
    if use_resilience:
        axes["resilience"] = {"delta": round(resilience_delta, 1), "details": resilience_details}
    if use_spirit:
        axes["spirit"] = {"delta": round(spirit_delta, 1), "details": spirit_details}

    return {
        "score": round(scaled, 1),
        "state": _map_state(scaled),
        "axes": axes,
        "is_foundation": False,
        "raw_delta": round(raw_delta, 1),
    }
