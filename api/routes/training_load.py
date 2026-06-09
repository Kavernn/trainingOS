"""Routes — Training Load (ACWR)."""
import logging
from flask import Blueprint, jsonify
import training_load_engine as _engine

training_load_bp = Blueprint("training_load", __name__)
logger = logging.getLogger("trainingos.training_load_route")


@training_load_bp.route("/api/training_load", methods=["GET"])
def api_training_load():
    try:
        return jsonify(_engine.compute())
    except Exception as e:
        logger.error("training_load error: %s", e)
        return jsonify({"has_data": False, "ratio": None, "zone": "optimal", "trend_4w": []})
