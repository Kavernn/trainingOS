"""Routes — Compound Interest Score."""
import logging
from flask import Blueprint, jsonify
import compound_score as _engine

compound_bp = Blueprint("compound", __name__)
logger = logging.getLogger("trainingos.compound_route")


@compound_bp.route("/api/compound_score", methods=["GET"])
def api_compound_score():
    try:
        return jsonify(_engine.compute())
    except Exception as e:
        logger.error("compound_score error: %s", e)
        return jsonify({"has_baseline": False, "score": 0.0, "trend": "stable"})
