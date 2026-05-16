"""Routes — Workout DNA."""
from flask import Blueprint, jsonify
import workout_dna as _dna

workout_dna_bp = Blueprint("workout_dna", __name__)


@workout_dna_bp.route("/api/workout_dna", methods=["GET"])
def api_workout_dna():
    return jsonify(_dna.compute())
