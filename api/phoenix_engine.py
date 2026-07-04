"""
phoenix_engine.py — Phoenix Score v2: transformation velocity over last 7 vs prior 7 days.

Four mandatory axes:
  Body      (40%) — volume + session frequency delta
  Mind      (20%) — PSS score delta (lower PSS = improvement)
  Fuel      (20%) — calorie + protein adherence delta
  Spirit    (20%) — breathwork / meditation / journaling regularity delta

Score 0 = identical week. Positive = ascending. Negative = regressing.
Weights are normalized across axes that have baseline data — missing pillars
are neutral (0), not a penalty.

War Room: optional silent multiplier on the final score (0.85–1.15).
Activated only when war_room_config.integration_phoenix = true.
"""
from __future__ import annotations
import db
import math
import logging
from datetime import datetime, timezone, timedelta, date
from utils import _today_mtl as _today_iso, get_nutrition_time_context

logger = logging.getLogger("trainingos.phoenix")


def _window(offset: int, span: int = 7) -> set[str]:
    """Return set of ISO date strings. offset=0 → last span days, offset=span → prior."""
    today = date.fromisoformat(_today_iso())
    return {(today - timedelta(days=offset + i)).isoformat() for i in range(span)}


# ── Axes ──────────────────────────────────────────────────────────────────────

def _find_stagnant_exercise(history: dict) -> str | None:
    """Return the name of the first exercise with identical weight on 3+ consecutive sessions."""
    for name, entries in history.items():
        if len(entries) < 3:
            continue
        last3 = entries[:3]
        weights = [float(e.get("weight") or 0) for e in last3]
        if weights[0] > 0 and len(set(weights)) == 1:
            return name
    return None


def _workout_axis(last7: set[str], prior7: set[str]) -> tuple[float, dict]:
    history = db.get_all_exercise_history(cutoff_days=14) or {}
    sessions_raw = db.get_workout_sessions(limit=50) or []

    last_sessions  = [s for s in sessions_raw if s.get("date") in last7  and s.get("completed")]
    prior_sessions = [s for s in sessions_raw if s.get("date") in prior7 and s.get("completed")]

    last_vol = 0.0
    prior_vol = 0.0
    for entries in history.values():
        for entry in entries:
            d = entry.get("date", "")
            weight = float(entry.get("weight") or 0)
            reps   = float(str(entry.get("reps") or "0").split(",")[0].strip() or "0")
            ev     = weight * reps
            if d in last7:
                last_vol += ev
            elif d in prior7:
                prior_vol += ev

    stagnant = _find_stagnant_exercise(history)
    details = {
        "last_sessions":     len(last_sessions),
        "prior_sessions":    len(prior_sessions),
        "last_volume":       round(last_vol),
        "prior_volume":      round(prior_vol),
        "stagnant_exercise": stagnant,
    }

    has_baseline = prior_vol > 0 or len(prior_sessions) > 0
    if not has_baseline:
        return 0.0, {**details, "has_baseline": False}

    vol_delta  = ((last_vol - prior_vol) / prior_vol * 100) if prior_vol > 0 else 0.0
    sess_delta = ((len(last_sessions) - len(prior_sessions)) / len(prior_sessions) * 100) if prior_sessions else 0.0
    delta = vol_delta * 0.70 + sess_delta * 0.30

    return delta, {**details, "has_baseline": True}


def _mind_axis(last7: set[str], prior7: set[str]) -> tuple[float, dict]:
    records = db.get_pss_records(limit=40) or []

    last_pss  = [float(r.get("pss_score") or r.get("score") or 0) for r in records if r.get("date") in last7]
    prior_pss = [float(r.get("pss_score") or r.get("score") or 0) for r in records if r.get("date") in prior7]

    details = {
        "last_count":  len(last_pss),
        "prior_count": len(prior_pss),
        "last_avg":    round(sum(last_pss) / len(last_pss), 1) if last_pss else None,
        "prior_avg":   round(sum(prior_pss) / len(prior_pss), 1) if prior_pss else None,
    }

    if not prior_pss or not last_pss:
        return 0.0, {**details, "has_baseline": False}

    last_avg  = sum(last_pss)  / len(last_pss)
    prior_avg = sum(prior_pss) / len(prior_pss)
    # PSS: lower = better → improvement when prior_avg > last_avg
    delta = ((prior_avg - last_avg) / prior_avg * 100) if prior_avg > 0 else 0.0

    return delta, {**details, "has_baseline": True}


def _fuel_axis(last7: set[str], prior7: set[str]) -> tuple[float, dict]:
    entries  = db.get_nutrition_entries_recent(16) or []
    settings = db.get_nutrition_settings() or {}

    cal_target  = float(settings.get("calorie_limit")  or settings.get("limite_calories")    or 2000)
    prot_target = float(settings.get("protein_target") or settings.get("objectif_proteines") or 150)

    # Exclude today from last7 if day is not substantially complete (< 80% of eating window)
    today = _today_iso()
    if today in last7:
        ctx = get_nutrition_time_context(today)
        if not ctx["is_end_of_day"]:
            last7 = last7 - {today}

    def _adherence(dates: set[str]) -> tuple[float, int]:
        day_entries = [e for e in entries if e.get("date") in dates]
        if not day_entries:
            return 0.0, 0
        daily_totals: dict[str, dict] = {}
        for e in day_entries:
            day = e.get("date", "")
            if day not in daily_totals:
                daily_totals[day] = {"calories": 0.0, "proteines": 0.0}
            daily_totals[day]["calories"]  += float(e.get("calories")  or 0)
            daily_totals[day]["proteines"] += float(e.get("proteines") or 0)
        scores = []
        for totals in daily_totals.values():
            cal_score  = min(1.0, totals["calories"]  / cal_target)  if cal_target  else 0.0
            prot_score = min(1.0, totals["proteines"] / prot_target) if prot_target else 0.0
            scores.append((cal_score + prot_score) / 2)
        return sum(scores) / len(scores), len(daily_totals)

    last_adh,  last_count  = _adherence(last7)
    prior_adh, prior_count = _adherence(prior7)

    details = {
        "last_count":       last_count,
        "prior_count":      prior_count,
        "last_adherence":   round(last_adh, 2),
        "prior_adherence":  round(prior_adh, 2),
    }

    if prior_count == 0:
        return 0.0, {**details, "has_baseline": False}

    # Empty week → neutral rather than -100% penalty
    if last_count == 0:
        return 0.0, {**details, "has_baseline": True}

    delta = ((last_adh - prior_adh) / prior_adh * 100) if prior_adh > 0 else (last_adh * 100 if last_adh > 0 else 0.0)
    return delta, {**details, "has_baseline": True}


def _spirit_axis(last7: set[str], prior7: set[str]) -> tuple[float, dict]:
    try:
        import spirit_engine as _se
        return _se.compute_spirit_axis(last7, prior7)
    except Exception as e:
        logger.warning("spirit_axis error: %s", e)
        return 0.0, {"has_baseline": False}


# ── War Room multiplier ───────────────────────────────────────────────────────

def _war_room_multiplier() -> float:
    """Silent multiplier 0.85–1.15. Applied to final scaled score only."""
    try:
        config = db.get_war_room_config() or {}
        if not config.get("integration_phoenix"):
            return 1.0
        streak = int(config.get("victory_streak") or 0)
        battles = db.get_war_room_battles(limit=10) or []
        lost = [b for b in battles if b.get("status") == "lost"]
        if lost:
            last_reset_str = (lost[0].get("date") or "")
            if last_reset_str:
                today_mtl = date.fromisoformat(_today_iso())
                days_since = (today_mtl - date.fromisoformat(last_reset_str)).days
                if days_since < 7:
                    # Recovery ramp: 0.85 at day 0 → 1.00 at day 7
                    return 0.85 + (days_since / 7.0) * 0.15
        if streak >= 30: return 1.15
        if streak >= 14: return 1.10
        if streak >= 7:  return 1.05
        return 1.0
    except Exception as e:
        logger.warning("war_room_multiplier error: %s", e)
        return 1.0


# ── Scaling + state ───────────────────────────────────────────────────────────

def _soft_scale(raw: float) -> float:
    # Wider headroom vs v1 (was /12 * 45). Practical range ±55 for extreme weeks.
    return math.copysign(math.log(1 + abs(raw) / 8) * 55, raw)


def _map_state(score: float) -> str:
    if score < -25: return "cendres"
    if score < -8:  return "braises"
    if score < 5:   return "braises_chaudes"
    if score < 25:  return "flamme"
    if score < 50:  return "envol"
    return "supernova"


# ── Full weights — normalized over axes with baseline ─────────────────────────

_WEIGHTS = {"workout": 0.40, "mind": 0.20, "fuel": 0.20, "spirit": 0.20}


# ── Guidance helpers ──────────────────────────────────────────────────────────

def _guidance_workout(details: dict) -> str:
    if not details.get("has_baseline"):
        return "Log tes données pour débloquer ce conseil."

    last_s   = details.get("last_sessions",  0)
    prior_s  = details.get("prior_sessions", 0)
    last_v   = details.get("last_volume",    0)
    prior_v  = details.get("prior_volume",   0)
    stagnant = details.get("stagnant_exercise")

    # Priority 1: fewer sessions than last week
    if last_s < prior_s:
        s_label = "séance" if last_s <= 1 else "séances"
        return (f"{last_s} {s_label} cette semaine vs {prior_s} la semaine dernière. "
                "Une séance aujourd'hui comblerait l'écart.")

    # Priority 2: volume down
    if prior_v > 0 and last_v < prior_v:
        pct = round((prior_v - last_v) / prior_v * 100)
        return (f"Ton volume est {pct}% sous la semaine dernière. "
                "Ajoute 1 série sur tes composés aujourd'hui.")

    # Priority 3: stagnant exercise
    if stagnant:
        return (f"{stagnant} stagne depuis 3 sessions. "
                "Revois la charge à ta prochaine séance.")

    return "Entraînement sur la bonne trajectoire. Continue."


def _guidance_mind(mind_details: dict) -> str:
    try:
        today  = date.fromisoformat(_today_iso())
        week   = {(today - timedelta(days=i)).isoformat() for i in range(7)}

        # 1. PSS — most recent within 7 days
        pss_records = db.get_pss_records(limit=10) or []
        recent_pss  = next((r for r in pss_records if r.get("date") in week), None)
        if recent_pss:
            score = float(recent_pss.get("pss_score") or recent_pss.get("score") or 0)
            if score > 20:
                return (f"Ton stress est élevé ({int(score)}/40). "
                        "10 min de respiration aujourd'hui.")

        # 2. HRV + sleep from recovery logs (enrichment only — no score impact)
        rec_logs     = db.get_recovery_logs(limit=8) or []
        recent_logs  = sorted(
            [r for r in rec_logs if r.get("date") in week],
            key=lambda r: r.get("date", ""), reverse=True
        )
        if recent_logs:
            hrv_vals = [float(r["hrv"]) for r in recent_logs if r.get("hrv")]
            if len(hrv_vals) >= 2:
                today_hrv  = hrv_vals[0]
                baseline   = sum(hrv_vals[1:]) / len(hrv_vals[1:])
                if baseline > 0 and today_hrv < baseline * 0.90:
                    return "Ton HRV est sous ta baseline. Priorise la récupération aujourd'hui."

            sleep_vals = [float(r["sleep_quality"]) for r in recent_logs if r.get("sleep_quality")]
            if sleep_vals:
                avg_sleep = sum(sleep_vals) / len(sleep_vals)
                if avg_sleep < 6:
                    return (f"Qualité de sommeil à {avg_sleep:.1f}/10 cette semaine. "
                            "Vise une heure de coucher plus tôt ce soir.")

        # 3. No PSS and no baseline data → prompt
        if not recent_pss and not mind_details.get("has_baseline"):
            return "Fais ton check-in PSS pour débloquer les insights Mind."

        return "Stress sous contrôle cette semaine."

    except Exception as exc:
        logger.warning("_guidance_mind error: %s", exc)
        return "Log tes données pour débloquer ce conseil."


def _guidance_fuel(fuel_details: dict) -> str:
    try:
        today_str = _today_iso()
        settings  = db.get_nutrition_settings() or {}
        cal_target  = float(settings.get("calorie_limit")  or settings.get("limite_calories")    or 2000)
        prot_target = float(settings.get("protein_target") or settings.get("objectif_proteines") or 150)

        entries     = db.get_nutrition_entries_recent(7) or []
        today_entry = next((e for e in entries if e.get("date") == today_str), None)

        if today_entry:
            prot = float(today_entry.get("proteines") or 0)
            cals = float(today_entry.get("calories")  or 0)

            if prot_target > 0 and prot < prot_target * 0.85:
                missing = round(prot_target - prot)
                return (f"Il te manque {missing}g de protéines aujourd'hui. "
                        "Un repas riche en protéines suffit.")

            if cal_target > 0 and cals < cal_target * 0.80:
                missing = round(cal_target - cals)
                return (f"{int(cals)} kcal loggées — {missing} kcal sous ton objectif "
                        f"de {int(cal_target)} kcal.")

        # Log consistency this week
        today_dt    = date.fromisoformat(today_str)
        week_dates  = {(today_dt - timedelta(days=i)).isoformat() for i in range(7)}
        logged_days = sum(1 for e in entries if e.get("date") in week_dates)
        missing_days = 7 - logged_days
        if missing_days > 2:
            return (f"Tu n'as pas loggé {missing_days} jours cette semaine. "
                    "Un log partiel vaut mieux que rien.")

        return "Nutrition sur cible. Continue."

    except Exception as exc:
        logger.warning("_guidance_fuel error: %s", exc)
        return "Log tes données pour débloquer ce conseil."


def _guidance_spirit(spirit_details: dict) -> str:
    try:
        bw_last  = spirit_details.get("breathwork_last",  0)
        med_last = spirit_details.get("meditation_last",  0)
        j_last   = spirit_details.get("journal_last",     0)

        # Priority 1: no journal entry this week
        if j_last == 0:
            return "Pas d'entrée journal cette semaine. 2 minutes ce soir suffisent."

        # Priority 2: no breathwork and no meditation → suggest morning ritual
        if bw_last == 0 and med_last == 0:
            ritual = db.get_ritual_today(_today_iso()) or {}
            if ritual and not ritual.get("morning_at"):
                return ("Aucune pratique cette semaine. "
                        "Commence par ton rituel matinal aujourd'hui.")
            return ("Aucune pratique cette semaine. "
                    "Commence par ton rituel matinal aujourd'hui.")

        # Priority 3: only one type active — suggest the missing one
        if bw_last > 0 and med_last == 0:
            return "Continue le breathwork — ajoute une session de méditation cette semaine."
        if med_last > 0 and bw_last == 0:
            return "Continue la méditation — ajoute une session de breathwork cette semaine."

        return "Pratiques Spirit consistantes. Continue."

    except Exception as exc:
        logger.warning("_guidance_spirit error: %s", exc)
        return "Log tes données pour débloquer ce conseil."


def compute_guidance(
    workout_details: dict,
    mind_details:    dict,
    fuel_details:    dict,
    spirit_details:  dict,
) -> dict:
    """Generate one actionable message per axis from real data. Additive — no score impact."""
    return {
        "workout":   _guidance_workout(workout_details),
        "stress":    _guidance_mind(mind_details),
        "nutrition": _guidance_fuel(fuel_details),
        "spirit":    _guidance_spirit(spirit_details),
    }


# ── Main entry ────────────────────────────────────────────────────────────────

def compute() -> dict:
    last7  = _window(0, 7)
    prior7 = _window(7, 7)

    workout_delta, workout_details = _workout_axis(last7, prior7)
    mind_delta,    mind_details    = _mind_axis(last7, prior7)
    fuel_delta,    fuel_details    = _fuel_axis(last7, prior7)
    spirit_delta,  spirit_details  = _spirit_axis(last7, prior7)

    axes_payload = {
        "workout":   {"delta": round(workout_delta, 1),  "details": workout_details},
        "stress":    {"delta": round(mind_delta, 1),     "details": mind_details},
        "nutrition": {"delta": round(fuel_delta, 1),     "details": fuel_details},
        "spirit":    {"delta": round(spirit_delta, 1),   "details": spirit_details},
    }

    active: dict[str, float] = {}
    if workout_details.get("has_baseline"): active["workout"] = workout_delta
    if mind_details.get("has_baseline"):    active["mind"]    = mind_delta
    if fuel_details.get("has_baseline"):    active["fuel"]    = fuel_delta
    if spirit_details.get("has_baseline"):  active["spirit"]  = spirit_delta

    guidance = compute_guidance(workout_details, mind_details, fuel_details, spirit_details)

    if not active:
        return {
            "score": 0.0, "state": "foundation",
            "axes": axes_payload, "is_foundation": True, "raw_delta": 0.0,
            "guidance": guidance,
        }

    # Normalize weights to active axes
    total_w = sum(_WEIGHTS[k] for k in active)
    raw_delta = sum(active[k] * (_WEIGHTS[k] / total_w) for k in active)

    scaled     = _soft_scale(raw_delta)
    multiplier = _war_room_multiplier()
    final      = scaled * multiplier

    result: dict = {
        "score":         round(final, 1),
        "state":         _map_state(final),
        "axes":          axes_payload,
        "is_foundation": False,
        "raw_delta":     round(raw_delta, 1),
        "guidance":      guidance,
    }
    if multiplier != 1.0:
        result["war_room_multiplier"] = round(multiplier, 3)
    return result
