"""Routes — Performance Conditions."""
import logging
from flask import Blueprint, jsonify
import performance_conditions_engine as _engine

performance_conditions_bp = Blueprint("performance_conditions", __name__)
logger = logging.getLogger("trainingos.perf_conditions_route")


@performance_conditions_bp.route("/api/performance_conditions", methods=["GET"])
def api_performance_conditions():
    try:
        return jsonify(_engine.compute())
    except Exception as e:
        logger.error("performance_conditions error: %s", e)
        return jsonify({"has_data": False, "conditions": [], "alignment_score": None, "message": ""})
