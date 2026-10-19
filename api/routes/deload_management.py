from datetime import date, timedelta
from flask import Blueprint, jsonify, request

import db
from deload import activer_deload, desactiver_deload
from utils import _today_mtl

deload_management_bp = Blueprint("deload_management", __name__)


@deload_management_bp.route("/api/deload/status", methods=["GET"])
def api_deload_status():
    """État courant lu depuis deload_periods (migration 080).
    La forme du payload est préservée pour l'iOS existant : `active`,
    `started_at`, `reason`, `duration_days`, `ends_at`, `days_remaining`,
    `last_completed`. `ends_at` = `scheduled_end` (alias legacy)."""
    period = db.get_active_deload_period()
    last_completed = db.get_last_completed_deload()

    if period is None:
        return jsonify({
            "active":         False,
            "started_at":     None,
            "reason":         None,
            "duration_days":  None,
            "ends_at":        None,
            "days_remaining": None,
            "last_completed": last_completed,
        })

    started_at = period.get("started_at")
    duration_days = period.get("duration_days")
    scheduled_end = period.get("scheduled_end")
    days_remaining = None
    try:
        if scheduled_end:
            end = date.fromisoformat(str(scheduled_end)[:10])
            days_remaining = max(0, (end - date.fromisoformat(_today_mtl())).days)
    except Exception:
        pass

    return jsonify({
        "active":         True,
        "started_at":     started_at,
        "reason":         period.get("reason"),
        "duration_days":  duration_days,
        "ends_at":        scheduled_end,
        "days_remaining": days_remaining,
        "last_completed": last_completed,
    })


@deload_management_bp.route("/api/deload/activate", methods=["POST"])
def api_deload_activate():
    body = request.get_json(silent=True) or {}
    reason = (body.get("reason") or "Repos volontaire").strip()
    duration_days = int(body.get("duration_days") or 7)
    started_at = body.get("started_at") or _today_mtl()
    if duration_days < 1 or duration_days > 21:
        return jsonify({"error": "duration_days doit être entre 1 et 21"}), 400
    if db.get_active_deload_period() is not None:
        return jsonify({"error": "Une décharge est déjà active"}), 409
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
