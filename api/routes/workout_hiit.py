from flask import Blueprint, jsonify, request
import logging

logger = logging.getLogger("trainingos")
workout_hiit_bp = Blueprint("workout_hiit", __name__)


@workout_hiit_bp.route("/api/log_hiit", methods=["POST"])
def api_log_hiit():
    import db as _db
    from utils import get_current_week, _today_mtl
    data           = (request.get_json(silent=True) or {})
    week           = get_current_week()
    today          = data.get("date") or _today_mtl()
    session_type   = data.get("session_type", "HIIT")
    second_session = data.get("second_session", False)
    hiit_log       = _db.get_hiit_logs() or []

    already_today = any(
        e.get("date") == today and e.get("session_type") == session_type
        for e in hiit_log
    )
    if already_today and not second_session:
        return jsonify({"error": "already_logged"}), 409

    entry = {
        "date":               today,
        "week":               week,
        "session_type":       session_type,
        "rounds_planifies":   data.get("rounds", 0),
        "rounds_completes":   data.get("rounds", 0),
        "vitesse_max":        data.get("speed"),
        "vitesse_croisiere":  data.get("vitesse_croisiere"),
        "rpe":                data.get("rpe"),
        "feeling":            data.get("feeling", "—"),
        "comment":            data.get("comment", "")
    }

    _db.insert_hiit_log(entry)
    return jsonify({"success": True})


@workout_hiit_bp.route("/api/delete_hiit", methods=["POST"])
def api_delete_hiit():
    import db as _db
    data     = (request.get_json(silent=True) or {})
    hiit_log = _db.get_hiit_logs() or []

    idx = data.get("index")
    if idx is not None and 0 <= idx < len(hiit_log):
        entry_id = hiit_log[idx].get("id")
        if entry_id:
            _db.delete_hiit_log_by_id(entry_id)
        return jsonify({"success": True})

    date         = data.get("date")
    session_type = data.get("session_type")
    if date and session_type:
        for entry in hiit_log:
            if entry.get("date") == date and entry.get("session_type") == session_type:
                _db.delete_hiit_log_by_id(entry.get("id"))
                return jsonify({"success": True})

    return jsonify({"error": "Entrée introuvable"}), 400


@workout_hiit_bp.route("/api/hiit/edit", methods=["POST"])
def api_hiit_edit():
    try:
        import db as _db
        data         = request.get_json(silent=True) or {}
        date         = data.get("date")
        session_type = data.get("session_type")
        hiit_log     = _db.get_hiit_logs() or []

        entry = next(
            (e for e in hiit_log
             if e.get("date") == date and e.get("session_type") == session_type),
            None
        )
        if entry is None:
            return jsonify({"error": "Entrée introuvable"}), 400

        patch = {}
        if "rpe"     in data: patch["rpe"]              = data["rpe"]
        if "rounds"  in data: patch["rounds_completes"] = data["rounds"]
        if "notes"   in data: patch["comment"]          = data["notes"]
        if "feeling" in data: patch["feeling"]          = data["feeling"]

        _db.update_hiit_log(entry.get("id"), patch)
        return jsonify({"success": True})
    except Exception:
        raise


@workout_hiit_bp.route("/api/hiit_data")
def api_hiit_data():
    from utils import load_hiit_log
    hiit_log = load_hiit_log()
    total    = len(hiit_log)
    avg_rpe  = round(sum(e.get("rpe", 0) for e in hiit_log) / total, 1) if total else 0
    return jsonify({
        "hiit_log": hiit_log,
        "total":    total,
        "avg_rpe":  avg_rpe,
    })
