"""Routes — Rupture Risk Detection."""
import logging
from flask import Blueprint, jsonify
import rupture_engine as _engine

rupture_bp = Blueprint("rupture", __name__)
logger = logging.getLogger("trainingos.rupture_route")


@rupture_bp.route("/api/rupture_risk", methods=["GET"])
def api_rupture_risk():
    try:
        return jsonify(_engine.compute())
    except Exception as e:
        logger.error("rupture_risk error: %s", e)
        return jsonify({"has_data": False, "score": 0, "signals": [], "message": ""})
