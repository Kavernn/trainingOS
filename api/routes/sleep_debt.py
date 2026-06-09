"""Routes — Sleep Debt Tracker."""
import logging
from flask import Blueprint, jsonify
import sleep_debt_engine as _engine

sleep_debt_bp = Blueprint("sleep_debt", __name__)
logger = logging.getLogger("trainingos.sleep_debt_route")


@sleep_debt_bp.route("/api/sleep_debt", methods=["GET"])
def api_sleep_debt():
    try:
        return jsonify(_engine.compute())
    except Exception as e:
        logger.error("sleep_debt error: %s", e)
        return jsonify({"has_data": False, "debt_7d": None, "trend": "stable"})
