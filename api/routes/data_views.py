from flask import Blueprint, jsonify, request
from datetime import datetime, timedelta
from utils import _now_mtl

data_views_bp = Blueprint("data_views", __name__)



@data_views_bp.route("/api/dashboard")
def api_dashboard():
    from weights import load_weights
    from sessions import load_sessions
    from user_profile import load_user_profile
    from goals import load_goals
    from planner import (load_program, get_today, get_today_date, get_week_schedule,
                         get_suggested_weights_for_today, get_today_evening)
    from nutrition import (load_settings as load_nutrition_settings)
    from blocks import get_strength_exercises
    from utils import get_current_week, load_hiit_log
    import db as _db

    weights      = load_weights()
    sessions     = load_sessions()
    profile      = load_user_profile()
    latest_bw = _db.get_body_weight_logs(limit=1)
    if latest_bw:
        profile["weight"] = latest_bw[0].get("weight")
    goals        = load_goals()
    full_program = load_program()
    hiit_log     = load_hiit_log()
    today_str    = get_today()
    _client_date = request.args.get("date", "").strip()
    try:
        datetime.strptime(_client_date, "%Y-%m-%d")
        today_date = _client_date
    except (ValueError, Exception):
        today_date = get_today_date()
    schedule     = get_week_schedule()
    suggestions  = get_suggested_weights_for_today(weights, full_program)

    # Nutrition totals avec date locale iOS (pas _today_mtl() serveur)
    _nutr_entries = _db.get_nutrition_entries(today_date)
    nutrition_totals = {
        "calories":  round(sum(e.get("calories", 0) for e in _nutr_entries)),
        "proteines": round(sum(e.get("proteines", 0) for e in _nutr_entries), 1),
        "glucides":  round(sum(e.get("glucides",  0) for e in _nutr_entries), 1),
        "lipides":   round(sum(e.get("lipides",   0) for e in _nutr_entries), 1),
    }

    _today_all = _db.get_today_sessions_all(today_date)
    # Séance terminée si : une session du jour a completed=True / rpe set, OU au moins 1 exercice loggué
    _today_logged_names: set[str] = set()
    try:
        for s in _today_all:
            sid = s.get("id")
            if not sid:
                continue
            resp = _db._client.table("exercise_logs").select("exercises(name)").eq("session_id", sid).execute()
            for r in (resp.data or []):
                n = (r.get("exercises") or {}).get("name")
                if n:
                    _today_logged_names.add(n)
    except Exception:
        pass
    already_logged_today = bool(
        any(s.get("completed") or s.get("rpe") is not None for s in _today_all)
        or _today_logged_names
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
    # get_daily_session_volumes somme par date pour couvrir les jours splittés
    # (morning + evening + bonus). Recover aussi les sessions qui ont des exercise logs
    # mais ni rpe ni completed (missed by initial filter).
    try:
        vol_by_date = _db.get_daily_session_volumes(days=500)
        for date, sv in vol_by_date.items():
            # Session has exercise logs → count it even if rpe/completed absent
            if sv and date not in merged_sessions and date in sessions:
                merged_sessions[date] = sessions[date]
            if date in merged_sessions and sv is not None:
                merged_sessions[date]["session_volume"] = sv
    except Exception:
        pass

    # Enrich today's session with all exercise names from exercise_logs so the
    # RÉCAP shows every exercise (including those added via "Finir la séance").
    # workout_sessions may have a legacy exos column with only the first batch;
    # _today_logged_names is the authoritative complete list from exercise_logs.
    if today_date in merged_sessions and _today_logged_names:
        existing_exos = merged_sessions[today_date].get("exos") or []
        existing_set = set(existing_exos) if isinstance(existing_exos, list) else set()
        merged_sessions[today_date]["exos"] = list(existing_exos) + [
            n for n in sorted(_today_logged_names) if n not in existing_set
        ]

    smart_goals_count = 0
    try:
        smart_goals_count = len(_db.get_smart_goals())
    except Exception:
        pass

    _total_workout_min_today = sum(int(s.get("duration_min") or 0) for s in _today_all)

    # Séance 2 planifiée : source de vérité UNIQUE = get_today_evening() (planner.py),
    # même helper que /api/seance_soir_data → jamais de divergence entre menu et vue.
    _evening_session_name = get_today_evening()
    _second_session_completed = bool(
        (_db.get_workout_session_second(today_date) or {}).get("completed")
    )

    # Bonus session (citoyen de première classe, décision D1).
    _bonus_session = _db.get_workout_session_bonus(today_date)
    _bonus_session_name = (_bonus_session or {}).get("session_name")
    _bonus_session_completed = bool((_bonus_session or {}).get("completed"))

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
        "total_workout_min_today": _total_workout_min_today if _total_workout_min_today > 0 else None,
        "has_evening_session":     _evening_session_name is not None,
        "evening_session_name":    _evening_session_name,
        "second_session_completed": _second_session_completed,
        "has_bonus_session":        _bonus_session is not None,
        "bonus_session_name":       _bonus_session_name,
        "bonus_session_completed":  _bonus_session_completed,
        # Cycle mésocycle — source serveur unique (programs.cycle_start_date).
        # Remplace le @AppStorage local iOS qui divergeait au reset/réinstall.
        "cycle_start_date":        _db.get_cycle_start_date(),
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

    program_id = request.args.get("program_id") or _db.get_active_program_id()
    full_program = _db.get_full_program(program_id) or load_program()
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
    inventory_rest     = {name: 120 for name in inv}
    # N'expose QUE les schemes réellement présents en DB. Un exo sans default_scheme
    # → absent du mapping → champ vide côté iOS → hint "Précisez un scheme" → Vince
    # décide. Le catalogue propose ce qu'il SAIT, jamais ce qu'il invente.
    inventory_schemes  = {name: info["default_scheme"] for name, info in inv.items() if info.get("default_scheme")}
    # Même règle pour muscle_group : n'expose que les valeurs réelles en DB.
    # Un exo sans muscle_group → absent du mapping → iOS affiche "Autre" en fallback,
    # jamais une déduction par nom (crime : Neck Curl → "Biceps" via pattern "curl").
    inventory_muscle_groups = {name: info["muscle_group"] for name, info in inv.items() if info.get("muscle_group")}
    inventory_muscles  = {name: info.get("muscles") or []             for name, info in inv.items()}
    inventory_patterns = {name: info.get("pattern") or ""             for name, info in inv.items()}
    exercise_order     = {seance: list(exs.keys()) for seance, exs in flat_program.items()}
    from db import get_current_1rm_estimates
    inventory_1rm = {r["name"]: r["estimated_1rm"] for r in get_current_1rm_estimates()}
    return jsonify({
        "full_program":        flat_program,
        "session_order":       list(flat_program.keys()),
        "schedule":            schedule,
        "inventory":           list(inv.keys()),
        "inventory_types":     inventory_types,
        "inventory_tracking":  inventory_tracking,
        "inventory_rest":      inventory_rest,
        "inventory_schemes":   inventory_schemes,
        "inventory_muscle_groups": inventory_muscle_groups,
        "inventory_muscles":   inventory_muscles,
        "inventory_patterns":  inventory_patterns,
        "inventory_1rm":       inventory_1rm,
        "exercise_order":      exercise_order,
        "programs":            programs,
        "current_program_id":  program_id,
        "all_sessions":        all_sessions,
        # Miroir du champ dashboard — ProgrammeVM charge programme_data et lit ici,
        # évite un fetch dashboard séparé pour la card Mésocycle.
        "cycle_start_date":    _db.get_cycle_start_date(),
    })


@data_views_bp.route("/api/inventaire_data")
def api_inventaire_data():
    import db as _db
    from inventory import load_inventory
    from planner import load_program
    from blocks import get_strength_exercises
    from db_exercises import get_exercise_use_counts

    inventory = load_inventory()
    if inventory is None:
        return jsonify({"inventory": {}, "in_program": []})

    use_counts = get_exercise_use_counts()
    enriched = {}
    for name, data in inventory.items():
        d = dict(data)
        d["use_count"] = use_counts.get(d.get("id", ""), 0)
        enriched[name] = d

    full_program = _db.get_full_program(None) or load_program()
    in_program: set = set()
    for session_def in full_program.values():
        exos = get_strength_exercises(session_def) if isinstance(session_def, dict) and "blocks" in session_def else (session_def if isinstance(session_def, dict) else {})
        in_program.update(exos.keys())
    return jsonify({"inventory": enriched, "in_program": sorted(in_program)})


@data_views_bp.route("/api/exercise_detail")
def api_exercise_detail():
    import json as _json
    import db as _db
    from planner import load_program
    from blocks import get_strength_exercises
    from db_sessions import get_exercise_detail_history
    from datetime import datetime, timedelta

    name = request.args.get("name", "").strip()
    if not name:
        return jsonify({"error": "name required"}), 400

    history_raw = get_exercise_detail_history(name, limit=10)

    def calc_e1rm(weight, reps_str):
        if not reps_str or not weight:
            return None
        try:
            w = float(weight)
        except (TypeError, ValueError):
            return None
        if w <= 0:
            return None
        from progression import estimate_1rm
        return estimate_1rm(w, str(reps_str)) or None

    history = []
    e1rms = []
    for row in history_raw:
        e1rm = calc_e1rm(row.get("weight"), row.get("reps"))
        if e1rm:
            e1rms.append(e1rm)
        sets_raw = row.get("sets_json")
        sets = []
        if sets_raw:
            try:
                parsed = _json.loads(sets_raw) if isinstance(sets_raw, str) else sets_raw
                sets = parsed if isinstance(parsed, list) else []
            except Exception:
                pass
        history.append({
            "date":   row.get("date"),
            "weight": row.get("weight"),
            "reps":   str(row.get("reps", "")),
            "sets":   sets,
            "rpe":    row.get("rpe"),
            "e1rm":   e1rm,
        })

    e1rm_current = e1rms[0] if e1rms else None
    e1rm_best    = max(e1rms) if e1rms else None

    cutoff_30d = (_now_mtl() - timedelta(days=30)).date()
    trend_30d = [
        {"date": h["date"], "e1rm": h["e1rm"]}
        for h in history
        if h["e1rm"] and h["date"]
        and datetime.strptime(h["date"], "%Y-%m-%d").date() >= cutoff_30d
    ]

    full_program = _db.get_full_program(None) or load_program()
    in_sessions = []
    for session_name, session_def in full_program.items():
        exos = (get_strength_exercises(session_def)
                if isinstance(session_def, dict) and "blocks" in session_def
                else (session_def if isinstance(session_def, dict) else {}))
        if name in exos:
            in_sessions.append(session_name)

    return jsonify({
        "e1rm_current": e1rm_current,
        "e1rm_best":    e1rm_best,
        "last_session": {"date": history[0]["date"], "weight": history[0]["weight"], "reps": history[0]["reps"]} if history else None,
        "history":      history[:5],
        "trend_30d":    trend_30d,
        "in_sessions":  sorted(in_sessions),
    })


@data_views_bp.route("/api/historique_data")
def api_historique_data():
    import db as _db
    from weights import load_weights

    limit  = min(int(request.args.get("limit",  90)),  200)
    offset = int(request.args.get("offset", 0))
    month  = request.args.get("month")  # "YYYY-MM" filter

    # Fetch sessions from DB with real LIMIT/OFFSET pushed to Supabase.
    # For the month-filter path we still need all sessions in that month,
    # so we fetch a generous cap there.  For paginated requests we fetch
    # `limit * 2 + 10` rows so that after deduplication / bonus-merge we
    # always have enough rows to fill the requested page.
    if month:
        # Month filter: fetch up to 200 sessions (a full month is typically <60)
        sessions = _db.get_workout_sessions(limit=200, offset=0)
    else:
        sessions = _db.get_workout_sessions(limit=limit * 2 + 10, offset=offset)

    # Collect session IDs to scope exercise history — avoids a full-table scan.
    page_session_ids = [s.get("id") for s in sessions if s.get("id")]
    ex_by_session = _db.get_exercise_history_grouped_by_session(
        session_ids=page_session_ids if page_session_ids else None
    )
    hiit_log = _db.get_hiit_logs(limit=30)

    # Deduplicate rows by (date, session_type).
    # In some environments old duplicates can exist (missing/late unique constraint),
    # and iOS uses date+session_type as row identity in HistoriqueView.
    # Keep the richest row so exercises are not hidden by an empty duplicate.
    best_by_key = {}

    # Filtre fantômes de duplication (calibré 2026-07-26 sur 55 rows / 591 exercise_logs).
    # Un exo est fantôme SSI weight non-multiple de 0.25 (moyenne recalculée, non-plaque)
    # ET sets_json vide/null. Ni poids-plaque ni per-set détaillé = aucune source valide.
    # Masqué à l'affichage historique UNIQUEMENT — JAMAIS supprimé (doctrine zéro-modif-
    # historique). Stats ACWR/volume restent polluées (Q6=90), à corriger par recalcul
    # depuis sets_json — ticket séparé.
    def _is_ghost_exo(e: dict) -> bool:
        w = e.get("weight")
        if w is None:
            return False
        if abs(w * 4 - round(w * 4)) <= 0.01:
            return False  # poids-plaque (multiple de 0.25) → réel
        return not (e.get("sets") or [])  # non-plate + sets vides = fantôme

    for s in sessions:
        d   = s.get("date")
        sid = s.get("id")
        stype = s.get("session_type") or ("evening" if s.get("is_second") else "morning")
        if not d:
            continue
        if month and not d.startswith(month):
            continue
        exos = [e for e in ex_by_session.get(sid, []) if not _is_ghost_exo(e)]
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

    # Bonus is a first-class session (décision D1) — no merge into morning.
    # Each session_id resolves its own exos, cf. commit 6285197 (récap hors-plan).
    # Cas historique : les jours avec morning + bonus étaient affichés fusionnés,
    # maintenant 2 cartes distinctes (chaque exo sous sa vraie séance).

    session_list = sorted(
        best_by_key.values(),
        key=lambda x: (x.get("date", ""), x.get("session_type", "")),
        reverse=True,
    )

    # Supplement exos from weights history (authoritative source).
    # Always merge — not just when empty — so exercises logged after session
    # completion (e.g. "Finir la séance") appear even if exercise_logs query
    # returned a partial result.
    #
    # Routage par (date, session_type), PAS par date seule (fix 2026-07-26) :
    # avant ce fix, l'enrichissement dumpait tous les exos d'une date sur TOUTES
    # les cartes du jour → morning et bonus contaminés mutuellement dès qu'ils
    # devenaient des cartes autonomes (retrait fusion bonus→morning). session_type
    # est fourni par get_all_exercise_history via le join workout_sessions.
    # Vérifié 2026-07-26 : 591/591 entries ont session_type peuplé.
    # Filtre ghost (_is_ghost_exo) appliqué ici AUSSI — sans lui, les fantômes
    # filtrés du path primaire ex_by_session étaient réinjectés par cette source.
    try:
        weights = load_weights()
        ex_by_key: dict[tuple[str, str], list[dict]] = {}
        for ex_name, ex_data in (weights or {}).items():
            for entry in ex_data.get("history", []):
                d = entry.get("date")
                st = entry.get("session_type")
                if not d or not st:
                    # Legacy row sans session_type : ignorée pour éviter la
                    # cross-contamination inter-sessions. Volume négligeable
                    # (0/591 en 2026-07-26).
                    continue
                candidate = {
                    "exercise": ex_name,
                    "weight": entry.get("weight", 0),
                    "reps": entry.get("reps", ""),
                    "sets": entry.get("sets") or [],
                }
                if _is_ghost_exo(candidate):
                    continue
                ex_by_key.setdefault((d, st), []).append(candidate)
        # Le supplément COMPLÈTE par-exo, jamais ne REMPLACE : un exo déjà présent
        # dans row["exos"] (venu de exercise_logs, source riche avec sets_json) garde
        # sa version. Un exo absent est ajouté depuis weights.history qui porte aussi
        # les sets (db_sessions.get_all_exercise_history L906-907). L'ancienne branche
        # `if not existing: row["exos"] = date_exos` écrasait une row exos=[] par
        # date_exos dépourvu de sets → format condensé côté iOS (bug 2026-07-20).
        for row in session_list:
            key = (row.get("date"), row.get("session_type"))
            date_exos = ex_by_key.get(key, [])
            if not date_exos:
                continue
            existing = row.get("exos") or []
            existing_names = {e.get("exercise") for e in existing}
            extra = [e for e in date_exos if e.get("exercise") not in existing_names]
            if extra:
                row["exos"] = list(existing) + extra
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

    # For the paginated path the DB already returned only the window we need
    # (offset was pushed to the query); take up to `limit` entries from the
    # deduplicated list.
    page = session_list[:limit]

    return jsonify({
        "session_list": page,
        "hiit_list":    hiit_log,
        "total":        len(page),
        "has_more":     len(session_list) > limit,
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
