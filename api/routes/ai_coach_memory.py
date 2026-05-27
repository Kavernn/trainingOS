from flask import Blueprint, jsonify, request
import logging

logger = logging.getLogger("trainingos")
ai_coach_memory_bp = Blueprint("ai_coach_memory", __name__)


@ai_coach_memory_bp.route("/api/coach/memory", methods=["GET"])
def get_coach_memory():
    """Return the coach memory entries stored in user_profile."""
    import db as _db
    entries = _db.get_coach_memory()
    return jsonify({"entries": entries})


@ai_coach_memory_bp.route("/api/coach/memory", methods=["POST"])
def save_coach_memory():
    """Persist coach memory entries. Replaces the full set."""
    import db as _db
    data    = request.get_json(silent=True) or {}
    entries = data.get("entries")
    if not isinstance(entries, list):
        return jsonify({"error": "entries must be a list"}), 400
    ok = _db.save_coach_memory(entries)
    return jsonify({"success": ok})


@ai_coach_memory_bp.route("/api/coach/war_room_share", methods=["GET"])
def get_war_room_share():
    """Return whether the user has opted in to sharing War Room data with the coach."""
    import db as _db
    return jsonify({"shared": _db.get_coach_war_room_shared()})


@ai_coach_memory_bp.route("/api/coach/war_room_share", methods=["POST"])
def set_war_room_share():
    """Toggle War Room sharing with the coach. Body: {"shared": bool}"""
    import db as _db
    data  = request.get_json(silent=True) or {}
    value = bool(data.get("shared", False))
    ok    = _db.set_coach_war_room_shared(value)
    return jsonify({"success": ok, "shared": value})
