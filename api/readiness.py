"""
readiness.py — Pre-session Readiness Score (0-100).

5 modules with adaptive weights:
  Fatigue accumulée   30%  (ACWR + sessions dures 48h)
  Bien-être (LSS)     25%  (sommeil + HRV + RHR + stress + fatigue entraînement)
  Nutrition           20%  (adhérence cals/protéines 24-48h)
  Récupération musc.  15%  (courbe exponentielle + multiplicateur volume)
  Pattern historique  10%  (jours de repos uniquement — weekday pattern retiré)

Verdict : go | moderate | rest
  — Relatif à baseline 28j si ≥14 jours de données (Plews et al. 2013)
  — Absolu (75/50) en cold start
"""
from __future__ import annotations

import math, time as _time, logging
from datetime import date as date_cls, datetime, timedelta, timezone

import db

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
    "fatigue":    0.30,
    "wellness":   0.25,
    "nutrition":  0.20,
    "muscle_rec": 0.15,
    "pattern":    0.10,
}

# Muscle recovery — courbe exponentielle (MacDougall 1995, Zatsiorsky & Kraemer 2006)
_RECOVERY_K              = 3.0   # k≈3 → 95% récupération à t=threshold
_VOL_THRESHOLD_HIGH      = 6     # >6 sets → +25% temps de récupération
_VOL_THRESHOLD_VERY_HIGH = 9     # >9 sets → +50% temps de récupération
_VOL_MULT_HIGH           = 1.25
_VOL_MULT_VERY_HIGH      = 1.50

# Repeated Bout Effect : avancé récupère plus vite (Zatsiorsky & Kraemer 2006)
_EXPERIENCE_MULT = {
    "beginner":     1.15,
    "intermediate": 1.00,
    "advanced":     0.85,
}


# ── Module 1: Accumulated Fatigue ─────────────────────────────────────────────

def _score_fatigue() -> tuple[float, dict]:
    details: dict = {}
    try:
        from acwr import calc_acwr
        acwr_data = calc_acwr()
        acwr = float(acwr_data.get("ratio") or 0)
        details["acwr"] = round(acwr, 2)
        details["acute"]   = round(float(acwr_data.get("acute_load")   or 0), 1)
        details["chronic"] = round(float(acwr_data.get("chronic_load") or 0), 1)
    except Exception:
        acwr = None
        details["acwr"] = None

    today     = date_cls.today()
    recent    = db.get_workout_sessions(limit=10) or []
    hard_48h  = 0
    for s in recent:
        try:
            delta = (today - date_cls.fromisoformat(str(s.get("date") or "")[:10])).days
        except ValueError:
            continue
        if delta < 2 and s.get("rpe") is not None and float(s.get("rpe") or 0) >= 7:
            hard_48h += 1
    details["hard_sessions_48h"] = hard_48h

    if acwr is None:
        return 65.0, details

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


# ── Module 2: Wellness (Life Stress Score — moteur central) ───────────────────

def _score_wellness() -> tuple[float, dict]:
    """Lit le Life Stress Score depuis le moteur central.

    Remplace _score_stress() qui lisait PSS directement.
    Le LSS est la source de vérité : sommeil 30%, HRV 25%, RHR 20%,
    stress subjectif 15%, fatigue 10% — pondération normalisée sur les
    données disponibles (fonctionne sans Apple Watch).
    """
    from life_stress_engine import get_life_stress_score

    try:
        lss        = get_life_stress_score(date_cls.today().isoformat())
        score      = float(lss.get("score") or 50.0)
        coverage   = float(lss.get("data_coverage") or 0.0)
        components = lss.get("components") or {}
        flags      = lss.get("flags") or {}
        return round(score, 1), {
            "lss":              round(score, 1),
            "data_coverage":    coverage,
            "sleep":            components.get("sleep_quality"),
            "hrv":              components.get("hrv_trend"),
            "rhr":              components.get("rhr_trend"),
            "subjective":       components.get("subjective_stress"),
            "training_fatigue": components.get("training_fatigue"),
            "flags":            flags,
        }
    except Exception as e:
        logger.exception("_score_lss failed: %s", e)
        return 65.0, {"lss": None, "data_coverage": 0.0, "flags": {}}


# ── Module 3: Nutrition ───────────────────────────────────────────────────────

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
    except Exception as e:
        logger.exception("_score_nutrition failed: %s", e)
        return 65.0, {"error": True}

    entries = db.get_nutrition_entries_recent(2) or []
    today   = date_cls.today()
    today_s = today.isoformat()
    yest_s  = (today - timedelta(days=1)).isoformat()

    by_day: dict[str, dict] = {}
    for e in entries:
        d = str(e.get("date") or "")[:10]
        if d not in by_day:
            by_day[d] = {"cal": 0.0, "prot": 0.0}
        by_day[d]["cal"]  += float(e.get("calories",  0) or 0)
        by_day[d]["prot"] += float(e.get("proteines", 0) or 0)

    pairs = []
    for d, w in [(today_s, 0.65), (yest_s, 0.35)]:
        if d not in by_day:
            continue
        cal_r  = by_day[d]["cal"]  / target_cal  if target_cal  > 0 else 0.0
        prot_r = by_day[d]["prot"] / target_prot if target_prot > 0 else 0.0
        pairs.append((_ratio_score(cal_r) * 0.5 + _ratio_score(prot_r) * 0.5, w))

    if not pairs:
        return 50.0, {"no_data": True}

    score = sum(s * w for s, w in pairs) / sum(w for _, w in pairs)

    if today_s in by_day:
        deficit = target_cal - by_day[today_s]["cal"]
        details["cal_deficit"] = int(deficit)
        if deficit > 500:
            score = max(0.0, score - 15.0)
        details["cal_pct"]  = int(by_day[today_s]["cal"]  / target_cal  * 100) if target_cal  > 0 else None
        details["prot_pct"] = int(by_day[today_s]["prot"] / target_prot * 100) if target_prot > 0 else None

    return round(max(0.0, min(100.0, score)), 1), details


# ── Module 4: Pattern (repos uniquement) ──────────────────────────────────────

def _score_pattern() -> tuple[float, dict]:
    """Score basé uniquement sur les jours de repos depuis la dernière séance.

    Retiré : pattern par jour de semaine — non validé scientifiquement
    (chronotype et contexte de vie sont de meilleurs prédicteurs).

    Gardé : jours depuis dernière séance — resynthèse glycogénique et
    supercompensation (Zatsiorsky & Kraemer 2006).
    """
    details: dict = {}
    raw   = db.get_workout_sessions(limit=20) or []
    today = date_cls.today()

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


# ── Module 5: Muscle Group Recovery ───────────────────────────────────────────

def _get_experience_mult() -> float:
    """Retourne le multiplicateur de récupération selon training_experience."""
    try:
        from user_profile import load_user_profile
        level = (load_user_profile().get("training_experience") or "").lower()
        return _EXPERIENCE_MULT.get(level, 1.0)
    except Exception as e:
        logger.exception("_get_experience_mult failed: %s", e)
        return 1.0


def _score_muscle_recovery() -> tuple[float, dict, dict]:
    """Returns (score, module_details, muscle_breakdown {cat: {...}}).

    Courbe exponentielle : frac = 1 - e^(-k × t/T)
    Plus réaliste que linéaire — récupération rapide dans les premières heures
    (clearance métabolique), ralentit ensuite (réparation structurelle).

    Volume multiplicateur : >6 sets → +25% threshold, >9 sets → +50%
    (MacDougall et al. 1995 — marqueurs de dommages musculaires).
    """
    all_hist  = db.get_all_exercise_history() or {}
    ex_info   = db.get_exercises_info_bulk(list(all_hist.keys())) if all_hist else {}
    today_dt  = datetime.now(timezone.utc)

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

    def _count_sets_for_cat(cat: str) -> int:
        """Compte les sets pour un groupe musculaire dans sa dernière session."""
        session_date = cat_date.get(cat, "")
        if not session_date:
            return 0
        total = 0
        for ex_name, entries in all_hist.items():
            if not entries:
                continue
            if str(entries[0].get("date") or "")[:10] != session_date:
                continue
            info = ex_info.get(ex_name) or {}
            if (info.get("category") or "other").lower() != cat:
                continue
            total += int(entries[0].get("sets") or entries[0].get("nb_sets") or 0)
        return total

    exp_mult = _get_experience_mult()

    breakdown: dict[str, dict] = {}
    fractions: list[float] = []

    for cat in relevant:
        h_ago     = cat_last_h[cat]
        lp        = cat_profile.get(cat, "compound_hypertrophy")
        threshold = float(_RECOVERY_H.get(lp, _DEFAULT_RECOVERY_H))

        vol_sets = _count_sets_for_cat(cat)
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
    worst = min(breakdown.items(), key=lambda x: x[1]["pct"])
    details = {
        "worst_cat":       worst[0],
        "worst_pct":       worst[1]["pct"],
        "worst_remaining": worst[1]["hours_remaining"],
        "worst_label":     worst[1]["label"],
    }
    return round(max(0.0, min(100.0, score)), 1), details, breakdown


# ── Baseline personnelle + Verdict ────────────────────────────────────────────

def _get_personal_baseline() -> dict:
    """Calcule la baseline personnelle sur 28 jours glissants.

    Cold start (<14 jours de données) : retourne mean=None → seuils absolus.
    """
    today  = date_cls.today()
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


def _verdict(score: float, baseline: dict | None = None) -> tuple[str, bool]:
    """Retourne (verdict, is_relative).

    Relatif (Plews et al. 2013 — zone method) si baseline ≥14 jours :
      go       : score ≥ mean - 0.5×SD
      moderate : mean - 1.5×SD ≤ score < mean - 0.5×SD
      rest     : score < mean - 1.5×SD

    Absolu en cold start (<14 jours de données) :
      go ≥75 · moderate 50-74 · rest <50
    """
    if baseline and baseline.get("mean") is not None:
        mean = baseline["mean"]
        sd   = baseline["sd"] or 5.0
        if score >= mean - 0.5 * sd:
            return "go", True
        if score >= mean - 1.5 * sd:
            return "moderate", True
        return "rest", True

    if score >= 75: return "go", False
    if score >= 50: return "moderate", False
    return "rest", False


# ── Messaging ─────────────────────────────────────────────────────────────────

def _build_messaging(
    verdict: str, modules: dict,
    fatigue_d: dict, wellness_d: dict, nutrition_d: dict,
    pattern_d: dict, muscle_d: dict, breakdown: dict,
) -> tuple[str, str | None, float]:
    """Returns (why, adjustment, progression_modifier)."""

    mod_scores = {k: modules[k]["score"] for k in modules}
    worst_k    = min(mod_scores, key=mod_scores.__getitem__)

    if verdict == "go":
        return "Toutes tes métriques sont au vert — c'est le bon moment pour pousser.", None, 1.0

    prog_mod = 0.65 if verdict == "rest" else 0.90

    if worst_k == "muscle_rec":
        lbl  = muscle_d.get("worst_label", "tes muscles")
        hrs  = muscle_d.get("worst_remaining", 0)
        pct  = muscle_d.get("worst_pct", 0)
        why  = f"Tes {lbl} ne sont récupérés qu'à {pct}% — il manque encore {hrs}h idéalement."
        if verdict == "rest":
            adj = "Repos actif recommandé — mobilité ou marche. Reviens demain pour ta séance prévue."
        else:
            ready = [v["label"] for c, v in breakdown.items() if v["pct"] >= 90 and c != muscle_d.get("worst_cat")]
            if ready:
                adj = f"Focus {' + '.join(ready[:2])} aujourd'hui — {lbl} pas encore prêts."
            else:
                adj = "Drop tes working sets de 10% et évite les exercices ciblant tes muscles fatigués."
        return why, adj, prog_mod

    if worst_k == "fatigue":
        acwr = fatigue_d.get("acwr") or "?"
        why  = f"Charge accumulée élevée (ACWR {acwr}) — tu as poussé fort ces derniers jours."
        if verdict == "rest":
            adj = "Repos ou cardio léger uniquement. Si tu t'entraînes : 60-70% des charges habituelles."
        else:
            adj = "Drop tes working sets de 10% — garde le même RPE cible, réduis le volume total."
        return why, adj, prog_mod

    if worst_k == "wellness":
        lss   = wellness_d.get("lss") or 50
        flags = wellness_d.get("flags") or {}
        parts = []
        if flags.get("sleep_deprivation"):
            parts.append("manque de sommeil")
        if flags.get("hrv_drop"):
            parts.append("chute de HRV")
        if flags.get("training_overload"):
            parts.append("surcharge d'entraînement")
        cause = " + ".join(parts) if parts else "stress global élevé"
        why   = f"Ton score bien-être est à {int(lss)}/100 ({cause}) — la récupération est limitée."
        if verdict == "rest":
            adj = "Rest day prioritaire. Mobilité légère OK mais pas d'intensité aujourd'hui."
        else:
            adj = "Entraîne-toi, mais ne cherche pas à battre des PRs — qualité d'exécution plutôt qu'intensité."
        return why, adj, prog_mod

    if worst_k == "nutrition":
        prot_pct = nutrition_d.get("prot_pct")
        deficit  = nutrition_d.get("cal_deficit")
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
        f_score, f_det = _score_fatigue()
        w_score, w_det = _score_wellness()
        n_score, n_det = _score_nutrition()
        p_score, p_det = _score_pattern()
        m_score, m_det, breakdown = _score_muscle_recovery()

        composite = (
            f_score * _WEIGHTS["fatigue"]
            + w_score * _WEIGHTS["wellness"]
            + n_score * _WEIGHTS["nutrition"]
            + m_score * _WEIGHTS["muscle_rec"]
            + p_score * _WEIGHTS["pattern"]
        )
        score    = round(max(0.0, min(100.0, composite)))
        baseline = _get_personal_baseline()
        verdict, is_relative = _verdict(float(score), baseline)

        modules = {
            "fatigue":    {"score": round(f_score), "label": "Fatigue",    "detail": _fatigue_detail(f_det)},
            "wellness":   {"score": round(w_score), "label": "Bien-être",  "detail": _wellness_detail(w_det)},
            "nutrition":  {"score": round(n_score), "label": "Nutrition",  "detail": _nutrition_detail(n_det)},
            "pattern":    {"score": round(p_score), "label": "Pattern",    "detail": _pattern_detail(p_det)},
            "muscle_rec": {"score": round(m_score), "label": "Récup musc", "detail": _muscle_detail(m_det)},
        }

        why, adjustment, prog_mod = _build_messaging(
            verdict, modules,
            f_det, w_det, n_det, p_det, m_det, breakdown,
        )

        today_session = None
        try:
            from planner import get_today
            today_session = get_today()
        except Exception:
            pass

        data = {
            "score":                score,
            "verdict":              verdict,
            "verdict_method":       "relative" if is_relative else "absolute_cold_start",
            "baseline":             baseline if is_relative else None,
            "why":                  why,
            "adjustment":           adjustment,
            "progression_modifier": prog_mod,
            "modules":              modules,
            "muscle_recovery":      breakdown,
            "today_session":        today_session,
            "computed_at":          datetime.now(timezone.utc).isoformat(),
        }
        _CACHE["result"] = {"data": data, "ts": now}
        return data

    except Exception as e:
        logger.exception("readiness.compute failed: %s", e)
        return {
            "score": 65, "verdict": "moderate",
            "verdict_method": "absolute_cold_start", "baseline": None,
            "why": "Données insuffisantes — écoute ton ressenti aujourd'hui.",
            "adjustment": None, "progression_modifier": 1.0,
            "modules": {}, "muscle_recovery": {}, "today_session": None,
            "computed_at": datetime.now(timezone.utc).isoformat(),
        }


def invalidate_cache() -> None:
    _CACHE.clear()


# ── Detail formatters ─────────────────────────────────────────────────────────

def _fatigue_detail(d: dict) -> str:
    acwr = d.get("acwr")
    if acwr is None:
        return "Données ACWR insuffisantes"
    zone = d.get("zone", "")
    h    = d.get("hard_sessions_48h", 0)
    s    = f"ACWR {acwr} — {zone}"
    if h >= 2:
        s += f" · {h} séances intenses/48h"
    return s


def _wellness_detail(d: dict) -> str:
    lss      = d.get("lss")
    coverage = d.get("data_coverage") or 0.0
    flags    = d.get("flags") or {}
    if lss is None:
        return "Données bien-être insuffisantes"
    parts = [f"LSS {int(lss)}/100"]
    if flags.get("sleep_deprivation"):
        parts.append("manque de sommeil")
    if flags.get("hrv_drop"):
        parts.append("HRV en baisse")
    if coverage < 0.6:
        parts.append(f"couverture {int(coverage * 100)}%")
    return " · ".join(parts)


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
