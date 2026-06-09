"""
energy.py — Bilan énergétique journalier.

TDEE = BMR + EAT + NEAT

BMR  : Katch-McArdle (si body_fat% valide) | Mifflin-St Jeor
EAT  : séances musculation (MET × poids × durée) + cardio GPS (calories directes ou MET)
NEAT : steps × 0.04 × (weight_kg / 70)   — ACSM formula
"""
from __future__ import annotations

from typing import Optional

import db
from tdee import compute_bmr, _LBS_TO_KG
from utils import _today_mtl, get_nutrition_time_context

_OBJECTIVE_LABELS = {
    "bulk":    "hypertrophie",
    "cut":     "sèche",
    "recomp":  "recomposition",
    "maintain":"maintien",
}

_TARGET_BALANCE = {
    "bulk":    "+200 à +400 kcal",
    "cut":     "-300 à -500 kcal",
    "recomp":  "±100 kcal",
    "maintain":"±100 kcal",
}


# ── MET helpers ───────────────────────────────────────────────────────────────

def _met_lifting(rpe: int) -> float:
    """MET musculation selon RPE (ACSM Compendium 2011).
    Plafond ACSM : 6.0 pour musculation très intense (code 02050).
    """
    if rpe <= 4: return 3.5
    if rpe <= 6: return 5.0
    if rpe <= 8: return 6.0
    return 6.0


def _met_cardio(ctype: str, duration_min: int,
                distance_km: Optional[float]) -> float:
    """MET estimé selon type de cardio + pace."""
    t = (ctype or "").lower()

    if t in ("run", "course", "running", "trail"):
        if distance_km and duration_min:
            pace = duration_min / distance_km   # min/km
            if pace >= 8:   return 8.0
            if pace >= 6:   return 10.0
            if pace >= 5:   return 12.0
            return 14.0
        return 9.0

    if t in ("bike", "vélo", "cycling", "cycle"):
        if distance_km and duration_min:
            speed_kmh = distance_km / (duration_min / 60)
            if speed_kmh < 16: return 6.0
            if speed_kmh < 22: return 9.0
            return 12.0
        return 9.0

    if t in ("walk", "marche", "walking", "hike", "randonnée"):
        if distance_km and duration_min:
            pace = duration_min / distance_km
            if pace >= 15: return 2.5
            return 4.0
        return 3.0

    if t == "hiit":
        return 10.0

    if t in ("swim", "natation"):
        return 8.0

    if t == "rowing":
        return 7.0

    return 7.0   # cardio générique


# ── EAT — musculation ─────────────────────────────────────────────────────────

def _eat_from_workouts(today: str, weight_kg: float) -> list[dict]:
    """Calories brûlées en séances musculation (workout_sessions complétées)."""
    result = []
    for stype in ("morning", "evening", "bonus"):
        s = db.get_workout_session_by_type(today, stype)
        if not s or not s.get("completed"):
            continue
        dur = int(s.get("duration_min") or 0)
        if not dur:
            continue
        rpe = int(s.get("rpe") or 5)
        met = _met_lifting(rpe)
        cals = round(met * weight_kg * dur / 60)
        result.append({
            "type":         "musculation",
            "name":         s.get("session_name"),
            "duration_min": dur,
            "rpe":          rpe,
            "calories":     cals,
            "met":          met,
            "source":       "met_estimate",
        })
    return result


# ── EAT — cardio ──────────────────────────────────────────────────────────────

def _eat_from_cardio_entries(entries: list[dict], weight_kg: float) -> list[dict]:
    """Calcule calories cardio depuis des entrées pré-filtrées pour un seul jour."""
    result = []
    for c in entries:
        dur   = int(c.get("duration_min") or 0)
        cals  = c.get("calories")
        ctype = c.get("type") or "cardio"
        dist  = c.get("distance_km")
        if cals and int(cals) > 0:
            result.append({"type": ctype, "duration_min": dur,
                           "calories": int(cals), "source": "gps"})
        elif dur:
            met  = _met_cardio(ctype, dur, dist)
            cals = min(round(met * weight_kg * dur / 60), 1500)
            result.append({"type": ctype, "duration_min": dur,
                           "calories": cals, "met": met, "source": "met_estimate"})
    return result


def _eat_from_cardio(today: str, weight_kg: float) -> list[dict]:
    """Calories brûlées en cardio aujourd'hui — GPS direct si dispo, sinon MET."""
    all_cardio   = db.get_cardio_logs(limit=30) or []
    today_cardio = [c for c in all_cardio if (c.get("date") or "")[:10] == today]
    return _eat_from_cardio_entries(today_cardio, weight_kg)


# ── NEAT ──────────────────────────────────────────────────────────────────────

def _neat_from_steps(steps: Optional[int], weight_kg: float) -> Optional[int]:
    """NEAT depuis steps — ACSM : steps × 0.04 × (poids_kg / 70).
    Cap à 30 000 steps pour filtrer les anomalies HealthKit.
    """
    if not steps:
        return None
    steps = min(steps, 30_000)
    return round(steps * 0.04 * (weight_kg / 70))


# ── Balance status ────────────────────────────────────────────────────────────

def _balance_status(balance: int, goal: str) -> str:
    if balance <= -700:
        return "deficit_severe"

    if goal == "cut":
        if -500 <= balance <= -300:  return "deficit_optimal"
        if balance < -500:           return "deficit_aggressive"
        if balance < 0:              return "deficit_light"
        return "surplus"

    if goal == "bulk":
        if 200 <= balance <= 400:    return "surplus_optimal"
        if balance > 600:            return "surplus_high"
        if balance > 0:              return "surplus_low"
        return "deficit"

    # recomp / maintain
    if abs(balance) <= 100:          return "balanced"
    return "deficit" if balance < 0 else "surplus"


# ── Entrée principale ─────────────────────────────────────────────────────────

def compute_energy_daily(date: Optional[str] = None) -> dict:
    """
    Calcule le bilan énergétique complet pour une date (défaut = aujourd'hui MTL).
    Retourne le payload JSON pour /api/energy/daily.
    """
    today        = date or _today_mtl()
    is_too_early = get_nutrition_time_context(today)["is_too_early"]

    # ── Profil ────────────────────────────────────────────────────────────────
    profile    = db.get_profile() or {}
    latest_bw  = db.get_body_weight_logs(limit=1)
    if latest_bw:
        profile["weight"] = latest_bw[0].get("weight") or profile.get("weight")
    weight_lbs = profile.get("weight")
    height_cm  = float(profile.get("height") or 0) or None
    age        = int(profile.get("age") or 0) or None
    sex        = str(profile.get("sex") or "m")
    goal       = str(profile.get("goal") or "maintain")
    body_fat   = profile.get("body_fat")
    weight_kg  = float(weight_lbs) * _LBS_TO_KG if weight_lbs else None

    missing = [f for f, v in [("weight", weight_kg),
                               ("height", height_cm),
                               ("age", age)] if not v]
    if missing:
        return {
            "error":   "profile_incomplete",
            "missing": missing,
            "message": "Complète ton profil (poids, taille, âge) pour calculer ton BMR.",
        }

    # ── BMR ───────────────────────────────────────────────────────────────────
    bmr_data    = compute_bmr(weight_kg, height_cm, age, sex, body_fat)
    bmr         = bmr_data["bmr"]
    bmr_formula = bmr_data["formula_used"]

    # ── EAT ───────────────────────────────────────────────────────────────────
    workout_sessions = _eat_from_workouts(today, weight_kg)
    cardio_sessions  = _eat_from_cardio(today, weight_kg)
    eat_workouts     = sum(s["calories"] for s in workout_sessions)
    eat_cardio       = sum(s["calories"] for s in cardio_sessions)

    # ── NEAT ──────────────────────────────────────────────────────────────────
    recovery_logs  = db.get_recovery_logs(limit=7) or []
    today_recovery = next(
        (r for r in recovery_logs if (r.get("date") or "")[:10] == today), {}
    )
    steps = today_recovery.get("steps")
    neat  = _neat_from_steps(steps, weight_kg)

    # ── TDEE ──────────────────────────────────────────────────────────────────
    tdee = bmr + eat_workouts + eat_cardio + (neat or 0)

    # ── Intake ────────────────────────────────────────────────────────────────
    nutrition = db.get_nutrition_entries(today) or []
    intake    = round(sum(float(e.get("calories") or 0) for e in nutrition))

    # ── Bilan ─────────────────────────────────────────────────────────────────
    balance        = intake - tdee
    balance_status = _balance_status(balance, goal)
    objective      = _OBJECTIVE_LABELS.get(goal, goal)
    target_balance = _TARGET_BALANCE.get(goal, "±100 kcal")

    return {
        "date":           today,
        "bmr":            bmr,
        "bmr_formula":    bmr_formula,
        "eat_workouts":   eat_workouts,
        "eat_cardio":     eat_cardio,
        "neat":           neat,
        "tdee":           tdee,
        "intake":         intake,
        "balance":        balance,
        "balance_status": balance_status,
        "is_too_early":   is_too_early,
        "objective":      objective,
        "target_balance": target_balance,
        "breakdown": {
            "workouts":      workout_sessions,
            "cardio":        cardio_sessions,
            "steps":         steps,
            "neat_calories": neat,
        },
    }


# ── Historique 7j ─────────────────────────────────────────────────────────────

def compute_energy_history(days: int = 7) -> list[dict]:
    """
    Calcule le bilan énergétique pour chaque jour des N derniers jours.
    Retourne une liste du plus ancien au plus récent.
    BMR constant (profil ne change pas jour à jour).
    EAT/NEAT/Intake recalculés depuis les logs archivés.
    """
    from datetime import date as date_cls, timedelta

    today   = _today_mtl()
    profile = db.get_profile() or {}

    latest_bw = db.get_body_weight_logs(limit=1)
    if latest_bw:
        profile["weight"] = latest_bw[0].get("weight") or profile.get("weight")

    weight_lbs = profile.get("weight")
    height_cm  = float(profile.get("height") or 0) or None
    age        = int(profile.get("age") or 0) or None
    sex        = str(profile.get("sex") or "m")
    goal       = str(profile.get("goal") or "maintain")
    body_fat   = profile.get("body_fat")
    weight_kg  = float(weight_lbs) * _LBS_TO_KG if weight_lbs else None

    if not weight_kg or not height_cm or not age:
        return []

    bmr_data = compute_bmr(weight_kg, height_cm, age, sex, body_fat)
    bmr = bmr_data["bmr"]

    # Batch fetch — une seule passe DB par type de données
    nutrition_by_date = {e["date"]: e
                         for e in (db.get_nutrition_entries_recent(days + 1) or [])}
    recovery_by_date  = {(r.get("date") or "")[:10]: r
                         for r in (db.get_recovery_logs(limit=days + 2) or [])}
    cardio_all        = db.get_cardio_logs(limit=60) or []
    sessions_all      = db.get_workout_sessions(limit=40) or []

    result = []
    for i in range(days - 1, -1, -1):          # plus ancien → aujourd'hui
        d = (date_cls.fromisoformat(today) - timedelta(days=i)).isoformat()

        # Apports
        nutr   = nutrition_by_date.get(d, {})
        intake = int(nutr.get("calories") or 0) or None

        # NEAT
        rec   = recovery_by_date.get(d, {})
        steps = rec.get("steps")
        neat  = _neat_from_steps(steps, weight_kg)

        # EAT — musculation (sessions complétées ce jour)
        day_sessions = [s for s in sessions_all
                        if (s.get("date") or "")[:10] == d and s.get("completed")]
        eat_w = sum(
            round(_met_lifting(int(s.get("rpe") or 5))
                  * weight_kg * int(s.get("duration_min") or 0) / 60)
            for s in day_sessions if s.get("duration_min")
        )

        # EAT — cardio
        day_cardio = [c for c in cardio_all if (c.get("date") or "")[:10] == d]
        eat_c = sum(s["calories"]
                    for s in _eat_from_cardio_entries(day_cardio, weight_kg))

        tdee    = bmr + eat_w + eat_c + (neat or 0)
        balance = (intake - tdee) if intake else None

        result.append({
            "date":           d,
            "bmr":            bmr,
            "eat_workouts":   eat_w,
            "eat_cardio":     eat_c,
            "neat":           neat,
            "tdee":           tdee,
            "intake":         intake,
            "balance":        balance,
            "balance_status": _balance_status(balance, goal) if balance is not None else None,
            "has_data":       bool(intake or steps or day_sessions or day_cardio),
        })

    return result
