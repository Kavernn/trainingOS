"""Routes — Phoenix Score."""
from flask import Blueprint, jsonify
import phoenix_engine as _phoenix

phoenix_bp = Blueprint("phoenix", __name__)


@phoenix_bp.route("/api/phoenix_score", methods=["GET"])
def api_phoenix_score():
    return jsonify(_phoenix.compute())
