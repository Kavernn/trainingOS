from flask import Blueprint, jsonify, request
from datetime import datetime, timedelta
import logging

logger = logging.getLogger("trainingos")

analytics_bp = Blueprint("analytics", __name__)


@analytics_bp.route("/api/sync_status")
def api_sync_status():
    """Returns count of dirty (unsynced) entries in the local SQLite cache."""
    from db import _sqlite_all_dirty
    dirty = _sqlite_all_dirty()
    return jsonify({"dirty_count": len(dirty), "dirty_keys": list(dirty.keys())})


@analytics_bp.route("/api/deload_status")
def api_deload_status():
    """Returns deload analysis: stagnation, RPE fatigue, recommendation."""
    from weights import load_weights
    from deload import analyser_deload
    weights = load_weights()
    rapport = analyser_deload(weights)
    logger.info(
        "Deload status — recommande=%s stagnants=%d rpe_moyen=%s",
        rapport["recommande"],
        len(rapport["stagnants"]),
        rapport["fatigue_rpe"],
    )
    return jsonify(rapport)


@analytics_bp.route("/api/deload")
def api_deload():
    from weights import load_weights
    from deload import analyser_deload
    return jsonify(analyser_deload(load_weights()))


@analytics_bp.route("/api/apply_deload", methods=["POST"])
def api_apply_deload():
    """Override current_weight for each exercise in poids_deload dict."""
    try:
        from weights import load_weights, save_weights
        data         = request.get_json(silent=True) or {}
        poids_deload = data.get("poids_deload", {})
        if not poids_deload:
            return jsonify({"error": "poids_deload manquant"}), 400

        weights = load_weights()
        updated = []
        for exercise, new_weight in poids_deload.items():
            if exercise in weights:
                weights[exercise]["current_weight"] = float(new_weight)
                updated.append(exercise)
        save_weights(weights)
        return jsonify({"success": True, "updated": updated})
    except Exception:
        raise


@analytics_bp.route("/api/acwr")
def api_acwr():
    from acwr import calc_acwr
    return jsonify(calc_acwr())


@analytics_bp.route("/api/coach/morning_brief")
def api_morning_brief():
    from morning_brief import get_morning_brief
    return jsonify(get_morning_brief())


@analytics_bp.route("/api/peak_prediction")
def api_peak_prediction():
    """Prédit le LSS des 7 prochains jours via régression linéaire sur les 14 derniers."""
    from life_stress_engine import get_recent_life_stress_trend
    from datetime import date as date_cls, timedelta

    history = get_recent_life_stress_trend(14)   # index 0 = today
    scores  = [h["score"] for h in history if h.get("score") is not None]

    # Régression linéaire simple (méthode des moindres carrés)
    n = len(scores)
    if n >= 3:
        xs = list(range(n))
        mx = sum(xs) / n
        my = sum(scores) / n
        num = sum((x - mx) * (y - my) for x, y in zip(xs, scores))
        den = sum((x - mx) ** 2 for x in xs)
        slope = num / den if den != 0 else 0
    else:
        slope = 0

    last_score = scores[0] if scores else 65.0
    today = date_cls.today()

    def level(s):
        if s >= 65:   return "go"
        if s >= 45:   return "go_caution"
        if s >= 25:   return "reduce"
        return "defer"

    result = []
    peak_idx = None
    peak_val = -1
    for i in range(1, 8):
        # Projection : tendance linéaire + retour vers 70 (régression vers la moyenne)
        projected = last_score + slope * i + (70 - last_score) * 0.08 * i
        projected = max(0, min(100, projected))
        d = (today + timedelta(days=i)).isoformat()
        if projected > peak_val:
            peak_val = projected
            peak_idx = i - 1
        result.append({"date": d, "predicted_lss": round(projected, 1), "level": level(projected), "is_peak": False})

    if peak_idx is not None and result:
        result[peak_idx]["is_peak"] = True

    return jsonify({"days": result, "slope": round(slope, 3), "baseline": round(last_score, 1)})


@analytics_bp.route("/api/insights")
def api_insights():
    import db as _db
    from weights import load_weights

    weights  = load_weights()
    sessions_raw = _db.get_workout_sessions(limit=365)
    sessions = {}
    for s in sessions_raw:
        d = s.get("date")
        if not d: continue
        if s.get("completed") or s.get("rpe") is not None:
            sessions[str(d)] = s

    now      = datetime.now()
    insights = []

    def dstr(d): return d.strftime("%Y-%m-%d")

    # 1. FATIGUE RPE — avg 7j vs 30j
    s7  = [s["rpe"] for d, s in sessions.items() if d >= dstr(now - timedelta(days=7))  and s.get("rpe")]
    s30 = [s["rpe"] for d, s in sessions.items() if d >= dstr(now - timedelta(days=30)) and s.get("rpe")]
    if len(s7) >= 2 and len(s30) >= 5:
        avg7  = sum(s7)  / len(s7)
        avg30 = sum(s30) / len(s30)
        if avg7 > avg30 + 0.8:
            insights.append({
                "type": "fatigue", "level": "warning",
                "icon": "flame.fill", "title": "Fatigue en hausse",
                "message": f"RPE moyen {avg7:.1f}/10 cette semaine vs {avg30:.1f}/10 sur 30 jours. Envisage de réduire l'intensité."
            })

    # 2. STAGNATION — même poids 4+ séances consécutives
    for ex, data in weights.items():
        hist = [e for e in (data.get("history") or []) if e.get("weight") and e.get("date")]
        if len(hist) < 4: continue
        ws = [e["weight"] for e in hist[:4]]
        if max(ws) == min(ws) and ws[0] > 0:
            insights.append({
                "type": "stagnation", "level": "info",
                "icon": "chart.line.flattrend.xyaxis", "title": f"Plateau — {ex}",
                "message": f"Même poids depuis 4 séances. Essaie un schéma différent ou une surcharge progressive."
            })
            break

    # 3. PR PROCHE — current dans les 5% du PR historique
    if not any(i["type"] == "stagnation" for i in insights):
        for ex, data in weights.items():
            hist = [e for e in (data.get("history") or []) if e.get("weight")]
            if len(hist) < 3: continue
            pr      = max(e["weight"] for e in hist)
            current = data.get("current_weight") or hist[0].get("weight", 0)
            if 0 < current < pr and current >= pr * 0.95:
                gap = round(pr - current, 1)
                insights.append({
                    "type": "pr_near", "level": "success",
                    "icon": "trophy.fill", "title": f"PR en vue — {ex}",
                    "message": f"Tu es à {gap} lbs de ton record ({pr:.0f} lbs). Pousse fort !"
                })
                break

    # 4. RÉGULARITÉ — 5+ séances sur 7 jours (si pas de fatigue)
    sessions_7d = sum(1 for d in sessions if d >= dstr(now - timedelta(days=7)))
    if sessions_7d >= 5 and not any(i["type"] == "fatigue" for i in insights):
        insights.append({
            "type": "consistency", "level": "success",
            "icon": "checkmark.seal.fill", "title": "Excellente régularité",
            "message": f"{sessions_7d} séances sur les 7 derniers jours. Continue !"
        })

    # 5. MILESTONE STREAK — à 1 séance du prochain palier
    streak = 0
    for i in range(365):
        d = dstr(now - timedelta(days=i))
        if d in sessions: streak += 1
        elif i > 0: break
    for m in [7, 14, 21, 30, 50, 75, 100]:
        if streak == m - 1:
            insights.append({
                "type": "milestone", "level": "success",
                "icon": "star.fill", "title": f"Demain : streak de {m} jours !",
                "message": f"Plus qu'une séance pour atteindre {m} jours consécutifs."
            })
            break

    return jsonify({"insights": insights[:3]})


@analytics_bp.route("/api/proactive_alerts")
def api_proactive_alerts():
    from alerts import get_all_alerts
    return jsonify({"alerts": get_all_alerts()})


@analytics_bp.route("/api/insights/correlations")
def api_insights_correlations():
    try:
        days = int(request.args.get("days", 60))
    except ValueError:
        days = 60
    from correlations import get_correlations
    return jsonify(get_correlations(days))


@analytics_bp.route("/api/stats_data")
def api_stats_data():
    from weights import load_weights
    from body_weight import load_body_weight
    from nutrition import (load_settings as load_nutrition_settings, get_recent_days)
    from inventory import load_inventory
    from utils import _calc_muscle_stats, _calc_weekly_sets_per_muscle, MUSCLE_LANDMARKS
    import db as _db
    from utils import load_hiit_log_local

    weights      = load_weights()
    all_sessions = _db.get_workout_sessions(limit=500)
    sessions = {
        s["date"]: s
        for s in all_sessions
        if isinstance(s, dict) and (s.get("completed") or s.get("rpe") is not None)
    }
    hiit_log     = load_hiit_log_local()
    body_weight  = load_body_weight()
    recovery_log = _db.get_recovery_logs() or []
    nutr_settings = load_nutrition_settings()
    nutr_entries  = get_recent_days(30)
    inventory       = load_inventory() or {}
    muscle_stats    = _calc_muscle_stats(sessions, weights, inventory)
    weekly_sets     = _calc_weekly_sets_per_muscle(weights, inventory)
    inventory_types = {name: info.get("type") or "machine" for name, info in inventory.items()}

    # Landmark data: only for muscles the user actually trains
    tracked_muscles = set(muscle_stats.keys()) | set(weekly_sets.keys())
    muscle_landmarks = {
        muscle: {**MUSCLE_LANDMARKS[muscle], "weekly_sets": weekly_sets.get(muscle, 0)}
        for muscle in tracked_muscles
        if muscle in MUSCLE_LANDMARKS
    }

    from utils import get_current_week
    return jsonify({
        "weights":          weights,
        "sessions":         sessions,
        "hiit_log":         hiit_log,
        "body_weight":      body_weight,
        "recovery_log":     recovery_log,
        "nutrition_target": nutr_settings,
        "nutrition_days":   nutr_entries,
        "week":             get_current_week(),
        "muscle_stats":     muscle_stats,
        "inventory_types":  inventory_types,
        "muscle_landmarks": muscle_landmarks,
    })


# MARK: - Smart Day Recommendation

@analytics_bp.route("/api/smart_day")
def api_smart_day():
    """
    Returns a session recommendation for today based on:
    - Recovery score (from today's recovery log)
    - HRV trend
    - Days since last session of each type
    - ACWR load ratio
    """
    from health_data import get_daily_health_summary
    from acwr import calc_acwr
    import db as _db
    from datetime import date as date_cls, timedelta

    today = date_cls.today().isoformat()
    summary      = get_daily_health_summary(today)
    recovery     = summary.get("recovery_score")      # 0–10
    hrv          = summary.get("hrv")
    resting_hr   = summary.get("resting_heart_rate")

    # Recent sessions — determine days since each session type
    sessions_raw = _db.get_workout_sessions(limit=30)
    sessions_by_type: dict[str, int] = {}  # session_type → days since last
    for s in sessions_raw:
        stype = s.get("session_type") or "morning"
        sname = s.get("session_name") or stype
        d = s.get("date")
        if not d:
            continue
        try:
            delta = (date_cls.today() - date_cls.fromisoformat(str(d))).days
        except ValueError:
            continue
        if sname not in sessions_by_type or delta < sessions_by_type[sname]:
            sessions_by_type[sname] = delta

    days_rest = min(sessions_by_type.values(), default=7)  # days since any session

    # ACWR — load ratio
    try:
        acwr_data = calc_acwr()
        acwr = acwr_data.get("acwr")
    except Exception:
        acwr = None

    # Decision logic
    if recovery is not None:
        score = recovery  # 0–10
    else:
        score = 5.0  # neutral default

    # Boost/reduce based on HRV if available
    if hrv is not None:
        if hrv >= 60:   score = min(10, score + 1)
        elif hrv < 30:  score = max(0,  score - 1.5)

    # Penalise high ACWR
    if acwr is not None and acwr > 1.5:
        score = max(0, score - 2)

    # Build recommendation
    if score >= 7:
        intensity  = "normale"
        confidence = round(min(0.95, 0.70 + score / 100), 2)
        if days_rest == 0:
            reason = "Récupération optimale — séance normale recommandée."
        else:
            reason = f"Récupération optimale ({score:.1f}/10) — c'est le moment de pousser."
        cta = "💪 Entraîne-toi"
    elif score >= 5:
        intensity  = "réduite"
        confidence = round(min(0.85, 0.55 + score / 100), 2)
        reason = f"Récupération modérée ({score:.1f}/10) — privilégie un volume réduit ou technique."
        cta = "🟡 Volume réduit"
    elif days_rest >= 3:
        intensity  = "normale"
        confidence = 0.60
        reason = f"Récupération faible ({score:.1f}/10) mais {days_rest} jours sans séance — écoute ton corps."
        cta = "⚠️ Léger ou repos"
    else:
        intensity  = "repos"
        confidence = round(min(0.90, 0.65 + (10 - score) / 20), 2)
        reason = f"Récupération insuffisante ({score:.1f}/10) — repos actif ou mobilité."
        cta = "😴 Repos recommandé"

    # Suggest least-recently-done session type
    suggested_session: str | None = None
    if intensity != "repos" and sessions_by_type:
        suggested_session = max(sessions_by_type, key=lambda k: sessions_by_type[k])

    return jsonify({
        "intensity":          intensity,
        "confidence":         confidence,
        "reason":             reason,
        "cta":                cta,
        "recovery_score":     recovery,
        "hrv":                hrv,
        "resting_hr":         resting_hr,
        "acwr":               acwr,
        "days_since_session": days_rest,
        "suggested_session":  suggested_session,
    })


# MARK: - Weekly Report

@analytics_bp.route("/api/weekly_report")
def api_weekly_report():
    """Aggregated summary for the last 7 days: volume, PRs, recovery, nutrition, sleep."""
    from health_data import get_weekly_health_summary
    from weights import load_weights
    from nutrition import get_recent_days
    import db as _db
    from datetime import date as date_cls, timedelta

    today = date_cls.today()
    week_start = (today - timedelta(days=6)).isoformat()

    # ── Sessions (muscu) ─────────────────────────────────────────────────────
    sessions_raw = _db.get_workout_sessions(limit=30)
    week_sessions = [
        s for s in sessions_raw
        if s.get("date") and str(s["date"]) >= week_start
        and (s.get("completed") or s.get("rpe") is not None)
    ]
    session_count = len(week_sessions)

    # ── Volume & PRs ─────────────────────────────────────────────────────────
    def _total_reps(reps_str: str) -> int:
        parts = [p.strip() for p in str(reps_str).split(",") if p.strip().isdigit()]
        return sum(int(p) for p in parts)

    def _avg_reps(reps_str: str) -> float:
        parts = [int(p.strip()) for p in str(reps_str).split(",") if p.strip().isdigit()]
        return sum(parts) / len(parts) if parts else 1.0

    weights   = load_weights()
    total_vol = 0.0
    pr_count  = 0
    top_exercise: str | None = None
    top_vol = 0.0
    for name, data in weights.items():
        hist = data.get("history") or []
        week_logs = [e for e in hist if e.get("date") and str(e["date"]) >= week_start]
        if not week_logs:
            continue
        ex_vol = sum(
            (e.get("weight") or 0) * _total_reps(e.get("reps") or "")
            for e in week_logs
        )
        total_vol += ex_vol
        if ex_vol > top_vol:
            top_vol = ex_vol
            top_exercise = name
        # PR: this week's max 1RM > all-time prior max
        week_ones = [
            e["weight"] * (1 + _avg_reps(e.get("reps") or "1") / 30)
            for e in week_logs if e.get("weight")
        ]
        all_ones = [
            e["weight"] * (1 + _avg_reps(e.get("reps") or "1") / 30)
            for e in hist if e.get("weight") and str(e.get("date", "")) < week_start
        ]
        if week_ones and (not all_ones or max(week_ones) > max(all_ones)):
            pr_count += 1

    # ── Health KPIs ──────────────────────────────────────────────────────────
    health_week = get_weekly_health_summary(days=7)
    sleep_vals   = [d["sleep_duration"]    for d in health_week if d.get("sleep_duration")]
    recovery_vals= [d["recovery_score"]    for d in health_week if d.get("recovery_score")]
    steps_vals   = [d["steps"]             for d in health_week if d.get("steps")]
    hrv_vals     = [d["hrv"]               for d in health_week if d.get("hrv")]

    avg_sleep    = round(sum(sleep_vals)    / len(sleep_vals),    1) if sleep_vals    else None
    avg_recovery = round(sum(recovery_vals) / len(recovery_vals), 1) if recovery_vals else None
    avg_steps    = int(sum(steps_vals)      / len(steps_vals))        if steps_vals    else None
    avg_hrv      = round(sum(hrv_vals)      / len(hrv_vals),      1) if hrv_vals      else None

    # ── Nutrition compliance ──────────────────────────────────────────────────
    nutr_days = get_recent_days(7)
    from nutrition import load_settings as load_nutrition_settings
    nutr_settings = load_nutrition_settings() or {}
    cal_target = nutr_settings.get("calorie_limit") or 0
    if cal_target > 0 and nutr_days:
        compliant = sum(
            1 for d in nutr_days
            if d.get("total_calories") and abs(d["total_calories"] - cal_target) / cal_target <= 0.10
        )
        nutrition_compliance = round(compliant / len(nutr_days) * 100)
    else:
        nutrition_compliance = None

    return jsonify({
        "week_start":            week_start,
        "week_end":              today.isoformat(),
        "session_count":         session_count,
        "total_volume_lbs":      round(total_vol),
        "pr_count":              pr_count,
        "top_exercise":          top_exercise,
        "avg_recovery_score":    avg_recovery,
        "avg_sleep_hours":       avg_sleep,
        "avg_steps":             avg_steps,
        "avg_hrv":               avg_hrv,
        "nutrition_compliance":  nutrition_compliance,
    })
