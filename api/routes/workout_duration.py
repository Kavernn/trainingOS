from flask import Blueprint, jsonify
import workout_duration_engine

workout_duration_bp = Blueprint("workout_duration", __name__)


@workout_duration_bp.route("/api/workout-duration")
def get_workout_duration():
    return jsonify(workout_duration_engine.compute())
