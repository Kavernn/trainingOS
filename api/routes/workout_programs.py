from flask import Blueprint, jsonify, request
import logging

logger = logging.getLogger("trainingos")
workout_programs_bp = Blueprint("workout_programs", __name__)

# Actions mutantes de POST /api/programme. Un payload ciblant un program_id !=
# actif est refusé 409 par le garde en tête d'api_programme — évite qu'un client
# cache-stale corrompe silencieusement le mauvais programme.
MUTATING_ACTIONS = frozenset({
    "create_seance", "delete_seance", "rename", "reorder_sessions",
    "add", "remove", "scheme", "replace", "reorder",
    "add_block", "remove_block", "reorder_blocks",
})


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
                        upsert_block, remove_block, reorder_blocks,
                        find_blocks_containing, find_add_target_block)
    from inventory import load_inventory, add_exercise, rename_inventory_exercise
    data       = (request.get_json(silent=True) or {})
    action     = data.get("action")
    jour       = data.get("jour")
    program_id = data.get("program_id") or None

    # Garde fail-fast unique : toute mutation cible le programme actif, ou 409.
    # Sortie garantie : program_id == active_pid (validé ou défaut). Aucun
    # fallback get_default_program_id silencieux atteint depuis les branches
    # mutantes en aval.
    if action in MUTATING_ACTIONS:
        active_pid = _db.get_active_program_id()
        if program_id is not None and program_id != active_pid:
            return jsonify({
                "error": "program_inactive",
                "detail": "Mutation refusée : le programme ciblé n'est pas le programme actif.",
                "active_program_id": active_pid,
                "requested_program_id": program_id,
            }), 409
        if program_id is None:
            program_id = active_pid

    if action == "create_seance":
        seance_name = (jour or "").strip()
        if not seance_name:
            return jsonify({"error": "Nom invalide"}), 400
        # Idempotence : évite qu'un double-tap ou un rejeu SyncManager rappelle
        # save_full_program avec un bloc vide sur une session déjà peuplée
        # (déclencherait le garde-fou "refusing to save 0 exercises over N existing").
        # Match exact — même sémantique que l'index unique (program_id, name)
        # de program_sessions : TEXT sans citext ni LOWER, sensible casse/accents.
        existing = _db.get_full_program(program_id) or {}
        if seance_name in existing:
            logger.info(
                "create_seance: '%s' already exists for program %s — no-op",
                seance_name, program_id,
            )
            return jsonify({"success": True, "created": False})
        _db.save_full_program(
            {seance_name: {"blocks": [make_strength_block({}, order=0)]}},
            program_id,
        )
        logger.info("create_seance: '%s' created for program %s", seance_name, program_id)
        return jsonify({"success": True, "created": True})

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
        # Dossier PERSISTANCE v3 : résout l'exo dans TOUS les REPS_BLOCKS
        # de CHAQUE séance. L'ancien code ne cherchait que "strength" → sur
        # v4, un exo en force/isolation/etc. n'était jamais renommé côté
        # programme, désynchronisant inventaire (renommé) et blocs.
        modified = {}
        for sname, sdef in program.items():
            matched = find_blocks_containing(sdef.get("blocks", []), old_ex)
            if not matched:
                continue
            for block in matched:
                exos = block.get("exercises") or {}
                # Préserve l'ordre : reconstruit le dict clé par clé.
                block["exercises"] = {
                    (new_ex if n == old_ex else n): s for n, s in exos.items()
                }
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
                    hits = find_blocks_containing(sdef.get("blocks", []), new_ex)
                    if hits:
                        scheme = (hits[0].get("exercises") or {}).get(new_ex, scheme)
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

    # Dossier PERSISTANCE v3 — Direction 1 : add/remove/scheme/replace résolvent
    # le bloc réel où vit l'exo (find_blocks_containing sur TOUS les REPS_BLOCKS),
    # au lieu de deviner type="strength". Le fallback historique
    # `get_block(blks, "strength") or make_strength_block(...)` fabriquait un
    # bloc strength fantôme sur v4-like → écritures dans un vide, exo réel
    # jamais touché, réapparition au reload via merge get_strength_exercises.
    # save_full_program reçoit uniquement les blocs mutés → aucun fantôme créé,
    # les autres blocs de la séance restent intacts en base.

    if action == "add":
        exercise = data.get("exercise")
        if find_blocks_containing(blks, exercise):
            return jsonify({"error": "Déjà dans le programme"}), 400
        inv    = load_inventory() or {}
        scheme = data.get("scheme") or inv.get(exercise, {}).get("default_scheme", "3x8-12")
        target = find_add_target_block(blks)
        if target is None:
            target = make_strength_block({}, order=len(blks))
            session_def["blocks"] = upsert_block(blks, target)
        target.setdefault("exercises", {})[exercise] = scheme
        if exercise not in inv:
            add_exercise(exercise, {"default_scheme": scheme, "type": "machine", "increment": 5})
        _db.save_full_program({jour: session_def}, program_id)
        logger.info(
            "programme add: jour='%s' exercise='%s' scheme='%s' target=%s order=%s post_count=%d",
            jour, exercise, scheme, target.get("type"), target.get("order"),
            len(target["exercises"]),
        )
        return jsonify({"success": True})

    if action == "remove":
        exercise_to_remove = data.get("exercise", "")
        matched = find_blocks_containing(blks, exercise_to_remove)
        if not matched:
            return jsonify({"error": "Exercice introuvable dans la séance"}), 404
        for block in matched:
            block.get("exercises", {}).pop(exercise_to_remove, None)
        _db.save_full_program({jour: session_def}, program_id, allow_empty_blocks=True)
        return jsonify({"success": True})

    if action == "scheme":
        exercise   = data.get("exercise")
        new_scheme = data.get("scheme")
        matched = find_blocks_containing(blks, exercise)
        if not matched:
            return jsonify({"error": "Exercice introuvable dans la séance"}), 404
        for block in matched:
            block.get("exercises", {})[exercise] = new_scheme
        _db.save_full_program({jour: session_def}, program_id)
        inv = load_inventory() or {}
        if exercise in inv and isinstance(inv[exercise], dict):
            entry = dict(inv[exercise])
            entry["default_scheme"] = new_scheme
            add_exercise(exercise, entry)
        return jsonify({"success": True})

    if action == "replace":
        old_ex = data.get("old_exercise")
        new_ex = data.get("new_exercise")
        scheme = data.get("scheme", "3x8-12")
        matched = find_blocks_containing(blks, old_ex)
        if not matched:
            return jsonify({"error": "Exercice introuvable dans la séance"}), 404
        for block in matched:
            exos = block.get("exercises", {})
            exos.pop(old_ex, None)
            exos[new_ex] = scheme
        _db.save_full_program({jour: session_def}, program_id, allow_empty_blocks=True)
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
        return jsonify({"success": True})

    if action == "reorder":
        # ponytail: hors périmètre Direction 1 — reorder cross-blocs sémantique
        # ambiguë (le payload iOS envoie une liste d'exos merged sans dire dans
        # quel bloc). Conserve le comportement legacy strength-only le temps que
        # la doctrine réordre multi-blocs soit tranchée (dossier séparé).
        strength = get_block(blks, "strength") or make_strength_block({}, order=0)
        exercises = strength.get("exercises", {})
        ordre = data.get("ordre", [])
        reordered = {ex: exercises[ex] for ex in ordre if ex in exercises}
        for ex, s in exercises.items():
            if ex not in reordered:
                reordered[ex] = s
        strength["exercises"] = reordered
        session_def["blocks"] = upsert_block(blks, strength)
        _db.save_full_program({jour: session_def}, program_id)
        return jsonify({"success": True})

    if action == "add_block":
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
        _db.save_full_program({jour: session_def}, program_id)
        return jsonify({"success": True})

    if action == "remove_block":
        session_def["blocks"] = remove_block(blks, data.get("block_type", ""))
        _db.save_full_program({jour: session_def}, program_id)
        return jsonify({"success": True})

    if action == "reorder_blocks":
        session_def["blocks"] = reorder_blocks(blks, data.get("order", []))
        _db.save_full_program({jour: session_def}, program_id)
        return jsonify({"success": True})

    return jsonify({"error": "action inconnue"}), 400
