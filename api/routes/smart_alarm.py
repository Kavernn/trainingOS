"""Routes — Smart Alarm: bedtime tap + calibrated latency."""
from __future__ import annotations
from flask import Blueprint, jsonify, request

smart_alarm_bp = Blueprint("smart_alarm", __name__)


@smart_alarm_bp.route("/api/smart_alarm/bedtime", methods=["POST"])
def api_smart_alarm_bedtime():
    """Record the moment the user taps 'Je me couche' on the dashboard."""
    import db as _db
    data        = request.get_json(silent=True) or {}
    bedtime_tap = data.get("bedtime_tap")   # "HH:mm"
    date_str    = data.get("date")          # "YYYY-MM-DD" — calendar date of the tap

    if not bedtime_tap or not date_str:
        return jsonify({"error": "bedtime_tap and date required"}), 400

    ok = _db.upsert_smart_alarm_session({"date": date_str, "bedtime_tap": bedtime_tap})
    return jsonify({"ok": ok})


@smart_alarm_bp.route("/api/smart_alarm/latency", methods=["GET"])
def api_smart_alarm_latency():
    """Return calibrated sleep latency (30-day truncated mean) or default 15 min."""
    import db as _db
    from datetime import timedelta
    from statistics import mean
    from utils import _today_mtl_date

    cutoff   = (_today_mtl_date() - timedelta(days=30)).isoformat()
    sessions = _db.get_smart_alarm_sessions(since=cutoff)

    valid = [
        s["latency_min"] for s in sessions
        if s.get("latency_min") is not None and 0 <= s["latency_min"] <= 90
    ]

    n       = len(valid)
    DEFAULT = 15.0

    if n < 14:
        return jsonify({"calibrated": False, "latency_min": DEFAULT, "n": n})

    sorted_vals = sorted(valid)
    trim        = max(1, int(len(sorted_vals) * 0.10))
    trimmed     = sorted_vals[trim:-trim] if trim < len(sorted_vals) // 2 else sorted_vals
    calibrated  = max(5.0, min(45.0, round(mean(trimmed), 1)))

    return jsonify({"calibrated": True, "latency_min": calibrated, "n": n})
