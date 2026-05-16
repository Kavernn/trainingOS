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
    """Score 0-100 for training readiness/quality."""
    details: dict = {}

    sessions_raw = db.get_workout_sessions(limit=14) or []
    recovery_raw = db.get_recovery_logs(limit=7) or []

    today_dates = set(_days_back(7))

    # Sessions in last 7 days
    recent = [s for s in sessions_raw if s.get("date") in today_dates]
    details["sessions_7d"] = len(recent)

    # Completion quality: prefer completed + has rpe
    completed = [s for s in recent if s.get("completed")]
    details["completed_7d"] = len(completed)

    # Average RPE (if available) — ideal is 7-8
    rpes = [float(s["rpe"]) for s in completed if s.get("rpe") is not None]
    avg_rpe = sum(rpes) / len(rpes) if rpes else None
    details["avg_rpe"] = round(avg_rpe, 1) if avg_rpe is not None else None

    # Today's recovery markers
    today = _today_iso()
    today_rec = next((r for r in recovery_raw if r.get("date") == today), None)
    yesterday = (datetime.fromisoformat(today) - timedelta(days=1)).strftime("%Y-%m-%d")
    prev_rec  = next((r for r in recovery_raw if r.get("date") == yesterday), None)
    rec = today_rec or prev_rec

    sleep_q   = float(rec["sleep_quality"]) if rec and rec.get("sleep_quality") else None
    soreness  = float(rec["soreness"])      if rec and rec.get("soreness")      else None
    hrv       = float(rec["hrv"])           if rec and rec.get("hrv")           else None
    details["sleep_quality"] = sleep_q
    details["soreness"]      = soreness

    # --- Score calculation ---
    score = 50.0  # neutral baseline

    # Workout frequency: 3-5 sessions/7 days = optimal (+15), fewer or more neutral/lower
    freq = len(recent)
    if   freq >= 4: score += 15
    elif freq == 3: score += 10
    elif freq == 2: score += 5
    elif freq == 0: score -= 10

    # RPE quality: 6-8.5 ideal
    if avg_rpe is not None:
        if   6.0 <= avg_rpe <= 8.5: score += 15
        elif 5.0 <= avg_rpe < 6.0:  score += 5
        elif avg_rpe > 9.0:          score -= 10
        elif avg_rpe < 5.0:          score -= 5

    # Sleep quality (1-5 scale)
    if sleep_q is not None:
        if   sleep_q >= 4.0: score += 10
        elif sleep_q >= 3.0: score += 3
        elif sleep_q < 2.5:  score -= 15

    # Soreness (1-5 scale, 5 = very sore)
    if soreness is not None:
        if   soreness <= 2.0: score += 5
        elif soreness >= 4.5: score -= 15
        elif soreness >= 3.5: score -= 8

    # HRV bonus (relative — if available, treat >55ms as positive)
    if hrv is not None:
        if   hrv >= 60: score += 8
        elif hrv >= 45: score += 3
        elif hrv < 30:  score -= 8

    return max(0.0, min(100.0, score)), details


# ── Stress pillar ──────────────────────────────────────────────────────────────

def _score_stress() -> tuple[float, dict]:
    """Score 0-100 for stress (higher = less stressed = better budget)."""
    details: dict = {}

    pss_records = db.get_pss_records(limit=3) or []
    recovery_raw = db.get_recovery_logs(limit=3) or []

    # PSS: 0-40 scale, 0=no stress. Invert for budget (0 stress → 100 score).
    pss_score = None
    if pss_records:
        raw = pss_records[0].get("pss_score") or pss_records[0].get("score")
        if raw is not None:
            pss_score = float(raw)
    details["pss_score"] = pss_score

    # HRV from recent recovery
    hrv_vals = [float(r["hrv"]) for r in recovery_raw if r.get("hrv") is not None]
    avg_hrv  = sum(hrv_vals) / len(hrv_vals) if hrv_vals else None
    details["hrv_avg"] = round(avg_hrv, 1) if avg_hrv is not None else None

    # --- Score ---
    score = 65.0  # default: moderate stress assumed

    if pss_score is not None:
        # PSS 0-13 → low stress, 14-26 → moderate, 27+ → high
        if   pss_score <= 13: score = 85.0
        elif pss_score <= 20: score = 70.0
        elif pss_score <= 26: score = 55.0
        else:                  score = 30.0

    # HRV modifier
    if avg_hrv is not None:
        if   avg_hrv >= 65: score = min(100.0, score + 10)
        elif avg_hrv >= 50: score = min(100.0, score + 4)
        elif avg_hrv < 35:  score = max(0.0,   score - 12)

    return max(0.0, min(100.0, score)), details


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
    pss    = s_details.get("pss_score")
    soreness = t_details.get("soreness")
    sleep_q  = t_details.get("sleep_quality")
    prot_r   = n_details.get("prot_ratio")
    days_logged = n_details.get("days_logged", 0)

    if score >= 80:
        return "Ton organisme est en pleine forme — conditions optimales pour performer."

    if s < 40 and pss is not None and pss > 26:
        return "Stress élevé détecté — favorise la récupération active aujourd'hui."

    if soreness is not None and soreness >= 4.5:
        return "Courbatures importantes — envisage une séance légère ou une journée off."

    if sleep_q is not None and sleep_q < 2.5:
        return "Mauvaise nuit détectée — réduis l'intensité et priorise la récupération."

    if prot_r is not None and prot_r < 0.70:
        return "Apport en protéines insuffisant ces derniers jours — vise tes objectifs pour optimiser la récupération."

    if days_logged < 2 and n < 55:
        return "Nutrition peu suivie — logge tes repas pour mieux piloter ta récupération."

    if t < 40:
        return "Peu d'activité récente — une séance aujourd'hui boostera ton budget."

    if score >= 65:
        return "Bon équilibre — maintiens le rythme."

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

        trend   = "stable"  # Single-session — no history to diff
        insight = _build_insight(score, t_score, s_score, n_score, t_det, s_det, n_det)

        return {
            "score":   score,
            "trend":   trend,
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
