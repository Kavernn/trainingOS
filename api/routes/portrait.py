"""Routes — Portrait J-90."""
import logging
from flask import Blueprint, jsonify
import portrait_engine as _engine

portrait_bp = Blueprint("portrait", __name__)
logger = logging.getLogger("trainingos.portrait_route")


@portrait_bp.route("/api/portrait_j90", methods=["GET"])
def api_portrait_j90():
    try:
        return jsonify(_engine.compute())
    except Exception as e:
        logger.error("portrait_j90 error: %s", e)
        return jsonify({"has_baseline": False, "dimensions": [], "transformation_score": None})
