"""Routes — Temporal Pattern Analysis (Syndrome du Dimanche)."""
import logging
from flask import Blueprint, jsonify
import temporal_patterns as _engine

temporal_bp = Blueprint("temporal", __name__)
logger = logging.getLogger("trainingos.temporal_route")


@temporal_bp.route("/api/temporal_patterns", methods=["GET"])
def api_temporal_patterns():
    try:
        return jsonify(_engine.compute())
    except Exception as e:
        logger.error("temporal_patterns error: %s", e)
        return jsonify({"has_baseline": False})
