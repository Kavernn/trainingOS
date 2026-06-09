from flask import Blueprint, jsonify
import body_weight_trend_engine

body_weight_trend_bp = Blueprint("body_weight_trend", __name__)


@body_weight_trend_bp.route("/api/body-weight-trend")
def get_body_weight_trend():
    return jsonify(body_weight_trend_engine.compute())
