"""Routes — Volume musculaire + muscles négligés."""
import logging
from flask import Blueprint, jsonify, request
import muscle_volume as _vol

muscle_volume_bp = Blueprint("muscle_volume", __name__)
logger = logging.getLogger("trainingos.muscle_volume_route")


@muscle_volume_bp.route("/api/muscle_volume", methods=["GET"])
def api_muscle_volume():
    """Full muscle volume report: current week + 4-week avg + MEV status + neglected muscles."""
    days_current = max(1, min(14, request.args.get("days_current", 7, type=int)))
    days_trend   = max(14, min(84, request.args.get("days_trend", 28, type=int)))
    try:
        return jsonify(_vol.compute_volume_full(
            days_current=days_current,
            days_trend=days_trend,
        ))
    except Exception as e:
        logger.error("muscle_volume error: %s", e)
        return jsonify({"current_week": {}, "weekly_avg": {}, "neglected": [],
                        "mev": 10, "mav": 20, "trend_days": days_trend}), 500
