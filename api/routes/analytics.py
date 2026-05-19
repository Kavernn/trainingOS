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
    import db as _db
    brief = get_morning_brief()

    # Enhance the hardcoded Python message with a Claude-generated personalized one
    try:
        import os
        import anthropic as _anthropic
        api_key = os.environ.get("ANTHROPIC_API_KEY", "")
        if api_key and brief.get("lss") is not None:
            ctx_parts = [
                f"LSS (Life Stress Score): {brief['lss']:.0f}/100",
                f"Séance prévue: {brief['session_today']} (intensité: {brief['session_intensity']})",
                f"Recommandation système: {brief['recommendation']}",
            ]
            active_flags = [k for k, v in (brief.get("flags") or {}).items() if v]
            if active_flags:
                ctx_parts.append(f"Alertes: {', '.join(active_flags)}")
            if brief.get("adjustments"):
                ctx_parts.append(f"Ajustements suggérés: {', '.join(brief['adjustments'])}")
            try:
                sessions = _db.get_workout_sessions(limit=3)
                if sessions:
                    last = sessions[0]
                    ctx_parts.append(
                        f"Dernière séance: {last.get('date','?')} — "
                        f"{last.get('session_name') or last.get('session_type','?')} "
                        f"RPE {last.get('rpe','?')}/10"
                    )
            except Exception:
                pass
            try:
                nutrition = _db.get_nutrition_entries_recent(n=1)
                if nutrition:
                    n = nutrition[0]
                    ctx_parts.append(
                        f"Nutrition hier: {n.get('calories','?')} kcal, "
                        f"{n.get('proteines','?')}g protéines"
                    )
            except Exception:
                pass

            client = _anthropic.Anthropic(api_key=api_key)
            msg = client.messages.create(
                model="claude-haiku-4-5-20251001",
                max_tokens=80,
                system=(
                    "Tu es un coach sportif. En une seule phrase (max 20 mots), "
                    "génère un message d'encouragement matinal personnalisé basé sur les données. "
                    "Cite UN chiffre concret (LSS, RPE, ou intensité). "
                    "Style direct, énergisant. Tutoiement. Français uniquement. "
                    "Pas de ponctuation finale superflue."
                ),
                messages=[{"role": "user", "content": "\n".join(ctx_parts)}],
            )
            brief["message"] = msg.content[0].text.strip()
    except Exception:
        pass  # fallback to Python-generated message

    return jsonify(brief)


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
    from nutrition import (load_settings as load_nutrition_settings)
    from inventory import load_inventory
    from utils import _calc_muscle_stats, _calc_weekly_sets_per_muscle, MUSCLE_LANDMARKS
    import db as _db
    from utils import load_hiit_log

    weights      = load_weights()
    all_sessions = _db.get_workout_sessions(limit=500)
    sessions = {
        s["date"]: s
        for s in all_sessions
        if isinstance(s, dict) and (s.get("completed") or s.get("rpe") is not None)
    }
    hiit_log     = load_hiit_log()
    body_weight  = load_body_weight()
    recovery_log = _db.get_recovery_logs() or []
    nutr_settings = load_nutrition_settings()
    # get_nutrition_daily_full inclut glucides + lipides (nécessaires pour MacrosBreakdownView)
    nutr_entries  = _db.get_nutrition_daily_full(180)  # 6M max — filtrage par période côté Swift
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
    weekly_tonnage       = _db.get_weekly_tonnage(8)
    pattern_volume       = _db.get_pattern_volume(28)
    programme_compliance = _db.get_programme_compliance(8)
    one_rm_trend         = _db.get_one_rm_trend(84)
    hiit_completion      = _db.get_hiit_completion(8)
    macros_by_day_type   = _db.get_macros_by_day_type(60)
    protein_weight_ratio = _db.get_protein_weight_ratio(60)

    return jsonify({
        "weights":               weights,
        "sessions":              sessions,
        "hiit_log":              hiit_log,
        "body_weight":           body_weight,
        "recovery_log":          recovery_log,
        "nutrition_target":      nutr_settings,
        "nutrition_days":        nutr_entries,
        "week":                  get_current_week(),
        "muscle_stats":          muscle_stats,
        "inventory_types":       inventory_types,
        "muscle_landmarks":      muscle_landmarks,
        "weekly_tonnage":        weekly_tonnage,
        "pattern_volume":        pattern_volume,
        "programme_compliance":  programme_compliance,
        "one_rm_trend":          one_rm_trend,
        "hiit_completion":       hiit_completion,
        "macros_by_day_type":    macros_by_day_type,
        "protein_weight_ratio":  protein_weight_ratio,
    })


# MARK: - Stats Wellness

@analytics_bp.route("/api/stats_wellness")
def api_stats_wellness():
    """Wellness correlations and mental health data for the Stats Bien-être tab."""
    import db as _db
    return jsonify({
        "mood_trend":              _db.get_mood_trend(60),
        "pss_history":             _db.get_pss_records(limit=20),
        "self_care_streaks":       _db.get_self_care_streaks_computed(),
        "self_care_compliance":    _db.get_self_care_compliance(30),
        "soreness_volume_scatter": _db.get_soreness_volume_scatter(),
        "sleep_volume_scatter":    _db.get_sleep_volume_scatter(),
        "rpe_progression":         _db.get_rpe_progression(),
        "rir_by_exercise":         _db.get_rir_by_exercise(),
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
    prs_list: list[str] = []
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
            prs_list.append(name)

    rpe_vals = [s["rpe"] for s in week_sessions if s.get("rpe") is not None]
    avg_rpe = round(sum(rpe_vals) / len(rpe_vals), 1) if rpe_vals else None

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

    # Weekly score (0–100)
    pts = min(int(session_count / 5 * 30), 30)
    if avg_sleep is not None:
        pts += 25 if avg_sleep >= 7.5 else 20 if avg_sleep >= 7 else 15 if avg_sleep >= 6.5 else 8
    else:
        pts += 12
    if nutrition_compliance is not None:
        pts += 25 if nutrition_compliance >= 80 else 18 if nutrition_compliance >= 60 else 12 if nutrition_compliance >= 40 else 6
    else:
        pts += 12
    if avg_recovery is not None:
        pts += 20 if avg_recovery >= 7 else 15 if avg_recovery >= 5 else 10 if avg_recovery >= 3 else 5
    else:
        pts += 10
    weekly_score = min(pts, 100)

    # Focus tips for next week
    focus: list[str] = []
    if avg_sleep is not None and avg_sleep < 7:
        focus.append(f"Améliore ton sommeil (moy. {avg_sleep}h) — vise 7h+")
    if nutrition_compliance is not None and nutrition_compliance < 70:
        focus.append(f"Compliance nutrition à {nutrition_compliance}% — vise 80%+")
    if session_count < 3:
        focus.append("Vise au moins 3 séances cette semaine")
    if avg_rpe is not None and avg_rpe > 8.5:
        focus.append("RPE élevé — inclure une journée de récupération active")
    if pr_count > 0:
        focus.append(f"{pr_count} PR cette semaine — consolide avant d'augmenter les charges")
    if not focus:
        focus.append("Continue sur ta lancée — belle semaine !")

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
        "avg_rpe":               avg_rpe,
        "weekly_score":          weekly_score,
        "prs":                   prs_list,
        "focus_next_week":       focus,
        "push_pull_ratio":       _compute_push_pull_ratio(week_start),
    })


def _compute_push_pull_ratio(since_date: str) -> dict:
    """Compute push vs pull volume ratio using inventory pattern tags (28 days)."""
    import db as _db
    try:
        pv = _db.get_pattern_volume(28)
        push_vol = float(pv.get("push",  0))
        pull_vol = float(pv.get("pull",  0))
        legs_vol = float(pv.get("squat", 0)) + float(pv.get("hinge", 0))

        ratio = round(push_vol / pull_vol, 2) if pull_vol > 0 else None
        imbalance = None
        if ratio is not None:
            if ratio > 1.3:
                imbalance = "push_dominant"
            elif ratio < 0.77:
                imbalance = "pull_dominant"
        return {
            "push_volume": round(push_vol),
            "pull_volume": round(pull_vol),
            "legs_volume": round(legs_vol),
            "ratio":       ratio,
            "imbalance":   imbalance,
        }
    except Exception:
        return {}


def _total_reps_str(reps: str) -> float:
    parts = [p.strip() for p in str(reps).split(",") if p.strip().isdigit()]
    if parts:
        return sum(int(p) for p in parts)
    try:
        return float(reps)
    except Exception:
        return 1.0


# MARK: - Pain Journal

@analytics_bp.route("/api/pain_journal")
def api_pain_journal():
    """Return exercise pain zones history for the injury journal."""
    import db as _db
    entries = _db.get_pain_journal(limit=200)
    # Aggregate by exercise — most recent occurrence + total count
    by_exercise: dict = {}
    for e in entries:
        ex = e.get("exercise") or "Inconnu"
        by_exercise.setdefault(ex, {"exercise": ex, "count": 0, "zones": [], "last_date": None, "entries": []})
        by_exercise[ex]["count"] += 1
        zone = e.get("pain_zone")
        if zone and zone not in by_exercise[ex]["zones"]:
            by_exercise[ex]["zones"].append(zone)
        if e.get("date") and (by_exercise[ex]["last_date"] is None or str(e["date"]) > str(by_exercise[ex]["last_date"])):
            by_exercise[ex]["last_date"] = e.get("date")
        by_exercise[ex]["entries"].append(e)
    result = sorted(by_exercise.values(), key=lambda x: (x["last_date"] or ""), reverse=True)
    return jsonify({"entries": entries, "by_exercise": result})


# MARK: - Body Composition Projection

@analytics_bp.route("/api/body_projection")
def api_body_projection():
    """Linear regression on body_fat_pct and lean mass → projected goal arrival dates."""
    import db as _db
    import math
    from datetime import date as date_cls

    bw_logs = _db.get_body_weight_logs(limit=200)
    smart_goals = _db.get_smart_goals()

    # Build timeline entries with body fat
    bf_series = [
        {"date": str(e.get("date", ""))[:10], "value": float(e["body_fat"])}
        for e in bw_logs
        if e.get("body_fat") is not None
    ]
    lean_series = []
    for e in bw_logs:
        if e.get("poids") is not None and e.get("body_fat") is not None:
            poids = float(e["poids"])
            bf = float(e["body_fat"])
            lean = poids * (1 - bf / 100)
            lean_series.append({"date": str(e.get("date", ""))[:10], "value": round(lean, 1)})
    weight_series = [
        {"date": str(e.get("date", ""))[:10], "value": float(e["poids"])}
        for e in bw_logs
        if e.get("poids") is not None
    ]

    def _linreg(series: list) -> dict | None:
        """Return slope (per day), intercept, r2, latest_value, days_to_goal."""
        series = sorted(series, key=lambda x: x["date"])
        if len(series) < 5:
            return None
        today = date_cls.today()
        def _days(d: str) -> int:
            try:
                return (date_cls.fromisoformat(d) - date_cls(2026, 1, 1)).days
            except Exception:
                return 0
        xs = [_days(p["date"]) for p in series]
        ys = [p["value"] for p in series]
        n = len(xs)
        mx = sum(xs) / n
        my = sum(ys) / n
        num = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
        den = sum((x - mx) ** 2 for x in xs)
        if abs(den) < 1e-9:
            return None
        slope = num / den
        intercept = my - slope * mx
        today_x = _days(today.isoformat())
        predicted_today = slope * today_x + intercept
        # R²
        ss_res = sum((y - (slope * x + intercept)) ** 2 for x, y in zip(xs, ys))
        ss_tot = sum((y - my) ** 2 for y in ys)
        r2 = round(1 - ss_res / ss_tot, 3) if ss_tot > 1e-9 else None
        return {
            "slope_per_day": round(slope, 4),
            "current_value": round(predicted_today, 1),
            "r2":            r2,
        }

    def _days_to_target(reg: dict, target: float, lower_is_better: bool) -> str | None:
        slope = reg["slope_per_day"]
        cur   = reg["current_value"]
        if abs(slope) < 1e-6:
            return None
        if lower_is_better and slope >= 0:
            return None
        if not lower_is_better and slope <= 0:
            return None
        days_needed = (target - cur) / slope
        if days_needed < 0:
            return None
        arrival = (date_cls.today() + timedelta(days=int(days_needed))).isoformat()
        return arrival

    bf_reg     = _linreg(bf_series)
    lean_reg   = _linreg(lean_series)
    weight_reg = _linreg(weight_series)

    projections = []
    for goal in smart_goals:
        gtype  = goal.get("type")
        target = goal.get("target_value")
        if gtype not in ("body_fat", "lean_mass") or target is None:
            continue
        if gtype == "body_fat" and bf_reg:
            arrival = _days_to_target(bf_reg, float(target), lower_is_better=True)
            projections.append({
                "goal_type":     gtype,
                "target":        target,
                "current":       bf_reg["current_value"],
                "slope_per_week": round(bf_reg["slope_per_day"] * 7, 3),
                "r2":            bf_reg["r2"],
                "projected_date": arrival,
            })
        if gtype == "lean_mass" and lean_reg:
            arrival = _days_to_target(lean_reg, float(target), lower_is_better=False)
            projections.append({
                "goal_type":     gtype,
                "target":        target,
                "current":       lean_reg["current_value"],
                "slope_per_week": round(lean_reg["slope_per_day"] * 7, 3),
                "r2":            lean_reg["r2"],
                "projected_date": arrival,
            })

    return jsonify({
        "body_fat":    bf_reg,
        "lean_mass":   lean_reg,
        "body_weight": weight_reg,
        "projections": projections,
        "bf_series":   bf_series[-30:] if bf_series else [],
        "lean_series": lean_series[-30:] if lean_series else [],
    })


# MARK: - HRV Baseline

@analytics_bp.route("/api/hrv_baseline")
def api_hrv_baseline():
    """28-day rolling HRV baseline + rest flag if today's HRV is significantly below."""
    import db as _db
    from datetime import date as date_cls

    rec_log = _db.get_recovery_logs(limit=60)
    today   = date_cls.today().isoformat()

    hrv_vals = []
    today_hrv = None
    for e in rec_log:
        hrv = e.get("hrv")
        d   = str(e.get("date", ""))[:10]
        if hrv is None:
            continue
        if d == today:
            today_hrv = float(hrv)
        elif d < today:
            hrv_vals.append(float(hrv))

    hrv_vals_28d = hrv_vals[:28]
    if not hrv_vals_28d:
        return jsonify({"baseline": None, "today_hrv": today_hrv, "flag_rest": False, "data_points": 0})

    baseline = round(sum(hrv_vals_28d) / len(hrv_vals_28d), 1)
    sd = (sum((v - baseline) ** 2 for v in hrv_vals_28d) / len(hrv_vals_28d)) ** 0.5

    flag_rest = False
    deviation = None
    if today_hrv is not None:
        deviation = round(today_hrv - baseline, 1)
        flag_rest = today_hrv < baseline - sd  # 1 SD below baseline

    return jsonify({
        "baseline":    baseline,
        "sd":          round(sd, 1),
        "today_hrv":   today_hrv,
        "deviation":   deviation,
        "flag_rest":   flag_rest,
        "data_points": len(hrv_vals_28d),
        "message":     (
            f"HRV aujourd'hui ({today_hrv}) est {abs(deviation):.0f} ms sous la baseline ({baseline}) — repos recommandé."
            if flag_rest and deviation is not None else None
        ),
    })


# MARK: - Overtraining Risk

@analytics_bp.route("/api/overtraining_risk")
def api_overtraining_risk():
    """Composite overtraining risk score from RPE trend, HRV drop, mood dip, performance drop."""
    import db as _db
    from datetime import date as date_cls

    today  = date_cls.today().isoformat()
    risk   = 0
    flags  = []
    detail = {}

    # 1. RPE trend (7j vs 21j)
    sessions_raw = _db.get_workout_sessions(limit=30)
    rpe_7  = [s["rpe"] for s in sessions_raw if s.get("rpe") and str(s.get("date","")) >= (date_cls.today() - timedelta(days=7)).isoformat()]
    rpe_21 = [s["rpe"] for s in sessions_raw if s.get("rpe") and str(s.get("date","")) >= (date_cls.today() - timedelta(days=21)).isoformat()]
    if len(rpe_7) >= 2 and len(rpe_21) >= 3:
        avg7  = sum(rpe_7)  / len(rpe_7)
        avg21 = sum(rpe_21) / len(rpe_21)
        detail["rpe_avg_7d"]  = round(avg7,  1)
        detail["rpe_avg_21d"] = round(avg21, 1)
        if avg7 > avg21 + 1.0:
            risk += 2
            flags.append("RPE élevé cette semaine")
        elif avg7 > avg21 + 0.5:
            risk += 1

    # 2. HRV drop (today vs 28d baseline)
    hrv_baseline_resp = api_hrv_baseline().get_json()
    if hrv_baseline_resp.get("flag_rest"):
        risk += 2
        flags.append(f"HRV sous baseline ({hrv_baseline_resp.get('today_hrv')} vs {hrv_baseline_resp.get('baseline')})")
    detail["hrv_flag"] = hrv_baseline_resp.get("flag_rest")

    # 3. Mood dip (last 3 days avg < 5/10)
    mood_logs = _db.get_mood_logs(days=7)
    recent_moods = [m["score"] for m in mood_logs[:3] if m.get("score") is not None]
    if recent_moods:
        avg_mood = sum(recent_moods) / len(recent_moods)
        detail["avg_mood_3d"] = round(avg_mood, 1)
        if avg_mood < 5:
            risk += 2
            flags.append(f"Humeur basse (moy. {avg_mood:.1f}/10)")
        elif avg_mood < 6.5:
            risk += 1

    # 4. Recovery score (today)
    rec_log = _db.get_recovery_logs(limit=5)
    today_rec = next((e for e in rec_log if str(e.get("date",""))[:10] == today), None)
    if today_rec:
        from health_data import compute_recovery_score
        rec_score = compute_recovery_score(today_rec)
        detail["recovery_score"] = rec_score
        if rec_score is not None:
            if rec_score < 4:
                risk += 2
                flags.append(f"Récupération faible ({rec_score}/10)")
            elif rec_score < 6:
                risk += 1

    # Risk level
    if risk >= 5:
        level = "high"
        recommendation = "Repos obligatoire ou séance mobilité seulement."
    elif risk >= 3:
        level = "moderate"
        recommendation = "Réduis le volume de 30-40%. Priorité à la qualité."
    else:
        level = "low"
        recommendation = "Entraîne-toi normalement."

    return jsonify({
        "risk_score":     risk,
        "level":          level,
        "flags":          flags,
        "recommendation": recommendation,
        "detail":         detail,
    })


# MARK: - 1RM Programming Table

@analytics_bp.route("/api/one_rm_programming")
def api_one_rm_programming():
    """Return estimated 1RM and % programming table for main compound lifts."""
    from weights import load_weights
    import db as _db

    weights  = load_weights()
    compound_categories = {"chest", "back", "legs", "shoulders", "compound_push", "compound_pull", "compound"}

    result = []
    for name, data in weights.items():
        ex_info = _db.get_exercise_info(name) or {}
        cat = (ex_info.get("category") or "").lower()
        load_profile = (ex_info.get("load_profile") or "").lower()

        # Only main compounds
        is_compound = (
            "compound" in load_profile
            or cat in compound_categories
            or any(k in name.lower() for k in ("squat", "deadlift", "bench", "press", "row", "pull"))
        )
        if not is_compound:
            continue

        hist = [e for e in (data.get("history") or []) if e.get("weight")]
        if len(hist) < 2:
            continue

        # Estimate 1RM from best recent set (Epley formula): 1RM = w * (1 + r/30)
        best_1rm = 0.0
        for entry in hist[:10]:  # last 10 sessions
            w = entry.get("weight", 0)
            reps_str = entry.get("reps", "") or ""
            reps_list = [int(p.strip()) for p in reps_str.split(",") if p.strip().isdigit()]
            r = (sum(reps_list) / len(reps_list)) if reps_list else 1.0
            estimated = w * (1 + r / 30)
            if estimated > best_1rm:
                best_1rm = estimated

        if best_1rm < 10:
            continue

        percentages = [50, 60, 65, 70, 75, 80, 85, 90, 95]
        table = [{"pct": p, "weight": round(best_1rm * p / 100 / 2.5) * 2.5} for p in percentages]

        result.append({
            "exercise":    name,
            "estimated_1rm": round(best_1rm, 1),
            "current_weight": data.get("current_weight"),
            "pct_of_1rm": round(data.get("current_weight", 0) / best_1rm * 100, 1) if best_1rm > 0 else None,
            "table":       table,
        })

    result.sort(key=lambda x: x["estimated_1rm"], reverse=True)
    return jsonify({"exercises": result[:12]})


# MARK: - Macro Gap + Meal Suggestions

@analytics_bp.route("/api/macro_gap")
def api_macro_gap():
    """Return today's macro deficit and meal suggestions from food catalog."""
    from nutrition import get_recent_days, load_settings as load_nutrition_settings
    import db as _db
    from datetime import date as date_cls

    today    = date_cls.today().isoformat()
    settings = load_nutrition_settings() or {}
    days     = get_recent_days(1)
    today_data = days[0] if days else {}

    target_cal  = settings.get("calorie_limit")  or 2500
    target_prot = settings.get("protein_target")  or 180
    target_carb = settings.get("glucides_target") or 250
    target_fat  = settings.get("lipides_target")  or 80

    actual_cal  = today_data.get("total_calories", 0) or 0
    actual_prot = today_data.get("total_protein",  0) or 0
    actual_carb = today_data.get("total_carbs",    0) or 0
    actual_fat  = today_data.get("total_fat",      0) or 0

    gap_cal  = max(0, target_cal  - actual_cal)
    gap_prot = max(0, target_prot - actual_prot)
    gap_carb = max(0, target_carb - actual_carb)
    gap_fat  = max(0, target_fat  - actual_fat)

    # Suggest food items that best fill the primary gap
    catalog = _db.get_food_catalog() or []
    suggestions = []
    primary_gap = "protein" if gap_prot > 20 else "carbs" if gap_carb > 30 else "calories"
    for item in catalog:
        prot = float(item.get("proteines_per_100g") or 0)
        carb = float(item.get("glucides_per_100g")  or 0)
        cal  = float(item.get("calories_per_100g")  or 0)
        if primary_gap == "protein" and prot >= 15:
            suggestions.append({"name": item.get("name"), "protein_per_100g": prot, "calories_per_100g": cal})
        elif primary_gap == "carbs" and carb >= 20 and prot >= 5:
            suggestions.append({"name": item.get("name"), "carbs_per_100g": carb, "calories_per_100g": cal})
        elif primary_gap == "calories":
            suggestions.append({"name": item.get("name"), "calories_per_100g": cal})

    sort_key = "protein_per_100g" if primary_gap == "protein" else "carbs_per_100g" if primary_gap == "carbs" else "calories_per_100g"
    suggestions.sort(key=lambda x: x.get(sort_key, 0), reverse=True)

    # Meal templates
    templates = _db.get_meal_templates() or []
    template_suggestions = []
    for t in templates:
        if primary_gap == "protein" and float(t.get("total_protein") or 0) >= 25:
            template_suggestions.append(t)
        elif primary_gap == "carbs" and float(t.get("total_carbs") or 0) >= 40:
            template_suggestions.append(t)
        elif primary_gap == "calories" and float(t.get("total_calories") or 0) >= 300:
            template_suggestions.append(t)

    return jsonify({
        "date":         today,
        "targets":      {"calories": target_cal, "protein": target_prot, "carbs": target_carb, "fat": target_fat},
        "actual":       {"calories": actual_cal,  "protein": actual_prot, "carbs": actual_carb,  "fat": actual_fat},
        "gaps":         {"calories": gap_cal, "protein": gap_prot, "carbs": gap_carb, "fat": gap_fat},
        "primary_gap":  primary_gap,
        "food_suggestions":     suggestions[:6],
        "template_suggestions": template_suggestions[:4],
    })


# MARK: - Mesocycle Status

@analytics_bp.route("/api/mesocycle_status")
def api_mesocycle_status():
    """Return current mesocycle phase based on training weeks since last deload."""
    from utils import get_current_week
    import db as _db

    current_week = get_current_week()

    # Detect last deload from sessions (session_name contains "Deload")
    sessions_raw = _db.get_workout_sessions(limit=60)
    last_deload_date = None
    for s in sessions_raw:
        sname = (s.get("session_name") or "").lower()
        if "deload" in sname or "décharge" in sname:
            d = str(s.get("date", ""))[:10]
            if last_deload_date is None or d > last_deload_date:
                last_deload_date = d

    # Weeks since last deload
    from datetime import date as date_cls
    if last_deload_date:
        weeks_since = (date_cls.today() - date_cls.fromisoformat(last_deload_date)).days // 7
    else:
        weeks_since = current_week % 8  # cycle by default

    # Determine phase (8-week mesocycle)
    week_in_cycle = weeks_since % 8
    if week_in_cycle <= 2:
        phase       = "accumulation"
        phase_label = "Accumulation"
        description = "Volume élevé, intensité modérée. Construis la base."
        icon        = "📈"
        rpe_target  = "7-8"
        vol_guidance = "Vise le MAV (volume maximum adaptable)."
    elif week_in_cycle <= 5:
        phase       = "intensification"
        phase_label = "Intensification"
        description = "Volume modéré, intensité élevée. Pousse les charges."
        icon        = "💪"
        rpe_target  = "8-9"
        vol_guidance = "Réduis les séries, augmente les charges."
    elif week_in_cycle == 6:
        phase       = "realization"
        phase_label = "Réalisation"
        description = "Volume bas, intensité maximale. Teste tes PRs."
        icon        = "🏆"
        rpe_target  = "9-10"
        vol_guidance = "Volume minimal, poids maximaux."
    else:
        phase       = "deload"
        phase_label = "Décharge"
        description = "Récupération active. Réduis volume et intensité de 40-50%."
        icon        = "😴"
        rpe_target  = "5-6"
        vol_guidance = "50% du volume habituel, charges légères."

    return jsonify({
        "current_week":         current_week,
        "week_in_cycle":        week_in_cycle,
        "weeks_since_deload":   weeks_since,
        "phase":                phase,
        "phase_label":          phase_label,
        "description":          description,
        "icon":                 icon,
        "rpe_target":           rpe_target,
        "vol_guidance":         vol_guidance,
        "last_deload_date":     last_deload_date,
        "next_deload_in_weeks": max(0, 8 - weeks_since),
    })


# MARK: - Soreness Personal Threshold

@analytics_bp.route("/api/soreness_threshold")
def api_soreness_threshold():
    """Compute personal soreness response curve from volume × soreness history."""
    import db as _db
    from datetime import date as date_cls

    rec_log  = _db.get_recovery_logs(limit=90)
    sessions = _db.get_sessions_for_correlations(days=90)

    # Pair: previous day volume → next day soreness
    pairs = []
    sorted_logs = sorted(rec_log, key=lambda e: str(e.get("date", "")))
    for i, e in enumerate(sorted_logs):
        d = str(e.get("date", ""))[:10]
        soreness = e.get("soreness")
        if soreness is None:
            continue
        # Find session volume from the day before
        from datetime import timedelta
        prev_date = (date_cls.fromisoformat(d) - timedelta(days=1)).isoformat()
        vol = sessions.get(prev_date, {}).get("session_volume")
        if vol is not None and float(vol) > 0:
            pairs.append({"volume": float(vol), "soreness": float(soreness), "date": d})

    if len(pairs) < 5:
        return jsonify({"pairs": pairs, "threshold": None, "message": "Données insuffisantes"})

    # Find volume threshold where soreness consistently exceeds 5/10
    pairs_sorted = sorted(pairs, key=lambda x: x["volume"])
    # Bin by quartile
    n = len(pairs_sorted)
    q1_vol = pairs_sorted[n // 4]["volume"]
    q3_vol = pairs_sorted[3 * n // 4]["volume"]
    low_sore  = [p["soreness"] for p in pairs_sorted[:n // 2]]
    high_sore = [p["soreness"] for p in pairs_sorted[n // 2:]]
    avg_low  = sum(low_sore)  / len(low_sore)
    avg_high = sum(high_sore) / len(high_sore)
    median_vol = pairs_sorted[n // 2]["volume"]

    threshold_vol = None
    for p in pairs_sorted:
        if p["soreness"] >= 6:
            threshold_vol = p["volume"]
            break

    return jsonify({
        "pairs":           pairs[-60:],
        "median_volume":   round(median_vol),
        "avg_soreness_low_vol":  round(avg_low,  1),
        "avg_soreness_high_vol": round(avg_high, 1),
        "threshold_vol":   round(threshold_vol) if threshold_vol else None,
        "message": (
            f"Au-dessus de {round(threshold_vol):,} lbs de volume, tes courbatures dépassent 6/10."
            if threshold_vol else None
        ),
    })


# MARK: - Self-care × PSS Correlation

@analytics_bp.route("/api/selfcare_pss_analysis")
def api_selfcare_pss_analysis():
    """Analyse la relation entre les streaks self-care et les scores PSS."""
    import db as _db
    from datetime import date as date_cls, timedelta

    streaks  = _db.get_self_care_streaks_computed()
    pss_recs = _db.get_pss_records(limit=20)
    sc_log   = _db.get_self_care_log(days=90)

    if not pss_recs:
        return jsonify({"correlation": None, "message": "Aucun enregistrement PSS"})

    # For each PSS record date, compute how many self-care habits were done in the 7 days before
    pss_with_sc = []
    for rec in pss_recs:
        d = str(rec.get("date") or rec.get("created_at") or "")[:10]
        if not d:
            continue
        pss_score = rec.get("pss_score") or rec.get("score")
        if pss_score is None:
            continue
        # Count SC completions in 7 days before this PSS
        total_sc = 0
        for i in range(1, 8):
            prev = (date_cls.fromisoformat(d) - timedelta(days=i)).isoformat()
            total_sc += len(sc_log.get(prev, []))
        pss_with_sc.append({"date": d, "pss": float(pss_score), "sc_completions": total_sc})

    if len(pss_with_sc) < 3:
        return jsonify({"data": pss_with_sc, "correlation": None, "message": "Données insuffisantes"})

    # Pearson between sc_completions and pss (negative = more self-care → lower PSS stress)
    xs = [p["sc_completions"] for p in pss_with_sc]
    ys = [p["pss"] for p in pss_with_sc]
    n  = len(xs)
    mx = sum(xs) / n
    my = sum(ys) / n
    num   = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    den_x = sum((x - mx) ** 2 for x in xs) ** 0.5
    den_y = sum((y - my) ** 2 for y in ys) ** 0.5
    r = round(num / (den_x * den_y), 3) if den_x > 0 and den_y > 0 else None

    message = None
    if r is not None:
        if r < -0.35:
            message = f"Self-care réduit le stress PSS (r={r:+.2f}). Plus tu pratiques, moins tu stresses."
        elif r > 0.35:
            message = f"Corrélation positive inattendue (r={r:+.2f}). Le stress te motive peut-être à prendre soin de toi."
        else:
            message = f"Pas de corrélation significative (r={r:+.2f}, n={n}). Continue à analyser avec plus de données."

    return jsonify({
        "data":        pss_with_sc,
        "correlation": r,
        "n":           n,
        "message":     message,
        "streaks":     streaks[:5],
    })


# MARK: - Readiness Score (pre-workout)

@analytics_bp.route("/api/readiness")
def api_readiness():
    """Return today's recovery/readiness score for pre-workout display."""
    from health_data import get_daily_health_summary, compute_recovery_score
    import db as _db
    from datetime import date as date_cls

    today   = date_cls.today().isoformat()
    summary = get_daily_health_summary(today)
    score   = summary.get("recovery_score")

    # Also get individual components for display
    rec_log  = _db.get_recovery_logs(limit=5)
    today_rec = next((e for e in rec_log if str(e.get("date",""))[:10] == today), None)

    components = {}
    if today_rec:
        sq = today_rec.get("sleep_quality")
        sh = today_rec.get("sleep_hours")
        so = today_rec.get("soreness")
        hv = today_rec.get("hrv")
        if sq is not None: components["sleep_quality"] = sq
        if sh is not None: components["sleep_hours"]   = sh
        if so is not None: components["soreness"]      = so
        if hv is not None: components["hrv"]           = hv

    # HRV baseline comparison
    from datetime import timedelta
    hrv_history = [
        float(e["hrv"]) for e in rec_log
        if e.get("hrv") and str(e.get("date",""))[:10] != today
    ]
    hrv_baseline = round(sum(hrv_history) / len(hrv_history), 1) if hrv_history else None

    # Readiness label
    if score is None:
        label = "Non mesuré"
        color = "gray"
    elif score >= 7.5:
        label = "Optimal"
        color = "green"
    elif score >= 5.5:
        label = "Bon"
        color = "yellow"
    elif score >= 4:
        label = "Modéré"
        color = "orange"
    else:
        label = "Faible"
        color = "red"

    return jsonify({
        "score":         score,
        "label":         label,
        "color":         color,
        "components":    components,
        "hrv_baseline":  hrv_baseline,
        "data_sources":  summary.get("data_sources", []),
    })


# MARK: - Nutrition Timing Analysis

@analytics_bp.route("/api/nutrition_timing")
def api_nutrition_timing():
    """Analyse pre/post workout nutrition timing from nutrition_entries.heure and workout_sessions."""
    import db as _db
    from datetime import date as date_cls, timedelta

    # Get nutrition entries with timing for the last 60 days
    cutoff = (date_cls.today() - timedelta(days=60)).isoformat()
    sessions_raw = _db.get_workout_sessions(limit=60)
    session_dates = {str(s.get("date", ""))[:10] for s in sessions_raw if s.get("date")}

    pre_window  = 2   # hours before session (start ~10am, so 8am is pre)
    post_window = 2   # hours after session

    pre_meals:  list[dict] = []
    post_meals: list[dict] = []
    all_macros_pre:  dict = {"calories": [], "proteines": [], "glucides": []}
    all_macros_post: dict = {"calories": [], "proteines": [], "glucides": []}

    if _db._client:
        try:
            resp = (
                _db._client.table("nutrition_entries")
                .select("date, heure, calories, proteines, glucides, lipides, aliment")
                .gte("date", cutoff)
                .not_.is_("heure", "null")
                .execute()
            )
            for row in (resp.data or []):
                d = str(row.get("date", ""))[:10]
                if d not in session_dates:
                    continue
                heure = row.get("heure") or ""
                try:
                    hour = int(str(heure)[:2])
                except Exception:
                    continue
                cal   = float(row.get("calories", 0)  or 0)
                prot  = float(row.get("proteines", 0) or 0)
                gluc  = float(row.get("glucides", 0)  or 0)
                entry = {"date": d, "hour": hour, "aliment": row.get("aliment"), "calories": cal, "protein": prot, "carbs": gluc}

                # Fenêtre basée sur l'heure réelle de séance (si disponible)
                session_hour = None
                sess = sessions.get(d)
                if sess and sess.get("started_at"):
                    try:
                        session_hour = int(str(sess["started_at"])[11:13])
                    except Exception:
                        pass

                is_pre = is_post = False
                if session_hour is not None:
                    is_pre  = (session_hour - 3) <= hour < session_hour
                    is_post = session_hour <= hour < (session_hour + 3)
                else:
                    # Heuristiques larges quand heure de séance inconnue
                    is_pre  = 5 <= hour < 11
                    is_post = 11 <= hour < 20

                if is_pre:
                    pre_meals.append(entry)
                    for k, v in [("calories", cal), ("proteines", prot), ("glucides", gluc)]:
                        all_macros_pre[k].append(v)
                elif is_post:
                    post_meals.append(entry)
                    for k, v in [("calories", cal), ("proteines", prot), ("glucides", gluc)]:
                        all_macros_post[k].append(v)
        except Exception as e:
            logger.error("api_nutrition_timing error: %s", e)

    def avg(lst): return round(sum(lst) / len(lst), 1) if lst else None

    return jsonify({
        "training_days_analyzed": len(session_dates),
        "pre_workout": {
            "meal_count":       len(pre_meals),
            "avg_calories":     avg(all_macros_pre["calories"]),
            "avg_protein":      avg(all_macros_pre["proteines"]),
            "avg_carbs":        avg(all_macros_pre["glucides"]),
            "top_foods":        list({m["aliment"] for m in pre_meals if m.get("aliment")})[:5],
        },
        "post_workout": {
            "meal_count":       len(post_meals),
            "avg_calories":     avg(all_macros_post["calories"]),
            "avg_protein":      avg(all_macros_post["proteines"]),
            "avg_carbs":        avg(all_macros_post["glucides"]),
            "top_foods":        list({m["aliment"] for m in post_meals if m.get("aliment")})[:5],
        },
        "insight": (
            f"Tu consommes {round(avg(all_macros_post['proteines']) or 0)}g prot post-workout. "
            "La distribution protéique sur 24h prime sur le timing précis (Schoenfeld & Aragon 2013)."
            if all_macros_post["proteines"] else
            "Pas encore assez de données de timing pour analyser ta nutrition pré/post-workout."
        ),
    })
