"""
readiness.py — Pre-session Readiness Score (0-100).

5 modules with adaptive weights:
  Fatigue accumulée   25%  (ACWR + sessions dures 48h)
  Stress PSS          20%  (dernier score + tendance 7j)
  Nutrition           20%  (adhérence cals/protéines 24-48h)
  Pattern historique  15%  (jour de semaine + repos depuis dernière séance)
  Récupération musc.  20%  (temps écoulé vs seuil par load_profile et categorie)

Verdict : go (75+) | moderate (50-74) | rest (0-49)
"""
from __future__ import annotations

import math, time as _time, logging
from collections import defaultdict
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
    "fatigue":    0.25,
    "stress":     0.20,
    "nutrition":  0.20,
    "pattern":    0.15,
    "muscle_rec": 0.20,
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

    # Count hard sessions (RPE ≥ 7) in last 48h
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


# ── Module 2: Stress ──────────────────────────────────────────────────────────

def _score_stress() -> tuple[float, dict]:
    details: dict = {}
    records = db.get_pss_records(limit=7) or []
    if not records:
        return 65.0, {"pss": None, "trend": "unknown"}

    pss = float(records[0].get("pss_score") or records[0].get("score") or 20)
    details["pss"] = int(pss)

    older = [float(r.get("pss_score") or r.get("score") or 20) for r in records[1:]]
    trend_mod = 0.0
    if older:
        avg_old = sum(older) / len(older)
        delta   = pss - avg_old
        if delta >= 3:
            trend_mod = -10.0; details["trend"] = "hausse"
        elif delta <= -3:
            trend_mod = +8.0;  details["trend"] = "baisse"
        else:
            details["trend"] = "stable"
    else:
        details["trend"] = "unknown"

    base  = 100.0 - (pss / 40.0 * 80.0)
    score = max(0.0, min(100.0, base + trend_mod))
    return round(score, 1), details


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
        settings   = db.get_nutrition_settings() or {}
        target_cal  = float(settings.get("calorie_limit")  or settings.get("limite_calories")  or 2400)
        target_prot = float(settings.get("protein_target") or settings.get("objectif_proteines") or 180)
    except Exception:
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


# ── Module 4: Historical Pattern ──────────────────────────────────────────────

def _score_pattern() -> tuple[float, dict]:
    details: dict = {}
    today_wd = date_cls.today().weekday()
    details["weekday"] = today_wd

    raw = db.get_workout_sessions(limit=60) or []
    by_wd: dict[int, list[float]] = defaultdict(list)
    days_since: dict[str, int] = {}
    today = date_cls.today()

    for s in raw:
        d = str(s.get("date") or "")[:10]
        if not d:
            continue
        try:
            dd = date_cls.fromisoformat(d)
        except ValueError:
            continue
        wd  = dd.weekday()
        rpe = s.get("rpe")
        if rpe is not None:
            by_wd[wd].append(float(rpe))
        name  = s.get("session_name") or s.get("session_type") or ""
        delta = (today - dd).days
        if name and (name not in days_since or delta < days_since[name]):
            days_since[name] = delta

    score = 70.0

    if today_wd in by_wd and len(by_wd[today_wd]) >= 3:
        avg_rpe = sum(by_wd[today_wd]) / len(by_wd[today_wd])
        details["avg_rpe_weekday"] = round(avg_rpe, 1)
        if avg_rpe < 7.0:  score += 5.0
        elif avg_rpe > 8.0: score -= 5.0

    if days_since:
        min_rest = min(days_since.values())
        details["days_since_last"] = min_rest
        if min_rest == 0:   score -= 15.0
        elif min_rest <= 2: score += 10.0
        elif min_rest >= 6: score -= 5.0

    return round(max(0.0, min(100.0, score)), 1), details


# ── Module 5: Muscle Group Recovery ───────────────────────────────────────────

def _score_muscle_recovery() -> tuple[float, dict, dict]:
    """Returns (score, module_details, muscle_breakdown {cat: {...}})."""
    all_hist  = db.get_all_exercise_history() or {}
    ex_info   = db.get_exercises_info_bulk(list(all_hist.keys())) if all_hist else {}
    today_dt  = datetime.now(timezone.utc)

    # Per-category: find the most recent training (hours ago)
    cat_last_h: dict[str, float] = {}
    cat_profile: dict[str, str]  = {}

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

        if hours_ago > 168:  # fully recovered — skip
            continue

        info = ex_info.get(ex_name) or {}
        cat  = (info.get("category") or "other").lower()
        lp   = info.get("load_profile") or "compound_hypertrophy"

        if cat not in cat_last_h or hours_ago < cat_last_h[cat]:
            cat_last_h[cat]   = hours_ago
            cat_profile[cat]  = lp

    relevant = [c for c in cat_last_h if c in _CAT_LABEL]
    if not relevant:
        return 85.0, {"no_recent_training": True}, {}

    breakdown: dict[str, dict] = {}
    fractions: list[float] = []

    for cat in relevant:
        h_ago     = cat_last_h[cat]
        lp        = cat_profile.get(cat, "compound_hypertrophy")
        threshold = _RECOVERY_H.get(lp, _DEFAULT_RECOVERY_H)
        frac      = min(1.0, h_ago / threshold)
        h_remain  = max(0.0, threshold - h_ago)

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


# ── Verdict + Why + Adjustment ────────────────────────────────────────────────

def _verdict(score: float) -> str:
    if score >= 75: return "go"
    if score >= 50: return "moderate"
    return "rest"


def _build_messaging(
    verdict: str, modules: dict,
    fatigue_d: dict, stress_d: dict, nutrition_d: dict,
    pattern_d: dict, muscle_d: dict, breakdown: dict,
) -> tuple[str, str | None, float]:
    """Returns (why, adjustment, progression_modifier)."""

    mod_scores = {k: modules[k]["score"] for k in modules}
    worst_k    = min(mod_scores, key=mod_scores.__getitem__)

    if verdict == "go":
        return "Toutes tes métriques sont au vert — c'est le bon moment pour pousser.", None, 1.0

    prog_mod = 0.65 if verdict == "rest" else 0.90

    # Muscle recovery
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

    # Fatigue
    if worst_k == "fatigue":
        acwr = fatigue_d.get("acwr") or "?"
        why  = f"Charge accumulée élevée (ACWR {acwr}) — tu as poussé fort ces derniers jours."
        if verdict == "rest":
            adj = "Repos ou cardio léger uniquement. Si tu t'entraînes : 60-70% des charges habituelles."
        else:
            adj = "Drop tes working sets de 10% — garde le même RPE cible, réduis le volume total."
        return why, adj, prog_mod

    # Stress
    if worst_k == "stress":
        pss   = stress_d.get("pss") or "?"
        trend = stress_d.get("trend") or "stable"
        why   = f"PSS à {pss} et en {trend} — le cortisol élevé freine la récupération musculaire."
        if verdict == "rest":
            adj = "Rest day prioritaire. Mobilité légère OK mais pas d'intensité aujourd'hui."
        else:
            adj = "Entraîne-toi, mais ne cherche pas à battre des PRs — qualité d'exécution plutôt qu'intensité."
        return why, adj, prog_mod

    # Nutrition
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

    # Pattern
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
        s_score, s_det = _score_stress()
        n_score, n_det = _score_nutrition()
        p_score, p_det = _score_pattern()
        m_score, m_det, breakdown = _score_muscle_recovery()

        composite = (
            f_score * _WEIGHTS["fatigue"]
            + s_score * _WEIGHTS["stress"]
            + n_score * _WEIGHTS["nutrition"]
            + p_score * _WEIGHTS["pattern"]
            + m_score * _WEIGHTS["muscle_rec"]
        )
        score   = round(max(0.0, min(100.0, composite)))
        verdict = _verdict(float(score))

        modules = {
            "fatigue":    {"score": round(f_score), "label": "Fatigue",    "detail": _fatigue_detail(f_det)},
            "stress":     {"score": round(s_score), "label": "Stress",     "detail": _stress_detail(s_det)},
            "nutrition":  {"score": round(n_score), "label": "Nutrition",  "detail": _nutrition_detail(n_det)},
            "pattern":    {"score": round(p_score), "label": "Pattern",    "detail": _pattern_detail(p_det)},
            "muscle_rec": {"score": round(m_score), "label": "Récup musc", "detail": _muscle_detail(m_det)},
        }

        why, adjustment, prog_mod = _build_messaging(
            verdict, modules,
            f_det, s_det, n_det, p_det, m_det, breakdown,
        )

        # Get today's planned session
        today_session = None
        try:
            from planner import get_today
            today_session = get_today()
        except Exception:
            pass

        data = {
            "score":                score,
            "verdict":              verdict,
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


def _stress_detail(d: dict) -> str:
    pss   = d.get("pss")
    trend = d.get("trend", "")
    if pss is None:
        return "Pas de score PSS récent"
    level = "faible" if pss <= 13 else ("modéré" if pss <= 26 else "élevé")
    return f"PSS {pss} — {level}, tendance {trend}"


def _nutrition_detail(d: dict) -> str:
    if d.get("no_data"):
        return "Aucune entrée nutrition récente"
    cal_p  = d.get("cal_pct")
    prot_p = d.get("prot_pct")
    if cal_p is not None and prot_p is not None:
        return f"Calories {cal_p}% · Protéines {prot_p}%"
    return "Données nutrition partielles"


def _pattern_detail(d: dict) -> str:
    wd_names = ["Lundi", "Mardi", "Mercredi", "Jeudi", "Vendredi", "Samedi", "Dimanche"]
    wd       = d.get("weekday")
    rpe      = d.get("avg_rpe_weekday")
    rest     = d.get("days_since_last")
    parts    = []
    if wd is not None:
        parts.append(wd_names[wd])
    if rpe is not None:
        parts.append(f"RPE moyen {rpe}/10 ce jour")
    if rest is not None:
        parts.append(f"{rest}j depuis dernière séance")
    return " · ".join(parts) if parts else "Peu d'historique"


def _muscle_detail(d: dict) -> str:
    if d.get("no_recent_training"):
        return "Aucun entraînement récent"
    worst  = d.get("worst_label")
    pct    = d.get("worst_pct")
    remain = d.get("worst_remaining")
    if worst:
        return f"{worst} récupérés à {pct}% · {remain}h restantes"
    return "Récupération musculaire OK"
