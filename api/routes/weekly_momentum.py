"""Routes — Blueprint Weekly Momentum Score."""
import logging
from flask import Blueprint, jsonify
import weekly_momentum_engine as _engine

weekly_momentum_bp = Blueprint("weekly_momentum", __name__)
logger = logging.getLogger("trainingos.weekly_momentum_route")


@weekly_momentum_bp.route("/api/weekly_momentum", methods=["GET"])
def api_weekly_momentum():
    try:
        return jsonify(_engine.compute())
    except Exception as e:
        logger.error("weekly_momentum error: %s", e)
        return jsonify({"has_data": False, "score": None, "pillars": None,
                        "prev_avg": None, "trend_pct": None,
                        "week_start": None, "history": [], "message": "Erreur de calcul."})
