from flask import Blueprint, jsonify, request
import logging

logger = logging.getLogger("trainingos")
workout_programs_bp = Blueprint("workout_programs", __name__)

# Actions mutantes de POST /api/programme. Un `program_id` explicite cible le
# programme consulté dans Structure ; en son absence, compatibilité historique
# sur le programme actif.
MUTATING_ACTIONS = frozenset({
    "create_seance", "delete_seance", "rename", "reorder_sessions",
    "add", "remove", "scheme", "replace", "reorder",
    "add_block", "remove_block", "reorder_blocks", "meta",
})


def _rest_seconds_or_error(value):
    """Repos de bibliothèque : entier > 0 obligatoire (jamais vide, jamais inventé)."""
    if isinstance(value, bool) or not isinstance(value, int) or value <= 0:
        return None, (jsonify({"error": "rest_seconds requis (entier > 0)"}), 400)
    return value, None


def _meta_fields_or_error(data):
    """Champs `meta` présents dans le payload → dict validé. rest_seconds null = « selon
    besoin » (l'app prend le repos de la bibliothèque) ; RIR null/null = pas de cible."""
    fields = {}
    if "rest_seconds" in data:
        v = data["rest_seconds"]
        if v is not None and (isinstance(v, bool) or not isinstance(v, int) or v <= 0):
            return None, (jsonify({"error": "rest_seconds invalide"}), 400)
        fields["rest_seconds"] = v
    if "target_rir_min" in data or "target_rir_max" in data:
        lo, hi = data.get("target_rir_min"), data.get("target_rir_max")
        both_null = lo is None and hi is None
        valid = all(isinstance(x, int) and not isinstance(x, bool) and 0 <= x <= 5 for x in (lo, hi))
        if not both_null and not (valid and lo <= hi):
            return None, (jsonify({"error": "RIR cible invalide (0 à 5, min ≤ max, ou les deux null)"}), 400)
        fields["target_rir_min"], fields["target_rir_max"] = lo, hi
    if "is_optional" in data:
        if not isinstance(data["is_optional"], bool):
            return None, (jsonify({"error": "is_optional invalide"}), 400)
        fields["is_optional"] = data["is_optional"]
    if not fields:
        return None, (jsonify({"error": "aucune valeur à écrire"}), 400)
    return fields, None


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

    # Structure peut éditer le contenu d'un programme non actif. Un ID explicite
    # est donc autoritaire ; seul un appel legacy sans ID retombe sur l'actif.
    # Le planning hebdomadaire reste, lui, global et actif-only via ses routes
    # dédiées — ce endpoint ne modifie jamais weekly_schedule directement.
    if action in MUTATING_ACTIONS:
        if program_id is None:
            program_id = _db.get_active_program_id()
        else:
            known_programs = _db.get_all_programs()
            if known_programs and not any(p.get("id") == program_id for p in known_programs):
                return jsonify({"error": "program_not_found"}), 404

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
        ok = _db.delete_program_session(jour, program_id)
        return jsonify({"success": ok})

    if action == "rename":
        program = _db.get_full_program(program_id)
        if program is None:
            return jsonify({"error": "Supabase indisponible"}), 503
        old_ex = data.get("old_exercise")
        new_ex = data.get("new_exercise")
        # new_scheme optional : combine rename + scheme change dans la même
        # route pour éviter deux appels API séparés (split state si le 2e
        # échoue). Appliqué dans la séance `jour` sur les blocs contenant
        # new_ex, puis UN SEUL save_full_program → fenêtre d'échec minimale.
        new_scheme = data.get("new_scheme")
        jour_for_scheme = data.get("jour") if new_scheme is not None else None

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

        # new_scheme : applique dans modified[jour] sur les blocs contenant new_ex.
        if new_scheme is not None and jour_for_scheme is not None:
            target_sdef = modified.get(jour_for_scheme) or program.get(jour_for_scheme)
            if target_sdef is None:
                return jsonify({"error": "Jour invalide"}), 400
            scheme_blocks = find_blocks_containing(target_sdef.get("blocks", []), new_ex)
            if not scheme_blocks:
                return jsonify({"error": "Exercice introuvable dans la séance"}), 404
            for block in scheme_blocks:
                block.get("exercises", {})[new_ex] = new_scheme
            modified[jour_for_scheme] = target_sdef

        # Rename atomique (migration 101) : la RPC renomme la row exercises
        # (même id → logs intacts) AVANT le pass programme, dans la même
        # transaction. Plus de row fantôme, plus de soft-delete silencieux.
        #
        # 3 cas valides + 1 erreur :
        #   (a) old présent, new absent  → rename atomique dans la RPC
        #   (b) old présent, new présent → merge non supporté (RPC lèvera
        #       unique_violation lors de l'étape 0 rename)
        #   (c) old absent, new présent  → pas de source à renommer, le
        #       programme pointera vers l'id existant de new (pas de rename,
        #       pas d'auto-create côté route non plus)
        #   (d) old absent, new absent   → ERREUR explicite. Même règle que
        #       la RPC : exercice inconnu = erreur, pas de valeurs inventées.
        inv = load_inventory() or {}
        rename_param: dict | None = None
        if old_ex != new_ex:
            if old_ex in inv:
                rename_param = {"old_name": old_ex, "new_name": new_ex}
            elif new_ex not in inv:
                # Cas (d) : catalogue désynchronisé — refuse explicitement.
                return jsonify({
                    "error": f"Renommage impossible : ni '{old_ex}' ni '{new_ex}' au catalogue.",
                    "programme_ok": False,
                }), 400
            # Cas (c) : new_ex déjà au catalogue → rename_param reste None

        try:
            report = _db.save_full_program(modified, program_id, rename=rename_param)
        except Exception as e:
            logger.error("rename: save_full_program_atomic a échoué: %s", e)
            return jsonify({
                "error": f"Échec de la sauvegarde du renommage: {e}",
                "programme_ok": False,
            }), 500

        # Règle build 3 : une modification dans un programme ne touche jamais la bibliothèque.
        return jsonify({"success": True, "report": report})

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
            # Création à la volée : ce schéma devient le 1er défaut ; repos obligatoire.
            rest, error = _rest_seconds_or_error(data.get("rest_seconds"))
            if error:
                return error
            add_exercise(exercise, {"default_scheme": scheme, "type": "machine", "increment": 5,
                                    "rest_seconds": rest})
            inv[exercise] = {"rest_seconds": rest}
        _db.save_full_program({jour: session_def}, program_id)
        # Valeur par défaut de la bibliothèque copiée À L'AJOUT ; ensuite l'exercice de
        # programme garde la sienne (modifier la bibliothèque ne la réécrit jamais).
        if not _db.set_program_exercise_meta(program_id, jour, exercise,
                                             {"rest_seconds": inv[exercise].get("rest_seconds")}):
            return jsonify({"error": "repos par défaut non copié (exercice introuvable après ajout)"}), 500
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
        return jsonify({"success": True})

    if action == "replace":
        old_ex = data.get("old_exercise")
        new_ex = data.get("new_exercise")
        scheme = data.get("scheme", "3x8-12")
        matched = find_blocks_containing(blks, old_ex)
        if not matched:
            return jsonify({"error": "Exercice introuvable dans la séance"}), 404
        # Le créneau garde son statut bonus et son RIR cible ; le repos repart du défaut
        # de bibliothèque du nouvel exercice (comme un ajout).
        old_meta = next((b.get("exercise_meta", {}).get(old_ex) for b in matched
                         if old_ex in b.get("exercise_meta", {})), None) or {}
        inv = load_inventory() or {}
        if new_ex not in inv:
            # Création à la volée (le catalogue doit connaître new_ex avant la RPC) :
            # copie de la fiche de l'ancien exercice, repos compris.
            entry = {**inv.get(old_ex, {}), "default_scheme": scheme}
            entry.setdefault("type", "machine")
            entry.setdefault("increment", 5)
            rest, error = _rest_seconds_or_error(entry.get("rest_seconds"))
            if error:
                return error
            add_exercise(new_ex, entry)
            inv[new_ex] = entry
        for block in matched:
            exos = block.get("exercises", {})
            exos.pop(old_ex, None)
            exos[new_ex] = scheme
        _db.save_full_program({jour: session_def}, program_id, allow_empty_blocks=True)
        meta = {"rest_seconds": inv[new_ex].get("rest_seconds"),
                "is_optional": bool(old_meta.get("is_optional")),
                "target_rir_min": old_meta.get("target_rir_min"),
                "target_rir_max": old_meta.get("target_rir_max")}
        if not _db.set_program_exercise_meta(program_id, jour, new_ex, meta):
            return jsonify({"error": "valeurs du créneau non copiées (exercice introuvable)"}), 500
        return jsonify({"success": True})

    if action == "meta":
        exercise = data.get("exercise")
        if not find_blocks_containing(blks, exercise):
            return jsonify({"error": "Exercice introuvable dans la séance"}), 404
        fields, error = _meta_fields_or_error(data)
        if error:
            return error
        if not _db.set_program_exercise_meta(program_id, jour, exercise, fields):
            return jsonify({"error": "Exercice introuvable dans la séance"}), 404
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
