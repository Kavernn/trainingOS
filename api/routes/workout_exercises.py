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
        "type":              data.get("type", "machine"),
        "increment":         float(data.get("increment", 5)),
        "bar_weight":        float(data.get("bar_weight", 0)),
        "default_scheme":    data.get("default_scheme", "3x8-12"),
        "muscles":           data.get("muscles", []),
        "category":          data.get("category", ""),
        "level":             data.get("level", ""),
        "pattern":           data.get("pattern", ""),
        "tracking_type":     "time" if data.get("weight_type") == "endurance" else data.get("tracking_type", "reps"),
        "rest_seconds":      data.get("rest_seconds"),
        "load_profile":      raw_load_profile if raw_load_profile else None,
        "tips":              data.get("tips") or None,
        # classification anatomique + fonctionnelle (migration 063)
        "muscle_group":      data.get("muscle_group") or None,
        "muscle_specific":   data.get("muscle_specific") or None,
        "secondary_muscles": data.get("secondary_muscles") or [],
        "movement_pattern":  data.get("movement_pattern") or None,
        "weight_type":       data.get("weight_type") or None,
        "equipment":         data.get("equipment") or [],
        "alternate_name":    data.get("alternate_name") or None,
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
    try:
        _db.recompute_exercise_pr(exercise)
    except Exception as _pr_exc:
        import logging as _logging
        _logging.getLogger("trainingos").warning("PR recompute skipped for %s: %s", exercise, _pr_exc)

    return jsonify({"success": True})


@workout_exercises_bp.route("/api/exercises/classification_gaps", methods=["GET"])
def api_classification_gaps():
    """Return exercises missing muscle_group or muscle_specific, with rule-based suggestions.

    Response: {"gaps": [{name, current_muscle_group, current_muscle_specific,
                          suggested_muscle_group, suggested_muscle_specific,
                          suggested_movement_pattern}], "total": N}
    """
    from inventory import load_inventory
    from muscle_classification import suggest_classification
    inv = load_inventory() or {}
    gaps = []
    for name, data in inv.items():
        mg = (data.get("muscle_group") or "").strip()
        ms = (data.get("muscle_specific") or "").strip()
        if mg and ms:
            continue
        suggestion = suggest_classification(name, data)
        if not suggestion:
            continue
        gaps.append({
            "name":                     name,
            "current_muscle_group":     mg or None,
            "current_muscle_specific":  ms or None,
            "suggested_muscle_group":   suggestion.get("muscle_group"),
            "suggested_muscle_specific": suggestion.get("muscle_specific"),
            "suggested_movement_pattern": suggestion.get("movement_pattern"),
        })
    gaps.sort(key=lambda x: x["name"])
    return jsonify({"gaps": gaps, "total": len(gaps)})


@workout_exercises_bp.route("/api/exercises/classify", methods=["POST"])
def api_exercise_classify():
    """Patch muscle_group / muscle_specific / movement_pattern on an existing exercise.

    Body: {"name": "...", "muscle_group": "...", "muscle_specific": "...", "movement_pattern": "..."}
    All classification fields are optional — only non-null values are written.
    """
    import db as _db
    data = request.get_json(silent=True) or {}
    name = data.get("name", "").strip()
    if not name:
        return jsonify({"error": "name required"}), 400
    ex_id = _db.get_exercise_id(name)
    if not ex_id:
        return jsonify({"error": "exercise not found"}), 404
    patch = {
        k: data.get(k) or None
        for k in ("muscle_group", "muscle_specific", "movement_pattern")
        if data.get(k)
    }
    if not patch:
        return jsonify({"error": "nothing to update"}), 400
    try:
        _db._client.table("exercises").update(patch).eq("id", ex_id).execute()
    except Exception as e:
        return jsonify({"error": str(e)}), 500
    return jsonify({"ok": True, "name": name, **patch})


@workout_exercises_bp.route("/api/exercises/auto_classify", methods=["POST"])
def api_auto_classify_all():
    """Apply suggest_classification() to all exercises missing muscle_group or movement_pattern.

    ?dry_run=true  → retourne le mapping prévu sans écrire en base.
    Returns: {"applied": N, "skipped": M, "errors": [...]}
    Dry-run: {"preview": [{name, patch}], "skipped": M}
    """
    from inventory import load_inventory
    from muscle_classification import suggest_classification
    import db as _db

    dry_run = request.args.get("dry_run", "").lower() in ("1", "true")
    inv = load_inventory() or {}
    applied = 0
    skipped = 0
    errors = []
    preview = []

    for name, data in inv.items():
        mg  = (data.get("muscle_group")     or "").strip()
        mp  = (data.get("movement_pattern") or "").strip()
        wt  = (data.get("weight_type")      or "").strip()
        if mg and mp and wt:
            skipped += 1
            continue

        suggestion = suggest_classification(name, data)
        if not suggestion:
            skipped += 1
            continue

        patch = {k: v for k, v in suggestion.items() if v and not data.get(k)}
        if not patch:
            skipped += 1
            continue

        if dry_run:
            preview.append({"name": name, "patch": patch})
            continue

        ex_id = _db.get_exercise_id(name)
        if not ex_id:
            errors.append(f"{name}: not found")
            continue

        try:
            _db._client.table("exercises").update(patch).eq("id", ex_id).execute()
            applied += 1
        except Exception as e:
            errors.append(f"{name}: {e}")

    if dry_run:
        return jsonify({"preview": preview, "skipped": skipped})
    return jsonify({"applied": applied, "skipped": skipped, "errors": errors})
