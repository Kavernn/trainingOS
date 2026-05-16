"""Routes — Time Capsule."""
from flask import Blueprint, jsonify, request
import time_capsule as _tc

time_capsule_bp = Blueprint("time_capsule", __name__)


@time_capsule_bp.route("/api/time_capsule/snapshot", methods=["GET"])
def api_capsule_snapshot():
    """Preview of current stats before sealing — no DB write."""
    return jsonify(_tc.capture_snapshot())


@time_capsule_bp.route("/api/time_capsule", methods=["GET"])
def api_list_capsules():
    return jsonify({"capsules": _tc.list_capsules()})


@time_capsule_bp.route("/api/time_capsule", methods=["POST"])
def api_create_capsule():
    body = request.get_json(silent=True) or {}
    try:
        duration_months = int(body.get("duration_months", 3))
    except (TypeError, ValueError):
        return jsonify({"error": "duration_months must be 1, 3 or 6"}), 400
    message = (body.get("message") or "").strip() or None
    try:
        capsule = _tc.create_capsule(duration_months, message)
        return jsonify(capsule), 201
    except (ValueError, RuntimeError) as e:
        return jsonify({"error": str(e)}), 400


@time_capsule_bp.route("/api/time_capsule/<capsule_id>", methods=["GET"])
def api_get_capsule(capsule_id: str):
    capsule = _tc.get_capsule_detail(capsule_id)
    if capsule is None:
        return jsonify({"error": "Not found"}), 404
    return jsonify(capsule)


@time_capsule_bp.route("/api/time_capsule/<capsule_id>/open", methods=["PATCH"])
def api_open_capsule(capsule_id: str):
    capsule = _tc.open_capsule(capsule_id)
    if capsule is None:
        return jsonify({"error": "Not found"}), 404
    return jsonify(capsule)
