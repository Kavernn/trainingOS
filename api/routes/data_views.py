from flask import Blueprint, jsonify, request
from datetime import datetime
import os

data_views_bp = Blueprint("data_views", __name__)


@data_views_bp.route("/api/dashboard")
def api_dashboard():
    from weights import load_weights
    from sessions import load_sessions
    from user_profile import load_user_profile
    from goals import load_goals
    from planner import (load_program, get_today, get_today_date, get_week_schedule,
                         get_suggested_weights_for_today)
    from nutrition import (load_settings as load_nutrition_settings, get_today_totals)
    from blocks import get_strength_exercises
    from utils import get_current_week, load_hiit_log_local
    import db as _db

    weights      = load_weights()
    sessions     = load_sessions()
    profile      = load_user_profile()
    goals        = load_goals()
    full_program = load_program()
    hiit_log     = load_hiit_log_local()
    nutrition_totals = get_today_totals()
    today_str    = get_today()
    today_date   = get_today_date()
    schedule     = get_week_schedule()
    suggestions  = get_suggested_weights_for_today(weights, full_program)

    _today_session = _db.get_workout_session(today_date)
    # Séance terminée si : completed=True OU rpe set OU au moins 1 exercice loggué
    _today_logged_names = set()
    try:
        _today_logged_names = {e["exercise_name"] for e in _db.get_session_exercise_logs(today_date)}
    except Exception:
        pass
    already_logged_today = bool(
        _today_session and (
            _today_session.get("completed") or
            _today_session.get("rpe") is not None or
            bool(_today_logged_names)
        )
    )

    has_partial_logs = False
    if not already_logged_today:
        try:
            program_names = set(get_strength_exercises(full_program.get(today_str, {})).keys())
            has_partial_logs = bool(_today_logged_names & program_names)
        except Exception:
            has_partial_logs = False

    goals_progress = {}
    for ex, goal in goals.items():
        current = weights.get(ex, {}).get("current_weight", 0) or 0
        goals_progress[ex] = {
            "current":  current,
            "goal":     goal["goal_weight"],
            "achieved": goal.get("achieved", False),
        }

    # Merge HIIT sessions into sessions dict so the heatmap shows them too.
    # Include if completed=True, rpe set, OR c'est aujourd'hui et already_logged_today.
    merged_sessions = {
        date: entry
        for date, entry in sessions.items()
        if entry.get("completed") or entry.get("rpe") is not None
           or (date == today_date and already_logged_today)
    }
    for entry in hiit_log:
        d = entry.get("date")
        if d and d not in merged_sessions:
            merged_sessions[d] = {"session_type": entry.get("session_type", "HIIT")}

    # Enrich merged_sessions with session_volume from v_session_volume view
    # (session_volume was removed from workout_sessions schema — lives in the view)
    # Also recover sessions that have exercise logs but no rpe/completed (missed by initial filter).
    try:
        vol_by_date = _db.get_sessions_for_correlations(days=500)
        for date, vol_data in vol_by_date.items():
            sv = vol_data.get("session_volume")
            # Session has exercise logs → count it even if rpe/completed absent
            if sv and date not in merged_sessions and date in sessions:
                merged_sessions[date] = sessions[date]
            if date in merged_sessions and sv is not None:
                merged_sessions[date]["session_volume"] = sv
    except Exception:
        pass

    smart_goals_count = 0
    try:
        smart_goals_count = len(_db.get_smart_goals())
    except Exception:
        pass

    return jsonify({
        "today":               today_str,
        "week":                get_current_week(),
        "today_date":          today_date,
        "already_logged_today": already_logged_today,
        "has_partial_logs":     has_partial_logs,
        "schedule":            schedule,
        "sessions":            merged_sessions,
        "suggestions":         suggestions,
        "goals":               goals_progress,
        "smart_goals_count":   smart_goals_count,
        "full_program":        {s: get_strength_exercises(sd) for s, sd in full_program.items()},
        "nutrition_totals":    nutrition_totals,
        "nutrition_settings":  load_nutrition_settings(),
        "profile":             profile,
    })


@data_views_bp.route("/api/weights")
def api_weights():
    from weights import load_weights
    exercise = request.args.get("exercise")
    if exercise:
        return jsonify(load_weights(exercise_names=[exercise]))
    return jsonify(load_weights())


@data_views_bp.route("/api/inventory")
def api_inventory():
    from inventory import load_inventory
    return jsonify(load_inventory())


@data_views_bp.route("/api/sessions")
def api_sessions():
    from sessions import load_sessions
    return jsonify(load_sessions())


@data_views_bp.route("/api/notes_data")
def api_notes_data():
    from sessions import load_sessions
    sessions = load_sessions()
    total    = len(sessions)
    rpes     = [s.get("rpe") for s in sessions.values() if s.get("rpe")]
    avg_rpe  = round(sum(rpes) / len(rpes), 1) if rpes else 0
    return jsonify({
        "sessions": sessions,
        "total":    total,
        "avg_rpe":  avg_rpe,
    })


@data_views_bp.route("/api/programme_data")
def api_programme_data():
    import db as _db
    from planner import load_program, get_week_schedule
    from inventory import load_inventory, add_exercise
    from blocks import get_strength_exercises

    program_id   = request.args.get("program_id") or None
    full_program = _db.get_full_program(program_id) or load_program()
    if program_id is None:
        program_id = _db.get_default_program_id()
    schedule     = get_week_schedule()
    inventory    = load_inventory()
    programs     = _db.get_all_programs()
    all_sessions = _db.get_all_session_names()
    from utils import cap_scheme_sets

    # Aplatit la structure bloc → {seance: {exercice: scheme}} pour le client iOS
    flat_program = {
        seance: {ex: cap_scheme_sets(s) for ex, s in get_strength_exercises(session_def).items()}
        for seance, session_def in full_program.items()
    }
    # Sync: ajoute dans l'inventaire tout exercice du programme qui en est absent.
    # IMPORTANT: ne sync que si inventory est un dict valide (pas None = erreur Supabase).
    # Si inventory est None, on skipe entièrement le sync pour ne pas écraser les données
    # custom avec des defaults {"type": "machine", "increment": 5}.
    inv = inventory if isinstance(inventory, dict) else {}
    if inventory is not None:
        for exos in flat_program.values():
            for ex_name, scheme in exos.items():
                if ex_name not in inv:
                    entry = {"type": "machine", "increment": 5, "default_scheme": scheme}
                    add_exercise(ex_name, entry)
                    inv[ex_name] = entry
    inventory_types    = {name: info.get("type") or "machine"          for name, info in inv.items()}
    inventory_tracking = {name: info.get("tracking_type", "reps")   for name, info in inv.items()}
    inventory_rest     = {name: info["rest_seconds"] for name, info in inv.items() if info.get("rest_seconds")}
    inventory_schemes  = {name: info.get("default_scheme", "3x8-12") for name, info in inv.items()}
    inventory_muscles  = {name: info.get("muscles") or []             for name, info in inv.items()}
    inventory_patterns = {name: info.get("pattern") or ""             for name, info in inv.items()}
    exercise_order     = {seance: list(exs.keys()) for seance, exs in flat_program.items()}
    return jsonify({
        "full_program":        flat_program,
        "schedule":            schedule,
        "inventory":           list(inv.keys()),
        "inventory_types":     inventory_types,
        "inventory_tracking":  inventory_tracking,
        "inventory_rest":      inventory_rest,
        "inventory_schemes":   inventory_schemes,
        "inventory_muscles":   inventory_muscles,
        "inventory_patterns":  inventory_patterns,
        "exercise_order":      exercise_order,
        "programs":            programs,
        "current_program_id":  program_id,
        "all_sessions":        all_sessions,
    })


@data_views_bp.route("/api/inventaire_data")
def api_inventaire_data():
    import db as _db
    from inventory import load_inventory
    from planner import load_program
    from blocks import get_strength_exercises

    inventory = load_inventory()
    if inventory is None:
        return jsonify({"inventory": {}, "in_program": []})
    # Derive which exercises are currently in the program
    full_program = _db.get_full_program(None) or load_program()
    in_program: set = set()
    for session_def in full_program.values():
        exos = get_strength_exercises(session_def) if isinstance(session_def, dict) and "blocks" in session_def else (session_def if isinstance(session_def, dict) else {})
        in_program.update(exos.keys())
    return jsonify({"inventory": inventory, "in_program": sorted(in_program)})


@data_views_bp.route("/api/historique_data")
def api_historique_data():
    import db as _db
    from weights import load_weights

    limit  = min(int(request.args.get("limit",  90)),  200)
    offset = int(request.args.get("offset", 0))
    month  = request.args.get("month")  # "YYYY-MM" filter

    sessions = _db.get_workout_sessions(limit=500)
    ex_by_session = _db.get_exercise_history_grouped_by_session()
    hiit_log = _db.get_hiit_logs(limit=500)

    # Deduplicate rows by (date, session_type).
    # In some environments old duplicates can exist (missing/late unique constraint),
    # and iOS uses date+session_type as row identity in HistoriqueView.
    # Keep the richest row so exercises are not hidden by an empty duplicate.
    best_by_key = {}

    for s in sessions:
        d   = s.get("date")
        sid = s.get("id")
        stype = s.get("session_type") or ("evening" if s.get("is_second") else "morning")
        if not d:
            continue
        if month and not d.startswith(month):
            continue
        exos = ex_by_session.get(sid, [])
        has_exos = bool(exos)
        if not s.get("completed") and s.get("rpe") is None and not has_exos:
            continue
        candidate = {
            "date":         d,
            "session_type": stype,
            "rpe":          s.get("rpe"),
            "comment":      s.get("comment", ""),
            "exos":         exos,
        }
        key = (d, stype)

        current = best_by_key.get(key)
        if current is None:
            best_by_key[key] = candidate
            continue

        # Prefer rows with exercises, then with explicit RPE/comment.
        current_score = (
            (1 if current.get("exos") else 0) * 100
            + (1 if current.get("rpe") is not None else 0) * 10
            + (1 if current.get("comment") else 0)
        )
        candidate_score = (
            (1 if candidate.get("exos") else 0) * 100
            + (1 if candidate.get("rpe") is not None else 0) * 10
            + (1 if candidate.get("comment") else 0)
        )
        if candidate_score > current_score:
            best_by_key[key] = candidate

    # Merge bonus sessions into their morning counterpart.
    # A bonus session is a complement (RPE/comment added after the fact),
    # not a separate workout — display them as one unified entry.
    for d_stype in list(best_by_key.keys()):
        d, stype = d_stype
        if stype != "bonus":
            continue
        bonus = best_by_key[d_stype]
        morning_key = (d, "morning")
        if morning_key in best_by_key:
            morning = best_by_key[morning_key]
            # Inherit RPE/comment from bonus if morning is missing them
            if morning.get("rpe") is None and bonus.get("rpe") is not None:
                morning["rpe"] = bonus["rpe"]
            if not morning.get("comment") and bonus.get("comment"):
                morning["comment"] = bonus["comment"]
            # Inherit exercises from bonus only if morning has none
            if not morning.get("exos") and bonus.get("exos"):
                morning["exos"] = bonus["exos"]
            del best_by_key[d_stype]
        else:
            # No morning session — keep bonus as the sole entry for that day
            pass

    session_list = sorted(
        best_by_key.values(),
        key=lambda x: (x.get("date", ""), x.get("session_type", "")),
        reverse=True,
    )

    # Fallback: if a session has no exos (legacy/duplicate linkage issues),
    # rebuild exercise rows from per-exercise history by date.
    try:
        weights = load_weights()
        ex_by_date: dict[str, list[dict]] = {}
        for ex_name, ex_data in (weights or {}).items():
            for entry in ex_data.get("history", []):
                d = entry.get("date")
                if not d:
                    continue
                ex_by_date.setdefault(d, []).append({
                    "exercise": ex_name,
                    "weight": entry.get("weight", 0),
                    "reps": entry.get("reps", ""),
                })
        for row in session_list:
            if not row.get("exos"):
                row["exos"] = ex_by_date.get(row.get("date"), [])
    except Exception:
        pass

    if month:
        filtered_hiit = [h for h in hiit_log if h.get("date", "").startswith(month)]
        return jsonify({
            "session_list": session_list,
            "hiit_list":    filtered_hiit,
            "total":        len(session_list),
            "has_more":     False,
        })

    total = len(session_list)
    page  = session_list[offset:offset + limit]

    return jsonify({
        "session_list": page,
        "hiit_list":    hiit_log[:30],
        "total":        total,
        "has_more":     offset + limit < total,
    })


@data_views_bp.route("/api/bodycomp_data")
def api_bodycomp_data():
    from body_weight import load_body_weight, get_tendance
    from user_profile import load_user_profile
    body_weight = load_body_weight()
    profile     = load_user_profile()
    tendance    = get_tendance(body_weight)
    return jsonify({
        "body_weight": body_weight,
        "profile":     profile,
        "tendance":    tendance,
    })


@data_views_bp.route("/api/export_data")
def api_export_data():
    """Export complet des données utilisateur en JSON."""
    import db as _db
    from body_weight import load_body_weight
    from goals import load_goals
    from utils import _today_mtl

    sessions     = _db.get_workout_sessions(limit=2000)
    hiit         = _db.get_hiit_logs(limit=1000)
    recovery     = _db.get_recovery_logs() or []
    body_weight  = load_body_weight()
    goals        = load_goals()
    cardio       = _db.get_cardio_logs() or []
    return jsonify({
        "export_date":  _today_mtl(),
        "sessions":     sessions,
        "hiit":         hiit,
        "recovery":     recovery,
        "body_weight":  body_weight,
        "goals":        goals,
        "cardio":       cardio,
    })
