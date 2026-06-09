from flask import Blueprint, jsonify
import volume_progression_engine

volume_progression_bp = Blueprint("volume_progression", __name__)


@volume_progression_bp.route("/api/volume-progression")
def get_volume_progression():
    return jsonify(volume_progression_engine.compute())
