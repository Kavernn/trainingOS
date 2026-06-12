from flask import Blueprint, jsonify, request
from datetime import datetime
import logging
import re
from utils import _now_mtl

logger = logging.getLogger("trainingos")
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
        from utils import _today_mtl
        import db as _db

        data     = request.get_json(silent=True) or {}
        exercise = data.get("exercise")
        weight   = float(data.get("weight", 0))
        reps_str = data.get("reps", "")
        rpe_raw  = data.get("rpe")
        rpe      = float(rpe_raw) if rpe_raw is not None else None

        force          = bool(data.get("force", False))
        is_second      = bool(data.get("is_second", False))
        is_bonus       = bool(data.get("is_bonus", False))
        session_date   = data.get("session_date") or data.get("date")
        session_type   = (data.get("session_type") or "").strip().lower()
        session_name   = data.get("session_name")
        equipment_type = data.get("equipment_type", "")
        pain_zone      = data.get("pain_zone", "")
        notes          = data.get("notes", "") or ""

        if not exercise or not reps_str:
            return jsonify({"error": "Données manquantes"}), 400

        weights   = load_weights([exercise], limit_per=10)

        existing_history = weights.get(exercise, {}).get("history", [])
        if not force and not is_second and not is_bonus and existing_history and existing_history[0]["date"] == _today_mtl():
            return jsonify({
                "error":      "already_logged",
                "new_weight": weights[exercise].get("current_weight", 0),
                "1rm":        existing_history[0].get("1rm", 0),
            }), 409

        if force and existing_history and existing_history[0]["date"] == _today_mtl():
            weights[exercise]["history"].pop(0)

        sets_data = data.get("sets", [])

        if sets_data:
            first_weights = [float(s["weight"]) for s in sets_data
                             if s.get("weight") and float(s["weight"]) > 0]
            if first_weights:
                weight = round(first_weights[0], 1)

        reps_list = parse_reps(reps_str)
        reps      = ",".join(map(str, reps_list))
        status    = progression_status(reps, exercise)
        if rpe is None:
            last_entry = weights.get(exercise, {}).get("history", [{}])[0] if weights.get(exercise, {}).get("history") else {}
            rpe = last_entry.get("rpe")
            if rpe is not None:
                rpe = float(rpe)
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
        onerm     = estimate_1rm(weight, reps) or 0.0

        prev_1rms = [e.get("1rm", 0) for e in existing_history]
        is_pr = bool(onerm > 0 and (not prev_1rms or onerm > max(prev_1rms)))

        if equipment_type == "bodyweight" and weight == 0:
            bw_logs = _db.get_body_weight_logs(limit=1)
            volume_weight = float(bw_logs[0]["weight"]) if bw_logs and bw_logs[0].get("weight") else 0.0
        else:
            volume_weight = weight

        if sets_data:
            for s in sets_data:
                sw = float(s.get("weight", 0) or 0)
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
        if not (equipment_type == "bodyweight" and weight == 0):
            weights[exercise]["current_weight"] = round(new_w, 1)
        weights[exercise]["last_reps"] = reps
        weights[exercise]["last_logged"]    = _now_mtl().strftime("%Y-%m-%d %H:%M")

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
            ok = _db.upsert_exercise_log_direct(
                sid, exercise, round(weight, 1), reps,
                sets_json=sets_data or None,
                rpe=rpe,
                pain_zone=pain_zone or None,
                notes=notes or None,
            )
            if not ok:
                return jsonify({"error": "Échec de l'enregistrement en base"}), 500
            if session_name:
                if is_bonus_session:
                    _db.update_workout_session_by_type(today, "bonus", {"session_name": session_name})
                elif is_evening:
                    _db.update_workout_session_by_type(today, "evening", {"session_name": session_name})
                else:
                    _db.update_workout_session_by_type(today, "morning", {"session_name": session_name})
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
    except Exception as e:
        logger.error("api/log error: %s", e, exc_info=True)
        return jsonify({"error": "Erreur interne lors de l'enregistrement"}), 500


@workout_bp.route("/api/session/edit", methods=["POST"])
def api_session_edit():
    """Edit an existing session: RPE, comment, and/or individual exercise weight/reps."""
    try:
        data    = request.get_json(silent=True) or {}
        date    = data.get("date")
        if not date:
            return jsonify({"error": "date manquante"}), 400

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

        import db as _db
        session_type = data.get("session_type", "morning")
        supabase_patch = {}
        if "rpe" in data:
            supabase_patch["rpe"] = data["rpe"]
        if "comment" in data:
            supabase_patch["comment"] = data["comment"]
        if supabase_patch:
            _db.update_workout_session_by_type(date, session_type, supabase_patch)

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
                updated = False
                for entry in history:
                    if entry.get("date") == date:
                        if new_w is not None:
                            entry["weight"] = float(new_w)
                        if new_r is not None:
                            entry["reps"] = str(new_r)
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
                if history:
                    most_recent = max(history, key=lambda e: e.get("date", ""))
                    weights[ex]["current_weight"] = most_recent["weight"]
                    weights[ex]["last_reps"]      = most_recent["reps"]
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
        data = request.get_json(silent=True) or {}
        date = data.get("date")
        if not date:
            return jsonify({"error": "date manquante"}), 400

        session_type = data.get("session_type", "morning")

        import db as _db
        if session_type == "bonus":
            bonus_session = _db.get_workout_session_bonus(date)
            if bonus_session:
                _db.delete_exercise_logs_for_session(bonus_session["id"])
            _db.delete_workout_session_by_type(date, "bonus")
        else:
            _db.delete_session_exercise_logs(date)
            _db.delete_workout_session_by_type(date, "morning")

        from weights import load_weights
        weights = load_weights()
        entries = []
        for ex, ex_data in weights.items():
            history = ex_data.get("history", [])
            if not history:
                continue
            most_recent = history[0]
            entries.append({
                "date": most_recent["date"],
                "exercise_name": ex,
                "weight": most_recent.get("weight"),
                "reps": most_recent.get("reps"),
            })
        if entries:
            _db.bulk_upsert_exercise_logs(entries)

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

        if exercises:
            patches = []
            for ex_patch in exercises:
                ex_name = (ex_patch.get("exercise") or "").strip()
                if not ex_name:
                    ex_errors.append("exercise missing")
                    continue
                action = (ex_patch.get("action") or "update").lower()
                if action != "delete" and ("weight" not in ex_patch or "reps" not in ex_patch):
                    ex_errors.append(f"{ex_name}: weight/reps required for {action}")
                    continue
                patches.append({
                    "exercise_name": ex_name,
                    "action": action,
                    "weight": ex_patch.get("weight"),
                    "reps": ex_patch.get("reps"),
                    "sets_json": ex_patch.get("sets"),
                })

            if patches:
                _, batch_errors = _db.bulk_apply_session_exercise_patches(date, session_type, patches)
                ex_errors.extend(batch_errors)

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

        data           = request.get_json(silent=True) or {}
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
        session_name   = data.get("session_name")

        def _parse_exo_summary(raw: str):
            text = (raw or "").strip()
            if not text:
                return None
            m = re.match(r"^(?P<name>.+?)\s+(?P<weight>-?\d+(?:\.\d+)?)lbs\s+(?P<reps>.+)$", text)
            if not m:
                return None
            try:
                return (m.group("name").strip(), float(m.group("weight")), m.group("reps").strip())
            except Exception:
                return None

        if not second_session and not bonus_session:
            existing = _db.get_workout_session(today)
            if existing and existing.get("completed"):
                sid = existing.get("id")
                if sid:
                    if isinstance(exercise_logs, list) and exercise_logs:
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
                            _db.upsert_exercise_log_direct(sid, ex_name, ex_weight, ex_reps)
                    elif isinstance(exos, list):
                        for raw_exo in exos:
                            parsed = _parse_exo_summary(str(raw_exo))
                            if not parsed:
                                continue
                            _db.upsert_exercise_log_direct(sid, parsed[0], parsed[1], parsed[2])
                return jsonify({"success": True})

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
            completed_ok = _db.complete_workout_session(today, patch=session_patch)
            if not completed_ok:
                _db.get_or_create_workout_session(today)
                completed_ok = _db.complete_workout_session(today, patch=session_patch)
            if not completed_ok:
                return jsonify({"error": "Impossible de marquer la séance comme terminée"}), 500

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
                _db.upsert_exercise_log_direct(sid, ex_name, ex_weight, ex_reps)
        elif sid and isinstance(exos, list):
            for raw_exo in exos:
                parsed = _parse_exo_summary(str(raw_exo))
                if not parsed:
                    continue
                ex_name, ex_weight, ex_reps = parsed
                _db.upsert_exercise_log_direct(sid, ex_name, ex_weight, ex_reps)

        return jsonify({"success": True})
    except Exception:
        raise
