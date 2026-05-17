"""Pattern detection routes."""
from __future__ import annotations
from flask import Blueprint, jsonify, request
import pattern_engine as _pe

patterns_bp = Blueprint("patterns", __name__)


@patterns_bp.route("/api/patterns/daily", methods=["GET"])
def api_daily_pattern():
    return jsonify(_pe.get_daily_pattern())


@patterns_bp.route("/api/patterns/pin", methods=["POST"])
def api_pin_pattern():
    body = request.get_json(silent=True) or {}
    pid  = (body.get("pattern_id") or "").strip()
    if not pid:
        return jsonify({"error": "pattern_id required"}), 400
    _pe.pin_pattern(pid)
    return jsonify({"ok": True})


@patterns_bp.route("/api/patterns/pin/<path:pattern_id>", methods=["DELETE"])
def api_unpin_pattern(pattern_id: str):
    _pe.unpin_pattern(pattern_id)
    return jsonify({"ok": True})


@patterns_bp.route("/api/patterns/war_room", methods=["GET"])
def api_war_room_patterns():
    """War Room-sandboxed patterns (families E and G). Only served in War Room context."""
    return jsonify(_pe.get_war_room_patterns())
