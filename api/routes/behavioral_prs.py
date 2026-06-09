"""Routes — Behavioral Personal Records."""
import logging
from flask import Blueprint, jsonify
import behavioral_prs as _engine

behavioral_prs_bp = Blueprint("behavioral_prs", __name__)
logger = logging.getLogger("trainingos.behavioral_prs_route")


@behavioral_prs_bp.route("/api/behavioral_prs", methods=["GET"])
def api_behavioral_prs():
    try:
        return jsonify(_engine.compute())
    except Exception as e:
        logger.error("behavioral_prs error: %s", e)
        return jsonify({"has_data": False, "prs": [], "total": 0, "active_prs": 0})
