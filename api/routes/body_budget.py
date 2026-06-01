"""
body_budget.py — Score global de ressources corporelles (Body Budget).

Calcule un score composite 0-100 basé sur 3 piliers :
  - training  : charge récente (fréquence + RPE 7j)
  - stress    : récupération + HRV + soreness
  - nutrition : compliance protéines + calories 7j

Tendance : comparaison 7j vs 7j précédents.
"""
from __future__ import annotations

from datetime import date as date_cls, timedelta
from flask import Blueprint, jsonify

from utils import _today_mtl

body_budget_bp = Blueprint("body_budget", __name__)


def _nutrition_pillar(nutr_entries: list, target_protein: float, target_cal: float) -> int:
    """0-100 : compliance protéines (60 %) + calories (40 %) sur 7j."""
    today = date_cls.fromisoformat(_today_mtl())
    cutoff = (today - timedelta(days=7)).isoformat()
    recent = [e for e in nutr_entries if e.get("date", "") >= cutoff and e.get("date", "") <= today.isoformat()]
    if not recent or target_protein <= 0:
        return 50  # neutre si pas de données

    prot_scores = []
    cal_scores  = []
    for e in recent:
        p = float(e.get("proteines") or 0)
        c = float(e.get("calories")  or 0)
        if target_protein > 0:
            prot_scores.append(min(1.0, p / target_protein))
        if target_cal > 0:
            # pénalise sur-consommation (>110%) et sous-consommation
            ratio = c / target_cal
            cal_scores.append(1.0 - min(1.0, abs(ratio - 1.0)))

    p_avg = sum(prot_scores) / len(prot_scores) if prot_scores else 0.5
    c_avg = sum(cal_scores)  / len(cal_scores)  if cal_scores  else 0.5
    return round((p_avg * 0.6 + c_avg * 0.4) * 100)


def _stress_pillar(recovery_log: list) -> int:
    """0-100 : HRV score + inverse soreness + sleep quality sur 7j."""
    today = date_cls.fromisoformat(_today_mtl())
    cutoff = (today - timedelta(days=7)).isoformat()
    recent = [r for r in recovery_log if (r.get("date") or "") >= cutoff]
    if not recent:
        return 50

    scores = []
    for r in recent:
        hrv       = r.get("hrv")
        soreness  = r.get("soreness")
        sleep_q   = r.get("sleep_quality")  # 1-10

        sub = []
        if hrv and hrv > 0:
            # HRV normalisé : 20 ms = 0, 80 ms = 100
            sub.append(min(100, max(0, int((hrv - 20) / 60 * 100))))
        if soreness and soreness > 0:
            # soreness 1-10 → inversé (1 = bien, 10 = mal)
            sub.append(max(0, 100 - int((soreness - 1) / 9 * 100)))
        if sleep_q and sleep_q > 0:
            # sleep_quality 1-10 → 0-100
            sub.append(min(100, int((sleep_q - 1) / 9 * 100)))

        if sub:
            scores.append(sum(sub) / len(sub))

    return round(sum(scores) / len(scores)) if scores else 50


def _training_pillar(sessions: list) -> int:
    """0-100 : fréquence (3-5 séances/sem = optimal) + RPE moyen."""
    today = date_cls.fromisoformat(_today_mtl())
    cutoff = (today - timedelta(days=7)).isoformat()
    recent = [s for s in sessions if (s.get("date") or "") >= cutoff and s.get("completed")]

    count = len(recent)
    # fréquence : <2 = faible, 3-5 = optimal, >6 = surcharge
    if count == 0:
        freq_score = 0
    elif count <= 2:
        freq_score = count / 3 * 70
    elif count <= 5:
        freq_score = 70 + (count - 2) / 3 * 30
    else:
        freq_score = max(40, 100 - (count - 5) * 15)

    rpes = [float(s["rpe"]) for s in recent if s.get("rpe") is not None]
    if rpes:
        avg_rpe = sum(rpes) / len(rpes)
        # RPE 6-8 = optimal ; <5 = sous-stimulation ; >9 = surcharge
        if avg_rpe < 5:
            rpe_score = avg_rpe / 5 * 60
        elif avg_rpe <= 8:
            rpe_score = 60 + (avg_rpe - 5) / 3 * 40
        else:
            rpe_score = max(30, 100 - (avg_rpe - 8) * 20)
        return round(freq_score * 0.6 + rpe_score * 0.4)

    return round(freq_score)


def _trend(score_now: int, score_prev: int) -> str:
    delta = score_now - score_prev
    if delta >= 5:
        return "up"
    if delta <= -5:
        return "down"
    return "stable"


def _insight(score: int, training: int, stress: int, nutrition: int) -> str:
    if score >= 75:
        return "Tes ressources corporelles sont bien rechargées — conditions optimales pour performer."
    if score >= 55:
        weakest = min([("entraînement", training), ("récupération", stress), ("nutrition", nutrition)],
                      key=lambda x: x[1])
        return f"Score solide. Levier principal à optimiser : {weakest[0]} ({weakest[1]}/100)."
    # score < 55
    if stress < 40:
        return "Récupération insuffisante — priorise le sommeil et réduis la charge cette semaine."
    if training < 40:
        return "Stimulation trop faible cette semaine — ajoute une séance pour maintenir l'adaptation."
    if nutrition < 40:
        return "Apports nutritionnels insuffisants — vérifie tes protéines et calories."
    return "Score faible sur plusieurs piliers — semaine de récupération recommandée."


@body_budget_bp.route("/api/body_budget")
def api_body_budget():
    import db as _db
    from nutrition import load_settings as load_nutrition_settings

    today     = _today_mtl()
    today_dt  = date_cls.fromisoformat(today)
    cutoff7   = (today_dt - timedelta(days=7)).isoformat()
    cutoff14  = (today_dt - timedelta(days=14)).isoformat()

    sessions     = _db.get_workout_sessions(limit=60) or []
    recovery_log = _db.get_recovery_logs(limit=30) or []
    nutr_settings = load_nutrition_settings() or {}
    nutr_entries  = _db.get_nutrition_daily_full(14)

    target_protein = float(nutr_settings.get("protein_target") or 0)
    target_cal     = float(nutr_settings.get("calorie_limit")  or 0)

    # ── Piliers semaine courante ─────────────────────────────────────────────
    training  = _training_pillar(sessions)
    stress    = _stress_pillar(recovery_log)
    nutrition = _nutrition_pillar(nutr_entries, target_protein, target_cal)
    score     = round(training * 0.4 + stress * 0.35 + nutrition * 0.25)

    # ── Piliers semaine précédente (pour tendance) ───────────────────────────
    sessions_prev  = [s for s in sessions     if cutoff14 <= (s.get("date") or "") < cutoff7]
    recovery_prev  = [r for r in recovery_log if cutoff14 <= (r.get("date") or "") < cutoff7]
    nutr_prev      = [e for e in nutr_entries if cutoff14 <= (e.get("date") or "") < cutoff7]

    training_p  = _training_pillar(sessions_prev)
    stress_p    = _stress_pillar(recovery_prev)
    nutrition_p = _nutrition_pillar(nutr_prev, target_protein, target_cal)
    score_prev  = round(training_p * 0.4 + stress_p * 0.35 + nutrition_p * 0.25)

    return jsonify({
        "score":       score,
        "trend":       _trend(score, score_prev),
        "insight":     _insight(score, training, stress, nutrition),
        "pillars": {
            "training":  training,
            "stress":    stress,
            "nutrition": nutrition,
        },
        "computed_at": today,
    })
