from flask import Blueprint, jsonify, request
import logging

logger = logging.getLogger("trainingos")
workout_programs_bp = Blueprint("workout_programs", __name__)


@workout_programs_bp.route("/api/programs", methods=["GET", "POST"])
def api_programs():
    """GET  → [{id, name, created_at}, ...]
    POST → {action: "create"|"rename"|"delete", ...}
    """
    import db as _db
    if request.method == "GET":
        return jsonify(_db.get_all_programs())

    data   = request.get_json() or {}
    action = data.get("action")

    if action == "create":
        name = (data.get("name") or "").strip()
        if not name:
            return jsonify({"error": "Nom invalide"}), 400
        pid = _db.create_program(name)
        return jsonify({"success": bool(pid), "id": pid})

    if action == "rename":
        pid  = data.get("program_id", "")
        name = (data.get("name") or "").strip()
        if not pid or not name:
            return jsonify({"error": "program_id et name requis"}), 400
        ok = _db.rename_program(pid, name)
        return jsonify({"success": ok})

    if action == "delete":
        pid = data.get("program_id", "")
        if not pid:
            return jsonify({"error": "program_id requis"}), 400
        if len(_db.get_all_programs()) <= 1:
            return jsonify({"error": "Impossible de supprimer le dernier programme"}), 400
        ok = _db.delete_program(pid)
        return jsonify({"success": ok})

    if action == "set_active":
        pid = data.get("program_id", "")
        if not pid:
            return jsonify({"error": "program_id requis"}), 400
        ok = _db.set_active_program_id(pid)
        return jsonify({"success": ok})

    return jsonify({"error": "action inconnue"}), 400


@workout_programs_bp.route("/api/programme", methods=["POST"])
def api_programme():
    import db as _db
    from planner import load_program, save_program
    from blocks import (make_strength_block, make_hiit_block, make_cardio_block,
                        get_block, get_strength_exercises,
                        upsert_block, remove_block, reorder_blocks)
    from inventory import load_inventory, add_exercise, rename_inventory_exercise
    data       = (request.get_json(silent=True) or {})
    action     = data.get("action")
    jour       = data.get("jour")
    program_id = data.get("program_id") or None

    if action == "create_seance":
        seance_name = (jour or "").strip()
        if not seance_name:
            return jsonify({"error": "Nom invalide"}), 400
        _db.save_full_program({seance_name: {"blocks": [make_strength_block({}, order=0)]}}, program_id)
        return jsonify({"success": True})

    if action == "delete_seance":
        if not jour:
            return jsonify({"error": "jour manquant"}), 400
        ok = _db.delete_program_session(jour)
        return jsonify({"success": ok})

    if action == "rename":
        program = _db.get_full_program(program_id)
        if program is None:
            return jsonify({"error": "Supabase indisponible"}), 503
        old_ex = data.get("old_exercise")
        new_ex = data.get("new_exercise")
        modified = {}
        for sname, sdef in program.items():
            sb = get_block(sdef.get("blocks", []), "strength")
            if sb and old_ex in sb.get("exercises", {}):
                sb["exercises"][new_ex] = sb["exercises"].pop(old_ex)
                modified[sname] = sdef
        if modified:
            _db.save_full_program(modified, program_id)
        inv = load_inventory() or {}
        if new_ex in inv:
            if old_ex in inv:
                from db import delete_exercise_by_name
                delete_exercise_by_name(old_ex)
        else:
            info = inv.get(old_ex)
            if info is None:
                scheme = "3x8-12"
                for sdef in program.values():
                    sb = get_block(sdef.get("blocks", []), "strength")
                    if sb and new_ex in sb.get("exercises", {}):
                        scheme = sb["exercises"][new_ex]
                        break
                info = {"type": "machine", "increment": 5, "default_scheme": scheme}
            rename_inventory_exercise(old_ex, new_ex, info)
        return jsonify({"success": True})

    if action == "reorder_sessions":
        order = data.get("order", [])
        if not order or not program_id:
            return jsonify({"error": "order et program_id requis"}), 400
        ok = _db.reorder_program_sessions(order, program_id)
        return jsonify({"success": ok})

    if jour is None:
        return jsonify({"error": "jour manquant"}), 400

    session_data = _db.get_full_program(program_id)
    if session_data is None:
        return jsonify({"error": "Impossible de lire le programme (Supabase indisponible)"}), 503
    if jour not in session_data:
        return jsonify({"error": "Jour invalide"}), 400

    session_def = session_data[jour]
    blks        = session_def.get("blocks", [])

    if action in ("add", "remove", "scheme", "replace", "reorder"):
        strength  = get_block(blks, "strength") or make_strength_block({}, order=0)
        exercises = strength.get("exercises", {})

        if action == "add":
            exercise = data.get("exercise")
            if exercise in exercises:
                return jsonify({"error": "Déjà dans le programme"}), 400
            inv    = load_inventory() or {}
            scheme = data.get("scheme") or inv.get(exercise, {}).get("default_scheme", "3x8-12")
            exercises[exercise] = scheme
            if exercise not in inv:
                add_exercise(exercise, {"default_scheme": scheme, "type": "machine", "increment": 5})

        elif action == "remove":
            exercise_to_remove = data.get("exercise", "")
            exercises.pop(exercise_to_remove, None)

        elif action == "scheme":
            exercise   = data.get("exercise")
            new_scheme = data.get("scheme")
            if exercise in exercises:
                exercises[exercise] = new_scheme
                inv = load_inventory() or {}
                if exercise in inv and isinstance(inv[exercise], dict):
                    entry = dict(inv[exercise])
                    entry["default_scheme"] = new_scheme
                    add_exercise(exercise, entry)

        elif action == "replace":
            old_ex = data.get("old_exercise")
            new_ex = data.get("new_exercise")
            scheme = data.get("scheme", "3x8-12")
            exercises.pop(old_ex, None)
            exercises[new_ex] = scheme
            inv = load_inventory() or {}
            if new_ex not in inv:
                entry = {**inv.get(old_ex, {}), "default_scheme": scheme}
                entry.setdefault("type", "machine")
                entry.setdefault("increment", 5)
                add_exercise(new_ex, entry)
            else:
                entry = dict(inv[new_ex])
                entry["default_scheme"] = scheme
                add_exercise(new_ex, entry)

        elif action == "reorder":
            ordre = data.get("ordre", [])
            reordered = {ex: exercises[ex] for ex in ordre if ex in exercises}
            for ex, scheme in exercises.items():
                if ex not in reordered:
                    reordered[ex] = scheme
            exercises = reordered

        strength["exercises"] = exercises
        session_def["blocks"] = upsert_block(blks, strength)

    elif action == "add_block":
        block_type = data.get("block_type")
        if block_type == "strength":
            new_block = make_strength_block(data.get("exercises", {}), order=len(blks))
        elif block_type == "hiit":
            new_block = make_hiit_block(data.get("hiit_config"), order=len(blks))
        elif block_type == "cardio":
            new_block = make_cardio_block(data.get("cardio_config"), order=len(blks))
        else:
            return jsonify({"error": "block_type invalide"}), 400
        session_def["blocks"] = upsert_block(blks, new_block)

    elif action == "remove_block":
        session_def["blocks"] = remove_block(blks, data.get("block_type", ""))

    elif action == "reorder_blocks":
        session_def["blocks"] = reorder_blocks(blks, data.get("order", []))

    _db.save_full_program({jour: session_def}, program_id)
    _db.set_active_program_id(program_id)
    return jsonify({"success": True})
