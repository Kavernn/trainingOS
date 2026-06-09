"""Routes — Velocity of Change."""
import logging
from flask import Blueprint, jsonify
import velocity_engine as _engine

velocity_bp = Blueprint("velocity", __name__)
logger = logging.getLogger("trainingos.velocity_route")


@velocity_bp.route("/api/velocity", methods=["GET"])
def api_velocity():
    try:
        return jsonify(_engine.compute())
    except Exception as e:
        logger.error("velocity error: %s", e)
        return jsonify({"has_baseline": False, "label": "foundation"})
