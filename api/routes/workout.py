from flask import Blueprint, jsonify, request
from datetime import datetime
import re

workout_bp = Blueprint("workout", __name__)


@workout_bp.route("/api/log", methods=["POST"])
def api_log():
    try:
        from weights import load_weights
        from progression import (estimate_1rm, progression_status, parse_reps,
                                  suggest_next_weight, prescribe_volume)
        from goals import check_goals_achieved
        from deload import get_cached_fatigue_score
        from volume import calc_set_volume, calc_exercise_volume
        from user_profile import load_user_profile
        from utils import _today_mtl
        import db as _db

        data     = request.get_json()
        exercise = data.get("exercise")
        weight   = float(data.get("weight", 0))
        reps_str = data.get("reps", "")
        rpe_raw  = data.get("rpe")
        rpe      = float(rpe_raw) if rpe_raw is not None else None

        force          = bool(data.get("force", False))
        is_second      = bool(data.get("is_second", False))
        is_bonus       = bool(data.get("is_bonus", False))
        # Allow client to explicitly route logs to a specific date/session type.
        session_date   = data.get("session_date") or data.get("date")
        session_type   = (data.get("session_type") or "").strip().lower()
        session_name   = data.get("session_name")
        equipment_type = data.get("equipment_type", "")
        pain_zone      = data.get("pain_zone", "")

        if not exercise or not reps_str:
            return jsonify({"error": "Données manquantes"}), 400

        weights   = load_weights()

        # Duplicate-prevention guard (skipped for force overwrite, evening, or bonus session)
        existing_history = weights.get(exercise, {}).get("history", [])
        if not force and not is_second and not is_bonus and existing_history and existing_history[0]["date"] == _today_mtl():
            return jsonify({
                "error":      "already_logged",
                "new_weight": weights[exercise].get("current_weight", 0),
                "1rm":        existing_history[0].get("1rm", 0),
            }), 409

        # Remove existing entry for today if force overwrite
        if force and existing_history and existing_history[0]["date"] == _today_mtl():
            weights[exercise]["history"].pop(0)

        # Optional per-set data: [{weight: X, reps: "5"}, ...]
        sets_data = data.get("sets", [])

        # If sets provided, use first working set as the training weight.
        # First set is the primary stimulus; averaging distorts progression
        # signals when later sets are lighter (fatigue drops, drop sets, etc.)
        if sets_data:
            first_weights = [float(s["weight"]) for s in sets_data
                             if s.get("weight") and float(s["weight"]) > 0]
            if first_weights:
                weight = round(first_weights[0], 1)

        reps_list = parse_reps(reps_str)
        reps      = ",".join(map(str, reps_list))
        status    = progression_status(reps, exercise)
        # RPE-based autoregulation: use last history RPE if not provided in request
        if rpe is None:
            last_entry = weights.get(exercise, {}).get("history", [{}])[0] if weights.get(exercise, {}).get("history") else {}
            rpe = last_entry.get("rpe")
            if rpe is not None:
                rpe = float(rpe)
        # Compute avg_rir from sets if provided
        avg_rir = None
        if sets_data:
            rir_vals = [float(s["rir"]) for s in sets_data if s.get("rir") is not None]
            if rir_vals:
                avg_rir = round(sum(rir_vals) / len(rir_vals), 1)

        fatigue_score = get_cached_fatigue_score()
        new_w, action = suggest_next_weight(
            exercise, weight, reps, rpe,
            history=existing_history, avg_rir=avg_rir,
            fatigue_score=fatigue_score,
        )
        increase  = action == "increase"
        onerm     = estimate_1rm(weight, reps)

        # PR detection: compare new 1RM against historical 1RMs (snapshot before insert)
        prev_1rms = [e.get("1rm", 0) for e in existing_history]
        is_pr = bool(onerm > 0 and (not prev_1rms or onerm > max(prev_1rms)))

        # Resolve volume weight for bodyweight exercises
        if equipment_type == "bodyweight" and weight == 0:
            bw_logs = _db.get_body_weight_logs(limit=1)
            if bw_logs and bw_logs[0].get("weight"):
                volume_weight = float(bw_logs[0]["weight"])
            else:
                profile = load_user_profile()
                volume_weight = float(profile.get("weight") or 0)
        else:
            volume_weight = weight

        # Annotate each set with total_weight and set_volume, compute exercise_volume
        if sets_data:
            for s in sets_data:
                sw = float(s.get("weight", 0) or 0)
                # For bodyweight sets with no lest, use volume_weight for set volume
                sv_weight = volume_weight if (equipment_type == "bodyweight" and sw == 0) else sw
                s["total_weight"] = sw
                s["set_volume"] = calc_set_volume(sv_weight, s.get("reps", 0))
            exercise_volume = round(sum(s.get("set_volume", 0.0) for s in sets_data), 2)
        else:
            exercise_volume = calc_exercise_volume(volume_weight, reps)

        action_notes = {"increase": f"+{new_w - weight:.1f}", "maintain": "stagné", "decrease": f"{new_w - weight:.1f}"}
        history_entry = {
            "date":            _today_mtl(),
            "weight":          round(weight, 1),
            "reps":            reps,
            "note":            action_notes.get(action, "stagné"),
            "1rm":             onerm,
            "exercise_volume": exercise_volume,
        }
        if rpe is not None:
            history_entry["rpe"] = rpe
        if sets_data:
            history_entry["sets"] = sets_data
        if pain_zone:
            history_entry["pain_zone"] = pain_zone

        if exercise not in weights:
            weights[exercise] = {"history": []}

        weights[exercise].setdefault("history", []).insert(0, history_entry)
        weights[exercise]["history"] = weights[exercise]["history"][:20]
        # Don't overwrite current_weight with 0 for bodyweight-only — keep last lest value
        if not (equipment_type == "bodyweight" and weight == 0):
            weights[exercise]["current_weight"] = round(new_w, 1)
        weights[exercise]["last_reps"] = reps
        weights[exercise]["last_logged"]    = datetime.now().strftime("%Y-%m-%d %H:%M")

        # Ensure session stub exists; write exercise log directly by session_id
        today = session_date or _today_mtl()
        is_evening = is_second or session_type == "evening"
        is_bonus_session = is_bonus or session_type == "bonus"
        if is_bonus_session:
            stub = _db.get_or_create_workout_session_bonus(today)
        elif is_evening:
            stub = _db.get_or_create_workout_session_second(today)
        else:
            stub = _db.get_or_create_workout_session(today)

        sid = (stub or {}).get("id")
        if sid:
            _db.upsert_exercise_log_direct(
                sid, exercise, round(weight, 1), reps,
                sets_json=sets_data or None,
                rpe=rpe,
                pain_zone=pain_zone or None,
            )
            # Keep the session label aligned with the logged exercise stream.
            if session_name:
                if is_bonus_session:
                    _db.update_workout_session_by_type(today, "bonus", {"session_name": session_name})
                elif is_evening:
                    _db.update_workout_session_by_type(today, "evening", {"session_name": session_name})
                else:
                    _db.update_workout_session_by_type(today, "morning", {"session_name": session_name})
        # Keep exercises.current_weight in sync (bodyweight skipped — weight=0)
        if not (equipment_type == "bodyweight" and weight == 0):
            _db.update_exercise_current_weight(exercise, round(new_w, 1))
        achieved = check_goals_achieved(weights)

        return jsonify({
            "success":    True,
            "status":     status,
            "increase":   increase,
            "new_weight": new_w,
            "1rm":        onerm,
            "is_pr":      is_pr,
            "achieved":   achieved
        })
    except Exception:
        raise


@workout_bp.route("/api/session/edit", methods=["POST"])
def api_session_edit():
    """Edit an existing session: RPE, comment, and/or individual exercise weight/reps."""
    try:
        data    = request.get_json()
        date    = data.get("date")
        if not date:
            return jsonify({"error": "date manquante"}), 400

        # Update sessions store (RPE / comment) — KV legacy
        from sessions import load_sessions, save_sessions
        from weights import load_weights
        sessions = load_sessions()
        if date not in sessions:
            sessions[date] = {}
        if "rpe" in data:
            sessions[date]["rpe"] = data["rpe"]
        if "comment" in data:
            sessions[date]["comment"] = data["comment"]
        save_sessions(sessions)

        # Persist RPE / comment to Supabase
        import db as _db
        session_type = data.get("session_type", "morning")
        supabase_patch = {}
        if "rpe" in data:
            supabase_patch["rpe"] = data["rpe"]
        if "comment" in data:
            supabase_patch["comment"] = data["comment"]
        if supabase_patch:
            _db.update_workout_session_by_type(date, session_type, supabase_patch)

        # Update weights store for each exercise edit
        exercise_edits = data.get("exercises", [])
        if exercise_edits:
            import db as _db
            weights = load_weights()
            for edit in exercise_edits:
                ex    = edit.get("exercise")
                new_w = edit.get("weight")
                new_r = edit.get("reps")
                if not ex or ex not in weights:
                    continue
                history = weights[ex].get("history", [])
                # Find and update existing entry for this date
                updated = False
                for entry in history:
                    if entry.get("date") == date:
                        if new_w is not None:
                            entry["weight"] = float(new_w)
                        if new_r is not None:
                            entry["reps"] = str(new_r)
                        # Recalculate 1RM (Epley) so stats/PRs stay accurate
                        w = entry["weight"]
                        reps_list = [int(x) for x in str(entry["reps"]).split(",") if x.strip().isdigit()]
                        if reps_list and w:
                            avg_reps = sum(reps_list) / len(reps_list)
                            entry["1rm"] = round(w * (1 + avg_reps / 30), 1)
                        updated = True
                        break
                if not updated:
                    w = float(new_w or 0)
                    r = str(new_r or "")
                    reps_list = [int(x) for x in r.split(",") if x.strip().isdigit()]
                    avg_reps  = sum(reps_list) / len(reps_list) if reps_list else 0
                    one_rm    = round(w * (1 + avg_reps / 30), 1) if w and avg_reps else 0
                    history.insert(0, {"date": date, "weight": w, "reps": r, "1rm": one_rm})
                    weights[ex]["history"] = history[:20]
                # Always recalculate current_weight/last_reps from the most recent entry
                if history:
                    most_recent = max(history, key=lambda e: e.get("date", ""))
                    weights[ex]["current_weight"] = most_recent["weight"]
                    weights[ex]["last_reps"]      = most_recent["reps"]
                # Persist the edited entry directly (may be a past date, not history[0])
                for entry in history:
                    if entry.get("date") == date:
                        _db.upsert_exercise_log(date, ex, entry.get("weight"), entry.get("reps"))
                        break

        return jsonify({"success": True})
    except Exception:
        raise


@workout_bp.route("/api/session/delete", methods=["POST"])
def api_session_delete():
    """Delete an entire session (removes from sessions store + weights history)."""
    try:
        data = request.get_json()
        date = data.get("date")
        if not date:
            return jsonify({"error": "date manquante"}), 400

        session_type = data.get("session_type", "morning")

        # Delete from relational layer
        import db as _db
        if session_type == "bonus":
            bonus_session = _db.get_workout_session_bonus(date)
            if bonus_session:
                _db.delete_exercise_logs_for_session(bonus_session["id"])
            _db.delete_workout_session_by_type(date, "bonus")
        else:
            _db.delete_session_exercise_logs(date)
            _db.delete_workout_session_by_type(date, "morning")

        # After relational delete, reload weights (history already excludes the deleted date)
        # and sync current_weight/last_reps to reflect the new most-recent entry
        from weights import load_weights
        weights = load_weights()
        for ex, ex_data in weights.items():
            history = ex_data.get("history", [])
            if not history:
                continue
            most_recent = history[0]
            _db.upsert_exercise_log(
                most_recent["date"], ex,
                most_recent.get("weight"), most_recent.get("reps"),
            )

        return jsonify({"success": True})
    except Exception:
        raise


@workout_bp.route("/api/update_session", methods=["POST"])
def api_update_session():
    """Patch session metadata and optionally add/update/delete exercise logs."""
    try:
        data = request.get_json() or {}
        date = data.get("date")
        if not date:
            return jsonify({"error": "date required"}), 400
        session_type = data.get("session_type", "morning")
        patch = {}
        if "rpe" in data:     patch["rpe"] = data["rpe"]
        if "comment" in data: patch["comment"] = data["comment"]
        import db as _db
        exercises = data.get("exercises") or []
        ex_errors = []

        # Exercise-level mutations (optional)
        for ex_patch in exercises:
            ex_name = (ex_patch.get("exercise") or "").strip()
            if not ex_name:
                ex_errors.append("exercise missing")
                continue
            action = (ex_patch.get("action") or "update").lower()

            if action == "delete":
                if hasattr(_db, "delete_exercise_log_entry_by_type"):
                    ok_ex = _db.delete_exercise_log_entry_by_type(date, session_type, ex_name)
                else:
                    ok_ex = _db.delete_exercise_log_entry(date, ex_name)
            else:
                if "weight" not in ex_patch or "reps" not in ex_patch:
                    ex_errors.append(f"{ex_name}: weight/reps required for {action}")
                    continue
                weight = float(ex_patch.get("weight") or 0)
                reps = str(ex_patch.get("reps") or "")
                sets_json = ex_patch.get("sets")
                if hasattr(_db, "upsert_exercise_log_by_type"):
                    ok_ex = _db.upsert_exercise_log_by_type(
                        date, session_type, ex_name, weight, reps, sets_json=sets_json
                    )
                else:
                    ok_ex = _db.upsert_exercise_log(date, ex_name, weight, reps, sets_json=sets_json)

            if not ok_ex:
                ex_errors.append(f"{ex_name}: {action} failed")

        if session_type == "bonus":
            ok = _db.update_workout_session_bonus(date, patch)
        else:
            ok = _db.update_workout_session(date, patch)
        if ex_errors:
            return jsonify({"success": False, "metadata_updated": ok, "exercise_errors": ex_errors}), 400
        return jsonify({"success": ok})
    except Exception:
        raise


@workout_bp.route("/api/log_session", methods=["POST"])
def api_log_session():
    try:
        from sessions import log_session, log_second_session, log_bonus_session
        from weights import load_weights
        from volume import _calc_session_volume_legacy
        from utils import _today_mtl
        import db as _db

        data           = request.get_json()
        # Utilise la date locale du client si fournie (évite le décalage UTC/EST)
        today          = data.get("date") or _today_mtl()
        rpe            = data.get("rpe")
        comment        = data.get("comment", "")
        exos           = data.get("exos", [])
        exercise_logs  = data.get("exercise_logs", [])
        blocks         = data.get("blocks")
        second_session = data.get("second_session", False)
        bonus_session  = data.get("bonus_session", False)
        duration_min   = data.get("duration_min")
        energy_pre     = data.get("energy_pre")
        session_name   = data.get("session_name")  # e.g. "Push A", "Pull B", "Legs"

        if not second_session and not bonus_session:
            existing = _db.get_workout_session(today)
            if existing and existing.get("completed"):
                return jsonify({"error": "already_logged"}), 409

        # Compute session volume stats from today's logged exercises
        weights   = load_weights()
        vol_stats = _calc_session_volume_legacy(exos, weights, today)

        session_patch = {
            "rpe":          rpe,
            "comment":      comment,
            "duration_min": duration_min,
            "energy_pre":   energy_pre,
            "session_name": session_name,
        }
        if bonus_session:
            log_bonus_session(today, rpe, comment, exos, duration_min, energy_pre,
                              blocks=blocks, **vol_stats)
            _db.complete_workout_session_bonus(today, patch=session_patch)
        elif second_session:
            log_second_session(today, rpe, comment, exos, duration_min, energy_pre,
                               blocks=blocks, **vol_stats, session_name=session_name)
            _db.update_workout_session_by_type(today, "evening", {
                **{k: v for k, v in session_patch.items() if v is not None},
                "completed": True,
            })
        else:
            log_session(today, rpe, comment, exos, duration_min, energy_pre,
                        blocks=blocks, **vol_stats, session_name=session_name)
            _db.complete_workout_session(today, patch=session_patch)

        # Fallback persistence path:
        # iOS sends `exos` as summary strings (e.g. "Bench Press 185.0lbs 5,5,5").
        # If per-exercise /api/log calls were skipped or failed, persist those rows now
        # so Historique still shows exercises for the session.
        def _parse_exo_summary(raw: str):
            text = (raw or "").strip()
            if not text:
                return None
            m = re.match(r"^(?P<name>.+?)\s+(?P<weight>-?\d+(?:\.\d+)?)lbs\s+(?P<reps>.+)$", text)
            if not m:
                return None
            try:
                return (
                    m.group("name").strip(),
                    float(m.group("weight")),
                    m.group("reps").strip(),
                )
            except Exception:
                return None

        sid = None
        if bonus_session:
            sid = (_db.get_or_create_workout_session_bonus(today) or {}).get("id")
        elif second_session:
            sid = (_db.get_or_create_workout_session_second(today) or {}).get("id")
        else:
            sid = (_db.get_or_create_workout_session(today) or {}).get("id")

        if sid and isinstance(exercise_logs, list) and exercise_logs:
            for row in exercise_logs:
                if not isinstance(row, dict):
                    continue
                ex_name = str(row.get("exercise", "")).strip()
                ex_reps = str(row.get("reps", "")).strip()
                try:
                    ex_weight = float(row.get("weight", 0) or 0)
                except Exception:
                    ex_weight = 0.0
                if not ex_name or not ex_reps:
                    continue
                _db.upsert_exercise_log_direct(
                    sid, ex_name, ex_weight, ex_reps
                )
        elif sid and isinstance(exos, list):
            for raw_exo in exos:
                parsed = _parse_exo_summary(str(raw_exo))
                if not parsed:
                    continue
                ex_name, ex_weight, ex_reps = parsed
                _db.upsert_exercise_log_direct(
                    sid, ex_name, ex_weight, ex_reps
                )

        return jsonify({"success": True})
    except Exception:
        raise


@workout_bp.route("/api/log_hiit", methods=["POST"])
def api_log_hiit():
    import db as _db
    from utils import get_current_week, _today_mtl
    data           = request.json
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


@workout_bp.route("/api/delete_hiit", methods=["POST"])
def api_delete_hiit():
    import db as _db
    data     = request.json
    hiit_log = _db.get_hiit_logs() or []

    # Support deletion by index OR by date+session_type
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


@workout_bp.route("/api/hiit/edit", methods=["POST"])
def api_hiit_edit():
    try:
        import db as _db
        data         = request.get_json()
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


@workout_bp.route("/api/save_exercise", methods=["POST"])
def api_save_exercise():
    from inventory import load_inventory, add_exercise, rename_inventory_exercise
    from planner import load_program, save_program
    from blocks import get_block, get_strength_exercises
    data          = request.json
    original_name = data.get("original_name", "").strip()
    name          = data.get("name", "").strip()

    if not name:
        return jsonify({"error": "Nom manquant"}), 400

    inv = load_inventory() or {}

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
    }

    if original_name and original_name != name:
        # Rename: targeted rename in exercises table + update programme
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
        # If Supabase unavailable, skip programme rename — inventory already renamed above
    else:
        add_exercise(name, entry)

    return jsonify({"success": True})


@workout_bp.route("/api/delete_exercise", methods=["POST"])
def api_delete_exercise():
    name = request.json.get("name", "").strip()
    if not name:
        return jsonify({"error": "Nom manquant"}), 400

    import db as _db

    # Hard delete — CASCADE removes exercise_logs and program_block_exercises rows.
    deleted = _db.delete_exercise_by_name(name)
    if not deleted:
        return jsonify({"error": "Exercice introuvable"}), 404

    return jsonify({"success": True})


@workout_bp.route("/api/delete_exercise_log", methods=["POST"])
def api_delete_exercise_log():
    """Remove a specific exercise history entry by name + date."""
    data     = request.json or {}
    exercise = data.get("exercise", "").strip()
    date     = data.get("date", "").strip()
    if not exercise or not date:
        return jsonify({"error": "exercise et date requis"}), 400

    # Delete from relational layer first
    import db as _db
    _db.delete_exercise_log_entry(date, exercise)

    return jsonify({"success": True})


@workout_bp.route("/api/programs", methods=["GET", "POST"])
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
        # Refuse de supprimer le dernier programme
        if len(_db.get_all_programs()) <= 1:
            return jsonify({"error": "Impossible de supprimer le dernier programme"}), 400
        ok = _db.delete_program(pid)
        return jsonify({"success": ok})

    return jsonify({"error": "action inconnue"}), 400


@workout_bp.route("/api/programme", methods=["POST"])
def api_programme():
    import db as _db
    from planner import load_program, save_program
    from blocks import (make_strength_block, make_hiit_block, make_cardio_block,
                        get_block, get_strength_exercises,
                        upsert_block, remove_block, reorder_blocks)
    from inventory import load_inventory, add_exercise, rename_inventory_exercise
    data       = request.json
    action     = data.get("action")
    jour       = data.get("jour")
    program_id = data.get("program_id") or None  # optional — falls back to default

    # ── Session-level actions (no target session required) ───────────────────
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

    # ── Rename: must read all sessions to rename across all ──────────────────
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

    # ── All other actions: read + modify + save ONLY the target session ──────
    if jour is None:
        return jsonify({"error": "jour manquant"}), 400

    # Read only the target session from Supabase
    session_data = _db.get_full_program(program_id)
    if session_data is None:
        return jsonify({"error": "Impossible de lire le programme (Supabase indisponible)"}), 503
    if jour not in session_data:
        return jsonify({"error": "Jour invalide"}), 400

    session_def = session_data[jour]
    blks        = session_def.get("blocks", [])

    # ── Exercise-level actions ────────────────────────────────────────────────
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
            # Do NOT delete from inventory — removing from a program only removes the reference

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
            # Only exercises that exist in both ordre AND current exercises dict
            reordered = {ex: exercises[ex] for ex in ordre if ex in exercises}
            # Append any exercises NOT in ordre — never drop, only reorder
            for ex, scheme in exercises.items():
                if ex not in reordered:
                    reordered[ex] = scheme
            exercises = reordered

        strength["exercises"] = exercises
        session_def["blocks"] = upsert_block(blks, strength)

    # ── Block-level actions ───────────────────────────────────────────────────
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

    # Save only the modified session — never touch other sessions
    _db.save_full_program({jour: session_def}, program_id)
    return jsonify({"success": True})


@workout_bp.route("/api/seance_data")
def api_seance_data():
    from weights import load_weights
    from sessions import load_sessions
    from planner import (load_program, get_today, get_today_date, get_week_schedule,
                         get_suggested_weights_for_today)
    from inventory import load_inventory
    from blocks import get_strength_exercises
    from progression import prescribe_volume
    from deload import get_cached_fatigue_score
    from utils import _parse_scheme, get_current_week, load_hiit_log_local

    sessions     = load_sessions()
    full_program = load_program()
    hiit_log     = load_hiit_log_local()
    inventory    = load_inventory()
    today_str  = get_today()
    today_date = get_today_date()
    schedule   = get_week_schedule()

    already_logged = today_date in sessions

    # Aplatit la structure bloc → {exercice: scheme} pour le client iOS
    flat_program = {
        seance: get_strength_exercises(session_def)
        for seance, session_def in full_program.items()
    }

    # PERF: load weights only for today's exercises (payload + query time)
    today_exercises = list((flat_program.get(today_str) or {}).keys())
    weights = load_weights(today_exercises, limit_per=20)
    suggestions = get_suggested_weights_for_today(weights, full_program)

    inv = inventory if isinstance(inventory, dict) else {}
    inventory_types    = {name: info.get("type") or "machine" for name, info in inv.items()}
    inventory_tracking = {name: info.get("tracking_type", "reps") for name, info in inv.items()}
    inventory_rest     = {name: info["rest_seconds"] for name, info in inv.items() if info.get("rest_seconds")}
    # Ordered list of exercise names per session (preserves user-defined order)
    exercise_order  = {seance: list(exs.keys()) for seance, exs in flat_program.items()}

    # Build per-exercise prescriptions (sets × reps adjusted for fatigue + trend)
    fatigue_score = get_cached_fatigue_score()
    prescriptions = {}
    for session_exos in flat_program.values():
        for ex_name, scheme in session_exos.items():
            base_sets, rmin, rmax = _parse_scheme(str(scheme))
            ex_history = weights.get(ex_name, {}).get("history", [])
            prescriptions[ex_name] = prescribe_volume(
                exercise=ex_name,
                base_sets=base_sets,
                rep_min=rmin,
                rep_max=rmax,
                fatigue_score=fatigue_score,
                history=ex_history,
            )

    # Per-exercise inline coaching (only when session not yet logged)
    import smart_progression as _sp
    exercise_suggestions = {}
    if not already_logged:
        for ex_name in today_exercises:
            s = _sp.generate_exercise_suggestion(ex_name)
            if s:
                exercise_suggestions[ex_name] = s

    return jsonify({
        "today": today_str,
        "today_date": today_date,
        "already_logged": already_logged,
        "schedule": schedule,
        "full_program": flat_program,
        "suggestions": suggestions,
        "weights": weights,
        "week": get_current_week(),
        "inventory_types": inventory_types,
        "inventory_tracking": inventory_tracking,
        "inventory_rest": inventory_rest,
        "exercise_order": exercise_order,
        "prescriptions": prescriptions,
        "exercise_suggestions": exercise_suggestions,
    })


@workout_bp.route("/api/seance_soir_data")
def api_seance_soir_data():
    import db as _db
    from planner import (load_program, get_today_date, get_today_evening,
                         get_suggested_weights_for_today, get_evening_schedule)
    from weights import load_weights
    from inventory import load_inventory
    from blocks import get_strength_exercises
    from utils import get_current_week

    today_soir = get_today_evening()
    if not today_soir:
        return jsonify({"has_evening_session": False})

    weights      = load_weights()
    full_program = load_program()
    inventory    = load_inventory()
    today_date   = get_today_date()
    schedule     = get_evening_schedule()
    already_logged = _db.get_workout_session_second(today_date) is not None

    flat_program = {
        seance: get_strength_exercises(session_def)
        for seance, session_def in full_program.items()
    }
    inv = inventory if isinstance(inventory, dict) else {}
    inventory_types    = {name: info.get("type") or "machine" for name, info in inv.items()}
    inventory_tracking = {name: info.get("tracking_type", "reps") for name, info in inv.items()}
    inventory_rest     = {name: info["rest_seconds"] for name, info in inv.items() if info.get("rest_seconds")}
    exercise_order  = {seance: list(exs.keys()) for seance, exs in flat_program.items()}
    suggestions     = get_suggested_weights_for_today(weights, full_program)

    return jsonify({
        "has_evening_session": True,
        "today_soir": today_soir,
        "today_date": today_date,
        "already_logged": already_logged,
        "schedule": schedule,
        "full_program": flat_program,
        "suggestions": suggestions,
        "weights": weights,
        "week": get_current_week(),
        "inventory_types": inventory_types,
        "inventory_tracking": inventory_tracking,
        "inventory_rest": inventory_rest,
        "exercise_order": exercise_order,
    })


@workout_bp.route("/api/evening_schedule", methods=["GET", "POST"])
def api_evening_schedule():
    import db as _db
    if request.method == "POST":
        schedule = request.get_json() or {}
        success = _db.set_evening_week_schedule(schedule)
        return jsonify({"success": success})
    return jsonify(_db.get_evening_week_schedule())


@workout_bp.route("/api/morning_schedule", methods=["POST"])
def api_morning_schedule():
    """Save morning weekly schedule: {"schedule": {"Lun": "Push A", "Mar": "Repos", ...}}"""
    import db as _db
    data     = request.get_json() or {}
    schedule = data.get("schedule", {})
    # Convert "Repos" sentinel to None (clears the day)
    cleaned  = {day: (None if seance in ("Repos", "") else seance)
                for day, seance in schedule.items()}
    ok = _db.set_relational_week_schedule(cleaned)
    return jsonify({"success": ok})


@workout_bp.route("/api/progression_suggestions")
def api_progression_suggestions():
    """Return per-exercise progression suggestions for a given session.

    Query params:
        date          – ISO date (defaults to today MTL)
        session_type  – "morning" | "evening"  (default "morning")
        session_name  – e.g. "Push A" (optional, improves matching)
    Response: {"suggestions": [...]}  — shape matches ProgressionSuggestionsResponse on iOS.
    """
    import smart_progression as _sp
    from utils import _today_mtl
    from planner import load_program

    date         = request.args.get("date") or _today_mtl()
    session_type = request.args.get("session_type", "morning")
    session_name = request.args.get("session_name", "")

    # Resolve exercise list for this session (improves session matching in _sp)
    try:
        program   = load_program()
        exercises = list(program.get(session_name, {}).keys()) if session_name else []
    except Exception:
        exercises = []

    suggestions = _sp.generate_suggestions(
        session_date=date,
        session_type=session_type,
        session_name=session_name,
        session_exercises=exercises,
    )
    return jsonify({"suggestions": suggestions})


@workout_bp.route("/api/hiit_data")
def api_hiit_data():
    from utils import load_hiit_log_local
    hiit_log = load_hiit_log_local()
    total    = len(hiit_log)
    avg_rpe  = round(sum(e.get("rpe", 0) for e in hiit_log) / total, 1) if total else 0
    return jsonify({
        "hiit_log": hiit_log,
        "total":    total,
        "avg_rpe":  avg_rpe,
    })
