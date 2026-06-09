"""Routes — Blueprint Comeback Arc."""
import logging
from flask import Blueprint, jsonify
import comeback_arc_engine as _engine

comeback_arc_bp = Blueprint("comeback_arc", __name__)
logger = logging.getLogger("trainingos.comeback_arc_route")


@comeback_arc_bp.route("/api/comeback_arc", methods=["GET"])
def api_comeback_arc():
    try:
        return jsonify(_engine.compute())
    except Exception as e:
        logger.error("comeback_arc error: %s", e)
        return jsonify({"has_data": False, "in_comeback": False, "rupture_start": None,
                        "rupture_end": None, "rupture_length": None,
                        "days_since_rupture": None, "active_days": None,
                        "active_since_pct": None, "message": "Erreur de calcul."})
