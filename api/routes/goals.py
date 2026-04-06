from flask import Blueprint, jsonify, request

goals_bp = Blueprint("goals", __name__)


@goals_bp.route("/api/set_goal", methods=["POST"])
def api_set_goal():
    from goals import set_goal
    data     = request.json
    exercise = data.get("exercise")
    weight   = float(data.get("goal_weight") or data.get("weight") or 0)
    deadline = data.get("deadline")
    note     = data.get("note", "")

    if not exercise or not weight:
        return jsonify({"error": "Données manquantes"}), 400

    set_goal(exercise, weight, deadline, note)
    return jsonify({"success": True})


@goals_bp.route("/api/body_weight", methods=["POST"])
def api_body_weight():
    try:
        from body_weight import log_body_weight
        data     = request.get_json()
        poids     = float(data.get("poids", 0))
        note      = data.get("note", "")
        body_fat  = data.get("body_fat")
        waist_cm  = data.get("waist_cm")
        arms_cm   = data.get("arms_cm")
        chest_cm  = data.get("chest_cm")
        thighs_cm = data.get("thighs_cm")
        hips_cm   = data.get("hips_cm")
        for key, val in [("body_fat", body_fat), ("waist_cm", waist_cm),
                         ("arms_cm", arms_cm), ("chest_cm", chest_cm),
                         ("thighs_cm", thighs_cm), ("hips_cm", hips_cm)]:
            if val is not None:
                locals()[key]  # already set
        body_fat  = float(body_fat)  if body_fat  is not None else None
        waist_cm  = float(waist_cm)  if waist_cm  is not None else None
        arms_cm   = float(arms_cm)   if arms_cm   is not None else None
        chest_cm  = float(chest_cm)  if chest_cm  is not None else None
        thighs_cm = float(thighs_cm) if thighs_cm is not None else None
        hips_cm   = float(hips_cm)   if hips_cm   is not None else None
        if not poids:
            return jsonify({"error": "Poids invalide"}), 400
        log_body_weight(poids, note, body_fat, waist_cm, arms_cm, chest_cm, thighs_cm, hips_cm)
        return jsonify({"success": True, "poids": poids})
    except Exception:
        raise


@goals_bp.route("/api/body_weight/update", methods=["POST"])
def api_update_body_weight():
    try:
        import db as _db
        data      = request.get_json()
        target_date = data.get("date", "")
        new_poids = float(data.get("poids", 0))
        body_fat  = float(data.get("body_fat")) if data.get("body_fat") is not None else None
        note      = data.get("note", "")
        waist_cm  = float(data.get("waist_cm"))  if data.get("waist_cm")  is not None else None
        arms_cm   = float(data.get("arms_cm"))   if data.get("arms_cm")   is not None else None
        chest_cm  = float(data.get("chest_cm"))  if data.get("chest_cm")  is not None else None
        thighs_cm = float(data.get("thighs_cm")) if data.get("thighs_cm") is not None else None
        hips_cm   = float(data.get("hips_cm"))   if data.get("hips_cm")   is not None else None
        ok = _db.upsert_body_weight(
            target_date, new_poids, note=note,
            body_fat=body_fat, waist_cm=waist_cm, arms_cm=arms_cm,
            chest_cm=chest_cm, thighs_cm=thighs_cm, hips_cm=hips_cm,
        )
        if not ok:
            return jsonify({"success": False, "error": "Entrée introuvable"}), 404
        return jsonify({"success": True})
    except Exception:
        raise


@goals_bp.route("/api/body_weight/delete", methods=["POST"])
def api_delete_body_weight():
    try:
        import db as _db
        data  = request.get_json()
        ok = _db.delete_body_weight(data.get("date", ""))
        if not ok:
            return jsonify({"success": False, "error": "Entrée introuvable"}), 404
        return jsonify({"success": True})
    except Exception:
        raise


@goals_bp.route("/api/smart_goals", methods=["GET"])
def api_get_smart_goals():
    import db as _db
    goals  = _db.get_smart_goals()
    result = []
    for g in goals:
        gtype   = g.get("type", "")
        target  = g.get("target_value") or 0
        initial = g.get("initial_value")
        meta    = _db.SMART_GOAL_META.get(gtype, {})
        lower   = meta.get("lower_is_better", False)
        current = _db.compute_smart_goal_current(gtype)
        progress = _db.compute_smart_goal_progress(current, target, initial, lower)
        achieved = (current is not None) and (current <= target if lower else current >= target)
        result.append({
            "id":              g.get("id"),
            "type":            gtype,
            "target_value":    target,
            "initial_value":   initial,
            "current_value":   current,
            "target_date":     str(g.get("target_date") or ""),
            "label":           meta.get("label", gtype),
            "unit":            meta.get("unit", ""),
            "lower_is_better": lower,
            "progress":        progress,
            "achieved":        achieved,
        })
    return jsonify({"smart_goals": result})


@goals_bp.route("/api/smart_goals/save", methods=["POST"])
def api_save_smart_goal():
    import db as _db
    data        = request.get_json()
    goal_type   = data.get("type", "")
    target      = float(data.get("target_value", 0))
    target_date = data.get("target_date") or None
    goal_id     = data.get("id")
    if not goal_type or not target:
        return jsonify({"error": "type et target_value requis"}), 400
    initial = None if goal_id else _db.compute_smart_goal_current(goal_type)
    row = _db.upsert_smart_goal(goal_type, target, initial_value=initial,
                                target_date=target_date, goal_id=goal_id)
    if row:
        return jsonify({"success": True, "id": row.get("id")})
    return jsonify({"error": "Erreur sauvegarde"}), 500


@goals_bp.route("/api/smart_goals/delete", methods=["POST"])
def api_delete_smart_goal():
    import db as _db
    data    = request.get_json()
    goal_id = data.get("id", "")
    if not goal_id:
        return jsonify({"error": "id requis"}), 400
    return jsonify({"success": _db.delete_smart_goal(goal_id)})


@goals_bp.route("/api/archive_objectif", methods=["POST"])
def api_archive_objectif():
    """Marque un objectif comme archivé (caché de la liste principale)."""
    import db as _db
    data     = request.get_json() or {}
    exercise = data.get("exercise", "")
    if not exercise:
        return jsonify({"error": "missing exercise"}), 400
    _db.add_goal_archived(exercise)
    return jsonify({"ok": True})


@goals_bp.route("/api/objectifs_data")
def api_objectifs_data():
    import db as _db
    from weights import load_weights
    from goals import load_goals, get_progress_bar
    weights  = load_weights()
    goals    = load_goals()
    archived = set(_db.get_goals_archived())
    goals_progress = {}
    for ex, goal in goals.items():
        current = weights.get(ex, {}).get("current_weight", 0) or 0
        goals_progress[ex] = {
            "current":  current,
            "goal":     goal.get("goal_weight") or goal.get("target_weight", 0),
            "bar":      get_progress_bar(current, goal.get("goal_weight") or goal.get("target_weight", 0)),
            "achieved": goal.get("achieved", False),
            "deadline": goal.get("deadline", "") or goal.get("target_date", ""),
            "note":     goal.get("note", ""),
            "archived": ex in archived,
        }
    return jsonify({"goals": goals_progress})
