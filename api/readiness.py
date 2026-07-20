"""
readiness.py — Pre-session Readiness Score (0-100).

9 modules with adaptive weights (Halson 2014, NSCA/ACSM aligned):
  HRV normalisé        20%  (baseline personnelle 7j — Plews 2013, Buchheit 2014)
  FC repos (RHR)       15%  (baseline personnelle 7j — Halson 2014)
  Charge ACWR          15%  (acute:chronic workload ratio — Gabbett 2016)
  Qualité du sommeil   15%  (score 0-10 — Fullagar et al. 2015)
  Durée du sommeil     10%  (objectif 8h — Fullagar et al. 2015)
  Fatigue subjective   10%  (Hooper Index — fatigue perçue — Hooper & Mackinnon 1995)
  Récupération musc.    8%  (courbe exponentielle — MacDougall 1995)
  Nutrition             4%  (adhérence cals/protéines — ACSM 2016)
  Pattern repos         3%  (supercompensation — Zatsiorsky & Kraemer 2006)

Modificateurs multiplicatifs post-scoring :
  Delta FC cardiaque   ±5%  (hr_morning / hr_post_workout)
  Active energy        −5%  (>800 kcal jour de repos)

Verdict : go | moderate | rest
  — Relatif à baseline 28j si ≥14 jours de données (Plews et al. 2013)
  — Absolu (75/50) en cold start
"""
from __future__ import annotations

import math, time as _time, logging
from datetime import date as date_cls, datetime, timedelta, timezone

import db
from utils import _today_mtl, get_nutrition_time_context

logger = logging.getLogger("trainingos.readiness")

# ── Constants ─────────────────────────────────────────────────────────────────

_RECOVERY_H = {
    "compound_heavy":       72,
    "compound_hypertrophy": 48,
    "isolation":            24,
}
_DEFAULT_RECOVERY_H = 48

_CAT_LABEL = {
    "legs":  "Jambes",
    "push":  "Poitrine/Épaules",
    "pull":  "Dos/Biceps",
    "core":  "Core",
}

_WEIGHTS = {
    "hrv":            0.20,  # Plews 2013, Buchheit 2014
    "rhr":            0.15,  # Halson 2014 — FC repos vs baseline personnelle
    "acwr":           0.15,  # Gabbett 2016
    "sleep_quality":  0.15,  # Fullagar et al. 2015
    "sleep_duration": 0.10,  # Fullagar et al. 2015
    "subjective":     0.10,  # Hooper & Mackinnon 1995
    "muscle_rec":     0.08,  # MacDougall 1995
    "nutrition":      0.04,  # ACSM 2016
    "pattern":        0.03,  # Zatsiorsky & Kraemer 2006
}

# Un module sous ce seuil = critique. Aligné messaging + veto : un seuil, une signification.
_MODULE_CRITICAL_THRESHOLD = 40

# Plancher absolu du verdict "go" : le mode relatif ne peut jamais valider un score
# sous ce plancher (Plews suppose une baseline saine — on ajoute le garde-fou qu'elle présuppose).
_FLOOR_ABSOLUTE = 60

# Muscle recovery — courbe exponentielle (MacDougall 1995, Zatsiorsky & Kraemer 2006)
_RECOVERY_K              = 3.0
_VOL_THRESHOLD_HIGH      = 6
_VOL_THRESHOLD_VERY_HIGH = 9
_VOL_MULT_HIGH           = 1.25
_VOL_MULT_VERY_HIGH      = 1.50

# Repeated Bout Effect (Zatsiorsky & Kraemer 2006)
_EXPERIENCE_MULT = {
    "beginner":     1.15,
    "intermediate": 1.00,
    "advanced":     0.85,
}


# ── Module 1: HRV normalisé ───────────────────────────────────────────────────

def _score_hrv(rec_logs: list | None = None) -> tuple[float | None, dict]:
    """HRV normalisé vs baseline personnelle 7j (Plews 2013).

    Délègue à hrv_engine.compute_hrv_analysis() pour cohérence.
    Score 100 = HRV du jour ≥ baseline; dégradation proportionnelle en dessous.
    Retourne None si baseline indisponible (< 3 jours de données).
    """
    from hrv_engine import compute_hrv_analysis
    try:
        from user_profile import load_user_profile
        sensitivity = str(load_user_profile().get("hrv_sensitivity") or "standard")
        rows     = rec_logs if rec_logs is not None else (db.get_recovery_logs() or [])
        analysis = compute_hrv_analysis(rows, _today_mtl(), sensitivity=sensitivity)
        if not analysis.get("baseline_available"):
            return None, {"data_insufficient": True, "reason": "baseline_unavailable"}
        score = analysis.get("hrv_score")
        if score is None:
            return None, {"data_insufficient": True}
        return round(float(score), 1), {
            "hrv_score": round(float(score), 1),
            "zone":      analysis.get("hrv_zone"),
            "today_hrv": analysis.get("today_rmssd"),
            "baseline":  analysis.get("hrv_7d_avg"),
        }
    except Exception as e:
        logger.exception("_score_hrv failed: %s", e)
        return None, {"data_insufficient": True}


# ── Module 2: Charge ACWR ─────────────────────────────────────────────────────

def _score_acwr() -> tuple[float | None, dict]:
    """Charge accumulée ACWR + séances intenses 48h (Gabbett 2016).

    Zone optimale 0.8–1.3 : sweet spot injury prevention / adaptation.
    Séances RPE ≥7 dans les 48h → pénalité supplémentaire si ≥2.
    """
    details: dict = {}
    try:
        from acwr import calc_acwr
        acwr_data = calc_acwr()
        acwr = float(acwr_data.get("ratio") or 0)
        details["acwr"]    = round(acwr, 2)
        details["acute"]   = round(float(acwr_data.get("acute_load")   or 0), 1)
        details["chronic"] = round(float(acwr_data.get("chronic_load") or 0), 1)
    except Exception:
        acwr = None
        details["acwr"] = None

    today    = date_cls.fromisoformat(_today_mtl())
    recent   = db.get_workout_sessions(limit=10) or []
    hard_48h = 0
    for s in recent:
        try:
            delta = (today - date_cls.fromisoformat(str(s.get("date") or "")[:10])).days
        except ValueError:
            continue
        if delta < 2 and s.get("rpe") is not None and float(s.get("rpe") or 0) >= 7:
            hard_48h += 1
    details["hard_sessions_48h"] = hard_48h

    if acwr is None:
        return None, {**details, "data_insufficient": True}

    if acwr < 0.8:
        score = 60.0
        details["zone"] = "Sous-charge"
    elif acwr <= 1.3:
        t = (acwr - 0.8) / 0.5
        score = 100.0 - t * 15.0
        details["zone"] = "Charge optimale"
    elif acwr <= 1.5:
        t = (acwr - 1.3) / 0.2
        score = 75.0 - t * 20.0
        details["zone"] = "Léger surmenage"
    else:
        score = max(10.0, 40.0 - (acwr - 1.5) * 60.0)
        details["zone"] = "Surcharge"

    if hard_48h >= 2:
        score = max(5.0, score - 15.0)

    return round(max(0.0, min(100.0, score)), 1), details


# ── Module 3: FC repos (RHR) ─────────────────────────────────────────────────

def _score_rhr(rec_logs: list | None = None) -> tuple[float | None, dict]:
    """FC repos vs baseline personnelle 7j (Halson 2014).

    Score 100 = RHR ≤ baseline. Dégradation proportionnelle si RHR élevée :
    +5% vs baseline → ~90, +10% → ~80, +20% → ~60.
    Retourne None si baseline insuffisante (<3 jours).
    """
    try:
        today_s  = _today_mtl()
        rec_logs = rec_logs if rec_logs is not None else (db.get_recovery_logs() or [])

        today_rec = next((e for e in rec_logs if str(e.get("date", ""))[:10] == today_s), None)
        if not today_rec or today_rec.get("rhr") is None:
            return None, {"data_insufficient": True}

        today_rhr = float(today_rec["rhr"])
        today_dt  = date_cls.fromisoformat(today_s)
        window_7d = [(today_dt - timedelta(days=i)).isoformat() for i in range(1, 8)]

        vals_7d = [
            float(e["rhr"])
            for e in rec_logs
            if str(e.get("date", ""))[:10] in window_7d and e.get("rhr") is not None
        ]
        if len(vals_7d) < 3:
            return None, {"data_insufficient": True, "reason": "baseline_insuffisante"}

        baseline  = sum(vals_7d) / len(vals_7d)
        delta_pct = (today_rhr - baseline) / baseline
        score     = round(max(0.0, min(100.0, 100.0 - delta_pct * 200.0)), 1)

        return score, {
            "today_rhr":   round(today_rhr, 1),
            "baseline_7d": round(baseline, 1),
            "delta_bpm":   round(today_rhr - baseline, 1),
        }
    except Exception as e:
        logger.exception("_score_rhr failed: %s", e)
        return None, {"data_insufficient": True}


# ── Module 5: Qualité du sommeil ──────────────────────────────────────────────

def _score_sleep_quality(rec_logs: list | None = None) -> tuple[float | None, dict]:
    """Qualité du sommeil 0-10 → 0-100 (Fullagar et al. 2015).

    Source : recovery_logs.sleep_quality (synchronisé depuis sleep_records × 2).
    """
    try:
        today_s   = _today_mtl()
        rec_logs  = rec_logs if rec_logs is not None else (db.get_recovery_logs() or [])
        today_rec = next((e for e in rec_logs if str(e.get("date", ""))[:10] == today_s), None)
        if not today_rec or today_rec.get("sleep_quality") is None:
            return None, {"data_insufficient": True}
        sq    = float(today_rec["sleep_quality"])
        # recovery_logs stores sleep_quality on 1-10 scale (min 1 from sleep.py)
        score = min(100.0, (sq - 1) / 9.0 * 100.0)
        return round(score, 1), {"sleep_quality": sq}
    except Exception as e:
        logger.exception("_score_sleep_quality failed: %s", e)
        return None, {"data_insufficient": True}


# ── Module 6: Durée du sommeil ────────────────────────────────────────────────

def _score_sleep_duration(rec_logs: list | None = None) -> tuple[float | None, dict]:
    """Durée du sommeil vs objectif 8h (Fullagar et al. 2015).

    Score 100 à 8h+; dégradation linéaire en dessous.
    Dormir plus de 8h ne pénalise pas (récupération prolongée = bénéfique).
    """
    try:
        today_s   = _today_mtl()
        rec_logs  = rec_logs if rec_logs is not None else (db.get_recovery_logs() or [])
        today_rec = next((e for e in rec_logs if str(e.get("date", ""))[:10] == today_s), None)
        if not today_rec or today_rec.get("sleep_hours") is None:
            return None, {"data_insufficient": True}
        hours = float(today_rec["sleep_hours"])
        from user_profile import load_user_profile
        sleep_goal = float(load_user_profile().get("sleep_goal_hours") or 8.0)
        score = min(100.0, (hours / sleep_goal) * 100.0)
        return round(score, 1), {"sleep_hours": hours, "sleep_goal": sleep_goal}
    except Exception as e:
        logger.exception("_score_sleep_duration failed: %s", e)
        return None, {"data_insufficient": True}


# ── Module 7: Fatigue subjective ──────────────────────────────────────────────

def _score_subjective(rec_logs: list | None = None) -> tuple[float | None, dict]:
    """Fatigue perçue — Hooper Index (Hooper & Mackinnon 1995).

    Signal primaire : fatigue_perceived (0-10, haut = très fatigué).
    Fallback : soreness (DOMS direct — signal physique proche).
    Retourne None si aucune donnée subjective disponible.
    """
    try:
        today_s   = _today_mtl()
        rec_logs  = rec_logs if rec_logs is not None else (db.get_recovery_logs() or [])
        today_rec = next((e for e in rec_logs if str(e.get("date", ""))[:10] == today_s), None)
        if not today_rec:
            return None, {"data_insufficient": True}
        fp = today_rec.get("fatigue_perceived")
        if fp is not None:
            score = (10.0 - float(fp)) * 10.0
            return round(min(100.0, max(0.0, score)), 1), {"signal": "fatigue_perceived", "value": float(fp)}
        soreness = today_rec.get("soreness")
        if soreness is not None and float(soreness) > 0:
            # soreness CHECK >= 1, so use /9 normalization for true 0-100 range
            score = (10.0 - float(soreness)) / 9.0 * 100.0
            return round(min(100.0, max(0.0, score)), 1), {"signal": "soreness_fallback", "value": float(soreness)}
        return None, {"data_insufficient": True}
    except Exception as e:
        logger.exception("_score_subjective failed: %s", e)
        return None, {"data_insufficient": True}


# ── Module 8: Nutrition ───────────────────────────────────────────────────────

def _ratio_score(r: float) -> float:
    if 0.85 <= r <= 1.10:  return 90.0
    if 0.75 <= r < 0.85:   return 65.0
    if 0.65 <= r < 0.75:   return 40.0
    if r < 0.65:            return 15.0
    return max(60.0, 90.0 - (r - 1.10) * 80.0)


def _score_nutrition() -> tuple[float, dict]:
    details: dict = {}
    try:
        settings    = db.get_nutrition_settings() or {}
        target_cal  = float(settings.get("calorie_limit")  or settings.get("limite_calories")  or 2400)
        target_prot = float(settings.get("protein_target") or settings.get("objectif_proteines") or 180)
        target_carb = float(settings.get("glucides_target") or 0)
    except Exception as e:
        logger.exception("_score_nutrition failed: %s", e)
        return 65.0, {"error": True}

    entries = db.get_nutrition_entries_recent(2) or []
    today   = date_cls.fromisoformat(_today_mtl())
    today_s = today.isoformat()
    yest_s  = (today - timedelta(days=1)).isoformat()

    ctx          = get_nutrition_time_context(today_s)
    is_too_early = ctx["is_too_early"]

    by_day: dict[str, dict] = {}
    for e in entries:
        d = str(e.get("date") or "")[:10]
        if d not in by_day:
            by_day[d] = {"cal": 0.0, "prot": 0.0, "carb": 0.0}
        by_day[d]["cal"]  += float(e.get("calories",  0) or 0)
        by_day[d]["prot"] += float(e.get("proteines", 0) or 0)
        by_day[d]["carb"] += float(e.get("glucides",  0) or 0)

    day_weights = [(yest_s, 1.0)] if is_too_early else [(today_s, 0.65), (yest_s, 0.35)]

    use_carbs = target_carb > 0

    pairs = []
    for d, w in day_weights:
        if d not in by_day:
            continue
        cal_r  = by_day[d]["cal"]  / target_cal  if target_cal  > 0 else 0.0
        prot_r = by_day[d]["prot"] / target_prot if target_prot > 0 else 0.0
        if use_carbs:
            carb_r    = by_day[d]["carb"] / target_carb
            day_score = (_ratio_score(cal_r) * 0.40
                         + _ratio_score(prot_r) * 0.40
                         + _ratio_score(carb_r) * 0.20)
        else:
            day_score = _ratio_score(cal_r) * 0.5 + _ratio_score(prot_r) * 0.5
        pairs.append((day_score, w))

    if not pairs:
        return 50.0, {"no_data": True}

    score = sum(s * w for s, w in pairs) / sum(w for _, w in pairs)

    if today_s in by_day and not is_too_early:
        expected_cal = target_cal * (ctx["progress"] if not ctx["is_end_of_day"] else 1.0)
        deficit = expected_cal - by_day[today_s]["cal"]
        details["cal_deficit"] = int(target_cal - by_day[today_s]["cal"])
        if deficit > 500:
            score = max(0.0, score - 15.0)
        details["cal_pct"]  = int(by_day[today_s]["cal"]  / target_cal  * 100) if target_cal  > 0 else None
        details["prot_pct"] = int(by_day[today_s]["prot"] / target_prot * 100) if target_prot > 0 else None
        if use_carbs:
            details["carb_pct"] = int(by_day[today_s]["carb"] / target_carb * 100)

    return round(max(0.0, min(100.0, score)), 1), details


# ── Module 9: Pattern (repos uniquement) ──────────────────────────────────────

def _score_pattern() -> tuple[float, dict]:
    """Score basé sur les jours de repos depuis la dernière séance.

    Resynthèse glycogénique et supercompensation (Zatsiorsky & Kraemer 2006).
    Pattern par jour de semaine retiré — non validé scientifiquement.
    """
    details: dict = {}
    raw   = db.get_workout_sessions(limit=20) or []
    today = date_cls.fromisoformat(_today_mtl())

    days_since: dict[str, int] = {}
    for s in raw:
        d = str(s.get("date") or "")[:10]
        if not d:
            continue
        try:
            dd = date_cls.fromisoformat(d)
        except ValueError:
            continue
        name  = s.get("session_name") or s.get("session_type") or "any"
        delta = (today - dd).days
        if name not in days_since or delta < days_since[name]:
            days_since[name] = delta

    score = 70.0

    if days_since:
        min_rest = min(days_since.values())
        details["days_since_last"] = min_rest
        if   min_rest == 0:          score -= 15.0
        elif min_rest == 1:          score += 5.0
        elif min_rest == 2:          score += 10.0
        elif 3 <= min_rest <= 5:     pass
        elif min_rest >= 6:          score -= 5.0
    else:
        details["days_since_last"] = None

    return round(max(0.0, min(100.0, score)), 1), details


# ── Module 10: Muscle Group Recovery ─────────────────────────────────────────

def _get_experience_mult() -> float:
    try:
        from user_profile import load_user_profile
        level = (load_user_profile().get("training_experience") or "").lower()
        return _EXPERIENCE_MULT.get(level, 1.0)
    except Exception as e:
        logger.exception("_get_experience_mult failed: %s", e)
        return 1.0


def _score_muscle_recovery(rec_logs: list | None = None) -> tuple[float, dict, dict]:
    """Returns (score, module_details, muscle_breakdown {cat: {...}}).

    Courbe exponentielle : frac = 1 - e^(-k × t/T)
    Volume multiplicateur : >6 sets → +25% threshold, >9 sets → +50% (MacDougall 1995).
    Soreness modifier — DOMS direct (Hooper & Mackinnon 1995).
    """
    all_hist  = db.get_all_exercise_history(cutoff_days=7) or {}
    ex_info   = db.get_exercises_info_bulk(list(all_hist.keys())) if all_hist else {}
    from utils import _now_mtl
    today_dt  = _now_mtl()

    cat_last_h: dict[str, float] = {}
    cat_profile: dict[str, str]  = {}
    cat_date: dict[str, str]     = {}

    for ex_name, entries in all_hist.items():
        if not entries:
            continue
        d_str = entries[0].get("date") or ""
        if not d_str:
            continue
        try:
            latest_dt = datetime.fromisoformat(d_str + "T12:00:00+00:00")
            hours_ago = (today_dt - latest_dt).total_seconds() / 3600
        except ValueError:
            continue

        if hours_ago > 168:
            continue

        info = ex_info.get(ex_name) or {}
        cat  = (info.get("category") or "other").lower()
        lp   = info.get("load_profile") or "compound_hypertrophy"

        if cat not in cat_last_h or hours_ago < cat_last_h[cat]:
            cat_last_h[cat]  = hours_ago
            cat_profile[cat] = lp
            cat_date[cat]    = d_str[:10]

    relevant = [c for c in cat_last_h if c in _CAT_LABEL]
    if not relevant:
        return 85.0, {"no_recent_training": True}, {}

    # Pre-index sets by (cat, date) — single pass replaces O(n×cats) inner loops
    _sets_by_date_cat: dict[tuple[str, str], int] = {}
    for _ex, _entries in all_hist.items():
        if not _entries:
            continue
        _d = str(_entries[0].get("date") or "")[:10]
        if not _d:
            continue
        _info = ex_info.get(_ex) or {}
        _cat  = (_info.get("category") or "other").lower()
        _sv   = _entries[0].get("sets") or _entries[0].get("nb_sets") or 0
        if isinstance(_sv, list):
            _sv = len(_sv)
        _sets_by_date_cat[(_cat, _d)] = _sets_by_date_cat.get((_cat, _d), 0) + int(_sv)

    exp_mult = _get_experience_mult()

    breakdown: dict[str, dict] = {}
    fractions: list[float] = []

    for cat in relevant:
        h_ago     = cat_last_h[cat]
        lp        = cat_profile.get(cat, "compound_hypertrophy")
        threshold = float(_RECOVERY_H.get(lp, _DEFAULT_RECOVERY_H))

        vol_sets = _sets_by_date_cat.get((cat, cat_date.get(cat, "")), 0)
        if vol_sets > _VOL_THRESHOLD_VERY_HIGH:
            threshold *= _VOL_MULT_VERY_HIGH
        elif vol_sets > _VOL_THRESHOLD_HIGH:
            threshold *= _VOL_MULT_HIGH

        threshold *= exp_mult

        frac     = 1.0 - math.exp(-_RECOVERY_K * h_ago / threshold)
        frac     = min(1.0, frac)
        h_remain = max(0.0, threshold - h_ago)

        status = "ready" if frac >= 1.0 else ("almost" if frac >= 0.75 else "partial")
        breakdown[cat] = {
            "pct":             int(frac * 100),
            "hours_remaining": int(h_remain),
            "hours_since":     int(h_ago),
            "status":          status,
            "label":           _CAT_LABEL.get(cat, cat.title()),
        }
        fractions.append(frac)

    score = (sum(fractions) / len(fractions)) * 100

    soreness_modifier: int | None = None
    try:
        today_s   = _today_mtl()
        _rl       = rec_logs if rec_logs is not None else (db.get_recovery_logs() or [])
        today_rec = next((e for e in _rl if str(e.get("date", ""))[:10] == today_s), None)
        if today_rec and today_rec.get("soreness") is not None:
            s = float(today_rec["soreness"])
            if s >= 7:
                score             *= 0.80
                soreness_modifier  = -20
            elif s <= 3:
                score              = min(100.0, score * 1.10)
                soreness_modifier  = +10
    except Exception:
        pass

    worst = min(breakdown.items(), key=lambda x: x[1]["pct"])
    details = {
        "worst_cat":         worst[0],
        "worst_pct":         worst[1]["pct"],
        "worst_remaining":   worst[1]["hours_remaining"],
        "worst_label":       worst[1]["label"],
        "soreness_modifier": soreness_modifier,
    }
    return round(max(0.0, min(100.0, score)), 1), details, breakdown


# ── Baseline personnelle + Verdict ────────────────────────────────────────────

def _get_personal_baseline() -> dict:
    """Calcule la baseline personnelle sur 28 jours glissants.

    Cold start (<14 jours de données) : retourne mean=None → seuils absolus.
    """
    today  = date_cls.fromisoformat(_today_mtl())
    window = {(today - timedelta(days=i)).isoformat() for i in range(1, 29)}

    try:
        history = db.get_readiness_history(days=28) or []
        scores  = [
            float(r["score"]) for r in history
            if r.get("score") is not None and str(r.get("date", ""))[:10] in window
        ]
    except Exception as e:
        logger.exception("_get_baseline_stats failed: %s", e)
        return {"mean": None, "sd": None, "n": 0}

    if len(scores) < 14:
        return {"mean": None, "sd": None, "n": len(scores)}

    mean = sum(scores) / len(scores)
    sd   = (sum((x - mean) ** 2 for x in scores) / len(scores)) ** 0.5
    return {"mean": round(mean, 1), "sd": round(sd, 1), "n": len(scores)}


def _verdict(
    score: float,
    baseline: dict | None = None,
    hrv_score: float | None = None,
    rhr_score: float | None = None,
) -> tuple[str, bool, str | None]:
    """Retourne (verdict, is_relative, downgrade_reason).

    Verdict brut :
      Relatif (Plews et al. 2013 — zone method) si baseline ≥14 jours :
        go       : score ≥ mean - 0.5×SD
        moderate : mean - 1.5×SD ≤ score < mean - 0.5×SD
        rest     : score < mean - 1.5×SD
      Absolu en cold start (<14 jours de données) :
        go ≥75 · moderate 50-74 · rest <50

    Garde-fous — jamais "go" si un seuil absolu est franchi. Le relatif module
    (calibre sur toi), l'absolu protège (Plews suppose une baseline saine — on
    ajoute le garde-fou qu'elle présuppose). Défaut structurel démontré : le
    composite pondéré ne peut pas tomber sous rest sur un seul module effondré
    (moyenne pondérée amortit) → veto par module nécessaire.
      - score < _FLOOR_ABSOLUTE                → moderate
      - hrv_score < _MODULE_CRITICAL_THRESHOLD → moderate (système nerveux)
      - rhr_score < _MODULE_CRITICAL_THRESHOLD → moderate (cardio-vasculaire)

    downgrade_reason exposé au payload pour transparence + calibration seuils.
    None quand aucun garde-fou ne s'applique.
    """
    if baseline and baseline.get("mean") is not None:
        mean = baseline["mean"]
        sd   = baseline["sd"] or 5.0
        if score >= mean - 0.5 * sd:
            raw = "go"
        elif score >= mean - 1.5 * sd:
            raw = "moderate"
        else:
            raw = "rest"
        is_relative = True
    else:
        if   score >= 75: raw = "go"
        elif score >= 50: raw = "moderate"
        else:             raw = "rest"
        is_relative = False

    if raw != "go":
        return raw, is_relative, None

    if score < _FLOOR_ABSOLUTE:
        return "moderate", is_relative, f"score {score:.0f} < plancher absolu {_FLOOR_ABSOLUTE}"
    if hrv_score is not None and hrv_score < _MODULE_CRITICAL_THRESHOLD:
        return "moderate", is_relative, f"HRV module {hrv_score:.0f} < veto {_MODULE_CRITICAL_THRESHOLD}"
    if rhr_score is not None and rhr_score < _MODULE_CRITICAL_THRESHOLD:
        return "moderate", is_relative, f"RHR module {rhr_score:.0f} < veto {_MODULE_CRITICAL_THRESHOLD}"

    return raw, is_relative, None


# ── Messaging ─────────────────────────────────────────────────────────────────

def _build_messaging(
    verdict: str,
    modules: dict,
    details: dict,
    breakdown: dict,
) -> tuple[str, str | None, float]:
    """Returns (why, adjustment, progression_modifier)."""

    scored = {k: modules[k]["score"] for k in modules if modules[k].get("score") is not None}
    if not scored:
        return "Données insuffisantes — écoute ton ressenti aujourd'hui.", None, 1.0

    worst_k = min(scored, key=scored.__getitem__)

    if verdict == "go":
        worst_score = scored[worst_k]
        if worst_score < _MODULE_CRITICAL_THRESHOLD:
            label = modules[worst_k]["label"]
            return (
                f"Verdict go mais ton {label} est bas ({worst_score}/100) — surveille tes sensations.",
                None,
                1.0,
            )
        return "Toutes tes métriques sont au vert — c'est le bon moment pour pousser.", None, 1.0

    prog_mod = 0.65 if verdict == "rest" else 0.90

    if worst_k == "muscle_rec":
        m_det = details.get("muscle_rec", {})
        lbl   = m_det.get("worst_label", "tes muscles")
        hrs   = m_det.get("worst_remaining", 0)
        pct   = m_det.get("worst_pct", 0)
        why   = f"Tes {lbl} ne sont récupérés qu'à {pct}% — il manque encore {hrs}h idéalement."
        if verdict == "rest":
            adj = "Repos actif recommandé — mobilité ou marche. Reviens demain pour ta séance prévue."
        else:
            ready = [v["label"] for c, v in breakdown.items() if v["pct"] >= 90 and c != m_det.get("worst_cat")]
            if ready:
                adj = f"Focus {' + '.join(ready[:2])} aujourd'hui — {lbl} pas encore prêts."
            else:
                adj = "Drop tes working sets de 10% et évite les exercices ciblant tes muscles fatigués."
        return why, adj, prog_mod

    if worst_k == "acwr":
        a_det = details.get("acwr", {})
        acwr  = a_det.get("acwr") or "?"
        why   = f"Charge accumulée élevée (ACWR {acwr}) — tu as poussé fort ces derniers jours."
        if verdict == "rest":
            adj = "Repos ou cardio léger uniquement. Si tu t'entraînes : 60-70% des charges habituelles."
        else:
            adj = "Drop tes working sets de 10% — garde le même RPE cible, réduis le volume total."
        return why, adj, prog_mod

    if worst_k == "hrv":
        h_det = details.get("hrv", {})
        zone  = h_det.get("zone", "")
        why   = f"Ta HRV est en dessous de ta baseline personnelle ({zone}) — ton système nerveux récupère encore."
        if verdict == "rest":
            adj = "Système nerveux sous pression — pas d'effort intense. Marche, yoga, ou repos complet."
        else:
            adj = "Entraîne-toi avec intention mais évite les efforts maximaux — laisse ton SNA se régénérer."
        return why, adj, prog_mod

    if worst_k == "rhr":
        r_det    = details.get("rhr", {})
        delta    = r_det.get("delta_bpm")
        base     = r_det.get("baseline_7d")
        today_rh = r_det.get("today_rhr")
        if delta is not None and delta > 0:
            why = f"FC repos élevée ({today_rh} bpm, +{delta:.0f} vs ta baseline {base:.0f}) — récupération cardiovasculaire incomplète."
        else:
            why = "FC repos au-dessus de ta baseline — le système cardiovasculaire récupère encore."
        if verdict == "rest":
            adj = "Repos ou effort très léger uniquement — ton cœur signale une fatigue systémique."
        else:
            adj = "Réduis l'intensité de 10-15% et évite les efforts aérobiques intenses."
        return why, adj, prog_mod

    if worst_k in ("sleep_quality", "sleep_duration"):
        sd_det = details.get("sleep_duration", {})
        sq_det = details.get("sleep_quality", {})
        hours  = sd_det.get("sleep_hours")
        sq     = sq_det.get("sleep_quality")
        if hours is not None and hours < 6:
            why = f"Seulement {hours:.1f}h de sommeil cette nuit — récupération incomplète."
        elif sq is not None and sq < 5:
            why = f"Qualité de sommeil faible ({sq:.0f}/10) — ton corps n'a pas bien récupéré."
        else:
            why = "Ton sommeil de cette nuit limite ta récupération."
        if verdict == "rest":
            adj = "Priorité à la récupération — couche-toi plus tôt ce soir. Pas d'entraînement intense."
        else:
            adj = "Réduis l'intensité de 10-15% et favorise les temps de repos entre les séries."
        return why, adj, prog_mod

    if worst_k == "subjective":
        s_det = details.get("subjective", {})
        value = s_det.get("value")
        if value is not None:
            why = f"Fatigue perçue élevée ({value:.0f}/10) — ton ressenti indique que le corps a besoin de récupérer."
        else:
            why = "Fatigue subjective élevée — écoute ton ressenti."
        if verdict == "rest":
            adj = "Repos actif ou récupération totale. Ton corps te dit qu'il a besoin de souffler."
        else:
            adj = "Entraîne-toi mais ne cherche pas à battre des PRs — qualité d'exécution plutôt qu'intensité."
        return why, adj, prog_mod

    if worst_k == "nutrition":
        n_det    = details.get("nutrition", {})
        prot_pct = n_det.get("prot_pct")
        deficit  = n_det.get("cal_deficit")
        if prot_pct is not None and prot_pct < 80:
            why = f"Protéines à {prot_pct}% de ton objectif hier — réserves énergétiques sous-optimales."
        elif deficit and deficit > 500:
            why = f"Déficit de {deficit} kcal aujourd'hui — pas assez de carburant pour performer."
        else:
            why = "Nutrition des 24-48h en dessous de tes objectifs — énergie disponible limitée."
        if verdict == "rest":
            adj = "Mange un repas complet, récupère. Ton corps a besoin de carburant avant de performer."
        else:
            adj = "Mange avant la séance et drop les sets de 5-10% — tu n'as pas le carburant pour aller au max."
        return why, adj, prog_mod

    why = "Tes métriques de récupération sont limitantes aujourd'hui — écoute ton corps."
    adj = "Drop tes working sets de 10% et priorise la technique sur l'intensité."
    return why, adj, prog_mod


# ── Active energy modifier (repos uniquement) ─────────────────────────────────

def _active_energy_modifier(rec_logs: list | None = None) -> tuple[float, bool]:
    """Retourne (multiplicateur, appliqué).

    Si jour de repos ET active_energy > 800 kcal → récupération moins efficace → −5%.
    Ignoré les jours d'entraînement (dépense attendue).
    """
    try:
        today_s   = _today_mtl()
        sessions  = db.get_workout_sessions(limit=5) or []
        has_today = any(str(s.get("date", ""))[:10] == today_s for s in sessions)
        if has_today:
            return 1.0, False

        _rl       = rec_logs if rec_logs is not None else (db.get_recovery_logs() or [])
        today_rec = next((e for e in _rl if str(e.get("date", ""))[:10] == today_s), None)
        if today_rec and today_rec.get("active_energy") is not None:
            if float(today_rec["active_energy"]) > 800:
                return 0.95, True
    except Exception:
        pass
    return 1.0, False


# ── 30-min cache ──────────────────────────────────────────────────────────────

_CACHE: dict = {}
_CACHE_TTL = 30 * 60


# ── Public API ─────────────────────────────────────────────────────────────────

def compute() -> dict:
    """Compute and return the full readiness payload."""
    now    = _time.time()
    cached = _CACHE.get("result")
    if cached and (now - cached["ts"]) < _CACHE_TTL:
        return cached["data"]

    try:
        rec_logs = db.get_recovery_logs() or []

        hrv_score,  hrv_det              = _score_hrv(rec_logs)
        rhr_score,  rhr_det              = _score_rhr(rec_logs)
        acwr_score, acwr_det             = _score_acwr()
        sq_score,   sq_det               = _score_sleep_quality(rec_logs)
        sd_score,   sd_det               = _score_sleep_duration(rec_logs)
        sub_score,  sub_det              = _score_subjective(rec_logs)
        m_score,    m_det,    breakdown  = _score_muscle_recovery(rec_logs)
        n_score,    n_det                = _score_nutrition()
        p_score,    p_det                = _score_pattern()

        _raw = [
            ("hrv",            hrv_score,  _WEIGHTS["hrv"]),
            ("rhr",            rhr_score,  _WEIGHTS["rhr"]),
            ("acwr",           acwr_score, _WEIGHTS["acwr"]),
            ("sleep_quality",  sq_score,   _WEIGHTS["sleep_quality"]),
            ("sleep_duration", sd_score,   _WEIGHTS["sleep_duration"]),
            ("subjective",     sub_score,  _WEIGHTS["subjective"]),
            ("muscle_rec",     m_score,    _WEIGHTS["muscle_rec"]),
            ("nutrition",      n_score,    _WEIGHTS["nutrition"]),
            ("pattern",        p_score,    _WEIGHTS["pattern"]),
        ]
        _avail   = [(s, w) for _, s, w in _raw if s is not None]
        _total_w = sum(w for _, w in _avail)
        composite = (sum(s * w for s, w in _avail) / _total_w) if _total_w > 0 else 65.0

        ae_mult, ae_applied = _active_energy_modifier(rec_logs)
        score    = round(max(0.0, min(100.0, composite * ae_mult)))
        baseline = _get_personal_baseline()
        verdict, is_relative, downgrade_reason = _verdict(
            float(score), baseline, hrv_score=hrv_score, rhr_score=rhr_score
        )

        def _mod_score(s: float | None) -> int | None:
            return round(s) if s is not None else None

        modules = {
            "hrv":            {"score": _mod_score(hrv_score),  "label": "HRV",            "detail": _hrv_detail(hrv_det)},
            "rhr":            {"score": _mod_score(rhr_score),  "label": "FC repos",        "detail": _rhr_detail(rhr_det)},
            "acwr":           {"score": _mod_score(acwr_score), "label": "Charge",          "detail": _acwr_detail(acwr_det)},
            "sleep_quality":  {"score": _mod_score(sq_score),   "label": "Qualité sommeil", "detail": _sleep_quality_detail(sq_det)},
            "sleep_duration": {"score": _mod_score(sd_score),   "label": "Durée sommeil",   "detail": _sleep_duration_detail(sd_det)},
            "subjective":     {"score": _mod_score(sub_score),  "label": "Ressenti",        "detail": _subjective_detail(sub_det)},
            "muscle_rec":     {"score": _mod_score(m_score),    "label": "Récup musc",      "detail": _muscle_detail(m_det)},
            "nutrition":      {"score": _mod_score(n_score),    "label": "Nutrition",       "detail": _nutrition_detail(n_det)},
            "pattern":        {"score": _mod_score(p_score),    "label": "Pattern",         "detail": _pattern_detail(p_det)},
        }

        all_details = {
            "hrv":            hrv_det,
            "rhr":            rhr_det,
            "acwr":           acwr_det,
            "sleep_quality":  sq_det,
            "sleep_duration": sd_det,
            "subjective":     sub_det,
            "muscle_rec":     m_det,
            "nutrition":      n_det,
            "pattern":        p_det,
        }

        why, adjustment, prog_mod = _build_messaging(verdict, modules, all_details, breakdown)

        today_session = None
        try:
            from planner import get_today
            today_session = get_today()
        except Exception:
            pass

        # Commit 4 — baseline HRV unifiée : le backend est source unique du
        # verdict HRV. Le bandeau iOS consomme "zone" au lieu de recalculer
        # sur HRVAnalysis local (seuils, sensitivity user_profile — vivent ici).
        hrv_status = None if hrv_det.get("data_insufficient") else {
            "score":       hrv_det.get("hrv_score"),
            "zone":        hrv_det.get("zone"),        # "green" | "orange" | "red"
            "today_rmssd": hrv_det.get("today_hrv"),
            "baseline_7d": hrv_det.get("baseline"),
        }

        data = {
            "score":                 score,
            "verdict":               verdict,
            "verdict_method":        "relative" if is_relative else "absolute_cold_start",
            "baseline":              baseline if is_relative else None,
            "downgrade_reason":      downgrade_reason,
            "hrv_status":            hrv_status,
            "why":                   why,
            "adjustment":            adjustment,
            "progression_modifier":  prog_mod,
            "modules":               modules,
            "muscle_recovery":       breakdown,
            "today_session":         today_session,
            "active_energy_penalty": ae_applied,
            "computed_at":           datetime.now(timezone.utc).isoformat(),
        }

        # Écriture PROSPECTIVE STRICTE (score du jour, jamais rétroactive).
        # target_date = _today_mtl() par design : compute() lit et calcule sur
        # aujourd'hui. Fail loud LOG uniquement, jamais throw — le score est
        # retourné à l'app même si la persistance échoue (chart perd un point,
        # pas de crash).
        target_date = _today_mtl()
        try:
            db.upsert_readiness_daily(target_date, score)
        except Exception as e:
            logger.warning("readiness_daily persist failed for %s: %s", target_date, e)

        _CACHE["result"] = {"data": data, "ts": now}
        return data

    except Exception as e:
        logger.exception("readiness.compute failed: %s", e)
        # Doctrine anti-fantôme (CLAUDE.md) : plus jamais de score inventé sur except.
        # L'échec de calcul remonte au blueprint → HTTP 500 explicite au client.
        # Distinct de la persistance L838-841 (score réel + write raté = fail loud LOG,
        # score retourné à l'app).
        raise


def invalidate_cache() -> None:
    _CACHE.clear()


# ── Detail formatters ─────────────────────────────────────────────────────────

def _hrv_detail(d: dict) -> str:
    if d.get("data_insufficient"):
        return "Baseline HRV insuffisante (< 3 jours)"
    score = d.get("hrv_score")
    zone  = d.get("zone", "")
    if score is not None:
        return f"HRV {int(score)}/100 — {zone}" if zone else f"HRV score {int(score)}/100"
    return "Données HRV indisponibles"


def _acwr_detail(d: dict) -> str:
    acwr = d.get("acwr")
    if acwr is None:
        return "Données ACWR insuffisantes"
    zone = d.get("zone", "")
    h    = d.get("hard_sessions_48h", 0)
    s    = f"ACWR {acwr} — {zone}"
    if h >= 2:
        s += f" · {h} séances intenses/48h"
    return s


def _sleep_quality_detail(d: dict) -> str:
    if d.get("data_insufficient"):
        return "Qualité sommeil non renseignée"
    sq = d.get("sleep_quality")
    return f"Qualité {sq:.0f}/10" if sq is not None else "Données sommeil indisponibles"


def _sleep_duration_detail(d: dict) -> str:
    if d.get("data_insufficient"):
        return "Durée sommeil non renseignée"
    hours = d.get("sleep_hours")
    return f"{hours:.1f}h cette nuit" if hours is not None else "Durée inconnue"


def _subjective_detail(d: dict) -> str:
    if d.get("data_insufficient"):
        return "Ressenti non renseigné"
    signal = d.get("signal", "")
    value  = d.get("value")
    if value is not None:
        if "soreness" in signal:
            return f"Courbatures {value:.0f}/10 (fallback)"
        return f"Fatigue perçue {value:.0f}/10"
    return "Données subjectives indisponibles"


def _nutrition_detail(d: dict) -> str:
    if d.get("no_data"):
        return "Aucune entrée nutrition récente"
    cal_p  = d.get("cal_pct")
    prot_p = d.get("prot_pct")
    if cal_p is not None and prot_p is not None:
        return f"Calories {cal_p}% · Protéines {prot_p}%"
    return "Données nutrition partielles"


def _pattern_detail(d: dict) -> str:
    rest = d.get("days_since_last")
    if rest is None:
        return "Peu d'historique"
    if rest == 0:
        return "Séance aujourd'hui — accumulation aiguë"
    if rest <= 2:
        return f"{rest}j de repos — récupération en cours"
    if rest >= 6:
        return f"{rest}j sans séance — légère décharge"
    return f"{rest}j depuis dernière séance"


def _muscle_detail(d: dict) -> str:
    if d.get("no_recent_training"):
        return "Aucun entraînement récent"
    worst  = d.get("worst_label")
    pct    = d.get("worst_pct")
    remain = d.get("worst_remaining")
    if worst:
        return f"{worst} récupérés à {pct}% · {remain}h restantes"
    return "Récupération musculaire OK"


def _rhr_detail(d: dict) -> str:
    if d.get("data_insufficient"):
        return "FC repos non renseignée ou baseline insuffisante"
    rhr     = d.get("today_rhr")
    base    = d.get("baseline_7d")
    delta   = d.get("delta_bpm")
    if rhr is not None and base is not None:
        sign = "+" if delta >= 0 else ""
        return f"FC repos {rhr:.0f} bpm · baseline 7j {base:.0f} ({sign}{delta:.0f} bpm)"
    return "Données FC repos indisponibles"
