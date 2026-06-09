from flask import Blueprint, jsonify
import stress_load_engine

stress_load_bp = Blueprint("stress_load", __name__)


@stress_load_bp.route("/api/stress-load")
def get_stress_load():
    return jsonify(stress_load_engine.compute())
