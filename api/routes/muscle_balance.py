"""Routes — Blueprint Équilibre Musculaire."""
import logging
from flask import Blueprint, jsonify
import muscle_balance_engine as _engine

muscle_balance_bp = Blueprint("muscle_balance", __name__)
logger = logging.getLogger("trainingos.muscle_balance_route")


@muscle_balance_bp.route("/api/muscle_balance", methods=["GET"])
def api_muscle_balance():
    try:
        return jsonify(_engine.compute())
    except Exception as e:
        logger.error("muscle_balance error: %s", e)
        return jsonify({"has_data": False, "ratios": None, "imbalances": [],
                        "total_analyzed": 0, "top_category": None})
