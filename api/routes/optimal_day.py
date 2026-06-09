"""Routes — Blueprint Jour Optimal d'Entraînement."""
import logging
from flask import Blueprint, jsonify
import optimal_day_engine as _engine

optimal_day_bp = Blueprint("optimal_day", __name__)
logger = logging.getLogger("trainingos.optimal_day_route")


@optimal_day_bp.route("/api/optimal_day", methods=["GET"])
def api_optimal_day():
    try:
        return jsonify(_engine.compute())
    except Exception as e:
        logger.error("optimal_day error: %s", e)
        return jsonify({"has_data": False, "best_day": None, "worst_day": None,
                        "by_day": [], "sessions_analyzed": 0})
