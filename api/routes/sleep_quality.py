from flask import Blueprint, jsonify
import sleep_quality_engine

sleep_quality_bp = Blueprint("sleep_quality", __name__)


@sleep_quality_bp.route("/api/sleep-quality")
def get_sleep_quality():
    return jsonify(sleep_quality_engine.compute())
