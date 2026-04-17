from flask import Blueprint, jsonify, request, render_template, redirect, url_for, make_response
from datetime import datetime
import os

data_views_bp = Blueprint("data_views", __name__)


@data_views_bp.route("/")
def index():
    from weights import load_weights
    from user_profile import load_user_profile
    from planner import (load_program, get_today, get_week_schedule,
                         get_suggested_weights_for_today)
    from goals import load_goals, get_progress_bar
    from deload import load_deload_state
    from sessions import load_sessions
    from nutrition import (load_settings as load_nutrition_settings, get_today_totals)
    from utils import _today_mtl, get_current_week, load_hiit_log_local

    weights      = load_weights()
    profile      = load_user_profile()
    full_program = load_program()
    suggestions  = get_suggested_weights_for_today(weights, full_program)
    goals        = load_goals()
    deload_state = load_deload_state()
    sessions     = load_sessions()

    goals_progress = {}
    for ex, goal in goals.items():
        current = weights.get(ex, {}).get("current_weight", 0) or 0
        goals_progress[ex] = {
            "current":  current,
            "goal":     goal["goal_weight"],
            "bar":      get_progress_bar(current, goal["goal_weight"]),
            "achieved": goal.get("achieved", False),
            "since":    deload_state.get("since", "")
        }

    today_str  = get_today()
    today_date = _today_mtl()
    hiit_log   = load_hiit_log_local()

    already_logged_today = sessions.get(today_date, {}).get("completed", False)

    return render_template("index.html",
        today        = today_str,
        week         = get_current_week(),
        profile      = profile,
        suggestions  = suggestions,
        goals        = goals_progress,
        schedule     = get_week_schedule(),
        full_program = full_program,
        deload_state = deload_state,
        sessions     = sessions,
        weights      = weights,
        hiit_log              = hiit_log,
        now                   = datetime.now().strftime("%A"),
        nutrition_totals      = get_today_totals(),
        nutrition_settings    = load_nutrition_settings(),
        already_logged_today  = already_logged_today,
    )


@data_views_bp.route("/nutrition")
def nutrition():
    from nutrition import (load_settings as load_nutrition_settings,
                           get_today_entries, get_today_totals, get_recent_days)
    from utils import _today_mtl
    settings = load_nutrition_settings()
    entries  = get_today_entries()
    totals   = get_today_totals()
    recent   = get_recent_days(7)
    return render_template("nutrition.html",
        settings = settings,
        entries  = entries,
        totals   = totals,
        recent   = recent,
        today    = _today_mtl(),
    )


@data_views_bp.route("/inventaire")
def inventaire():
    from inventory import load_inventory
    return render_template("inventaire.html", inventory=load_inventory())


@data_views_bp.route("/programme")
def programme():
    from planner import load_program, get_today, get_week_schedule
    from inventory import load_inventory
    return render_template("programme.html",
        program   = load_program(),
        inventory = load_inventory(),
        today     = get_today(),
        schedule  = get_week_schedule()
    )


@data_views_bp.route("/seance")
def seance():
    from weights import load_weights
    from planner import load_program, get_today
    from sessions import load_sessions
    from inventory import load_inventory, calculate_plates
    from hiit import get_hiit_str
    from utils import _today_mtl, get_current_week

    weights  = load_weights()
    today    = get_today()
    sessions = load_sessions()
    today_date = _today_mtl()

    if today in ['Yoga / Tai Chi', 'Recovery']:
        return redirect(url_for('data_views.seance_speciale', session_type=today))

    already_logged   = today_date in sessions
    previous_session = sessions.get(today_date)

    program   = load_program()
    inv       = load_inventory()
    exercises = []

    if today in program:
        for ex, scheme in program[today].items():
            data    = weights.get(ex, {})
            ex_info = inv.get(ex, {})
            current = data.get("current_weight", 0) or 0
            ex_type = ex_info.get("type") or "machine"
            bar_w   = ex_info.get("bar_weight", 45.0)

            if ex_type == "barbell" and current:
                display = f"{(current - bar_w) / 2:.1f} lbs par côté"
            elif ex_type == "dumbbell" and current:
                display = f"{current / 2:.1f} lbs par haltère"
            else:
                display = f"{current:.1f} lbs" if current else "À définir"

            plates_needed = []
            if ex_type == "barbell" and current > bar_w:
                plates_needed = calculate_plates(current, bar_w)

            history      = data.get("history", [])
            logged_today = bool(history and history[0]["date"] == today_date)

            exercises.append({
                "name":         ex,
                "scheme":       scheme,
                "current":      current,
                "display":      display,
                "type":         ex_type,
                "plates":       plates_needed,
                "history":      history[:3],
                "1rm":          history[0].get("1rm", 0) if history else 0,
                "logged_today": logged_today,
            })

    return render_template("seance.html",
        today            = today,
        exercises        = exercises,
        is_hiit          = "HIIT" in today,
        hiit_str         = get_hiit_str(get_current_week()) if "HIIT" in today else "",
        week             = get_current_week(),
        already_logged   = already_logged,
        previous_session = previous_session
    )


@data_views_bp.route("/seance_speciale/<path:session_type>")
def seance_speciale(session_type):
    from urllib.parse import unquote
    from sessions import load_sessions
    from utils import _today_mtl, get_current_week, load_hiit_log_local

    session_type = unquote(session_type)  # ← décode HIIT%201 → HIIT 1

    week = get_current_week()
    if week <= 4:
        protocole = {"rounds": 8, "sprint_spd": 13.0, "jog_spd": 6.5, "duree": 20}
    elif week <= 8:
        protocole = {"rounds": 10, "sprint_spd": 13.0, "jog_spd": 6.5, "duree": 25}
    elif week <= 12:
        protocole = {"rounds": 12, "sprint_spd": 13.0, "jog_spd": 6.5, "duree": 28}
    elif week <= 16:
        protocole = {"rounds": 8, "sprint_spd": 14.0, "jog_spd": 7.0, "duree": 20}
    else:
        protocole = {"rounds": 10, "sprint_spd": 14.0, "jog_spd": 7.0, "duree": 25}

    today_date = _today_mtl()
    hiit_log   = load_hiit_log_local()

    sessions         = load_sessions()
    already_logged   = today_date in sessions
    previous_session = sessions.get(today_date)

    return render_template("seance_speciale.html",
                           session_type=session_type,
                           protocole=protocole,
                           week=week,
                           hiit_log=hiit_log,
                           now=today_date,
                           already_logged=already_logged,
                           previous_session=previous_session,
                           )


@data_views_bp.route("/historique")
def historique():
    from weights import load_weights
    from sessions import load_sessions
    from utils import load_hiit_log_local

    weights  = load_weights()
    sessions = load_sessions()
    hiit_log = load_hiit_log_local()

    # Build index: date -> list of {exercise, weight, reps}
    ex_by_date = {}
    for ex, data in weights.items():
        for entry in data.get("history", []):
            d = entry.get("date")
            if not d:
                continue
            ex_by_date.setdefault(d, []).append({
                "exercise": ex,
                "weight":   entry.get("weight", 0),
                "reps":     entry.get("reps", ""),
            })

    # Merge muscu sessions and HIIT into unified list sorted by date desc
    all_dates = set(sessions.keys()) | set(ex_by_date.keys())
    session_list = []
    for d in sorted(all_dates, reverse=True):
        s = sessions.get(d, {})
        session_list.append({
            "date":    d,
            "type":    "muscu",
            "rpe":     s.get("rpe"),
            "comment": s.get("comment", ""),
            "exos":    ex_by_date.get(d, []),
        })

    hiit_list = sorted(hiit_log, key=lambda x: x.get("date",""), reverse=True)

    return render_template("historique.html",
        session_list = session_list[:60],
        hiit_list    = hiit_list[:30],
        weights      = weights,
    )


@data_views_bp.route("/hiit")
def hiit_historique():
    from utils import load_hiit_log_local
    return render_template("hiit.html", hiit_log=load_hiit_log_local())


@data_views_bp.route("/notes")
def notes():
    from sessions import load_sessions
    return render_template("notes.html", sessions=load_sessions())


@data_views_bp.route("/objectifs")
def objectifs():
    from weights import load_weights
    from goals import load_goals
    weights    = load_weights()
    goals      = load_goals()
    goals_data = []
    for ex, goal in goals.items():
        current = weights.get(ex, {}).get("current_weight", 0) or 0
        pct     = min(current / goal["goal_weight"] * 100, 100) if goal["goal_weight"] else 0
        goals_data.append({
            "exercise": ex,
            "current":  current,
            "goal":     goal["goal_weight"],
            "pct":      round(pct, 1),
            "achieved": goal.get("achieved", False),
            "deadline": goal.get("deadline", ""),
        })
    return render_template("objectifs.html", goals=goals_data)


@data_views_bp.route("/timer")
def timer():
    from utils import _today_mtl
    return render_template("timer.html",
        now  = _today_mtl(),
        week = datetime.now().isocalendar()[1]
    )


@data_views_bp.route("/xp")
def xp():
    from weights import load_weights
    from sessions import load_sessions
    from inventory import load_inventory
    from utils import _today_mtl, load_hiit_log_local
    return render_template("xp.html",
        weights   = load_weights(),
        sessions  = load_sessions(),
        hiit_log  = load_hiit_log_local(),
        inventory = load_inventory(),
        now       = _today_mtl(),
        week      = datetime.now().isocalendar()[1]
    )


@data_views_bp.route("/bodycomp")
def bodycomp():
    from body_weight import load_body_weight, get_tendance
    from user_profile import load_user_profile
    from utils import _today_mtl
    bw = load_body_weight()
    return render_template("bodycomp.html",
        body_weight = bw,
        profile     = load_user_profile(),
        tendance    = get_tendance(bw) if bw else "Pas de données",
        now         = _today_mtl(),
        week        = datetime.now().isocalendar()[1]
    )


@data_views_bp.route("/intelligence")
def intelligence():
    from weights import load_weights
    from sessions import load_sessions
    from inventory import load_inventory
    from planner import load_program
    from utils import _today_mtl, load_hiit_log_local
    return render_template("intelligence.html",
        weights   = load_weights(),
        sessions  = load_sessions(),
        hiit_log  = load_hiit_log_local(),
        inventory = load_inventory(),
        program   = load_program(),
        now       = _today_mtl(),
        week      = datetime.now().isocalendar()[1]
    )


@data_views_bp.route("/planificateur")
def planificateur():
    from weights import load_weights
    from sessions import load_sessions
    from planner import load_program, get_week_schedule
    from utils import _today_mtl, load_hiit_log_local
    return render_template("planificateur.html",
        weights      = load_weights(),
        sessions     = load_sessions(),
        hiit_log     = load_hiit_log_local(),
        full_program = load_program(),
        schedule     = get_week_schedule(),
        now          = _today_mtl(),
        week         = datetime.now().isocalendar()[1]
    )


@data_views_bp.route("/stats")
def stats():
    from weights import load_weights
    from sessions import load_sessions
    from body_weight import load_body_weight
    from inventory import load_inventory
    from utils import _today_mtl, load_hiit_log_local
    return render_template("stats.html",
        weights     = load_weights(),
        sessions    = load_sessions(),
        hiit_log    = load_hiit_log_local(),
        body_weight = load_body_weight(),
        inventory   = load_inventory(),
        now         = _today_mtl()
    )


@data_views_bp.route("/profil")
def profil():
    from user_profile import load_user_profile
    from body_weight import load_body_weight, get_tendance
    profile     = load_user_profile()
    body_weight = load_body_weight()
    tendance    = get_tendance(body_weight) if body_weight else "Pas de données"
    return render_template("profil.html",
        profile          = profile,
        body_weight      = body_weight[:10] if body_weight else [],
        body_weight_all  = body_weight,
        tendance         = tendance
    )


@data_views_bp.route("/sw.js")
def service_worker():
    # Version = SHA git sur Vercel, timestamp horaire en local
    # Change automatiquement à chaque déploiement → nouveau CACHE_NAME → SW update → reload
    import re
    BASE_DIR = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
    build_version = (
        os.getenv('VERCEL_GIT_COMMIT_SHA', '')[:8]
        or datetime.now().strftime('%Y%m%d%H')
    )
    with open(os.path.join(BASE_DIR, "static", "sw.js")) as f:
        content = f.read()
    # Remplace le CACHE_NAME hardcodé par la version du build
    content = re.sub(
        r"(const CACHE_NAME\s*=\s*')[^']*(')",
        f"\\g<1>trainingos-{build_version}\\2",
        content
    )
    resp = make_response(content, 200)
    resp.headers['Content-Type']  = 'application/javascript'
    resp.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    resp.headers['Pragma']        = 'no-cache'
    resp.headers['Expires']       = '0'
    return resp


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
    try:
        vol_by_date = _db.get_sessions_for_correlations(days=500)
        for date, vol_data in vol_by_date.items():
            if date in merged_sessions and vol_data.get("session_volume") is not None:
                merged_sessions[date]["session_volume"] = vol_data["session_volume"]
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
        "full_program":        {s: get_strength_exercises(sd) for s, sd in full_program.items()},
        "nutrition_totals":    nutrition_totals,
        "nutrition_settings":  load_nutrition_settings(),
        "profile":             profile,
    })


@data_views_bp.route("/api/weights")
def api_weights():
    from weights import load_weights
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
    # Aplatit la structure bloc → {seance: {exercice: scheme}} pour le client iOS
    flat_program = {
        seance: get_strength_exercises(session_def)
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
    exercise_order     = {seance: list(exs.keys()) for seance, exs in flat_program.items()}
    return jsonify({
        "full_program":        flat_program,
        "schedule":            schedule,
        "inventory":           list(inv.keys()),
        "inventory_types":     inventory_types,
        "inventory_tracking":  inventory_tracking,
        "inventory_rest":      inventory_rest,
        "inventory_schemes":   inventory_schemes,
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
