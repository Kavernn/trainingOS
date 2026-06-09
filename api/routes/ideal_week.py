"""Routes — Blueprint Semaine Idéale."""
import logging
from flask import Blueprint, jsonify
import ideal_week_engine as _engine

ideal_week_bp = Blueprint("ideal_week", __name__)
logger = logging.getLogger("trainingos.ideal_week_route")


@ideal_week_bp.route("/api/ideal_week", methods=["GET"])
def api_ideal_week():
    try:
        return jsonify(_engine.compute())
    except Exception as e:
        logger.error("ideal_week error: %s", e)
        return jsonify({"has_data": False, "best_week": None, "current_week": None,
                        "match_pct": None, "gaps": []})
