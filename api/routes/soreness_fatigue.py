from flask import Blueprint, jsonify
import soreness_fatigue_engine

soreness_fatigue_bp = Blueprint("soreness_fatigue", __name__)


@soreness_fatigue_bp.route("/api/soreness-fatigue")
def get_soreness_fatigue():
    return jsonify(soreness_fatigue_engine.compute())
