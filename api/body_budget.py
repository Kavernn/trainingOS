"""
body_budget.py — Daily 0-100 Body Budget score.

Three pillars:
  T (Training)  — workout quality + recovery markers (last 7 days)
  S (Stress)    — PSS score + HRV (last 7 days)
  N (Nutrition) — calorie/protein adherence + consistency (last 3 days)

Non-additive interaction modifiers applied after pillar calculation.
3-day exponential smoothing for stability.
"""
from __future__ import annotations
import db
import logging
from datetime import datetime, timezone, timedelta

logger = logging.getLogger("trainingos.body_budget")

# ── Weights ────────────────────────────────────────────────────────────────────
_W_T = 0.40   # Training pillar weight
_W_S = 0.30   # Stress pillar weight
_W_N = 0.30   # Nutrition pillar weight


# ── Helpers ────────────────────────────────────────────────────────────────────

def _today_iso() -> str:
    try:
        from zoneinfo import ZoneInfo
        return datetime.now(ZoneInfo("America/Montreal")).strftime("%Y-%m-%d")
    except Exception:
        utc = datetime.now(timezone.utc)
        return (utc - timedelta(hours=5)).strftime("%Y-%m-%d")


def _days_back(n: int) -> list[str]:
    """Return list of ISO date strings from today back n days (inclusive)."""
    from datetime import date
    today = date.fromisoformat(_today_iso())
    return [(today - timedelta(days=i)).isoformat() for i in range(n)]


# ── Training pillar ────────────────────────────────────────────────────────────

def _score_training() -> tuple[float, dict]:
    """Score 0-100 pour la qualité d'entraînement récente.

    Retiré : sleep_quality et HRV — déjà dans le LSS (source de vérité).
    Gardé : fréquence, RPE, soreness (feedback musculaire direct).
    """
    details: dict = {}

    sessions_raw = db.get_workout_sessions(limit=14) or []
    recovery_raw = db.get_recovery_logs(limit=2) or []

    today_dates = set(_days_back(7))

    recent = [s for s in sessions_raw if s.get("date") in today_dates]
    details["sessions_7d"] = len(recent)

    completed = [s for s in recent if s.get("completed")]
    details["completed_7d"] = len(completed)

    rpes    = [float(s["rpe"]) for s in completed if s.get("rpe") is not None]
    avg_rpe = sum(rpes) / len(rpes) if rpes else None
    details["avg_rpe"] = round(avg_rpe, 1) if avg_rpe is not None else None

    # Soreness kept: direct muscular feedback, not duplicated in LSS
    today     = _today_iso()
    yesterday = (datetime.fromisoformat(today) - timedelta(days=1)).strftime("%Y-%m-%d")
    rec = next((r for r in recovery_raw if r.get("date") in {today, yesterday}), None)
    soreness = float(rec["soreness"]) if rec and rec.get("soreness") else None
    details["soreness"] = soreness

    score = 50.0

    freq = len(recent)
    if   freq >= 4: score += 15
    elif freq == 3: score += 10
    elif freq == 2: score += 5
    elif freq == 0: score -= 10

    if avg_rpe is not None:
        if   6.0 <= avg_rpe <= 8.5: score += 15
        elif 5.0 <= avg_rpe < 6.0:  score += 5
        elif avg_rpe > 9.0:          score -= 10
        elif avg_rpe < 5.0:          score -= 5

    if soreness is not None:
        if   soreness <= 2.0: score += 5
        elif soreness >= 4.5: score -= 15
        elif soreness >= 3.5: score -= 8

    return max(0.0, min(100.0, score)), details


# ── Stress pillar ──────────────────────────────────────────────────────────────

def _score_stress() -> tuple[float, dict]:
    """Score 0-100 de stress — lit le LSS depuis le moteur central.

    Body Budget est un consommateur du wellness engine, pas un calculateur.
    Élimine la duplication PSS + HRV qui vivaient déjà dans life_stress_engine.
    """
    from life_stress_engine import get_life_stress_score
    details: dict = {}

    try:
        lss   = get_life_stress_score(_today_iso())
        score = float(lss.get("score") or 65.0)
        flags = lss.get("flags") or {}
        comps = lss.get("components") or {}
        details["lss"]               = round(score, 1)
        details["hrv_drop"]          = flags.get("hrv_drop", False)
        details["sleep_deprivation"] = flags.get("sleep_deprivation", False)
        details["pss_score"]         = comps.get("subjective_stress")
        return max(0.0, min(100.0, score)), details
    except Exception:
        return 65.0, {"lss": None}


# ── Nutrition pillar ───────────────────────────────────────────────────────────

def _score_nutrition() -> tuple[float, dict]:
    """Score 0-100 for nutrition adherence (last 3 days)."""
    details: dict = {}

    settings_raw = db.get_nutrition_settings() or {}
    target_cal   = float(settings_raw.get("calorie_limit")  or settings_raw.get("limite_calories") or 2400)
    target_prot  = float(settings_raw.get("protein_target") or settings_raw.get("objectif_proteines") or 180)

    # Recent 3 days of entries
    recent_entries = db.get_nutrition_entries_recent(3) or []
    days_back3     = set(_days_back(3))

    by_day: dict[str, dict] = {}
    for e in recent_entries:
        d = e.get("date", "")
        if d not in days_back3:
            continue
        if d not in by_day:
            by_day[d] = {"cal": 0.0, "prot": 0.0, "count": 0}
        by_day[d]["cal"]   += float(e.get("calories",  0) or 0)
        by_day[d]["prot"]  += float(e.get("proteines", 0) or 0)
        by_day[d]["count"] += 1

    details["days_logged"] = len(by_day)
    details["target_cal"]  = int(target_cal)
    details["target_prot"] = int(target_prot)

    if not by_day:
        return 50.0, details  # no data → neutral

    cal_ratios  = [d["cal"]  / target_cal  for d in by_day.values()]
    prot_ratios = [d["prot"] / target_prot for d in by_day.values()]
    avg_cal_r  = sum(cal_ratios)  / len(cal_ratios)
    avg_prot_r = sum(prot_ratios) / len(prot_ratios)
    details["cal_ratio"]  = round(avg_cal_r,  2)
    details["prot_ratio"] = round(avg_prot_r, 2)

    # Calorie score (0.85–1.10 = ideal)
    cal_score  = _ratio_score(avg_cal_r,  ideal_lo=0.85, ideal_hi=1.10)
    prot_score = _ratio_score(avg_prot_r, ideal_lo=0.85, ideal_hi=1.10)

    # Consistency bonus
    consistency_bonus = (len(by_day) - 1) * 5  # +0/+5/+10 for 1/2/3 days logged

    score = cal_score * 0.5 + prot_score * 0.5 + consistency_bonus
    return max(0.0, min(100.0, score)), details


def _ratio_score(ratio: float, ideal_lo: float, ideal_hi: float) -> float:
    """Convert a target ratio to 0-90 score (90 = ideal range)."""
    if ideal_lo <= ratio <= ideal_hi:
        return 90.0
    if ratio < ideal_lo:
        deficit = ideal_lo - ratio
        return max(0.0, 90.0 - deficit * 150)
    excess = ratio - ideal_hi
    return max(0.0, 90.0 - excess * 120)


# ── Interaction modifiers ──────────────────────────────────────────────────────

def _apply_interactions(t: float, s: float, n: float) -> float:
    """Non-additive modifiers for compound effects."""
    raw = _W_T * t + _W_S * s + _W_N * n

    # Synergy: good training + good nutrition → +3
    if t >= 70 and n >= 70:
        raw = min(100.0, raw + 3)

    # Compound fatigue: high stress + poor nutrition → -5
    if s < 45 and n < 45:
        raw = max(0.0, raw - 5)

    # Recovery optimiser: low training stress + high nutrition → +4
    if t < 50 and n >= 75 and s >= 70:
        raw = min(100.0, raw + 4)

    return raw


# ── Smoothing (3-day EMA) ──────────────────────────────────────────────────────

def _smooth(scores: list[float]) -> float:
    """3-value exponential moving average (most recent weighted highest)."""
    if not scores:
        return 50.0
    if len(scores) == 1:
        return scores[0]
    alpha = 0.6
    result = scores[-1]
    for s in reversed(scores[:-1]):
        result = alpha * result + (1 - alpha) * s
    return result


# ── Trend ─────────────────────────────────────────────────────────────────────

def _compute_trend(current: float, prev_scores: list[float]) -> str:
    if not prev_scores:
        return "stable"
    avg_prev = sum(prev_scores) / len(prev_scores)
    delta = current - avg_prev
    if   delta >=  8: return "up"
    elif delta <= -8: return "down"
    return "stable"


# ── Insight rules ──────────────────────────────────────────────────────────────

def _build_insight(score: float, t: float, s: float, n: float,
                   t_details: dict, s_details: dict, n_details: dict) -> str:
    """Return a single contextual insight sentence in French."""
    lss        = s_details.get("lss")
    sleep_dep  = s_details.get("sleep_deprivation", False)
    soreness   = t_details.get("soreness")
    prot_r     = n_details.get("prot_ratio")
    days_logged = n_details.get("days_logged", 0)

    if score >= 80:
        return "Ton organisme est en pleine forme — conditions optimales pour performer."

    if s < 40 and lss is not None:
        return "Score bien-être bas — favorise la récupération active aujourd'hui."

    if soreness is not None and soreness >= 4.5:
        return "Courbatures importantes — envisage une séance légère ou une journée off."

    if sleep_dep:
        return "Manque de sommeil détecté — réduis l'intensité et priorise la récupération nocturne."

    if prot_r is not None and prot_r < 0.70:
        return "Apport en protéines insuffisant ces derniers jours — vise tes objectifs pour optimiser la récupération."

    if days_logged < 2 and n < 55:
        return "Nutrition peu suivie — logge tes repas pour mieux piloter ta récupération."

    if t < 40:
        return "Peu d'activité récente — une séance aujourd'hui boostera ton budget."

    if score >= 65:
        # Mettre en avant la meilleure métrique disponible plutôt qu'un fallback générique
        highlights: list[str] = []
        if t_details.get("sessions_7d", 0) >= 4:
            highlights.append(f"{t_details['sessions_7d']} séances cette semaine")
        if (avg_rpe := t_details.get("avg_rpe")) and 6.5 <= avg_rpe <= 8.0:
            highlights.append(f"RPE moyen {avg_rpe}/10")
        if (prot_r := n_details.get("prot_ratio")) and prot_r >= 0.90:
            highlights.append("protéines sur cible")
        highlight = highlights[0] if highlights else "bonne trajectoire"
        return f"En forme. {highlight.capitalize()} — continue sur cette lancée."

    return "Quelques ajustements aujourd'hui pourraient optimiser ton énergie."


# ── Public API ─────────────────────────────────────────────────────────────────

def compute() -> dict:
    """Compute today's Body Budget and return the full response dict."""
    try:
        t_score, t_det = _score_training()
        s_score, s_det = _score_stress()
        n_score, n_det = _score_nutrition()

        raw = _apply_interactions(t_score, s_score, n_score)

        # Smoothing: compare with previous 2 days (not implemented in DB — single-pass for now)
        # Future: store daily scores in KV for multi-day smoothing
        score = round(max(0.0, min(100.0, raw)))

        insight = _build_insight(score, t_score, s_score, n_score, t_det, s_det, n_det)

        return {
            "score":           score,
            "trend":           None,     # EMA 3j non implémenté — supprimer flèche UI
            "trend_available": False,
            "insight": insight,
            "pillars": {
                "training":   round(t_score),
                "stress":     round(s_score),
                "nutrition":  round(n_score),
            },
            "details": {
                "training":  t_det,
                "stress":    s_det,
                "nutrition": n_det,
            },
            "computed_at": datetime.now(timezone.utc).isoformat(),
        }
    except Exception as e:
        logger.exception("Body Budget compute failed: %s", e)
        return {
            "score":   50,
            "trend":   "stable",
            "insight": "Données insuffisantes — continue à enregistrer tes séances et repas.",
            "pillars": {"training": 50, "stress": 65, "nutrition": 50},
            "details": {},
            "computed_at": datetime.now(timezone.utc).isoformat(),
        }
