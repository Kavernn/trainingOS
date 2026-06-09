"""Routes — Blueprint Nutrition × Performance Correlation."""
import logging
from flask import Blueprint, jsonify
import nutrition_performance_engine as _engine

nutrition_performance_bp = Blueprint("nutrition_performance", __name__)
logger = logging.getLogger("trainingos.nutrition_performance_route")


@nutrition_performance_bp.route("/api/nutrition_performance", methods=["GET"])
def api_nutrition_performance():
    try:
        return jsonify(_engine.compute())
    except Exception as e:
        logger.error("nutrition_performance error: %s", e)
        return jsonify({"has_data": False, "avg_rpe_with": None, "avg_rpe_without": None,
                        "count_with": 0, "count_without": 0, "rpe_diff": None,
                        "impact_pct": None, "sessions_analyzed": 0,
                        "message": "Erreur de calcul."})
