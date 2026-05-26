from flask import Blueprint, jsonify, request
from datetime import datetime, timedelta
import logging

logger = logging.getLogger("trainingos")

analytics_stats_bp = Blueprint("analytics_stats", __name__)


@analytics_stats_bp.route("/api/stats_data")
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
    nutr_entries  = _db.get_nutrition_daily_full(180)
    inventory       = load_inventory() or {}
    muscle_stats    = _calc_muscle_stats(sessions, weights, inventory)
    weekly_sets     = _calc_weekly_sets_per_muscle(weights, inventory)
    inventory_types = {name: info.get("type") or "machine" for name, info in inventory.items()}

    tracked_muscles = set(muscle_stats.keys()) | set(weekly_sets.keys())
    muscle_landmarks = {
        muscle: {**MUSCLE_LANDMARKS[muscle], "weekly_sets": weekly_sets.get(muscle, 0)}
        for muscle in tracked_muscles
        if muscle in MUSCLE_LANDMARKS
    }

    from utils import get_current_week
    weekly_tonnage       = _db.get_weekly_tonnage(26)
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


@analytics_stats_bp.route("/api/stats_wellness")
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


@analytics_stats_bp.route("/api/macro_gap")
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


@analytics_stats_bp.route("/api/nutrition_timing")
def api_nutrition_timing():
    """Analyse pre/post workout nutrition timing from nutrition_entries.heure and workout_sessions."""
    import db as _db
    from datetime import date as date_cls, timedelta

    cutoff = (date_cls.today() - timedelta(days=60)).isoformat()
    sessions_raw = _db.get_workout_sessions(limit=60)
    session_dates = {str(s.get("date", ""))[:10] for s in sessions_raw if s.get("date")}

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

                session_hour = None
                sess = next((s for s in sessions_raw if str(s.get("date", ""))[:10] == d), None)
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
