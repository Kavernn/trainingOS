"""Plateau detection and deload recommendation engine.

All weights are in lbs.
"""
from __future__ import annotations
import logging, math, time
from datetime import datetime, date, timedelta
from collections import defaultdict, Counter
from typing import Optional

import db

logger = logging.getLogger(__name__)

_CACHE: dict = {}
_CACHE_TTL = 7200  # 2h

_COMPOUND_TYPES    = {"compound_heavy", "compound_hypertrophy"}
_COMPOUND_KEYWORDS = (
    "squat", "deadlift", "bench", "overhead press", "ohp",
    "row", "pull-up", "pullup", "chin-up", "chinup",
    "press", "lunge", "hip thrust", "rdl", "romanian", "leg press",
)
_LOWER_KEYWORDS = (
    "squat", "deadlift", "rdl", "romanian", "lunge",
    "hip thrust", "leg press", "leg curl", "leg extension",
)


def _is_compound(name: str, ex_type: str) -> bool:
    if ex_type.lower() in _COMPOUND_TYPES:
        return True
    n = name.lower()
    return any(k in n for k in _COMPOUND_KEYWORDS)


def _is_lower(name: str) -> bool:
    n = name.lower()
    return any(k in n for k in _LOWER_KEYWORDS)


def _epley(weight_lbs: float, reps: int) -> float:
    r = min(reps, 20)
    if r <= 1:
        return weight_lbs
    return weight_lbs * (1.0 + r / 30.0)


def _round_lbs(w: float, step: float = 5.0) -> float:
    return round(w / step) * step


# ── Data gathering ────────────────────────────────────────────────────────────

def _working_sets(days: int = 28) -> dict[str, list[dict]]:
    """
    Returns {exercise_name: [sessions oldest→newest]} for compound exercises
    in the last N days. One entry per date = max-e1RM set.
    """
    cutoff = (date.today() - timedelta(days=days)).isoformat()

    history       = db.get_all_exercise_history()     # {name: [{date, weight, reps}]} newest-first
    exercises_meta = db.get_exercises() or {}

    best_by_date: dict[str, dict[str, dict]] = defaultdict(dict)

    for ex_name, entries in history.items():
        meta    = exercises_meta.get(ex_name, {})
        ex_type = meta.get("type", meta.get("category", ""))

        if not _is_compound(ex_name, ex_type):
            continue

        for entry in entries:
            d = str(entry.get("date", ""))[:10]
            if d < cutoff:
                continue

            w = float(entry.get("weight") or 0)
            r = int(str(entry.get("reps") or "0").split(",")[0].strip() or "0")
            if w <= 0 or r <= 0:
                continue

            e1rm = _epley(w, r)
            existing = best_by_date[ex_name].get(d)
            if existing is None or e1rm > existing["e1rm_lbs"]:
                best_by_date[ex_name][d] = {
                    "date":       d,
                    "weight_lbs": round(w, 1),
                    "reps":       r,
                    "e1rm_lbs":   round(e1rm, 1),
                }

    result = {}
    for ex_name, by_date in best_by_date.items():
        sessions = sorted(by_date.values(), key=lambda x: x["date"])
        if len(sessions) >= 3:
            result[ex_name] = sessions
    return result


def _pss_context() -> dict:
    records = db.get_pss_records(limit=90)
    if not records:
        return {"available": False}

    today         = date.today()
    week_ago      = (today - timedelta(days=7)).isoformat()
    three_wks_ago = (today - timedelta(days=21)).isoformat()

    recent = [r["score"] for r in records
              if r.get("score") is not None
              and three_wks_ago <= str(r.get("date", ""))[:10]
              and str(r.get("date", ""))[:10] >= week_ago]
    prior  = [r["score"] for r in records
              if r.get("score") is not None
              and three_wks_ago <= str(r.get("date", ""))[:10] < week_ago]

    recent_avg = sum(recent) / len(recent) if recent else None
    prior_avg  = sum(prior)  / len(prior)  if prior  else None
    trend      = (recent_avg - prior_avg) if (recent_avg and prior_avg) else 0.0

    return {
        "available":  True,
        "recent_avg": round(recent_avg, 1) if recent_avg else None,
        "prior_avg":  round(prior_avg, 1)  if prior_avg  else None,
        "trend":      round(trend, 1),
        "is_high":    recent_avg is not None and recent_avg > 70,
        "is_rising":  trend > 10,
    }


def _nutrition_context() -> dict:
    recent14   = db.get_nutrition_entries_recent(14)
    baseline30 = db.get_nutrition_entries_recent(30)

    if not recent14:
        return {"available": False}

    def _avg_cal(entries):
        vals = [e.get("calories", 0) or 0 for e in entries if e.get("calories")]
        return sum(vals) / len(vals) if vals else 0.0

    def _avg_protein(entries):
        vals = [e.get("proteines", 0) or 0 for e in entries if e.get("proteines")]
        return sum(vals) / len(vals) if vals else 0.0

    recent_cal     = _avg_cal(recent14)
    baseline_cal   = _avg_cal(baseline30) if baseline30 else recent_cal
    recent_protein = _avg_protein(recent14)

    bw_lbs             = _body_weight_lbs()
    protein_threshold  = bw_lbs * 0.73 if bw_lbs else None
    deficit            = baseline_cal - recent_cal
    cal_days_logged    = len([e for e in recent14 if e.get("calories")])

    return {
        "available":           True,
        "recent_cal_avg":      round(recent_cal),
        "baseline_cal_avg":    round(baseline_cal),
        "caloric_deficit":     round(deficit),
        "deficit_flag":        deficit > 300 and cal_days_logged >= 7,
        "protein_avg_g":       round(recent_protein, 1),
        "low_protein_flag":    protein_threshold is not None and recent_protein < protein_threshold,
        "protein_threshold_g": round(protein_threshold) if protein_threshold else None,
    }


def _body_weight_lbs() -> Optional[float]:
    logs = db.get_body_weight_logs(limit=5)
    for row in logs:
        w = row.get("weight")
        if w and float(w) > 0:
            return float(w)
    return None


# ── Plateau scoring ───────────────────────────────────────────────────────────

def _score(sessions: list[dict]) -> dict:
    """Compute plateau score 0–100 for one exercise over the last 3 weeks."""
    cutoff = (date.today() - timedelta(days=21)).isoformat()
    window = [s for s in sessions if s["date"] >= cutoff]

    if len(window) < 3:
        return {"score": 0}

    weights  = [s["weight_lbs"] for s in window]
    e1rms    = [s["e1rm_lbs"]   for s in window]
    reps_l   = [s["reps"]       for s in window]

    # Noise filter: intentional variation → skip
    mean_w = sum(weights) / len(weights)
    if mean_w > 0:
        std_w = math.sqrt(sum((w - mean_w) ** 2 for w in weights) / len(weights))
        if std_w / mean_w > 0.15:
            return {"score": 0, "flags": ["intentional_variation"]}

    score = 0
    flags: list[str] = []

    # Signal 1 — days since last e1RM improvement ≥2%
    peak             = e1rms[0]
    last_improvement = window[0]["date"]
    for i in range(1, len(e1rms)):
        if e1rms[i] > peak * 1.02:
            peak             = e1rms[i]
            last_improvement = window[i]["date"]

    days_since = (date.today() - date.fromisoformat(last_improvement)).days
    if   days_since > 21: score += 30
    elif days_since > 14: score += 20
    elif days_since > 10: score += 10

    # Signal 2 — e1RM trend slope via linear regression
    n      = len(e1rms)
    xs     = list(range(n))
    x_mean = (n - 1) / 2.0
    y_mean = sum(e1rms) / n
    num    = sum((xs[i] - x_mean) * (e1rms[i] - y_mean) for i in range(n))
    den    = sum((xs[i] - x_mean) ** 2 for i in range(n))
    slope_per_session = num / den if den else 0.0

    date_span         = max(1, (date.fromisoformat(window[-1]["date"]) -
                                date.fromisoformat(window[0]["date"])).days)
    sessions_per_week = len(window) / (date_span / 7.0)
    slope_per_week    = slope_per_session * sessions_per_week

    regression = slope_per_week < -0.5

    if   slope_per_week > 1.0:  score += 0
    elif slope_per_week > 0:    score += 10
    elif slope_per_week > -0.5: score += 20
    else:
        score += 30
        flags.append("regression")

    # Signal 3 — repeated identical top sets
    top_sets = [(_round_lbs(s["weight_lbs"]), s["reps"]) for s in window]
    if any(v >= 2 for v in Counter(top_sets).values()):
        score += 20
        flags.append("repeated_sets")

    # Signal 4 — rep ceiling (≥6 reps at same weight, 2+ consecutive sessions)
    for i in range(len(window) - 1):
        if (window[i]["reps"] >= 6 and window[i + 1]["reps"] >= 6
                and abs(window[i]["weight_lbs"] - window[i + 1]["weight_lbs"]) < 10):
            flags.append("rep_ceiling")
            score += 20
            break

    return {
        "score":                  min(score, 100),
        "flags":                  flags,
        "regression":             regression,
        "days_since_improvement": days_since,
        "slope_per_week":         round(slope_per_week, 2),
        "e1rm_series":            [{"date": s["date"], "e1rm_lbs": s["e1rm_lbs"]} for s in window],
        "working_weight_lbs":     window[-1]["weight_lbs"],
        "working_reps":           window[-1]["reps"],
    }


# ── Decision tree ─────────────────────────────────────────────────────────────

def _classify(plateau_info: dict, pss: dict, nutrition: dict) -> dict:
    flags      = plateau_info.get("flags", [])
    regression = plateau_info.get("regression", False)

    if regression or (pss.get("is_high") and pss.get("is_rising")):
        return {"root_cause": "overreaching",   "severity": "critical", "deload_type": "rest"}
    if nutrition.get("deficit_flag"):
        return {"root_cause": "underfueling",   "severity": "warning",  "deload_type": "nutrition_first"}
    if "rep_ceiling" in flags and not pss.get("is_high"):
        return {"root_cause": "adaptation",     "severity": "warning",  "deload_type": "rep_range"}
    return     {"root_cause": "neural_fatigue", "severity": "warning",  "deload_type": "light_week"}


# ── Deload plan ───────────────────────────────────────────────────────────────

def _deload_plan(deload_type: str, exercise_name: str,
                 weight_lbs: float, reps: int, is_lower: bool) -> dict:
    step = 10.0 if is_lower else 5.0

    if deload_type == "rest":
        return {
            "instruction":       "Repos complet 4-5 jours. Marche légère, mobilité. Ton SNC a besoin de récupérer.",
            "return_weight_lbs": _round_lbs(weight_lbs * 0.70, step),
            "return_sets":       3,
            "return_reps":       reps,
            "exercises":         [],
        }

    if deload_type == "light_week":
        to_lbs = _round_lbs(weight_lbs * 0.80, step)
        return {
            "instruction": "Mêmes exercices, 80% du poids habituel. 2 sets max. Aucun échec. Focus technique.",
            "exercises": [{
                "name":     exercise_name,
                "from_lbs": weight_lbs,
                "to_lbs":   to_lbs,
                "sets":     2,
                "reps":     reps,
                "note":     f"{exercise_name}: {weight_lbs:.0f} → {to_lbs:.0f} lbs (-20%)",
            }],
        }

    if deload_type == "rep_range":
        force_lbs  = _round_lbs(weight_lbs * 1.125, step)
        volume_lbs = _round_lbs(weight_lbs * 0.80,  step)
        return {
            "instruction": f"Pattern bloqué à {reps} reps. Briser avec force (3-4 reps lourds) ou volume (12-15 reps légers).",
            "exercises": [{
                "name":          exercise_name,
                "from_lbs":      weight_lbs,
                "from_reps":     reps,
                "force_option":  {"weight_lbs": force_lbs,  "reps": "3-4"},
                "volume_option": {"weight_lbs": volume_lbs, "reps": "12-15"},
            }],
        }

    if deload_type == "nutrition_first":
        to_lbs = _round_lbs(weight_lbs * 0.80, step)
        return {
            "instruction": "Remonte les calories +350 kcal/jour pendant 10 jours. Volume réduit à 80% du poids, 2 sets.",
            "exercises": [{
                "name":     exercise_name,
                "from_lbs": weight_lbs,
                "to_lbs":   to_lbs,
                "sets":     2,
                "reps":     reps,
            }],
            "nutrition_prescription": {
                "caloric_increase_kcal": 350,
                "duration_days":         10,
                "protein_target_note":   "Vise ≥0.73g de protéines par lb de poids corporel",
            },
        }

    return {"instruction": "", "exercises": []}


# ── Rebound prediction ────────────────────────────────────────────────────────

def _rebound(deload_type: str, plateau_weeks: int, pss: dict) -> dict:
    base = {
        "rest":            (5, 10),
        "light_week":      (7, 14),
        "rep_range":       (14, 21),
        "nutrition_first": (10, 21),
    }.get(deload_type, (7, 14))

    lo, hi = base
    if plateau_weeks <= 2:
        lo, hi = int(lo * 0.8), int(hi * 0.8)
    elif plateau_weeks >= 5:
        lo, hi = int(lo * 1.3), int(hi * 1.3)

    if pss.get("trend", 0) < -10:
        lo, hi = int(lo * 0.8), int(hi * 0.8)

    return {
        "days_min": lo,
        "days_max": hi,
        "message":  f"Avec ton profil, les athlètes similaires reprennent en {lo}-{hi} jours après ce deload.",
    }


# ── DB persistence ────────────────────────────────────────────────────────────

def _persist(alert: dict) -> Optional[str]:
    """Insert alert to DB; return existing id if a live alert already exists."""
    cli = db._client
    if not cli:
        return None

    ex = alert["exercise_name"]
    try:
        existing = (cli.table("plateau_alerts")
                    .select("id")
                    .eq("exercise_name", ex)
                    .in_("status", ["pending", "accepted", "active"])
                    .limit(1)
                    .execute().data)
        if existing:
            return existing[0]["id"]

        row = {
            "exercise_name":   ex,
            "plateau_score":   alert["plateau_score"],
            "plateau_weeks":   alert["plateau_weeks"],
            "root_cause":      alert["root_cause"],
            "severity":        alert["severity"],
            "deload_type":     alert.get("deload_type"),
            "deload_plan":     alert.get("deload_plan"),
            "rebound_days_min": alert.get("rebound_days_min"),
            "rebound_days_max": alert.get("rebound_days_max"),
            "status": "pending",
        }
        result = cli.table("plateau_alerts").insert(row).execute()
        if result.data:
            return result.data[0]["id"]
    except Exception as e:
        logger.warning("Failed to persist plateau alert for %s: %s", ex, e)
    return None


# ── Main entry ────────────────────────────────────────────────────────────────

def detect(force: bool = False) -> dict:
    """Detect plateaus on all compound exercises. 2h cache."""
    global _CACHE
    now = time.time()
    if not force and _CACHE.get("ts") and now - _CACHE["ts"] < _CACHE_TTL:
        return _CACHE["data"]

    working_sets = _working_sets(days=28)
    pss          = _pss_context()
    nutrition    = _nutrition_context()

    alerts = []

    for exercise_name, sessions in working_sets.items():
        info  = _score(sessions)
        score = info.get("score", 0)
        if score < 40:
            continue

        cutoff_21 = (date.today() - timedelta(days=21)).isoformat()
        window    = [s for s in sessions if s["date"] >= cutoff_21]
        if not window:
            continue

        first_date    = date.fromisoformat(window[0]["date"])
        plateau_weeks = max(1, round((date.today() - first_date).days / 7))

        weight_lbs = info["working_weight_lbs"]
        reps       = info["working_reps"]
        is_lower_b = _is_lower(exercise_name)

        if score >= 60:
            ctx = _classify(info, pss, nutrition)
        else:
            ctx = {"root_cause": "monitoring", "severity": "advisory", "deload_type": None}

        deload_plan  = None
        rebound_info = None
        if ctx.get("deload_type"):
            deload_plan  = _deload_plan(ctx["deload_type"], exercise_name, weight_lbs, reps, is_lower_b)
            rebound_info = _rebound(ctx["deload_type"], plateau_weeks, pss)

        alert = {
            "exercise_name":      exercise_name,
            "detected_at":        datetime.utcnow().isoformat(),
            "plateau_score":      score,
            "plateau_weeks":      plateau_weeks,
            "root_cause":         ctx["root_cause"],
            "severity":           ctx["severity"],
            "deload_type":        ctx.get("deload_type"),
            "deload_plan":        deload_plan,
            "rebound_days_min":   rebound_info["days_min"] if rebound_info else None,
            "rebound_days_max":   rebound_info["days_max"] if rebound_info else None,
            "rebound_message":    rebound_info["message"]  if rebound_info else None,
            "e1rm_series":        info.get("e1rm_series", []),
            "working_weight_lbs": weight_lbs,
            "working_reps":       reps,
            "pss_context":        pss       if pss.get("available")       else None,
            "nutrition_context":  {
                "caloric_deficit": nutrition.get("caloric_deficit"),
                "deficit_flag":    nutrition.get("deficit_flag"),
            } if nutrition.get("available") else None,
            "status": "pending",
        }

        if score >= 60:
            alert_id   = _persist(alert)
            alert["id"] = alert_id

        alerts.append(alert)

    severity_order = {"critical": 0, "warning": 1, "advisory": 2}
    alerts.sort(key=lambda a: (severity_order.get(a["severity"], 3), -a["plateau_score"]))

    data = {"alerts": alerts, "computed_at": datetime.utcnow().isoformat()}
    _CACHE = {"ts": now, "data": data}
    return data
