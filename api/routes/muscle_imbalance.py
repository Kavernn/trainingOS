"""Routes — Agoniste/Antagoniste Imbalance."""
import logging
from flask import Blueprint, jsonify, request
import muscle_imbalance_engine as _engine

muscle_imbalance_bp = Blueprint("muscle_imbalance", __name__)
logger = logging.getLogger("trainingos.muscle_imbalance_route")


@muscle_imbalance_bp.route("/api/muscle_imbalance", methods=["GET"])
def api_muscle_imbalance():
    days = max(30, min(365, request.args.get("days", 90, type=int)))
    try:
        return jsonify(_engine.compute(days=days))
    except Exception as e:
        logger.error("muscle_imbalance error: %s", e)
        return jsonify({"has_data": False, "pairs": [], "has_imbalance": False,
                        "total_analyzed": 0, "period_days": days}), 500
