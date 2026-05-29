from flask import Blueprint, jsonify, request
import logging
from utils import _today_mtl

logger = logging.getLogger("trainingos")
nutrition_hydration_bp = Blueprint("nutrition_hydration", __name__)


@nutrition_hydration_bp.route("/api/nutrition/hydration", methods=["GET", "POST"])
def api_hydration():
    """
    GET  — objectif hydrique du jour (35 ml/kg + 600 ml si séance) + total loggué.
    POST — quick-add (défaut 250 ml, paramètre ml accepté).

    Référence objectif : Cheuvront & Kenefick 2014 (2 % déshydratation = -10-20 % performance).
    """
    import db as _db
    from datetime import date

    if request.method == "GET":
        profile    = _db.get_profile() or {}
        weight_lbs = float(profile.get("weight") or 0)
        weight_kg  = weight_lbs * 0.453592 if weight_lbs else 75.0
        base_ml    = round(weight_kg * 35)

        today    = _today_mtl()
        sessions = _db.get_workout_sessions(limit=7) or []
        had_session = any(
            s.get("date") == today and s.get("completed")
            for s in sessions
        )
        target_ml = base_ml + (600 if had_session else 0)
        logged_ml = _db.get_hydration_today()

        return jsonify({
            "target_ml":    target_ml,
            "logged_ml":    logged_ml,
            "remaining_ml": max(0, target_ml - logged_ml),
            "pct":          round(logged_ml / target_ml * 100) if target_ml else 0,
            "weight_kg":    round(weight_kg, 1),
            "session_bonus": 600 if had_session else 0,
        })

    # POST — quick-add
    data   = request.get_json(silent=True) or {}
    amount = int(data.get("ml", 250))
    if amount <= 0 or amount > 2000:
        return jsonify({"error": "Quantité invalide (1–2000 ml)"}), 422
    _db.log_hydration(amount)
    return jsonify({"success": True, "added_ml": amount})
