from flask import Blueprint, jsonify, request
import logging

logger = logging.getLogger("trainingos")
workout_schedule_bp = Blueprint("workout_schedule", __name__)


@workout_schedule_bp.route("/api/seance_data")
def api_seance_data():
    from weights import load_weights
    from planner import (load_program, get_today, get_today_date, get_week_schedule,
                         get_suggested_weights_for_today, get_today_evening)
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

    # logged_today_names : union des exos loggés aujourd'hui tous slots
    # (morning + evening + bonus). Source unique = get_today_sessions_all
    # (P1.A) + lookup exercise_logs par session_id (mécanique P1.B).
    logged_today_names: set[str] = set()
    try:
        _today_all = _db.get_today_sessions_all(today_date)
        for s in _today_all:
            sid = s.get("id")
            if not sid:
                continue
            resp = _db._client.table("exercise_logs").select("exercises(name)").eq("session_id", sid).execute()
            for r in (resp.data or []):
                n = (r.get("exercises") or {}).get("name")
                if n:
                    logged_today_names.add(n)
    except Exception:
        pass

    from utils import cap_scheme_sets
    flat_program = {
        seance: {ex: cap_scheme_sets(s) for ex, s in get_strength_exercises(session_def).items()}
        for seance, session_def in full_program.items()
    }

    # Étape 3 — appliquer les session_plan_overrides via get_day_plan (SOURCE
    # UNIQUE, cf. planner.py). Un exo déplacé matin→soir disparaît d'ici.
    from planner import get_day_plan
    _day_plan = get_day_plan(today_date, full_program)
    if today_str and today_str in flat_program:
        flat_program[today_str] = {
            ex: cap_scheme_sets(s) for ex, s in _day_plan["morning"].items()
        }

    today_exercises = list((flat_program.get(today_str) or {}).keys())
    # Union planifiés ∪ loggés du jour (toutes séances : matin+soir+bonus via
    # logged_today_names L38-51). Sans quoi les exos hors-plan sortent
    # nom-only dans "RÉCAP D'AUJOURD'HUI" (data.weights[exo] nil côté iOS,
    # SeanceView.swift:214 lookup échoue).
    weights = load_weights(sorted(set(today_exercises) | logged_today_names), limit_per=20)
    suggestions = get_suggested_weights_for_today(weights, full_program)

    inv = inventory if isinstance(inventory, dict) else {}
    inventory_types    = {name: info.get("type") or "machine" for name, info in inv.items()}
    inventory_tracking = {name: info.get("tracking_type", "reps") for name, info in inv.items()}
    inventory_rest     = {name: (info.get("rest_seconds") or 120) for name, info in inv.items()}
    inventory_hints    = {name: info["tips"] for name, info in inv.items() if info.get("tips")}
    # Ne mappe QUE les schemes réellement présents en DB (jamais de "3x8-12"
    # inventé). Un exo sans default_scheme → absent → champ vide côté iOS.
    inventory_schemes  = {name: info["default_scheme"] for name, info in inv.items() if info.get("default_scheme")}
    # Idem muscle_group : n'expose que les vraies valeurs. iOS fallback "Autre"
    # au lieu de déduire par nom (crime).
    inventory_muscle_groups = {name: info["muscle_group"] for name, info in inv.items() if info.get("muscle_group")}
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
        "inventory_schemes": inventory_schemes,
        "inventory_muscle_groups": inventory_muscle_groups,
        "exercise_order": exercise_order,
        "exercise_supersets": exercise_supersets,
        "prescriptions": prescriptions,
        "exercise_suggestions": exercise_suggestions,
        "logged_today_names": sorted(logged_today_names),
        # Étape 3b — liste des exos poussés matin→soir aujourd'hui (SOURCE UNIQUE
        # get_day_plan). Consommé par iOS SeanceData.pushedToEvening qui remplace
        # SeanceSplitStore local. Noms strings alignés au plan (même table exercises).
        "pushed_to_evening": _day_plan["pushed_to_evening"],
        # Nom soir résolu (override manuel > héritage matin > None). Exposé pour
        # que les call sites iOS de SeanceSoirView passent le vrai nom soir sans
        # deviner ni faire un fetch séparé. Cf. commit héritage soir.
        "evening_session_name": get_today_evening(),
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
    weights      = load_weights()
    full_program = load_program()
    inventory    = load_inventory()
    today_date   = get_today_date()
    schedule     = get_evening_schedule()

    # Étape 3a-iii — pseudo-séance soir si un override matin→soir apporte des
    # exos alors qu'aucun soir n'est planifié au schedule (§F.3). Sans ça, l'exo
    # déplacé s'évaporait : ni matin (retiré), ni soir (early return).
    # La row workout_session soir N'EST PAS créée ici (aucun log encore) —
    # l'override est une intention au niveau plan, cohérent avec la doctrine.
    from planner import get_day_plan
    _day_plan = get_day_plan(today_date, full_program)
    _virtual_soir = False
    if not today_soir:
        if not _day_plan.get("evening"):
            return jsonify({"has_evening_session": False})
        # Overrides ont apporté des exos evening sans schedule soir → pseudo-séance.
        today_soir = "Séance soir"
        _virtual_soir = True

    already_logged = _db.get_workout_session_second(today_date) is not None

    from utils import cap_scheme_sets
    flat_program = {
        seance: {ex: cap_scheme_sets(s) for ex, s in get_strength_exercises(session_def).items()}
        for seance, session_def in full_program.items()
    }

    # Applique le plan evening post-overrides sur today_soir (réel OU pseudo).
    flat_program[today_soir] = {
        ex: cap_scheme_sets(s) for ex, s in _day_plan["evening"].items()
    }

    inv = inventory if isinstance(inventory, dict) else {}
    inventory_types    = {name: info.get("type") or "machine" for name, info in inv.items()}
    inventory_tracking = {name: info.get("tracking_type", "reps") for name, info in inv.items()}
    inventory_rest     = {name: (info.get("rest_seconds") or 120) for name, info in inv.items()}
    # Ne mappe QUE les schemes réellement présents en DB (voir /api/seance_data).
    inventory_schemes  = {name: info["default_scheme"] for name, info in inv.items() if info.get("default_scheme")}
    inventory_muscle_groups = {name: info["muscle_group"] for name, info in inv.items() if info.get("muscle_group")}
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
        "inventory_schemes": inventory_schemes,
        "inventory_muscle_groups": inventory_muscle_groups,
        "exercise_order": exercise_order,
        # Étape 3b — même que seance_data : liste exposée pour SeanceData.pushedToEvening.
        "pushed_to_evening": _day_plan["pushed_to_evening"],
    })


@workout_schedule_bp.route("/api/evening_schedule", methods=["GET", "POST"])
def api_evening_schedule():
    import db as _db
    if request.method == "POST":
        schedule = request.get_json() or {}
        success = _db.set_evening_week_schedule(schedule)
        return jsonify({"success": success})
    return jsonify(_db.get_evening_week_schedule())


@workout_schedule_bp.route("/api/cycle_start_date", methods=["GET", "POST"])
def api_cycle_start_date():
    """Source serveur unique du mésocycle (programs.cycle_start_date).
    GET  → {"date": "YYYY-MM-DD" | null}
    POST → {"date": "YYYY-MM-DD"} définit la date, retourne {"success": bool}.
    Remplace le @AppStorage iOS qui divergeait au reset/réinstall.
    """
    import db as _db
    if request.method == "POST":
        payload = request.get_json() or {}
        date_str = (payload.get("date") or "").strip()
        if not date_str:
            return jsonify({"success": False, "error": "date_required"}), 400
        success = _db.set_cycle_start_date(date_str)
        return jsonify({"success": success})
    return jsonify({"date": _db.get_cycle_start_date()})


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
        # Étape 3 — respect des overrides via get_day_plan (SOURCE UNIQUE).
        # Pour morning/evening, les exos du slot (post-override) l'emportent sur
        # le template session_name. Bonus garde le fallback session_name.
        if session_type in ("morning", "evening"):
            from planner import get_day_plan
            _day_plan = get_day_plan(date, program)
            exercises = list(_day_plan[session_type].keys())
        else:
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


@workout_schedule_bp.route("/api/move_planned_exercise", methods=["POST"])
def api_move_planned_exercise():
    """Déplacer un exercice planifié entre séances matin/soir pour une date.

    Garde-fou zéro-modif-historique : refuse (409) si un exercise_log existe
    pour (date, exercise_id) — la ligne log garde toujours son session_id.

    `from_session_type` est déterminé PAR LE BACKEND (schedule + override
    actuel), l'iOS ne peut pas mentir sur l'origine.

    Idempotent via UPSERT sur UNIQUE(date, exercise_id). Re-déplacer au même
    endroit = 400 no_op. Bouger un exo déjà déplacé (matin→soir puis
    soir→matin) = update in place, pas doublon.

    Body   : {"date": "YYYY-MM-DD" (opt, défaut today MTL),
              "exercise_id": "uuid",
              "to_session_type": "morning" | "evening"}
    Retour : 200 {"override": {...}, "created": bool}
             400 {"error": "..."} params invalides / exo non planifié / no_op
             409 {"error": "exercise_already_logged"} si un log existe

    Limitation v1 : opère sur TODAY (get_today/get_today_evening = MTL
    courant). Support date arbitraire = ticket futur (helper
    get_schedule_for_date).
    """
    import db as _db
    from planner import get_today, get_today_evening, load_program
    from blocks import get_strength_exercises
    from utils import _today_mtl

    data = request.get_json(silent=True) or {}
    date = data.get("date") or _today_mtl()
    exercise_id = data.get("exercise_id")
    to_slot = (data.get("to_session_type") or "").strip().lower()

    if not exercise_id or to_slot not in ("morning", "evening"):
        return jsonify({
            "error": "bad_request",
            "detail": "exercise_id + to_session_type in {morning,evening} required",
        }), 400

    # Garde-fou zéro-modif-historique (avant toute écriture).
    if _db.exercise_has_log_on(date, exercise_id):
        return jsonify({
            "error": "exercise_already_logged",
            "detail": "un exo loggé ne peut pas être déplacé",
        }), 409

    # Résolution nom de l'exo (les overrides et le schedule sont keyés par name côté plan).
    try:
        r = _db._client.table("exercises").select("name").eq("id", exercise_id).single().execute()
        exo_name = (r.data or {}).get("name")
    except Exception:
        exo_name = None
    if not exo_name:
        return jsonify({"error": "exercise_not_found"}), 400

    # Résolution du slot actuel (source de vérité pour from) : schedule modulé
    # par les overrides existants — un exo déjà déplacé matin→soir a maintenant
    # sa source effective = soir.
    full_program = load_program()
    morning_name = get_today()
    evening_name = get_today_evening()
    morning_exos = set(get_strength_exercises(full_program.get(morning_name, {})).keys()) if morning_name else set()
    evening_exos = set(get_strength_exercises(full_program.get(evening_name, {})).keys()) if evening_name else set()

    existing_overrides = _db.get_session_plan_overrides(date)
    override_effective_slot_by_name: dict = {}
    ov_ex_ids = [o["exercise_id"] for o in existing_overrides]
    if ov_ex_ids:
        try:
            resp = _db._client.table("exercises").select("id,name").in_("id", ov_ex_ids).execute()
            id_to_name_ov = {e["id"]: e["name"] for e in (resp.data or [])}
            for o in existing_overrides:
                nm = id_to_name_ov.get(o["exercise_id"])
                if nm:
                    override_effective_slot_by_name[nm] = o["to_session_type"]
        except Exception:
            pass

    current_slot = override_effective_slot_by_name.get(exo_name)
    if current_slot is None:
        if exo_name in morning_exos:
            current_slot = "morning"
        elif exo_name in evening_exos:
            current_slot = "evening"
        else:
            return jsonify({
                "error": "exercise_not_planned",
                "detail": f"'{exo_name}' n'est pas planifié le {date}",
            }), 400

    if current_slot == to_slot:
        return jsonify({
            "error": "no_op",
            "detail": f"'{exo_name}' est déjà dans {to_slot}",
        }), 400

    row = _db.upsert_session_plan_override(date, exercise_id, current_slot, to_slot)
    if not row:
        return jsonify({"error": "upsert_failed"}), 500
    return jsonify({"override": row, "created": True})


@workout_schedule_bp.route("/api/clear_plan_overrides", methods=["POST"])
def api_clear_plan_overrides():
    """Bulk DELETE tous les overrides pour une date.

    Backend du bouton « Tout ramener » iOS (WorkoutActiveView L1301) — annule
    tous les déplacements matin↔soir du jour d'un coup. AUCUN garde-fou de log
    (contrairement à move) : la doctrine zéro-modif-historique concerne les
    exercise_logs, pas les overrides — un override sur exo loggé n'a plus
    d'effet fonctionnel (l'exo est fixé par son session_id), le supprimer
    est safe.

    Body   : {"date": "YYYY-MM-DD"}  (opt, défaut today MTL)
    Retour : 200 {"deleted": N}
    """
    import db as _db
    from utils import _today_mtl

    data = request.get_json(silent=True) or {}
    date = data.get("date") or _today_mtl()
    n = _db.clear_session_plan_overrides(date)
    return jsonify({"deleted": n})
