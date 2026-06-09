from flask import Blueprint, jsonify, request
import logging

logger = logging.getLogger("trainingos")
nutrition_bp = Blueprint("nutrition", __name__)


@nutrition_bp.route("/api/nutrition/add", methods=["POST"])
def api_nutrition_add():
    from nutrition import (add_entry as nutrition_add_entry, get_today_totals)
    data  = request.get_json() or {}
    if not data.get("nom", "").strip():
        return jsonify({"error": "nom requis"}), 422
    calories_val = float(data.get("calories", 0))
    if calories_val < 0:
        return jsonify({"error": "calories ne peut pas être négatif"}), 422
    for field in ("proteines", "glucides", "lipides"):
        val = float(data.get(field, 0))
        if val < 0 or val > 10000:
            return jsonify({"error": f"{field} invalide (0–10000)"}), 422
    entry = nutrition_add_entry(
        nom       = data.get("nom", ""),
        calories  = calories_val,
        proteines = float(data.get("proteines", 0)),
        glucides  = float(data.get("glucides", 0)),
        lipides   = float(data.get("lipides", 0)),
        meal_type = data.get("meal_type"),
        source    = data.get("source", "manual"),
    )
    return jsonify({"success": True, "entry": entry, "totals": get_today_totals()})


@nutrition_bp.route("/api/nutrition/delete", methods=["POST"])
def api_nutrition_delete():
    from nutrition import (delete_entry as nutrition_delete_entry, get_today_totals)
    data = request.get_json(silent=True) or {}
    ok   = nutrition_delete_entry(data.get("id", ""))
    return jsonify({"success": ok, "totals": get_today_totals()})


@nutrition_bp.route("/api/nutrition/edit", methods=["POST"])
def api_nutrition_edit():
    try:
        import db as _db
        from nutrition import get_today_totals
        data     = request.get_json(silent=True) or {}
        entry_id = data.get("id", "")
        if not entry_id:
            return jsonify({"error": "id manquant"}), 400
        patch = {k: data[k] for k in ("nom", "calories", "proteines", "glucides", "lipides", "quantity")
                 if k in data}
        ok = _db.update_nutrition_entry(entry_id, patch)
        return jsonify({"success": ok, "totals": get_today_totals()})
    except Exception:
        raise


@nutrition_bp.route("/api/nutrition/settings", methods=["POST"])
def api_nutrition_settings():
    from nutrition import (save_settings as save_nutrition_settings)
    data = request.get_json(silent=True) or {}

    dtt_raw = data.get("day_type_targets")
    day_type_targets = None
    if isinstance(dtt_raw, dict):
        day_type_targets = {}
        for key in ("light", "moderate", "heavy", "rest"):
            t = dtt_raw.get(key) or {}
            if t:
                day_type_targets[key] = {
                    "calories": int(t.get("calories", 0)),
                    "glucides": int(t.get("glucides", 0)),
                }

    save_nutrition_settings(
        int(data.get("limite_calories",    2400)),
        int(data.get("objectif_proteines", 180)),
        float(data.get("glucides", 235)),
        float(data.get("lipides",  75)),
        day_type_targets=day_type_targets,
        nutrition_end_time=data.get("nutrition_end_time") or None,
    )
    return jsonify({"success": True})


@nutrition_bp.route("/api/nutrition/tdee", methods=["POST"])
def api_nutrition_tdee():
    """
    Recalcule BMR/TDEE depuis le profil utilisateur et met à jour nutrition_settings.
    POST sans body — lit user_profile automatiquement.
    """
    import db as _db
    from tdee import compute_tdee, compute_dynamic_day_targets, check_goal_realism
    from nutrition import save_settings as save_nutrition_settings

    profile = _db.get_profile() or {}
    latest_bw = _db.get_body_weight_logs(limit=1)
    if latest_bw:
        profile["weight"] = latest_bw[0].get("weight") or profile.get("weight")
    tdee_data = compute_tdee(profile)
    if not tdee_data:
        return jsonify({"error": "Profil incomplet — renseigne poids, taille et âge."}), 422

    weight_lbs = float(profile.get("weight") or 0)
    weight_kg  = weight_lbs * 0.453592 if weight_lbs else None
    dtt = compute_dynamic_day_targets(weight_kg, tdee_data["calorie_target"]) if weight_kg else None

    save_nutrition_settings(
        tdee_data["calorie_target"],
        tdee_data["objectif_proteines"],
        float(tdee_data["glucides"]),
        float(tdee_data["lipides"]),
        day_type_targets=dtt,
    )

    import db as _db2
    _db2.update_nutrition_settings({
        "bmr_kcal":          tdee_data["bmr_kcal"],
        "tdee_kcal":         tdee_data["tdee_kcal"],
        "calorie_target":    tdee_data["calorie_target"],
        "activity_factor":   tdee_data["activity_factor"],
        "sessions_per_week": tdee_data["sessions_per_week"],
        "formula_used":      tdee_data["formula_used"],
        "goal_phase":        tdee_data["goal_phase"],
    })

    goal_check = check_goal_realism(profile, tdee_data)
    return jsonify({"success": True, **tdee_data, "goal_realism": goal_check})


@nutrition_bp.route("/api/nutrition/adaptive-check", methods=["GET"])
def api_nutrition_adaptive_check():
    """
    Évalue la progression du poids sur 14 jours et propose ±150 kcal si nécessaire.
    Lecture seule — l'utilisateur applique l'ajustement manuellement.
    """
    from tdee import check_weight_progress
    from nutrition import load_settings

    settings = load_settings()
    goal     = settings.get("goal_phase") or "maintain"
    cal      = int(settings.get("limite_calories") or 2400)

    result = check_weight_progress(goal, cal)
    if result is None:
        return jsonify({
            "available": False,
            "reason": "Moins de 14 pesées — continue à enregistrer ton poids quotidiennement.",
        })
    return jsonify({"available": True, "current_target_kcal": cal, **result})


@nutrition_bp.route("/api/nutrition")
def api_nutrition_day():
    """Source de vérité unique pour les totaux du jour. Date locale passée par iOS."""
    import db as _db
    from datetime import datetime as _dt
    date_param = request.args.get("date", "").strip()
    try:
        _dt.strptime(date_param, "%Y-%m-%d")
        date = date_param
    except (ValueError, Exception):
        from utils import _today_mtl
        date = _today_mtl()
    entries = _db.get_nutrition_entries(date)
    return jsonify({
        "date":          date,
        "calories":      round(sum(e.get("calories", 0) for e in entries)),
        "proteines":     round(sum(e.get("proteines", 0) for e in entries), 1),
        "glucides":      round(sum(e.get("glucides",  0) for e in entries), 1),
        "lipides":       round(sum(e.get("lipides",   0) for e in entries), 1),
        "entries_count": len(entries),
    })


@nutrition_bp.route("/api/nutrition_data")
def api_nutrition_data():
    from nutrition import (load_settings as load_nutrition_settings,
                           get_recent_days, _get_day_intensity)
    import db as _db
    from datetime import datetime as _dt
    date_param = request.args.get("date", "").strip()
    try:
        _dt.strptime(date_param, "%Y-%m-%d")
        today = date_param
    except (ValueError, Exception):
        from utils import _today_mtl
        today = _today_mtl()
    settings = load_nutrition_settings()
    entries  = _db.get_nutrition_entries(today)
    totals   = {
        "calories":  round(sum(e.get("calories", 0) for e in entries)),
        "proteines": round(sum(e.get("proteines", 0) for e in entries), 1),
        "glucides":  round(sum(e.get("glucides",  0) for e in entries), 1),
        "lipides":   round(sum(e.get("lipides",   0) for e in entries), 1),
    }
    days    = min(int(request.args.get("days", 7)), 90)
    history = get_recent_days(days)
    intensity, today_session = _get_day_intensity()
    return jsonify({
        "settings":      settings,
        "entries":       entries,
        "totals":        totals,
        "history":       history,
        "today_type":    intensity,
        "today_session": today_session,
    })


@nutrition_bp.route("/api/nutrition/quality", methods=["GET"])
def api_nutrition_quality():
    from readiness import _score_nutrition
    from utils import get_nutrition_time_context, _today_mtl
    score, details = _score_nutrition()
    ctx = get_nutrition_time_context(_today_mtl())
    return jsonify({
        "score":        int(score),
        "cal_pct":      details.get("cal_pct"),
        "prot_pct":     details.get("prot_pct"),
        "is_too_early": ctx.get("is_too_early", False),
        "no_data":      details.get("no_data", False),
    })
