"""Routes — Plateau detection & deload."""
from datetime import datetime
from flask import Blueprint, jsonify, request
import plateau as _plateau
from utils import _now_mtl

plateau_bp = Blueprint("plateau", __name__)


@plateau_bp.route("/api/plateau_alerts", methods=["GET"])
def api_plateau_alerts():
    force = request.args.get("force", "0") == "1"
    return jsonify(_plateau.detect(force=force))


@plateau_bp.route("/api/plateau_alerts/<alert_id>", methods=["PATCH"])
def api_update_plateau_alert(alert_id):
    import db
    cli = db._client
    if not cli:
        return jsonify({"error": "DB unavailable"}), 503

    body   = request.get_json(silent=True) or {}
    status = body.get("status")

    if status not in {"accepted", "active", "completed", "dismissed"}:
        return jsonify({"error": "Invalid status"}), 400

    patch = {"status": status}
    now   = _now_mtl().isoformat()
    if status == "dismissed":
        patch["dismissed_at"] = now
    elif status == "completed":
        patch["completed_at"] = now

    result = cli.table("plateau_alerts").update(patch).eq("id", alert_id).execute()
    if not result.data:
        return jsonify({"error": "Alert not found"}), 404

    _plateau._CACHE.clear()
    return jsonify(result.data[0])
