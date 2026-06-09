"""Routes — Blueprint Score de Consistance."""
import logging
from flask import Blueprint, jsonify
import consistency_engine as _engine

consistency_bp = Blueprint("consistency", __name__)
logger = logging.getLogger("trainingos.consistency_route")


@consistency_bp.route("/api/consistency", methods=["GET"])
def api_consistency():
    try:
        return jsonify(_engine.compute())
    except Exception as e:
        logger.error("consistency error: %s", e)
        return jsonify({"has_data": False, "score": None, "std_dev": None,
                        "avg_sessions_per_week": None, "trend": "stable",
                        "weekly_counts": [], "message": "Erreur de calcul."})
