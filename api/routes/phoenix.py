"""Routes — Phoenix Score."""
import logging
from flask import Blueprint, jsonify
import phoenix_engine as _phoenix

phoenix_bp = Blueprint("phoenix", __name__)
logger = logging.getLogger("trainingos.phoenix_route")


@phoenix_bp.route("/api/phoenix_score", methods=["GET"])
def api_phoenix_score():
    try:
        return jsonify(_phoenix.compute())
    except Exception as e:
        logger.error("phoenix_score error: %s", e)
        return jsonify({
            "score": 0.0, "state": "foundation",
            "axes": {
                "workout":   {"delta": 0.0},
                "stress":    {"delta": 0.0},
                "nutrition": {"delta": 0.0},
                "spirit":    {"delta": 0.0},
            },
            "is_foundation": True,
            "raw_delta": 0.0,
        })
