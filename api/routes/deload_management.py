from flask import Blueprint, jsonify, request
from deload import activer_deload, desactiver_deload, load_deload_state
from utils import _today_mtl

deload_management_bp = Blueprint("deload_management", __name__)


@deload_management_bp.route("/api/deload/status", methods=["GET"])
def api_deload_status():
    state = load_deload_state()
    active = bool(state.get("active", False))
    started_at = state.get("started_at")
    duration_days = int(state.get("duration_days") or 7)
    ends_at = None
    days_remaining = None
    if active and started_at:
        from datetime import date, timedelta
        try:
            start = date.fromisoformat(started_at)
            end = start + timedelta(days=duration_days)
            ends_at = end.isoformat()
            days_remaining = max(0, (end - date.fromisoformat(_today_mtl())).days)
        except Exception:
            pass
    return jsonify({
        "active":         active,
        "started_at":     started_at,
        "reason":         state.get("reason"),
        "duration_days":  duration_days,
        "ends_at":        ends_at,
        "days_remaining": days_remaining,
        "last_completed": state.get("last_completed"),
    })


@deload_management_bp.route("/api/deload/activate", methods=["POST"])
def api_deload_activate():
    body = request.get_json(silent=True) or {}
    reason = (body.get("reason") or "Repos volontaire").strip()
    duration_days = int(body.get("duration_days") or 7)
    started_at = body.get("started_at") or _today_mtl()
    if duration_days < 1 or duration_days > 21:
        return jsonify({"error": "duration_days doit être entre 1 et 21"}), 400
    activer_deload(reason=reason, duration_days=duration_days, started_at=started_at)
    from routes.daily_brief import invalidate_cache as _brief_invalidate
    _brief_invalidate()
    return jsonify({"ok": True, "started_at": started_at, "duration_days": duration_days})


@deload_management_bp.route("/api/deload/deactivate", methods=["POST"])
def api_deload_deactivate():
    desactiver_deload()
    from routes.daily_brief import invalidate_cache as _brief_invalidate
    _brief_invalidate()
    return jsonify({"ok": True, "completed_at": _today_mtl()})
