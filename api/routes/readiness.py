"""GET /api/readiness — Pre-session readiness score."""
from flask import Blueprint, jsonify
import readiness as _r

readiness_bp = Blueprint("readiness", __name__)


@readiness_bp.route("/api/readiness", methods=["GET"])
def api_readiness():
    return jsonify(_r.compute())
