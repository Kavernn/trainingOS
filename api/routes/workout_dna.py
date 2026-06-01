"""Routes — Workout DNA."""
from flask import Blueprint, jsonify, request
import workout_dna as _dna

workout_dna_bp = Blueprint("workout_dna", __name__)


@workout_dna_bp.route("/api/workout_dna", methods=["GET"])
def api_workout_dna():
    period = max(30, min(365, request.args.get("period", 90, type=int)))
    return jsonify(_dna.compute(period_days=period))
