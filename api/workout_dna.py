"""workout_dna.py — Workout DNA profile: 5-dimension training fingerprint."""
from __future__ import annotations

import hashlib
import json
import logging
import math
from datetime import date as date_cls, datetime, timedelta, timezone
from utils import _today_mtl
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

def _classify_ppl(category: str, name: str = "") -> str:
    """Classification push/pull/legs/core/other.

    Pattern-based doctrine : deadlift / RDL / hinge sont des mouvements de
    jambes (chaîne postérieure), pas de pull. Curl reste pull (bras tirés).
    L'ordre des checks est significatif : les keywords legs sont évalués
    AVANT pull pour qu'un nom contenant "deadlift" ou "rdl" tombe en legs.
    """
    cat = category.lower()
    if any(k in cat for k in ("quad", "hamstring", "glute", "leg", "calf", "hip", "rdl", "deadlift")):
        return "legs"
    if any(k in cat for k in ("chest", "pec", "shoulder", "delt", "tricep", "push")):
        return "push"
    if any(k in cat for k in ("back", "lat", "trap", "bicep", "rear", "row", "pull")):
        return "pull"
    if any(k in cat for k in ("core", "abs", "oblique")):
        return "core"
    # Name-based fallback — ordre : legs → push → pull.
    n = name.lower()
    if any(k in n for k in ("squat", "lunge", "leg", "calf", "glute", "hip thrust", "nordic",
                            "hamstring", "split squat", "deadlift", "rdl")):
        return "legs"
    if any(k in n for k in ("press", "fly", "pec", "dip", "push", "chest", "shoulder",
                            "delt", "tricep", "lateral raise")):
        return "push"
    if any(k in n for k in ("row", "pull", "chin", "shrug", "curl", "lat", "rear delt")):
        return "pull"
    return "other"


def _compute_ppl(history: dict, ex_info: dict, period_days: int = 90) -> dict:
    """PPL balance via sets catalogue, décharges exclues via is_deload_day.

    Garde-fou : < MIN_SESSIONS_PER_SECTION sessions distinctes dans la
    fenêtre (hors décharge) → insufficient_data=True, aucun verdict ni
    pourcentages inventés. Erreur du prédicat is_deload_day → remontée
    en erreur explicite de la section (clé "error"), pas en insufficient.
    """
    try:
        from analytics_adapter import is_deload_day

        cutoff = (date_cls.fromisoformat(_today_mtl()) - timedelta(days=period_days)).isoformat()
        counts = {"push": 0, "pull": 0, "legs": 0, "core": 0, "other": 0}
        session_dates: set[str] = set()
        invalid_dates = 0

        for name, entries in history.items():
            cat   = (ex_info.get(name, {}).get("category") or "")
            group = _classify_ppl(cat, name)
            for e in entries:
                d_str = e.get("date") or ""
                if d_str < cutoff:
                    continue
                try:
                    d = date_cls.fromisoformat(d_str[:10])
                except ValueError:
                    invalid_dates += 1
                    continue
                if is_deload_day(d):
                    continue
                session_dates.add(d_str[:10])
                sets_list = e.get("sets")
                counts[group] += len(sets_list) if isinstance(sets_list, list) else 1
    except Exception as exc:
        logger.exception("PPL section error: %s", exc)
        return {"error": str(exc), "n_sessions": 0, "invalid_dates": 0}

    n_sessions = len(session_dates)
    if n_sessions < MIN_SESSIONS_PER_SECTION:
        return {
            "insufficient_data": True,
            "n_sessions":        n_sessions,
            "invalid_dates":     invalid_dates,
        }

    total     = sum(counts.values()) or 1
    ppl_total = (counts["push"] + counts["pull"] + counts["legs"]) or 1

    push_n = round(counts["push"] / ppl_total * 100)
    pull_n = round(counts["pull"] / ppl_total * 100)
    legs_n = max(0, 100 - push_n - pull_n)

    core_pct  = round(counts["core"]  / total * 100)
    other_pct = round(counts["other"] / total * 100)

    dev           = (abs(push_n - 33) + abs(pull_n - 33) + abs(legs_n - 33)) / 3
    balance_score = max(0, round(100 - dev * 2))

    verdict = "Équilibré"
    if push_n - pull_n > 12:   verdict = "Pull-déficit"
    elif pull_n - push_n > 12: verdict = "Push-déficit"
    elif legs_n < 20:          verdict = "Jambes négligées"

    return {
        "push_pct":          push_n,
        "pull_pct":          pull_n,
        "legs_pct":          legs_n,
        "core_pct":          core_pct,
        "other_pct":         other_pct,
        "balance_score":     balance_score,
        "verdict":           verdict,
        "insufficient_data": False,
        "n_sessions":        n_sessions,
        "invalid_dates":     invalid_dates,
    }


# ── 2. Intensity Profile ──────────────────────────────────────────────────────

def _compute_intensity(history: dict, ex_info: dict, period_days: int = 90) -> dict:
    """Profil d'intensité, décharges exclues.

    Fallback explicite : exercice sans `load_profile` catalogue → EXCLU de
    la stat et compté dans excluded_no_load_profile (plus de score=50
    silencieux). Garde-fou MIN_SESSIONS_PER_SECTION. Erreur du prédicat
    is_deload_day → clé "error", pas insufficient.
    """
    try:
        from analytics_adapter import is_deload_day

        cutoff = (date_cls.fromisoformat(_today_mtl()) - timedelta(days=period_days)).isoformat()
        zone_counts = {"strength": 0, "power": 0, "hypertrophy": 0, "endurance": 0, "conditioning": 0}
        compound_sets = isolation_sets = 0
        weighted: list[float] = []
        session_dates: set[str] = set()
        excluded_names: set[str] = set()
        invalid_dates = 0

        for name, entries in history.items():
            profile = (ex_info.get(name, {}).get("load_profile") or "").lower()
            if not profile:
                # Fallback explicite — un exo sans load_profile ne gonfle pas
                # un score fantôme à 50. Compté séparément.
                if any((e.get("date") or "") >= cutoff for e in entries):
                    excluded_names.add(name)
                continue
            load_score  = _LOAD_SCORE.get(profile, 50)
            is_compound = "compound" in profile
            w_factor    = 1.3 if is_compound else 0.85

            for e in entries:
                d_str = e.get("date") or ""
                if d_str < cutoff:
                    continue
                try:
                    d = date_cls.fromisoformat(d_str[:10])
                except ValueError:
                    invalid_dates += 1
                    continue
                if is_deload_day(d):
                    continue
                session_dates.add(d_str[:10])
                default_reps = int(str(e.get("reps") or "8").split(",")[0].strip() or 8)
                sets_list    = e.get("sets")
                rpe          = e.get("rpe")

                iter_reps: list[int] = []
                if isinstance(sets_list, list):
                    for s in sets_list:
                        raw = s.get("reps") if isinstance(s, dict) else default_reps
                        r = default_reps if raw is None else int(raw)
                        iter_reps.append(r)
                else:
                    iter_reps = [default_reps]

                for r in iter_reps:
                    if rpe and isinstance(rpe, (int, float)) and 1 <= rpe <= 10:
                        rpe_score = (rpe / 10) * 100
                        score = (_rep_score(r) * 0.50 + load_score * 0.30 + rpe_score * 0.20) * w_factor
                    else:
                        score = (_rep_score(r) * 0.60 + load_score * 0.40) * w_factor
                    weighted.append(score)
                    if is_compound: compound_sets += 1
                    else:           isolation_sets += 1
                    if r <= 4:    zone_counts["strength"]    += 1
                    elif r <= 7:  zone_counts["power"]       += 1
                    elif r <= 12: zone_counts["hypertrophy"] += 1
                    elif r <= 20: zone_counts["endurance"]   += 1
                    else:         zone_counts["conditioning"] += 1
    except Exception as exc:
        logger.exception("Intensity section error: %s", exc)
        return {"error": str(exc), "n_sessions": 0, "invalid_dates": 0,
                "excluded_no_load_profile": 0}

    n_sessions = len(session_dates)
    if n_sessions < MIN_SESSIONS_PER_SECTION or not weighted:
        return {
            "insufficient_data":         True,
            "n_sessions":                n_sessions,
            "excluded_no_load_profile":  len(excluded_names),
            "invalid_dates":             invalid_dates,
        }

    total_sets    = sum(zone_counts.values()) or 1
    i_score       = max(0, min(100, round(sum(weighted) / len(weighted))))
    force_pct     = round((zone_counts["strength"] + zone_counts["power"]) / total_sets * 100)
    hyp_pct       = round(zone_counts["hypertrophy"] / total_sets * 100)
    endurance_pct = max(0, 100 - force_pct - hyp_pct)
    compound_pct  = (
        round(compound_sets / (compound_sets + isolation_sets) * 100)
        if (compound_sets + isolation_sets) else 0
    )

    if i_score >= 71:   label = "Strength Athlete"
    elif i_score >= 51: label = "Power Builder"
    elif i_score >= 31: label = "Hypertrophy Builder"
    else:               label = "Pump Artist"

    return {
        "score":                    i_score,
        "label":                    label,
        "force_pct":                force_pct,
        "hypertrophy_pct":          hyp_pct,
        "endurance_pct":            endurance_pct,
        "compound_pct":             compound_pct,
        "isolation_pct":            100 - compound_pct,
        "insufficient_data":        False,
        "n_sessions":               n_sessions,
        "excluded_no_load_profile": len(excluded_names),
        "invalid_dates":            invalid_dates,
    }


# ── 3. Consistency ────────────────────────────────────────────────────────────

def _compute_consistency(period_days: int = 90) -> dict:
    """Constance via weekly_streaks.compute — source unique partagée avec
    /api/stats/streaks et le dashboard. DNA ne recalcule rien :

      - weekly_counts     = days_active de chaque semaine (grille 13 sem).
      - sessions_per_week = total days_active / 13.
      - cv                = stddev(days_active) / mean(days_active).
      - active_weeks_pct  = pct de semaines avec ≥ 1 jour actif.
      - weekly_streak_*   = valeurs serveur.

    Jour actif = workout completed/rpe + HIIT + cardio + exercise_logs
    (même règle que la grille Régularité, pas la row brute workout_sessions).
    period_days reçu mais ignoré : la grille streaks est toujours 13 semaines
    (90j), c'est le pattern aligné avec le dashboard.
    """
    try:
        from weekly_streaks import compute as _compute_weekly_streaks
        payload = _compute_weekly_streaks(_today_mtl())
    except Exception as e:
        logger.error("consistency weekly_streaks failed: %s", e)
        return {}

    weeks = payload.get("weeks") or []
    # weeks[] : oldest → newest, 13 entries. weekly_counts garde cette direction.
    weekly_counts = [int(w.get("days_active") or 0) for w in weeks]

    total_days_active = sum(weekly_counts)
    if total_days_active == 0:
        return {
            "score":                 0,
            "sessions_per_week":     0.0,
            "cv":                    1.0,
            "archetype":             "En construction",
            "weekly_streak_current": int(payload.get("weekly_streak_current") or 0),
            "weekly_streak_best":    int(payload.get("weekly_streak_best") or 0),
            "active_weeks_pct":      0,
            "weekly_counts":         [0] * 13,
        }

    n = len(weekly_counts) or 1
    spw = round(total_days_active / 13.0, 1)
    mean_c = total_days_active / n
    std_c = math.sqrt(sum((x - mean_c) ** 2 for x in weekly_counts) / n) if n > 1 else 0.0
    cv = round(std_c / mean_c if mean_c > 0 else 1.0, 2)
    active_pct = round(sum(1 for c in weekly_counts if c > 0) / n * 100)

    if cv < 0.3 and spw >= 4:    archetype = "Machine"
    elif cv < 0.3 and spw >= 2:  archetype = "Régulier"
    elif cv < 0.6 and spw >= 3:  archetype = "Warrior"
    elif cv < 0.6:               archetype = "En construction"
    else:                        archetype = "Erratique"

    score = round(min(100, active_pct * 0.5 + (1 - min(cv, 1)) * 30 + min(spw / 5, 1) * 20))

    weekly_streak_current = int(payload.get("weekly_streak_current") or 0)
    weekly_streak_best    = int(payload.get("weekly_streak_best") or 0)

    return {
        "score":                 score,
        "sessions_per_week":     spw,
        "cv":                    cv,
        "archetype":             archetype,
        "weekly_streak_current": weekly_streak_current,
        "weekly_streak_best":    weekly_streak_best,
        "active_weeks_pct":      active_pct,
        "weekly_counts":         weekly_counts,  # oldest → newest, 13 entrées
    }


# ── 4. Session Spacing (ex-"Recovery Profile" DNA, renommée lot e) ───────────

def _percentile(sorted_vals: list[float], p: float) -> float:
    """Interpolation linéaire. sorted_vals doit être non-vide et trié."""
    if len(sorted_vals) == 1:
        return float(sorted_vals[0])
    idx = (len(sorted_vals) - 1) * p
    lo = int(idx)
    hi = min(lo + 1, len(sorted_vals) - 1)
    frac = idx - lo
    return sorted_vals[lo] + frac * (sorted_vals[hi] - sorted_vals[lo])


def _compute_session_spacing(period_days: int = 90) -> dict:
    """Médiane + IQR (p25–p75) des jours entre deux séances actives
    consécutives sur la fenêtre DNA, décharges exclues.

    Source : weekly_streaks.active_dates (même règle que /api/stats/streaks
    et DNA Constance). Décharges exclues via is_deload_day : les dates qui
    tombent dans une période de décharge enregistrée ne comptent ni comme
    séance ni comme "trou" (on les retire avant le calcul des gaps).

    Garde-fou : < MIN_SESSIONS_PER_SECTION (8) séances dans la fenêtre →
    insufficient_data=True, pas de médiane/IQR inventées.

    Suppression lot e vs ancien _compute_recovery : plus de "optimal_rest_days"
    dérivé du score d'intensité, plus de ratio, plus de score/100, plus de
    verdict "Optimal" — toutes des valeurs inventées sans base documentée.
    La vue expose uniquement ce qu'elle mesure : des gaps entre séances.
    """
    try:
        from weekly_streaks import active_dates as _active_dates
        from analytics_adapter import is_deload_day

        today = date_cls.fromisoformat(_today_mtl())
        cutoff = (today - timedelta(days=period_days - 1)).isoformat()

        raw_dates = _active_dates(today.isoformat())
        parsed: list[date_cls] = []
        invalid_dates = 0
        for ds in raw_dates:
            if ds < cutoff:
                continue
            try:
                parsed.append(date_cls.fromisoformat(ds[:10]))
            except ValueError:
                invalid_dates += 1

        # Exclusion décharge au niveau des dates — un gap "entre deux
        # séances actives hors décharge" seulement.
        excluded_deload = 0
        kept: list[date_cls] = []
        for d in parsed:
            if is_deload_day(d):
                excluded_deload += 1
                continue
            kept.append(d)
        kept.sort()
    except Exception as exc:
        logger.exception("session_spacing section error: %s", exc)
        return {"error": str(exc), "n_sessions": 0, "n_gaps": 0,
                "invalid_dates": 0, "excluded_deload_sessions": 0}

    n_sessions = len(kept)
    if n_sessions < MIN_SESSIONS_PER_SECTION:
        return {
            "insufficient_data":        True,
            "n_sessions":               n_sessions,
            "n_gaps":                   max(0, n_sessions - 1),
            "invalid_dates":            invalid_dates,
            "excluded_deload_sessions": excluded_deload,
        }

    gaps = [(kept[i] - kept[i - 1]).days for i in range(1, n_sessions)]
    sorted_gaps = sorted(gaps)
    median = round(_percentile(sorted_gaps, 0.5), 1)
    p25    = round(_percentile(sorted_gaps, 0.25), 1)
    p75    = round(_percentile(sorted_gaps, 0.75), 1)

    return {
        "insufficient_data":        False,
        "n_sessions":               n_sessions,
        "n_gaps":                   len(gaps),
        "median_days":              median,
        "p25_days":                 p25,
        "p75_days":                 p75,
        "invalid_dates":            invalid_dates,
        "excluded_deload_sessions": excluded_deload,
    }


def _compute_recovery(intensity_score: int, period_days: int = 90) -> dict:
    if db._client is None:
        return {}
    cutoff = (date_cls.fromisoformat(_today_mtl()) - timedelta(days=period_days)).isoformat()
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

def _compute_signature_lifts(client, period_days: int = 90) -> list:
    """Signature lifts via strength_exposures (fenêtre DNA, décharge exclue
    pour la fréquence) + exercise_prs pour l'affichage e1RM.

    Classement : par FRÉQUENCE (nombre de séances distinctes dans la fenêtre
    DNA, hors décharge). Égalités départagées par la récence (dernière
    séance la plus récente).

    pr_e1rm_lbs = valeur affichée (même source que PR tracker, table
    exercise_prs).

    progression_pct : via strength_exposures (même pipeline que top movers).
    Meilleur e1RM des 30 PREMIERS jours de la fenêtre DNA vs meilleur e1RM
    des 30 DERNIERS jours. Si une des deux sous-fenêtres est vide pour un
    lift → progression_pct=None (pas 0 — on ne sait pas).
    first_date / last_date exposent les vraies dates observées dans la
    fenêtre DNA (pour que l'iOS affiche "depuis le <date>").

    Filtre baseline_count ≥ 2 (identique PR tracker). Top 5.
    """
    from analytics_adapter import fetch_raw_analytics_rows, adapt_analytics_rows
    from metric_semantics import DateWindow, best_e1rm_for_exposure

    pr_rows = db.get_exercise_prs() or []
    pr_map = {p["exercise_name"]: p for p in pr_rows}
    if not pr_map:
        return []

    today = date_cls.fromisoformat(_today_mtl())
    period = DateWindow(today - timedelta(days=period_days - 1), today)
    raw_rows = fetch_raw_analytics_rows(client, period=period)
    adapted = adapt_analytics_rows(raw_rows, period=period)

    # Sous-fenêtres bornées par la fenêtre DNA — sur 90j elles sont disjointes ;
    # sur < 60j elles se chevauchent (le même set peut compter dans les deux).
    early_sub_days = min(30, period_days)
    late_sub_days  = min(30, period_days)
    early_end  = period.start + timedelta(days=early_sub_days - 1)
    late_start = period.end   - timedelta(days=late_sub_days - 1)

    by_lift: dict[str, dict] = {}
    for exp in adapted.strength_exposures:
        name = exp.exercise_name
        if name not in pr_map:
            continue
        bucket = by_lift.setdefault(name, {
            "sessions_non_deload": set(),
            "last_date":           None,
            "first_date":          None,
            "best_e1rm_early":     None,
            "best_e1rm_late":      None,
        })
        if not exp.is_deload:
            bucket["sessions_non_deload"].add(
                getattr(exp, "session_id", None) or exp.exposure_id
            )
        if bucket["last_date"] is None or exp.date > bucket["last_date"]:
            bucket["last_date"] = exp.date
        if bucket["first_date"] is None or exp.date < bucket["first_date"]:
            bucket["first_date"] = exp.date

        result = best_e1rm_for_exposure(
            tracking_type=exp.tracking_type,
            sets=(
                tuple({"weight": s.weight, "reps": s.reps} for s in exp.sets)
                if exp.sets is not None else None
            ),
            weight=exp.weight,
            reps=exp.reps,
        )
        best = result.best_e1rm
        if best is None or best <= 0:
            continue
        if exp.date <= early_end and (bucket["best_e1rm_early"] is None or best > bucket["best_e1rm_early"]):
            bucket["best_e1rm_early"] = best
        if exp.date >= late_start and (bucket["best_e1rm_late"] is None or best > bucket["best_e1rm_late"]):
            bucket["best_e1rm_late"] = best

    results: list[dict] = []
    for name, pr_info in pr_map.items():
        if int(pr_info.get("baseline_count") or 0) < 2:
            continue
        pr_e1rm = float(pr_info.get("pr_e1rm_lbs") or 0)
        pr_weight = float(pr_info.get("pr_weight_lbs") or 0)
        if pr_e1rm <= 0 or pr_weight <= 0:
            continue
        bucket = by_lift.get(name)
        if bucket is None:
            continue  # aucune exposure dans la fenêtre DNA
        session_count = len(bucket["sessions_non_deload"])
        if session_count <= 0:
            continue

        early_e1rm = bucket["best_e1rm_early"]
        late_e1rm  = bucket["best_e1rm_late"]
        if early_e1rm is None or late_e1rm is None or early_e1rm <= 0:
            progression_pct = None
        else:
            progression_pct = round((late_e1rm - early_e1rm) / early_e1rm * 100, 1)

        results.append({
            "name":            name,
            "session_count":   session_count,
            "pr_lbs":          pr_weight,                   # legacy — à retirer étape c3
            "pr_e1rm_lbs":     round(pr_e1rm, 1),
            "pr_reps":         int(pr_info.get("pr_reps") or 1),
            "pr_date":         pr_info.get("pr_date") or "",
            "first_date":      bucket["first_date"].isoformat() if bucket["first_date"] else "",
            "last_date":       bucket["last_date"].isoformat()  if bucket["last_date"]  else "",
            "progression_pct": progression_pct,
        })

    # Ranking : fréquence desc, tie-break par last_date desc (plus récent gagne).
    results.sort(key=lambda x: (x["session_count"], x["last_date"]), reverse=True)
    return results[:5]


# ── 6. Muscle Dominants ───────────────────────────────────────────────────────

# Seuil générique DNA : chaque section (PPL, Intensité, Muscles, Patterns,
# Espacement) nécessite ≥ MIN_SESSIONS_PER_SECTION séances distinctes dans
# la fenêtre pour exposer des stats. Sous ce seuil, insufficient_data=True.
MIN_SESSIONS_PER_SECTION = 8


def _compute_muscle_dominants(client, period_days: int = 90) -> tuple[list, dict]:
    """Via summarize_muscle_workload — source canonique partagée avec le cockpit.

    Retourne (muscles_list, meta) :
      - muscles_list : [{muscle, sets (legacy int), effective_sets (float), pct (int)}]
        trié par effective_sets desc, top 6.
      - meta : {n_sessions, insufficient_data, excluded_full_deload}.

    effective_sets = weekly_effective_sets de MuscleWorkload (séries effectives
    hebdomadaires, HORS décharge au numérateur ET au dénominateur). Fusion
    canonique via adapt_analytics_rows. Muscles dont weekly_effective_sets
    est None (fenêtre 100 % décharge) : exclus de la stat et comptés dans
    excluded_full_deload — pas affichés à 0.
    pct normalisé sur TOUS les muscles de la fenêtre (volume effectif total).
    """
    from analytics_adapter import fetch_raw_analytics_rows, adapt_analytics_rows, is_deload_day
    from metric_semantics import DateWindow
    from muscle_workload_analytics import summarize_muscle_workload

    today = date_cls.fromisoformat(_today_mtl())
    period = DateWindow(today - timedelta(days=period_days - 1), today)

    raw_rows = fetch_raw_analytics_rows(client, period=period)
    adapted = adapt_analytics_rows(raw_rows, period=period)
    summary = summarize_muscle_workload(
        adapted.training_load_exposures,
        adapted.assignments,
        period=period,
        is_deload=lambda d: is_deload_day(d),
    )

    n_sessions = len({e.session_id for e in adapted.training_load_exposures})
    if n_sessions < MIN_SESSIONS_PER_SECTION:
        return [], {
            "n_sessions":            n_sessions,
            "insufficient_data":     True,
            "excluded_full_deload":  0,
        }

    scored: list[tuple[str, float]] = []
    excluded_full_deload = 0
    for m in summary.muscles:
        if m.weekly_effective_sets is None:
            excluded_full_deload += 1
            continue
        if m.weekly_effective_sets <= 0:
            continue
        scored.append((m.muscle, m.weekly_effective_sets))

    scored.sort(key=lambda t: t[1], reverse=True)
    total_all = sum(e for _, e in scored) or 1.0
    top = scored[:6]
    muscles_list = [
        {
            "muscle":         name,
            "sets":           round(effective),       # legacy int — à retirer étape a3
            "effective_sets": round(effective, 1),
            "pct":            round(effective / total_all * 100),
        }
        for name, effective in top
    ]
    return muscles_list, {
        "n_sessions":           n_sessions,
        "insufficient_data":    False,
        "excluded_full_deload": excluded_full_deload,
    }


# ── 7. Movement Patterns ─────────────────────────────────────────────────────

def _compute_movement_patterns(history: dict, ex_info: dict, period_days: int = 90) -> dict:
    """Patterns de mouvement, décharges exclues.

    Fallback explicite : exercice sans `movement_pattern` catalogue → EXCLU
    et compté dans excluded_no_pattern (plus d'exclusion silencieuse qui
    cachait les trous de catalogue). Garde-fou MIN_SESSIONS_PER_SECTION.
    Erreur du prédicat is_deload_day → clé "error", pas insufficient.
    """
    try:
        from analytics_adapter import is_deload_day

        cutoff = (date_cls.fromisoformat(_today_mtl()) - timedelta(days=period_days)).isoformat()
        pattern_sets: dict[str, int] = {}
        session_dates: set[str] = set()
        excluded_names: set[str] = set()
        invalid_dates = 0

        for name, entries in history.items():
            pattern = (ex_info.get(name, {}).get("movement_pattern") or "").strip()
            if not pattern:
                if any((e.get("date") or "") >= cutoff for e in entries):
                    excluded_names.add(name)
                continue
            for e in entries:
                d_str = e.get("date") or ""
                if d_str < cutoff:
                    continue
                try:
                    d = date_cls.fromisoformat(d_str[:10])
                except ValueError:
                    invalid_dates += 1
                    continue
                if is_deload_day(d):
                    continue
                session_dates.add(d_str[:10])
                sets_list = e.get("sets")
                n_sets = len(sets_list) if isinstance(sets_list, list) else 1
                pattern_sets[pattern] = pattern_sets.get(pattern, 0) + n_sets
    except Exception as exc:
        logger.exception("Patterns section error: %s", exc)
        return {"error": str(exc), "n_sessions": 0, "invalid_dates": 0,
                "excluded_no_pattern": 0, "has_data": False,
                "patterns": [], "ratios": {}, "diversity_score": 0}

    n_sessions = len(session_dates)
    if n_sessions < MIN_SESSIONS_PER_SECTION or not pattern_sets:
        return {
            "has_data":            False,
            "patterns":            [],
            "ratios":              {},
            "diversity_score":     0,
            "insufficient_data":   True,
            "n_sessions":          n_sessions,
            "excluded_no_pattern": len(excluded_names),
            "invalid_dates":       invalid_dates,
        }

    total = sum(pattern_sets.values()) or 1
    patterns_ranked = sorted(
        [{"pattern": p, "sets": s, "pct": round(s / total * 100)} for p, s in pattern_sets.items()],
        key=lambda x: x["sets"], reverse=True,
    )

    hinge  = pattern_sets.get("hinge", 0)
    squat  = pattern_sets.get("squat", 0)
    push_h = pattern_sets.get("push_horizontal", 0)
    push_v = pattern_sets.get("push_vertical", 0)

    ratios: dict = {}
    if squat > 0:
        ratios["hinge_squat"] = round(hinge / squat, 2)
    if push_v > 0:
        ratios["push_horiz_vert"] = round(push_h / push_v, 2)

    diversity = round(len(pattern_sets) / 17 * 100)  # % des 17 patterns canoniques présents

    return {
        "has_data":            True,
        "patterns":            patterns_ranked,
        "ratios":              ratios,
        "diversity_score":     diversity,
        "total_sets":          total,
        "insufficient_data":   False,
        "n_sessions":          n_sessions,
        "excluded_no_pattern": len(excluded_names),
        "invalid_dates":       invalid_dates,
    }


# ── 8. Intensity Timeline ─────────────────────────────────────────────────────

def _compute_intensity_timeline(history: dict, months: int = 6) -> list[dict]:
    """Monthly rep-zone breakdown — last N months."""
    today = date_cls.fromisoformat(_today_mtl())
    month_buckets: dict[str, dict[str, int]] = {}
    for i in range(months - 1, -1, -1):
        m = today.month - i
        y = today.year
        while m <= 0:
            m += 12
            y -= 1
        month_buckets[f"{y}-{m:02d}"] = {"strength": 0, "power": 0, "hypertrophy": 0, "endurance": 0}

    for name, entries in history.items():
        for e in entries:
            month_key = str(e.get("date") or "")[:7]
            if month_key not in month_buckets:
                continue
            default_reps = int(str(e.get("reps") or "8").split(",")[0].strip() or 8)
            sets_list = e.get("sets")
            iter_reps: list[int] = []
            if isinstance(sets_list, list):
                for s in sets_list:
                    raw = s.get("reps") if isinstance(s, dict) else default_reps
                    iter_reps.append(default_reps if raw is None else int(raw))
            else:
                iter_reps = [default_reps]

            bkt = month_buckets[month_key]
            for r in iter_reps:
                if r <= 4:    bkt["strength"]    += 1
                elif r <= 7:  bkt["power"]       += 1
                elif r <= 12: bkt["hypertrophy"] += 1
                else:         bkt["endurance"]   += 1

    result = []
    for month_key, zones in sorted(month_buckets.items()):
        total = sum(zones.values()) or 1
        result.append({
            "month":           month_key,
            "strength_pct":    round((zones["strength"] + zones["power"]) / total * 100),
            "hypertrophy_pct": round(zones["hypertrophy"] / total * 100),
            "endurance_pct":   round(zones["endurance"] / total * 100),
            "total_sets":      sum(zones.values()),
        })
    return result


# ── Archetype ─────────────────────────────────────────────────────────────────

def _archetype(ppl: dict, intensity: dict, consistency: dict) -> dict:
    """Archétype calculé uniquement si les 3 piliers (PPL, Intensité,
    Constance) sont tous `insufficient_data=False` et sans "error".
    Sinon : sentinel "insufficient" + available=False. Zéro fallback 50
    (le fantôme "builder" généré par des scores manquants est supprimé)."""
    _INSUFFICIENT = {
        "key":       "insufficient",
        "label":     "Données insuffisantes",
        "tagline":   "Logge plus pour voir ton DNA",
        "available": False,
    }

    for pilier in (ppl, intensity, consistency):
        if pilier.get("insufficient_data") or pilier.get("error"):
            return _INSUFFICIENT

    i   = intensity.get("score")
    c   = consistency.get("score")
    b   = ppl.get("balance_score")
    spw = consistency.get("sessions_per_week")
    legs = ppl.get("legs_pct")
    if any(v is None for v in (i, c, b, spw, legs)):
        return _INSUFFICIENT

    if i >= 70 and b >= 60 and c >= 65:
        base = {"key": "powerlifter", "label": "The Powerlifter", "tagline": "Compound. Heavy. Consistent."}
    elif i >= 40 and legs >= 25 and c >= 60:
        base = {"key": "bodybuilder",  "label": "The Bodybuilder",  "tagline": "Volume. Symmetry. Discipline."}
    elif c >= 85 and spw >= 4.5:
        base = {"key": "grinder",      "label": "The Grinder",      "tagline": "Never misses. Never quits."}
    elif spw <= 2.5 and i >= 60:
        base = {"key": "warrior",      "label": "Weekend Warrior",  "tagline": "Rare but fierce."}
    elif b >= 75 and 45 <= i <= 65 and c >= 65:
        base = {"key": "athlete",      "label": "The Athlete",      "tagline": "Balanced. Efficient. Sharp."}
    else:
        base = {"key": "builder",      "label": "The Builder",      "tagline": "Building, day by day."}
    base["available"] = True
    return base


def _dna_seed(ppl: dict, intensity: dict, consistency: dict, recovery: dict) -> str:
    payload = json.dumps({
        "push": ppl.get("push_pct", 0),  "pull": ppl.get("pull_pct", 0),
        "legs": ppl.get("legs_pct", 0),  "i":    intensity.get("score", 0),
        "cv":   consistency.get("cv", 0), "rest": recovery.get("avg_rest_days", 0),
    }, sort_keys=True)
    return hashlib.md5(payload.encode()).hexdigest()[:8]


# ── Public ────────────────────────────────────────────────────────────────────

def compute(period_days: int = 90) -> dict:
    now_ts    = datetime.now(timezone.utc).timestamp()
    cache_key = f"dna_{period_days}"
    cached    = _CACHE.get(cache_key)
    if cached and (now_ts - cached["ts"]) < _CACHE_TTL:
        return cached["data"]

    try:
        history  = db.get_all_exercise_history(full_history=True)
        ex_info  = db.get_exercises_info_bulk(list(history.keys()))

        ppl                = _compute_ppl(history, ex_info, period_days)
        intensity          = _compute_intensity(history, ex_info, period_days)
        consistency        = _compute_consistency(period_days)
        recovery           = _compute_recovery(intensity.get("score", 50), period_days)
        session_spacing    = _compute_session_spacing(period_days)
        lifts              = _compute_signature_lifts(db._client, period_days)
        muscle_dominants, muscle_dominants_meta = _compute_muscle_dominants(db._client, period_days)
        movement_patterns  = _compute_movement_patterns(history, ex_info, period_days)
        intensity_timeline = _compute_intensity_timeline(history)
        arch               = _archetype(ppl, intensity, consistency)
        seed               = _dna_seed(ppl, intensity, consistency, recovery)

        result = {
            "period":                 {"from": (date_cls.fromisoformat(_today_mtl()) - timedelta(days=period_days)).isoformat(),
                                       "to":   date_cls.fromisoformat(_today_mtl()).isoformat()},
            "archetype":              arch,
            "ppl":                    ppl,
            "intensity":              intensity,
            "consistency":            consistency,
            "recovery":               recovery,            # legacy — à retirer étape e3
            "session_spacing":        session_spacing,     # nouveau lot e
            "signature_lifts":        lifts,
            "muscle_dominants":       muscle_dominants,
            "muscle_dominants_meta":  muscle_dominants_meta,
            "movement_patterns":      movement_patterns,
            "intensity_timeline":     intensity_timeline,
            "dna_seed":               seed,
            "computed_at":            datetime.now(timezone.utc).isoformat(),
        }
        _CACHE[cache_key] = {"data": result, "ts": now_ts}
        return result

    except Exception as e:
        logger.exception("workout_dna error: %s", e)
        raise
