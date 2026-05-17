"""Routes — Graveyard."""
from flask import Blueprint, jsonify
import graveyard_engine as _graveyard

graveyard_bp = Blueprint("graveyard", __name__)


@graveyard_bp.route("/api/graveyard", methods=["GET"])
def api_graveyard():
    return jsonify(_graveyard.compute())
