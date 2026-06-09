from flask import Blueprint, jsonify
import progressive_overload_engine

progressive_overload_bp = Blueprint("progressive_overload", __name__)


@progressive_overload_bp.route("/api/progressive-overload")
def get_progressive_overload():
    return jsonify(progressive_overload_engine.compute())
