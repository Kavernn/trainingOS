from flask import Blueprint, jsonify
import session_quality_engine

session_quality_bp = Blueprint("session_quality", __name__)


@session_quality_bp.route("/api/session-quality")
def get_session_quality():
    return jsonify(session_quality_engine.compute())
