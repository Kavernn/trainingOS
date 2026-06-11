from flask import Blueprint, jsonify
import session_progression_engine

session_progression_bp = Blueprint("session_progression", __name__)


@session_progression_bp.route("/api/session-progression")
def get_session_progression():
    return jsonify(session_progression_engine.compute())
