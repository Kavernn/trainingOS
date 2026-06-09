from flask import Blueprint, jsonify
import sleep_hrv_engine

sleep_hrv_bp = Blueprint("sleep_hrv", __name__)


@sleep_hrv_bp.route("/api/sleep-hrv")
def get_sleep_hrv():
    return jsonify(sleep_hrv_engine.compute())
