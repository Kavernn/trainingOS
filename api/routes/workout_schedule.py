from flask import Blueprint, jsonify, request
import logging

logger = logging.getLogger("trainingos")
workout_schedule_bp = Blueprint("workout_schedule", __name__)


@workout_schedule_bp.route("/api/seance_data")
def api_seance_data():
    from weights import load_weights
    from planner import (load_program, get_today, get_today_date, get_week_schedule,
                         get_suggested_weights_for_today)
    from inventory import load_inventory
    from blocks import get_strength_exercises
    from progression import prescribe_volume
    from deload import get_cached_fatigue_score
    from utils import _parse_scheme, get_current_week, get_mesocycle_info
    import db as _db

    program_id_param = request.args.get("program_id") or None
    full_program = _db.get_full_program(program_id_param) if program_id_param else load_program()
    inventory    = load_inventory()
    today_date = get_today_date()
    schedule   = get_week_schedule()

    session_name_override = request.args.get("session_name", "").strip()
    if session_name_override:
        today_str     = session_name_override
        already_logged = False
    else:
        today_str  = get_today()
        _s = _db.get_workout_session(today_date) or {}
        already_logged = bool(_s.get("completed"))

    from utils import cap_scheme_sets
    flat_program = {
        seance: {ex: cap_scheme_sets(s) for ex, s in get_strength_exercises(session_def).items()}
        for seance, session_def in full_program.items()
    }

    today_exercises = list((flat_program.get(today_str) or {}).keys())
    weights = load_weights(today_exercises, limit_per=20)
    suggestions = get_suggested_weights_for_today(weights, full_program)

    inv = inventory if isinstance(inventory, dict) else {}
    inventory_types    = {name: info.get("type") or "machine" for name, info in inv.items()}
    inventory_tracking = {name: info.get("tracking_type", "reps") for name, info in inv.items()}
    inventory_rest     = {name: 120 for name in inv}
    inventory_hints    = {name: info["tips"] for name, info in inv.items() if info.get("tips")}
    exercise_order  = {seance: list(exs.keys()) for seance, exs in flat_program.items()}
    exercise_supersets = _db.get_session_supersets(program_id_param or _db.get_active_program_id())

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

    import smart_progression as _sp
    exercise_suggestions = {}
    if not already_logged and today_exercises:
        ex_info_bulk = _db.get_exercises_info_bulk(today_exercises)
        exercise_suggestions = _sp.generate_exercise_suggestions_bulk(
            today_exercises, weights, ex_info_bulk
        )
        for ex_name, sug in exercise_suggestions.items():
            if sug.get("suggestion_type") == "increase_weight" and sug.get("suggested_weight"):
                if ex_name in weights:
                    weights[ex_name] = {**weights[ex_name], "current_weight": sug["suggested_weight"]}

    return jsonify({
        "today": today_str,
        "today_date": today_date,
        "already_logged": already_logged,
        "schedule": schedule,
        "full_program": flat_program,
        "suggestions": suggestions,
        "weights": weights,
        "week": get_current_week(),
        "mesocycle": get_mesocycle_info(),
        "inventory_types": inventory_types,
        "inventory_tracking": inventory_tracking,
        "inventory_rest": inventory_rest,
        "inventory_hints": inventory_hints,
        "exercise_order": exercise_order,
        "exercise_supersets": exercise_supersets,
        "prescriptions": prescriptions,
        "exercise_suggestions": exercise_suggestions,
    })


@workout_schedule_bp.route("/api/seance_soir_data")
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

    from utils import cap_scheme_sets
    flat_program = {
        seance: {ex: cap_scheme_sets(s) for ex, s in get_strength_exercises(session_def).items()}
        for seance, session_def in full_program.items()
    }
    inv = inventory if isinstance(inventory, dict) else {}
    inventory_types    = {name: info.get("type") or "machine" for name, info in inv.items()}
    inventory_tracking = {name: info.get("tracking_type", "reps") for name, info in inv.items()}
    inventory_rest     = {name: 120 for name in inv}
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


@workout_schedule_bp.route("/api/evening_schedule", methods=["GET", "POST"])
def api_evening_schedule():
    import db as _db
    if request.method == "POST":
        schedule = request.get_json() or {}
        success = _db.set_evening_week_schedule(schedule)
        return jsonify({"success": success})
    return jsonify(_db.get_evening_week_schedule())


@workout_schedule_bp.route("/api/morning_schedule", methods=["POST"])
def api_morning_schedule():
    """Save morning weekly schedule: {"schedule": {"Lun": "Push A", "Mar": "Repos", ...}}"""
    import db as _db
    data     = request.get_json() or {}
    schedule = data.get("schedule", {})
    cleaned  = {day: (None if seance in ("Repos", "") else seance)
                for day, seance in schedule.items()}
    ok = _db.set_relational_week_schedule(cleaned)
    return jsonify({"success": ok})


@workout_schedule_bp.route("/api/session_override", methods=["GET", "POST", "DELETE"])
def api_session_override():
    """GET  → current override {"date": "...", "session": "..."} or {}
    POST → {"session": "Push B"} to set today's override
    DELETE → clear today's override
    """
    import db as _db
    if request.method == "DELETE":
        ok = _db.set_session_override(None)
        return jsonify({"success": ok})
    if request.method == "POST":
        data    = request.get_json() or {}
        session = (data.get("session") or "").strip()
        if not session:
            return jsonify({"error": "session requis"}), 400
        ok = _db.set_session_override(session)
        return jsonify({"success": ok})
    override = _db.get_session_override()
    return jsonify(override or {})


@workout_schedule_bp.route("/api/progression_suggestions")
def api_progression_suggestions():
    """Return per-exercise progression suggestions for a given session."""
    import smart_progression as _sp
    from utils import _today_mtl
    from planner import load_program

    date         = request.args.get("date") or _today_mtl()
    session_type = request.args.get("session_type", "morning")
    session_name = request.args.get("session_name", "")

    try:
        program   = load_program()
        exercises = list(program.get(session_name, {}).keys()) if session_name else []
    except Exception:
        exercises = []

    from utils import get_mesocycle_info
    meso  = get_mesocycle_info()
    phase = meso.get("phase")

    suggestions = _sp.generate_suggestions(
        session_date=date,
        session_type=session_type,
        session_name=session_name,
        session_exercises=exercises,
        phase=phase,
    )
    return jsonify({"suggestions": suggestions})
