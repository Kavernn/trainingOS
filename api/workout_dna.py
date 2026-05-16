"""workout_dna.py — Workout DNA profile: 5-dimension training fingerprint."""
from __future__ import annotations

import hashlib
import json
import logging
import math
from datetime import date as date_cls, datetime, timedelta, timezone
from typing import Optional

import db

logger = logging.getLogger("trainingos.workout_dna")

_CACHE: dict = {}
_CACHE_TTL = 4 * 3600


# ── Rep zone → intensity score (0-100, higher = more force) ──────────────────

def _rep_score(reps: int) -> int:
    if reps <= 4:  return 95
    if reps <= 7:  return 75
    if reps <= 12: return 55
    if reps <= 20: return 30
    return 15

_LOAD_SCORE = {
    "compound_heavy":       80,
    "compound_hypertrophy": 55,
    "isolation":            35,
    "cardio":               20,
    "bodyweight":           45,
}


# ── 1. PPL Balance ────────────────────────────────────────────────────────────

def _classify_ppl(category: str) -> str:
    cat = category.lower()
    if any(k in cat for k in ("chest", "pec", "shoulder", "delt", "tricep", "push")):
        return "push"
    if any(k in cat for k in ("back", "lat", "trap", "bicep", "rear", "row", "pull")):
        return "pull"
    if any(k in cat for k in ("quad", "hamstring", "glute", "leg", "calf", "hip", "rdl")):
        return "legs"
    if any(k in cat for k in ("core", "abs", "oblique")):
        return "core"
    return "other"


def _compute_ppl(history: dict, ex_info: dict) -> dict:
    cutoff = (date_cls.today() - timedelta(days=90)).isoformat()
    counts = {"push": 0, "pull": 0, "legs": 0, "core": 0, "other": 0}

    for name, entries in history.items():
        cat   = (ex_info.get(name, {}).get("category") or "")
        group = _classify_ppl(cat)
        for e in entries:
            if (e.get("date") or "") < cutoff:
                continue
            sets_list = e.get("sets")
            counts[group] += len(sets_list) if isinstance(sets_list, list) else 1

    total     = sum(counts.values()) or 1
    ppl_total = (counts["push"] + counts["pull"] + counts["legs"]) or 1

    push_pct  = round(counts["push"]  / total * 100)
    pull_pct  = round(counts["pull"]  / total * 100)
    legs_pct  = round(counts["legs"]  / total * 100)
    core_pct  = round(counts["core"]  / total * 100)
    other_pct = max(0, 100 - push_pct - pull_pct - legs_pct - core_pct)

    push_n = round(counts["push"] / ppl_total * 100)
    pull_n = round(counts["pull"] / ppl_total * 100)
    legs_n = round(counts["legs"] / ppl_total * 100)
    dev    = (abs(push_n - 33) + abs(pull_n - 33) + abs(legs_n - 33)) / 3
    balance_score = max(0, round(100 - dev * 2))

    verdict = "Équilibré"
    if push_n - pull_n > 12:   verdict = "Pull-déficit"
    elif pull_n - push_n > 12: verdict = "Push-déficit"
    elif legs_n < 20:          verdict = "Jambes négligées"

    return {
        "push_pct":      push_pct,
        "pull_pct":      pull_pct,
        "legs_pct":      legs_pct,
        "core_pct":      core_pct,
        "other_pct":     other_pct,
        "balance_score": balance_score,
        "verdict":       verdict,
    }


# ── 2. Intensity Profile ──────────────────────────────────────────────────────

def _compute_intensity(history: dict, ex_info: dict) -> dict:
    cutoff = (date_cls.today() - timedelta(days=90)).isoformat()
    zone_counts = {"strength": 0, "power": 0, "hypertrophy": 0, "endurance": 0, "conditioning": 0}
    compound_sets = isolation_sets = 0
    weighted: list[float] = []

    for name, entries in history.items():
        profile    = (ex_info.get(name, {}).get("load_profile") or "").lower()
        load_score = _LOAD_SCORE.get(profile, 50)
        is_compound = "compound" in profile
        w_factor    = 1.3 if is_compound else 0.85

        for e in entries:
            if (e.get("date") or "") < cutoff:
                continue
            default_reps = int(e.get("reps") or 8)
            sets_list    = e.get("sets")

            iter_reps: list[int] = []
            if isinstance(sets_list, list):
                for s in sets_list:
                    r = int(s.get("reps") if isinstance(s, dict) else default_reps)
                    iter_reps.append(r)
            else:
                iter_reps = [default_reps]

            for r in iter_reps:
                score = (_rep_score(r) * 0.6 + load_score * 0.4) * w_factor
                weighted.append(score)
                if is_compound: compound_sets += 1
                else:           isolation_sets += 1
                if r <= 4:    zone_counts["strength"]    += 1
                elif r <= 7:  zone_counts["power"]       += 1
                elif r <= 12: zone_counts["hypertrophy"] += 1
                elif r <= 20: zone_counts["endurance"]   += 1
                else:         zone_counts["conditioning"] += 1

    total_sets    = sum(zone_counts.values()) or 1
    i_score       = round(sum(weighted) / len(weighted)) if weighted else 50
    i_score       = max(0, min(100, i_score))
    force_pct     = round((zone_counts["strength"] + zone_counts["power"]) / total_sets * 100)
    hyp_pct       = round(zone_counts["hypertrophy"] / total_sets * 100)
    endurance_pct = max(0, 100 - force_pct - hyp_pct)
    compound_pct  = round(compound_sets / (compound_sets + isolation_sets) * 100) \
                    if (compound_sets + isolation_sets) else 50

    if i_score >= 71:   label = "Strength Athlete"
    elif i_score >= 51: label = "Power Builder"
    elif i_score >= 31: label = "Hypertrophy Builder"
    else:               label = "Pump Artist"

    return {
        "score":           i_score,
        "label":           label,
        "force_pct":       force_pct,
        "hypertrophy_pct": hyp_pct,
        "endurance_pct":   endurance_pct,
        "compound_pct":    compound_pct,
        "isolation_pct":   100 - compound_pct,
    }


# ── 3. Consistency ────────────────────────────────────────────────────────────

def _compute_consistency() -> dict:
    if db._client is None:
        return {}
    cutoff = (date_cls.today() - timedelta(days=90)).isoformat()
    try:
        resp  = db._client.table("workout_sessions").select("date").gte("date", cutoff).order("date").execute()
        rows  = resp.data or []
    except Exception as e:
        logger.error("consistency error: %s", e)
        return {}

    dates = sorted(set(r["date"] for r in rows if r.get("date")))
    if not dates:
        return {"score": 0, "sessions_per_week": 0.0, "cv": 1.0,
                "archetype": "En construction", "current_streak": 0,
                "longest_streak": 0, "active_weeks_pct": 0, "weekly_counts": [0]*13}

    spw = round(len(dates) / 13.0, 1)

    today = date_cls.today()
    weekly: dict[int, int] = {w: 0 for w in range(13)}
    for d_str in dates:
        w = min(12, (today - date_cls.fromisoformat(d_str)).days // 7)
        weekly[w] = weekly.get(w, 0) + 1

    counts     = list(weekly.values())
    mean_c     = sum(counts) / len(counts) if counts else 1
    std_c      = math.sqrt(sum((x - mean_c)**2 for x in counts) / len(counts)) if len(counts) > 1 else 0
    cv         = round(std_c / mean_c if mean_c > 0 else 1.0, 2)
    active_pct = round(sum(1 for c in counts if c > 0) / len(counts) * 100)

    # Current streak (days since last gap > 2d)
    all_set = set(dates)
    current = 0
    d       = today
    while current < 365:
        if d.isoformat() in all_set:
            current += 1; d -= timedelta(days=1)
        elif (d - timedelta(days=1)).isoformat() in all_set:
            d -= timedelta(days=2)
        else:
            break

    # Longest streak
    longest = run = 0
    prev = None
    for d_str in dates:
        d = date_cls.fromisoformat(d_str)
        run = run + 1 if (prev and (d - prev).days <= 2) else 1
        longest = max(longest, run)
        prev = d

    if cv < 0.3 and spw >= 4:    archetype = "Machine"
    elif cv < 0.3 and spw >= 2:  archetype = "Régulier"
    elif cv < 0.6 and spw >= 3:  archetype = "Warrior"
    elif cv < 0.6:               archetype = "En construction"
    else:                        archetype = "Erratique"

    score = round(min(100, active_pct * 0.5 + (1 - min(cv, 1)) * 30 + min(spw / 5, 1) * 20))

    return {
        "score":             score,
        "sessions_per_week": spw,
        "cv":                cv,
        "archetype":         archetype,
        "current_streak":    current,
        "longest_streak":    longest,
        "active_weeks_pct":  active_pct,
        "weekly_counts":     [weekly.get(w, 0) for w in range(12, -1, -1)],  # oldest→newest
    }


# ── 4. Recovery Profile ───────────────────────────────────────────────────────

def _compute_recovery(intensity_score: int) -> dict:
    if db._client is None:
        return {}
    cutoff = (date_cls.today() - timedelta(days=90)).isoformat()
    try:
        resp  = db._client.table("workout_sessions").select("date").gte("date", cutoff).order("date").execute()
        dates = sorted(set(r["date"] for r in (resp.data or []) if r.get("date")))
    except Exception as e:
        logger.error("recovery error: %s", e)
        return {}

    if len(dates) < 2:
        return {"avg_rest_days": 1.5, "optimal_rest_days": 1.5, "ratio": 1.0,
                "score": 75, "verdict": "Optimal"}

    gaps = [(date_cls.fromisoformat(dates[i]) - date_cls.fromisoformat(dates[i-1])).days - 1
            for i in range(1, len(dates))]
    gaps = [g for g in gaps if 0 <= g <= 14]

    avg_rest = round(sum(gaps) / len(gaps), 1) if gaps else 1.5
    optimal  = 2.0 if intensity_score >= 70 else 1.5 if intensity_score >= 45 else 1.0
    ratio    = round(avg_rest / optimal, 2)

    if ratio < 0.75:    verdict = "Sous-récupéré"
    elif ratio <= 1.30: verdict = "Optimal"
    else:               verdict = "Sur-récupéré"

    return {
        "avg_rest_days":     avg_rest,
        "optimal_rest_days": optimal,
        "ratio":             ratio,
        "score":             round(max(0, 100 - abs(ratio - 1.0) * 60)),
        "verdict":           verdict,
    }


# ── 5. Signature Lifts ────────────────────────────────────────────────────────

def _compute_signature_lifts(history: dict) -> list:
    cutoff_30 = (date_cls.today() - timedelta(days=30)).isoformat()
    lifts: dict[str, dict] = {}

    for name, entries in history.items():
        pr_weight = first_weight = 0.0
        pr_reps = 1; pr_date = first_date = ""
        session_dates: set[str] = set()
        recency = 0

        for e in entries:
            w = float(e.get("weight") or 0)
            d = e.get("date") or ""
            if not w or not d:
                continue
            session_dates.add(d)
            if not first_date or d < first_date:
                first_date  = d
                first_weight = w
            if w > pr_weight:
                pr_weight = w
                pr_reps   = int(e.get("reps") or 1)
                pr_date   = d
            if d >= cutoff_30:
                recency += 1

        if pr_weight == 0 or len(session_dates) < 3:
            continue

        prog = round((pr_weight - first_weight) / first_weight * 100, 1) \
               if first_weight > 0 and pr_weight > first_weight else 0.0

        lifts[name] = {
            "name":            name,
            "session_count":   len(session_dates),
            "pr_kg":           pr_weight,
            "pr_reps":         pr_reps,
            "pr_date":         pr_date,
            "first_date":      first_date,
            "progression_pct": prog,
            "recency":         recency,
            "_score":          len(session_dates) * 0.5 + recency * 10 + prog * 0.3,
        }

    ranked = sorted(lifts.values(), key=lambda x: x["_score"], reverse=True)[:5]
    for r in ranked:
        del r["_score"]
    return ranked


# ── Archetype ─────────────────────────────────────────────────────────────────

def _archetype(ppl: dict, intensity: dict, consistency: dict) -> dict:
    i = intensity.get("score", 50)
    c = consistency.get("score", 50)
    b = ppl.get("balance_score", 50)
    spw = consistency.get("sessions_per_week", 3)
    legs = ppl.get("legs_pct", 0)

    if i >= 70 and b >= 60 and c >= 65:
        return {"key": "powerlifter", "label": "The Powerlifter", "tagline": "Compound. Heavy. Consistent."}
    if i >= 40 and legs >= 25 and c >= 60:
        return {"key": "bodybuilder",  "label": "The Bodybuilder",  "tagline": "Volume. Symmetry. Discipline."}
    if c >= 85 and spw >= 4.5:
        return {"key": "grinder",      "label": "The Grinder",      "tagline": "Never misses. Never quits."}
    if spw <= 2.5 and i >= 60:
        return {"key": "warrior",      "label": "Weekend Warrior",  "tagline": "Rare but fierce."}
    if b >= 75 and 45 <= i <= 65 and c >= 65:
        return {"key": "athlete",      "label": "The Athlete",      "tagline": "Balanced. Efficient. Sharp."}
    return {"key": "builder",          "label": "The Builder",      "tagline": "Building, day by day."}


def _dna_seed(ppl: dict, intensity: dict, consistency: dict, recovery: dict) -> str:
    payload = json.dumps({
        "push": ppl.get("push_pct", 0),  "pull": ppl.get("pull_pct", 0),
        "legs": ppl.get("legs_pct", 0),  "i":    intensity.get("score", 0),
        "cv":   consistency.get("cv", 0), "rest": recovery.get("avg_rest_days", 0),
    }, sort_keys=True)
    return hashlib.md5(payload.encode()).hexdigest()[:8]


# ── Public ────────────────────────────────────────────────────────────────────

def compute() -> dict:
    now_ts = datetime.now(timezone.utc).timestamp()
    cached = _CACHE.get("dna")
    if cached and (now_ts - cached["ts"]) < _CACHE_TTL:
        return cached["data"]

    try:
        history  = db.get_all_exercise_history()
        ex_info  = db.get_exercises_info_bulk(list(history.keys()))

        ppl         = _compute_ppl(history, ex_info)
        intensity   = _compute_intensity(history, ex_info)
        consistency = _compute_consistency()
        recovery    = _compute_recovery(intensity.get("score", 50))
        lifts       = _compute_signature_lifts(history)
        arch        = _archetype(ppl, intensity, consistency)
        seed        = _dna_seed(ppl, intensity, consistency, recovery)

        result = {
            "period":          {"from": (date_cls.today() - timedelta(days=90)).isoformat(),
                                "to":   date_cls.today().isoformat()},
            "archetype":       arch,
            "ppl":             ppl,
            "intensity":       intensity,
            "consistency":     consistency,
            "recovery":        recovery,
            "signature_lifts": lifts,
            "dna_seed":        seed,
            "computed_at":     datetime.now(timezone.utc).isoformat(),
        }
        _CACHE["dna"] = {"data": result, "ts": now_ts}
        return result

    except Exception as e:
        logger.error("workout_dna error: %s", e)
        return {"error": str(e)}
