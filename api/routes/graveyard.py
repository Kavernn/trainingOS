"""Routes — Graveyard."""
from flask import Blueprint, jsonify, request
import graveyard_engine as _graveyard

graveyard_bp = Blueprint("graveyard", __name__)


@graveyard_bp.route("/api/graveyard", methods=["GET"])
def api_graveyard():
    if request.args.get("count_only") == "true":
        result = _graveyard.compute()
        return jsonify({"total_count": result["total_count"]})
    return jsonify(_graveyard.compute())
