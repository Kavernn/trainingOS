from flask import Blueprint, jsonify, request
import logging

logger = logging.getLogger("trainingos")
workout_exercises_bp = Blueprint("workout_exercises", __name__)


@workout_exercises_bp.route("/api/save_exercise", methods=["POST"])
def api_save_exercise():
    from inventory import load_inventory, add_exercise, rename_inventory_exercise
    from planner import load_program, save_program
    from blocks import get_block, get_strength_exercises
    data          = (request.get_json(silent=True) or {})
    original_name = data.get("original_name", "").strip()
    name          = data.get("name", "").strip()

    if not name:
        return jsonify({"error": "Nom manquant"}), 400

    inv = load_inventory() or {}

    raw_load_profile = data.get("load_profile")
    entry = {
        "type":           data.get("type", "machine"),
        "increment":      float(data.get("increment", 5)),
        "bar_weight":     float(data.get("bar_weight", 0)),
        "default_scheme": data.get("default_scheme", "3x8-12"),
        "muscles":        data.get("muscles", []),
        "category":       data.get("category", ""),
        "level":          data.get("level", ""),
        "pattern":        data.get("pattern", ""),
        "tracking_type":  data.get("tracking_type", "reps"),
        "rest_seconds":   data.get("rest_seconds"),
        "load_profile":   raw_load_profile if raw_load_profile else None,
        "tips":           data.get("tips") or None,
    }

    if original_name and original_name != name:
        rename_inventory_exercise(original_name, name, entry)
        import db as _db
        program = _db.get_full_program()
        if program is not None:
            modified = {}
            for sname, sdef in program.items():
                sb = get_block(sdef.get("blocks", []), "strength")
                if sb and original_name in sb.get("exercises", {}):
                    sb["exercises"][name] = sb["exercises"].pop(original_name)
                    modified[sname] = sdef
            if modified:
                save_program(modified)
    else:
        add_exercise(name, entry)
        import db as _db
        ex_id = _db.get_exercise_id(name)
        new_scheme = entry.get("default_scheme", "")
        if ex_id and new_scheme:
            _db.update_program_scheme_for_exercise(ex_id, new_scheme)

    return jsonify({"success": True})


@workout_exercises_bp.route("/api/exercises/normalize_schemes", methods=["POST"])
def api_normalize_schemes():
    import db as _db
    max_sets = (request.get_json(silent=True) or {}).get("max_sets", 3)
    n = _db.normalize_schemes_max_sets(int(max_sets))
    return jsonify({"ok": True, "updated": n})


@workout_exercises_bp.route("/api/exercises/set_all_rest", methods=["POST"])
def api_set_all_rest():
    import db as _db
    seconds = (request.get_json(silent=True) or {}).get("seconds", 120)
    if not isinstance(seconds, int) or seconds < 10:
        return jsonify({"error": "seconds doit être un entier ≥ 10"}), 400
    ok = _db.bulk_set_rest_seconds(seconds)
    if not ok:
        return jsonify({"error": "Erreur base de données"}), 500
    return jsonify({"ok": True, "seconds": seconds})


@workout_exercises_bp.route("/api/delete_exercise", methods=["POST"])
def api_delete_exercise():
    name = (request.get_json(silent=True) or {}).get("name", "").strip()
    if not name:
        return jsonify({"error": "Nom manquant"}), 400

    import db as _db
    deleted = _db.delete_exercise_by_name(name)
    if not deleted:
        return jsonify({"error": "Exercice introuvable ou déjà supprimé"}), 404

    return jsonify({"success": True})


@workout_exercises_bp.route("/api/delete_exercise_log", methods=["POST"])
def api_delete_exercise_log():
    """Remove a specific exercise history entry by name + date."""
    data     = (request.get_json(silent=True) or {}) or {}
    exercise = data.get("exercise", "").strip()
    date     = data.get("date", "").strip()
    if not exercise or not date:
        return jsonify({"error": "exercise et date requis"}), 400

    import db as _db
    _db.delete_exercise_log_entry(date, exercise)

    return jsonify({"success": True})


@workout_exercises_bp.route("/api/exercise/set_gif", methods=["POST"])
def api_exercise_set_gif():
    """Manually override gif_url for a specific exercise.
    Body: {"name": "Nordic Curl", "gif_url": "https://..."}
    """
    import db as _db
    data    = request.get_json(silent=True) or {}
    name    = data.get("name", "").strip()
    gif_url = data.get("gif_url", "").strip()
    if not name:
        return jsonify({"error": "name required"}), 400
    update = {"gif_url": gif_url if gif_url else None}
    try:
        _db._client.table("exercises").update(update).eq("name", name).execute()
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    return jsonify({"ok": True, "name": name, "gif_url": gif_url or None})


@workout_exercises_bp.route("/api/exercise/media", methods=["GET"])
def api_exercise_media():
    import db as _db
    name = request.args.get("name", "").strip()
    if not name:
        return jsonify({"error": "name required"}), 400
    row = _db.get_exercise_by_name(name)
    if not row:
        return jsonify({}), 404
    return jsonify({
        "gif_url":  row.get("gif_url"),
        "alt_url":  row.get("image_url_alt"),
        "muscles":  row.get("muscles") or [],
        "tips":     row.get("tips"),
        "level":    row.get("level") or "",
        "pattern":  row.get("pattern") or "",
        "type":     row.get("type") or "",
    })
