# api/index.py
from __future__ import annotations
import os, sys, json, socket, webbrowser, logging
from threading import Timer, Lock
from concurrent.futures import ThreadPoolExecutor, as_completed
from datetime import datetime, date
from pathlib import Path

# ── Logging setup ────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(name)s — %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger("trainingos")

# Charge le .env pour le dev local (no-op sur Vercel)
try:
    from dotenv import load_dotenv
    load_dotenv(Path(__file__).parent.parent / '.env')
except ImportError:
    pass

# ✅ Ajoute /api au path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

# ── Timezone Montréal (gère l'heure d'été) ───────────────────
def _now_mtl() -> datetime:
    # 1. zoneinfo + tzdata
    try:
        from zoneinfo import ZoneInfo
        return datetime.now(ZoneInfo("America/Montreal"))
    except Exception:
        pass
    # 2. pytz
    try:
        import pytz
        return datetime.now(pytz.timezone("America/Montreal"))
    except Exception:
        pass
    # 3. Calcul DST manuel (aucune dépendance)
    from datetime import timezone, timedelta as td
    utc = datetime.now(timezone.utc)
    def nth_sunday(y, m, n):
        first = datetime(y, m, 1)
        return first + td(days=(6 - first.weekday()) % 7 + 7 * (n - 1))
    y = utc.year
    dst_start = nth_sunday(y, 3,  2).replace(hour=7, tzinfo=timezone.utc)
    dst_end   = nth_sunday(y, 11, 1).replace(hour=6, tzinfo=timezone.utc)
    offset = -4 if dst_start <= utc < dst_end else -5
    return utc.astimezone(timezone(td(hours=offset)))

def _today_mtl() -> str:
    return _now_mtl().strftime("%Y-%m-%d")

from flask import Flask, render_template, jsonify, request, redirect, url_for, send_from_directory
from werkzeug.utils import secure_filename

from planner      import get_today, get_today_date, get_week_schedule, get_suggested_weights_for_today, load_program, save_program, get_today_evening, get_evening_schedule
from blocks       import (make_strength_block, make_hiit_block, make_cardio_block,
                           get_block, get_strength_exercises,
                           upsert_block, remove_block, reorder_blocks)
from hiit         import get_hiit_str
from weights      import load_weights, save_weights
from log_workout  import log_single_exercise
from inventory    import load_inventory, save_inventory, add_exercise, rename_inventory_exercise, calculate_plates
from sessions     import load_sessions, log_session, log_second_session, session_exists
from user_profile import load_user_profile, save_user_profile
from progression  import estimate_1rm, should_increase, next_weight, parse_reps, progression_status, suggest_next_weight
from deload       import analyser_deload, load_deload_state
from goals        import load_goals, check_goals_achieved, get_progress_bar, set_goal
from body_weight  import load_body_weight, log_body_weight, get_tendance
from nutrition    import (load_settings as load_nutrition_settings,
                          save_settings as save_nutrition_settings,
                          get_today_entries, get_today_totals,
                          add_entry as nutrition_add_entry,
                          delete_entry as nutrition_delete_entry,
                          get_recent_days)
from db           import get_json, set_json
from db           import _ON_VERCEL
from volume       import calc_set_volume, calc_exercise_volume, calc_session_volume, _calc_session_volume_legacy
import wearable

# ── App config ──────────────────────────────────────────────
_API_DIR  = os.path.dirname(os.path.abspath(__file__))
BASE_DIR  = os.path.dirname(_API_DIR)  # remonte à la racine

# Sur Vercel, templates/static sont à la racine
TEMPLATES = os.path.join(BASE_DIR, "templates")
STATIC    = os.path.join(BASE_DIR, "static")

app = Flask(
    __name__,
    template_folder = TEMPLATES,
    static_folder   = STATIC,
)
_SECRET_KEY_DEFAULT = "trainingos-secret-change-in-prod"
_secret_key = os.getenv("SECRET_KEY", _SECRET_KEY_DEFAULT)
if os.getenv("VERCEL") and _secret_key == _SECRET_KEY_DEFAULT:
    raise RuntimeError("SECRET_KEY must be set to a secure value in production (Vercel env vars)")
app.secret_key = _secret_key

# ── Wearable / Apple Watch routes ───────────────────────────
wearable.register_routes(app)

UPLOAD_FOLDER      = os.path.join(BASE_DIR, "static", "uploads")
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'gif'}
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER
RAPID_API_KEY = os.getenv("X_RAPIDAPI_KEY")

# ── Rate limiting for Anthropic AI routes ─────────────────────────────────────
# Token bucket: refills at 1 token/6 min → max 10 calls/hour
_AI_RATE_LOCK      = Lock()
_AI_TOKENS         = 10        # current bucket level
_AI_MAX_TOKENS     = 10
_AI_REFILL_SECONDS = 360       # 1 token per 6 minutes
_AI_LAST_REFILL    = datetime.utcnow()

def _ai_rate_check() -> bool:
    """Return True if the request is allowed, False if rate limited."""
    global _AI_TOKENS, _AI_LAST_REFILL
    with _AI_RATE_LOCK:
        now     = datetime.utcnow()
        elapsed = (now - _AI_LAST_REFILL).total_seconds()
        refill  = int(elapsed / _AI_REFILL_SECONDS)
        if refill > 0:
            _AI_TOKENS      = min(_AI_MAX_TOKENS, _AI_TOKENS + refill)
            _AI_LAST_REFILL = now
        if _AI_TOKENS <= 0:
            return False
        _AI_TOKENS -= 1
        return True


# ── Helpers ─────────────────────────────────────────────────

def get_current_week() -> int:
    START_DATE = date(2026, 3, 3)
    delta      = date.today() - START_DATE
    return max(1, (delta.days // 7) + 1)


def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS


def load_hiit_log_local() -> list:
    import db as _db
    return _db.get_hiit_logs() or []


# ── Pages HTML ───────────────────────────────────────────────

@app.route("/")
def index():
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

    already_logged_today = today_date in sessions

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


@app.route("/nutrition")
def nutrition():
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


@app.route("/api/nutrition/add", methods=["POST"])
def api_nutrition_add():
    data  = request.get_json()
    entry = nutrition_add_entry(
        nom      = data.get("nom", ""),
        calories = float(data.get("calories", 0)),
        proteines= float(data.get("proteines", 0)),
        glucides = float(data.get("glucides", 0)),
        lipides  = float(data.get("lipides", 0)),
    )
    return jsonify({"success": True, "entry": entry, "totals": get_today_totals()})


@app.route("/api/nutrition/delete", methods=["POST"])
def api_nutrition_delete():
    data = request.get_json()
    ok   = nutrition_delete_entry(data.get("id", ""))
    return jsonify({"success": ok, "totals": get_today_totals()})


@app.route("/api/nutrition/settings", methods=["POST"])
def api_nutrition_settings():
    data = request.get_json()
    save_nutrition_settings(
        int(data.get("limite_calories", 2200)),
        int(data.get("objectif_proteines", 160)),
    )
    return jsonify({"success": True})


@app.route("/inventaire")
def inventaire():
    return render_template("inventaire.html", inventory=load_inventory())


@app.route("/programme")
def programme():
    return render_template("programme.html",
        program   = load_program(),
        inventory = load_inventory(),
        today     = get_today(),
        schedule  = get_week_schedule()
    )


@app.route("/seance")
def seance():
    weights  = load_weights()
    today    = get_today()
    sessions = load_sessions()
    today_date = _today_mtl()

    if today in ['Yoga / Tai Chi', 'Recovery']:
        return redirect(url_for('seance_speciale', session_type=today))

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
            ex_type = ex_info.get("type", "machine")
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


@app.route("/seance_speciale/<path:session_type>")
def seance_speciale(session_type):
    from urllib.parse import unquote
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

@app.route("/historique")
def historique():
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


@app.route("/hiit")
def hiit_historique():
    return render_template("hiit.html", hiit_log=load_hiit_log_local())


@app.route("/notes")
def notes():
    return render_template("notes.html", sessions=load_sessions())


@app.route("/objectifs")
def objectifs():
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


@app.route("/timer")
def timer():
    return render_template("timer.html",
        now  = _today_mtl(),
        week = datetime.now().isocalendar()[1]
    )


@app.route("/xp")
def xp():
    return render_template("xp.html",
        weights   = load_weights(),
        sessions  = load_sessions(),
        hiit_log  = load_hiit_log_local(),
        inventory = load_inventory(),
        now       = _today_mtl(),
        week      = datetime.now().isocalendar()[1]
    )


@app.route("/bodycomp")
def bodycomp():
    bw = load_body_weight()
    return render_template("bodycomp.html",
        body_weight = bw,
        profile     = load_user_profile(),
        tendance    = get_tendance(bw) if bw else "Pas de données",
        now         = _today_mtl(),
        week        = datetime.now().isocalendar()[1]
    )


@app.route("/intelligence")
def intelligence():
    return render_template("intelligence.html",
        weights   = load_weights(),
        sessions  = load_sessions(),
        hiit_log  = load_hiit_log_local(),
        inventory = load_inventory(),
        program   = load_program(),
        now       = _today_mtl(),
        week      = datetime.now().isocalendar()[1]
    )


@app.route("/planificateur")
def planificateur():
    return render_template("planificateur.html",
        weights      = load_weights(),
        sessions     = load_sessions(),
        hiit_log     = load_hiit_log_local(),
        full_program = load_program(),
        schedule     = get_week_schedule(),
        now          = _today_mtl(),
        week         = datetime.now().isocalendar()[1]
    )


@app.route("/stats")
def stats():
    return render_template("stats.html",
        weights     = load_weights(),
        sessions    = load_sessions(),
        hiit_log    = load_hiit_log_local(),
        body_weight = load_body_weight(),
        inventory   = load_inventory(),
        now         = _today_mtl()
    )


@app.route("/profil")
def profil():
    profile     = load_user_profile()
    body_weight = load_body_weight()
    tendance    = get_tendance(body_weight) if body_weight else "Pas de données"
    return render_template("profil.html",
        profile          = profile,
        body_weight      = body_weight[:10] if body_weight else [],
        body_weight_all  = body_weight,
        tendance         = tendance
    )


# ── API ──────────────────────────────────────────────────────

@app.route("/api/log", methods=["POST"])
def api_log():
    try:
        data     = request.get_json()
        exercise = data.get("exercise")
        weight   = float(data.get("weight", 0))
        reps_str = data.get("reps", "")
        rpe_raw  = data.get("rpe")
        rpe      = float(rpe_raw) if rpe_raw is not None else None

        force          = bool(data.get("force", False))
        is_second      = bool(data.get("is_second", False))
        equipment_type = data.get("equipment_type", "")

        if not exercise or not reps_str:
            return jsonify({"error": "Données manquantes"}), 400

        weights   = load_weights()

        # Duplicate-prevention guard (skipped for force overwrite or evening session)
        existing_history = weights.get(exercise, {}).get("history", [])
        if not force and not is_second and existing_history and existing_history[0]["date"] == _today_mtl():
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

        # If sets provided, recompute average weight server-side
        if sets_data:
            set_weights = [float(s["weight"]) for s in sets_data if "weight" in s]
            if set_weights:
                weight = round(sum(set_weights) / len(set_weights), 1)

        reps_list = parse_reps(reps_str)
        reps      = ",".join(map(str, reps_list))
        status    = progression_status(reps, exercise)
        # RPE-based autoregulation: use last history RPE if not provided in request
        if rpe is None:
            last_entry = weights.get(exercise, {}).get("history", [{}])[0] if weights.get(exercise, {}).get("history") else {}
            rpe = last_entry.get("rpe")
            if rpe is not None:
                rpe = float(rpe)
        new_w, action = suggest_next_weight(exercise, weight, reps, rpe)
        increase  = action == "increase"
        onerm     = estimate_1rm(weight, reps)

        # PR detection: compare new 1RM against historical 1RMs (snapshot before insert)
        prev_1rms = [e.get("1rm", 0) for e in existing_history]
        is_pr = bool(onerm > 0 and (not prev_1rms or onerm > max(prev_1rms)))

        # Resolve volume weight for bodyweight exercises
        if equipment_type == "bodyweight" and weight == 0:
            import db as _db
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

        if exercise not in weights:
            weights[exercise] = {"history": []}

        weights[exercise].setdefault("history", []).insert(0, history_entry)
        weights[exercise]["history"] = weights[exercise]["history"][:20]
        # Don't overwrite current_weight with 0 for bodyweight-only — keep last lest value
        if not (equipment_type == "bodyweight" and weight == 0):
            weights[exercise]["current_weight"] = round(new_w, 1)
        weights[exercise]["last_reps"] = reps
        weights[exercise]["last_logged"]    = datetime.now().strftime("%Y-%m-%d %H:%M")

        # Ensure session stub exists so upsert_exercise_log can write the FK
        import db as _db
        if is_second:
            _db.get_or_create_workout_session_second(_today_mtl())
        else:
            _db.get_or_create_workout_session(_today_mtl())
        save_weights(weights)
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
        return jsonify({"error": str(e)}), 500


@app.route("/api/session/edit", methods=["POST"])
def api_session_edit():
    """Edit an existing session: RPE, comment, and/or individual exercise weight/reps."""
    try:
        data    = request.get_json()
        date    = data.get("date")
        if not date:
            return jsonify({"error": "date manquante"}), 400

        # Update sessions store (RPE / comment)
        sessions = load_sessions()
        if date not in sessions:
            sessions[date] = {}
        if "rpe" in data:
            sessions[date]["rpe"] = data["rpe"]
        if "comment" in data:
            sessions[date]["comment"] = data["comment"]
        from sessions import save_sessions
        save_sessions(sessions)

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
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/session/delete", methods=["POST"])
def api_session_delete():
    """Delete an entire session (removes from sessions store + weights history)."""
    try:
        data = request.get_json()
        date = data.get("date")
        if not date:
            return jsonify({"error": "date manquante"}), 400

        # Delete from relational layer (cascades to exercise_logs via FK)
        import db as _db
        _db.delete_session_exercise_logs(date)
        _db.delete_workout_session(date)

        # After relational delete, reload weights (history already excludes the deleted date)
        # and sync current_weight/last_reps to reflect the new most-recent entry
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
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/update_session", methods=["POST"])
def api_update_session():
    """Patch RPE and/or comment on an existing workout session."""
    try:
        data = request.get_json() or {}
        date = data.get("date")
        if not date:
            return jsonify({"error": "date required"}), 400
        patch = {}
        if "rpe" in data:     patch["rpe"] = data["rpe"]
        if "comment" in data: patch["comment"] = data["comment"]
        import db as _db
        ok = _db.update_workout_session(date, patch)
        return jsonify({"success": ok})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/log_session", methods=["POST"])
def api_log_session():
    try:
        data           = request.get_json()
        # Utilise la date locale du client si fournie (évite le décalage UTC/EST)
        today          = data.get("date") or _today_mtl()
        rpe            = data.get("rpe")
        comment        = data.get("comment", "")
        exos           = data.get("exos", [])
        blocks         = data.get("blocks")
        second_session = data.get("second_session", False)
        duration_min   = data.get("duration_min")
        energy_pre     = data.get("energy_pre")

        import db as _db
        if not second_session:
            existing = _db.get_workout_session(today)
            if existing and existing.get("completed"):
                return jsonify({"error": "already_logged"}), 409

        # Compute session volume stats from today's logged exercises
        weights   = load_weights()
        vol_stats = _calc_session_volume_legacy(exos, weights, today)

        if second_session:
            log_second_session(today, rpe, comment, exos, duration_min, energy_pre,
                               blocks=blocks, **vol_stats)
        else:
            log_session(today, rpe, comment, exos, duration_min, energy_pre,
                        blocks=blocks, **vol_stats)
            _db.complete_workout_session(today)

        return jsonify({"success": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/log_hiit", methods=["POST"])
def api_log_hiit():
    import db as _db
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


@app.route("/api/delete_hiit", methods=["POST"])
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


@app.route("/api/hiit/edit", methods=["POST"])
def api_hiit_edit():
    try:
        import db as _db
        data     = request.get_json()
        idx      = data.get("index")
        hiit_log = _db.get_hiit_logs() or []

        if idx is None or not (0 <= idx < len(hiit_log)):
            return jsonify({"error": "Index introuvable"}), 400

        entry = hiit_log[idx]
        patch = {f: data[f] for f in ("rpe", "feeling", "comment", "rounds_completes",
                                       "vitesse_max", "vitesse_croisiere", "duration")
                 if f in data}
        _db.update_hiit_log(entry.get("id"), patch)
        return jsonify({"success": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/save_exercise", methods=["POST"])
def api_save_exercise():
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
    }

    if original_name and original_name != name:
        # Rename: targeted rename in exercises table + update programme
        rename_inventory_exercise(original_name, name, entry)
        add_exercise(name, entry)
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


@app.route("/api/delete_exercise", methods=["POST"])
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


@app.route("/api/delete_exercise_log", methods=["POST"])
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

    # Delete from KV
    weights = load_weights()
    if exercise in weights:
        history = weights[exercise].get("history", [])
        weights[exercise]["history"] = [e for e in history if e.get("date") != date]
        if weights[exercise]["history"]:
            weights[exercise]["current_weight"] = weights[exercise]["history"][0].get("weight", 0)
        save_weights(weights)

    return jsonify({"success": True})


@app.route("/api/programme", methods=["POST"])
def api_programme():
    import db as _db
    data    = request.json
    action  = data.get("action")
    jour    = data.get("jour")

    # ── Rename: must read all sessions to rename across all ──────────────────
    if action == "rename":
        program = _db.get_full_program()
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
            save_program(modified)
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
    session_data = _db.get_full_program()
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
            exercises.pop(data.get("exercise", ""), None)

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
    save_program({jour: session_def})
    return jsonify({"success": True})


@app.route("/api/update_profile", methods=["POST"])
def api_update_profile():
    existing = load_user_profile()
    existing.update({k: v for k, v in request.json.items() if v is not None})
    ok = save_user_profile(existing)
    if ok:
        return jsonify({"success": True})
    return jsonify({"success": False, "error": "Erreur sauvegarde Supabase"}), 500


@app.route("/api/update_profile_photo", methods=["POST"])
def api_update_profile_photo():
    # Reçoit du JSON avec photo_b64 déjà compressée/redimensionnée côté client
    data = request.get_json(silent=True) or {}
    data_url = data.get("photo_b64", "")

    if not data_url or not data_url.startswith("data:image"):
        return jsonify({"success": False, "error": "Image invalide"}), 400

    # Vérifie la taille (~600KB max en base64 = ~450KB image)
    if len(data_url) > 800_000:
        return jsonify({"success": False, "error": "Image trop lourde après compression"}), 400

    profile = load_user_profile()
    profile["photo_b64"] = data_url
    profile.pop("photo", None)
    ok = save_user_profile(profile)

    if ok:
        return jsonify({"success": True})
    return jsonify({"success": False, "error": "Erreur sauvegarde"}), 500


@app.route("/api/set_goal", methods=["POST"])
def api_set_goal():
    data     = request.json
    exercise = data.get("exercise")
    weight   = float(data.get("weight", 0))
    deadline = data.get("deadline")
    note     = data.get("note", "")

    if not exercise or not weight:
        return jsonify({"error": "Données manquantes"}), 400

    set_goal(exercise, weight, deadline, note)
    return jsonify({"success": True})


@app.route("/api/body_weight", methods=["POST"])
def api_body_weight():
    try:
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
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/body_weight/update", methods=["POST"])
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
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/body_weight/delete", methods=["POST"])
def api_delete_body_weight():
    try:
        import db as _db
        data  = request.get_json()
        ok = _db.delete_body_weight(data.get("date", ""))
        if not ok:
            return jsonify({"success": False, "error": "Entrée introuvable"}), 404
        return jsonify({"success": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/ai/propose", methods=["POST"])
def api_ai_propose():
    """Claude returns structured program modification proposals as JSON."""
    if not _ai_rate_check():
        return jsonify({"error": "Trop de requêtes — réessaie dans quelques minutes."}), 429
    import os, json as _json
    import anthropic as _anthropic
    api_key = os.environ.get("ANTHROPIC_API_KEY", "")
    if not api_key:
        return jsonify({"error": "ANTHROPIC_API_KEY manquant"}), 500
    try:
        data    = request.get_json()
        context = data.get("context", "")
        if not context:
            return jsonify({"error": "Contexte manquant"}), 400

        logger.info("Claude propose — tokens_remaining=%d context_len=%d", _AI_TOKENS, len(context))
        client  = _anthropic.Anthropic(api_key=api_key)
        message = client.messages.create(
            model="claude-sonnet-4-6",
            max_tokens=1500,
            system=(
                "Tu es un coach expert en programmation musculaire. "
                "Tu reçois des données d'entraînement et tu proposes des modifications concrètes au programme. "
                "Tu DOIS répondre UNIQUEMENT avec un tableau JSON valide, sans texte avant ni après. "
                "Format exact de chaque proposition:\n"
                '{"jour": "Nom du jour/session", "action": "add|remove|replace|scheme", '
                '"exercise": "nom (pour add)", "old_exercise": "nom (pour remove/replace)", '
                '"new_exercise": "nom (pour replace)", "scheme": "ex: 3x8-10", '
                '"reason": "explication courte en français"}\n'
                "Propose 3 à 6 modifications pertinentes basées sur les données. "
                "Ne compare jamais le volume brut entre muscles — utilise les sets."
            ),
            messages=[{"role": "user", "content": context}]
        )
        raw = message.content[0].text.strip()
        # Extract JSON array from response
        start = raw.find('[')
        end   = raw.rfind(']') + 1
        if start == -1 or end == 0:
            return jsonify({"error": "Réponse non structurée", "raw": raw}), 500
        proposals = _json.loads(raw[start:end])
        return jsonify({"proposals": proposals})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/ai/coach", methods=["POST"])
def api_ai_coach():
    if not _ai_rate_check():
        return jsonify({"error": "Trop de requêtes — réessaie dans quelques minutes."}), 429
    import os
    import anthropic as _anthropic
    api_key = os.environ.get("ANTHROPIC_API_KEY", "")
    if not api_key:
        return jsonify({"error": "ANTHROPIC_API_KEY manquant dans .env"}), 500
    try:
        data   = request.get_json()
        prompt = data.get("prompt", "")
        if not prompt:
            return jsonify({"error": "Prompt vide"}), 400

        mode   = data.get("mode", "custom")
        logger.info("Claude coach — tokens_remaining=%d prompt_len=%d mode=%s", _AI_TOKENS, len(prompt), mode)
        client = _anthropic.Anthropic(api_key=api_key)
        message = client.messages.create(
            model="claude-sonnet-4-6",
            max_tokens=800,
            system=(
                "Tu es un coach sportif expert en musculation, HIIT et périodisation de l'entraînement. "
                "Tu reçois des données réelles d'entraînement et tu les analyses avec rigueur. "
                "Règles importantes:\n"
                "- Ne compare JAMAIS le volume brut (lbs×reps) entre groupes musculaires — les jambes "
                "utilisent toujours des charges plus lourdes, ça ne veut pas dire qu'elles sont sur-entraînées.\n"
                "- Utilise le NOMBRE DE SETS par groupe musculaire comme indicateur de volume réel.\n"
                "- Pour les suggestions de programme, sois précis: nomme les exercices à ajouter/retirer/modifier "
                "avec les schemes (ex: 3x8-10, 4x5-7).\n"
                "- Pour le HIIT, analyse la fréquence, les types et la récupération entre sessions.\n"
                "- Réponds toujours en français, de façon directe et actionnable. Max 7 phrases."
            ),
            messages=[{"role": "user", "content": prompt}]
        )
        response_text = message.content[0].text

        # Persist exchange in coach_history (keep last 50)
        history = get_json("coach_history", [])
        history.insert(0, {
            "timestamp": _now_mtl().strftime("%Y-%m-%d %H:%M"),
            "date":      _today_mtl(),
            "mode":      mode,
            "response":  response_text,
        })
        set_json("coach_history", history[:50])

        return jsonify({"response": response_text})
    except _anthropic.AuthenticationError:
        return jsonify({"error": "Clé ANTHROPIC_API_KEY invalide"}), 500
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/ai/coach/history")
def api_ai_coach_history():
    """Returns the last N coach exchanges."""
    limit = min(int(request.args.get("limit", 20)), 50)
    history = get_json("coach_history", [])
    return jsonify({"history": history[:limit]})


@app.route("/api/sync_status")
def api_sync_status():
    """Returns count of dirty (unsynced) entries in the local SQLite cache."""
    from db import _sqlite_all_dirty
    dirty = _sqlite_all_dirty()
    return jsonify({"dirty_count": len(dirty), "dirty_keys": list(dirty.keys())})


@app.route("/api/deload_status")
def api_deload_status():
    """Returns deload analysis: stagnation, RPE fatigue, recommendation."""
    weights = load_weights()
    rapport = analyser_deload(weights)
    logger.info(
        "Deload status — recommande=%s stagnants=%d rpe_moyen=%s",
        rapport["recommande"],
        len(rapport["stagnants"]),
        rapport["fatigue_rpe"].get("rpe_moyen"),
    )
    return jsonify(rapport)


@app.route("/api/weights")
def api_weights():
    return jsonify(load_weights())


@app.route("/api/inventory")
def api_inventory():
    return jsonify(load_inventory())


@app.route("/api/sessions")
def api_sessions():
    return jsonify(load_sessions())


@app.route("/api/deload")
def api_deload():
    return jsonify(analyser_deload(load_weights()))


@app.route("/api/acwr")
def api_acwr():
    from acwr import calc_acwr
    return jsonify(calc_acwr())


@app.route("/api/coach/morning_brief")
def api_morning_brief():
    from morning_brief import get_morning_brief
    return jsonify(get_morning_brief())


@app.route("/api/insights/correlations")
def api_insights_correlations():
    try:
        days = int(request.args.get("days", 60))
    except ValueError:
        days = 60
    from correlations import get_correlations
    return jsonify(get_correlations(days))


@app.route("/sw.js")
def service_worker():
    # Version = SHA git sur Vercel, timestamp horaire en local
    # Change automatiquement à chaque déploiement → nouveau CACHE_NAME → SW update → reload
    build_version = (
        os.getenv('VERCEL_GIT_COMMIT_SHA', '')[:8]
        or datetime.now().strftime('%Y%m%d%H')
    )
    with open(os.path.join(BASE_DIR, "static", "sw.js")) as f:
        content = f.read()
    # Remplace le CACHE_NAME hardcodé par la version du build
    import re
    content = re.sub(
        r"(const CACHE_NAME\s*=\s*')[^']*(')",
        f"\\g<1>trainingos-{build_version}\\2",
        content
    )
    from flask import make_response
    resp = make_response(content, 200)
    resp.headers['Content-Type']  = 'application/javascript'
    resp.headers['Cache-Control'] = 'no-cache, no-store, must-revalidate'
    resp.headers['Pragma']        = 'no-cache'
    resp.headers['Expires']       = '0'
    return resp


@app.route("/api/dashboard")
def api_dashboard():
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

    import db as _db
    _today_session = _db.get_workout_session(today_date)
    already_logged_today = bool(_today_session and _today_session.get("completed", False))

    has_partial_logs = False
    if not already_logged_today:
        try:
            logged_names = {e["exercise_name"] for e in _db.get_session_exercise_logs(today_date)}
            program_names = set(get_strength_exercises(full_program.get(today_str, {})).keys())
            has_partial_logs = bool(logged_names & program_names)
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
    # Include if completed=True (new sessions) OR rpe is not None (historical sessions
    # logged before the completed field existed). Stubs have completed=False AND rpe=None.
    merged_sessions = {
        date: entry
        for date, entry in sessions.items()
        if entry.get("completed") or entry.get("rpe") is not None
    }
    for entry in hiit_log:
        d = entry.get("date")
        if d and d not in merged_sessions:
            merged_sessions[d] = {"session_type": entry.get("session_type", "HIIT")}

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
        "profile":             profile,
    })


# ── JSON GET endpoints ───────────────────────────────────────

@app.route("/api/seance_data")
def api_seance_data():
    weights      = load_weights()
    sessions     = load_sessions()
    full_program = load_program()
    hiit_log     = load_hiit_log_local()
    inventory    = load_inventory()
    today_str  = get_today()
    today_date = get_today_date()
    schedule   = get_week_schedule()
    suggestions = get_suggested_weights_for_today(weights, full_program)

    already_logged = today_date in sessions

    # Aplatit la structure bloc → {exercice: scheme} pour le client iOS
    flat_program = {
        seance: get_strength_exercises(session_def)
        for seance, session_def in full_program.items()
    }

    inv = inventory if isinstance(inventory, dict) else {}
    inventory_types = {name: info.get("type", "machine") for name, info in inv.items()}
    # Ordered list of exercise names per session (preserves user-defined order)
    exercise_order  = {seance: list(exs.keys()) for seance, exs in flat_program.items()}

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
        "exercise_order": exercise_order,
    })


@app.route("/api/seance_soir_data")
def api_seance_soir_data():
    import db as _db
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
    inventory_types = {name: info.get("type", "machine") for name, info in inv.items()}
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
        "exercise_order": exercise_order,
    })


@app.route("/api/evening_schedule", methods=["GET", "POST"])
def api_evening_schedule():
    import db as _db
    if request.method == "POST":
        schedule = request.get_json() or {}
        success = _db.set_evening_week_schedule(schedule)
        return jsonify({"success": success})
    return jsonify(_db.get_evening_week_schedule())


def _calc_muscle_stats(sessions: dict, weights: dict, inventory: dict) -> dict:
    """Compute per-muscle volume from weights history × inventory muscles.

    sessions.exos is unreliable (often empty in relational layer), so we
    derive exercise dates directly from weights history entries.

    Returns {muscle: {volume, sessions, last_date}}.
    """
    muscle_data: dict = {}
    # Track which muscles were hit per date to avoid double-counting sessions
    date_muscles_seen: dict = {}

    for ex_name, ex_data in weights.items():
        muscles = (inventory.get(ex_name) or {}).get("muscles") or []
        if not muscles:
            continue
        history = ex_data.get("history") or []
        for entry in history:
            date      = entry.get("date", "")
            if not date:
                continue
            w         = float(entry.get("weight") or 0)
            reps_list = parse_reps(entry.get("reps") or "")
            vol       = round(w * sum(reps_list), 2) if w > 0 and reps_list else 0.0

            for muscle in muscles:
                if muscle not in muscle_data:
                    muscle_data[muscle] = {"volume": 0.0, "sessions": 0, "last_date": ""}
                muscle_data[muscle]["volume"] = round(muscle_data[muscle]["volume"] + vol, 2)
                # Count one session per (muscle, date) pair
                key = (muscle, date)
                if key not in date_muscles_seen:
                    date_muscles_seen[key] = True
                    muscle_data[muscle]["sessions"] += 1
                if date > muscle_data[muscle]["last_date"]:
                    muscle_data[muscle]["last_date"] = date
    return muscle_data


@app.route("/api/stats_data")
def api_stats_data():
    weights      = load_weights()
    import db as _db
    all_sessions = _db.get_workout_sessions(limit=500)
    sessions = {
        s["date"]: s
        for s in all_sessions
        if isinstance(s, dict) and (s.get("completed") or s.get("rpe") is not None)
    }
    hiit_log     = load_hiit_log_local()
    body_weight  = load_body_weight()
    recovery_log = _db.get_recovery_logs() or []
    nutr_settings = load_nutrition_settings()
    nutr_entries  = get_recent_days(7)
    inventory       = load_inventory() or {}
    muscle_stats    = _calc_muscle_stats(sessions, weights, inventory)
    inventory_types = {name: info.get("type", "machine") for name, info in inventory.items()}
    return jsonify({
        "weights":          weights,
        "sessions":         sessions,
        "hiit_log":         hiit_log,
        "body_weight":      body_weight,
        "recovery_log":     recovery_log,
        "nutrition_target": nutr_settings,
        "nutrition_days":   nutr_entries,
        "week":             get_current_week(),
        "muscle_stats":     muscle_stats,
        "inventory_types":  inventory_types,
    })


@app.route("/api/objectifs_data")
def api_objectifs_data():
    weights = load_weights()
    goals   = load_goals()
    goals_progress = {}
    for ex, goal in goals.items():
        current = weights.get(ex, {}).get("current_weight", 0) or 0
        goals_progress[ex] = {
            "current":  current,
            "goal":     goal["goal_weight"],
            "bar":      get_progress_bar(current, goal["goal_weight"]),
            "achieved": goal.get("achieved", False),
            "deadline": goal.get("deadline", ""),
            "note":     goal.get("note", ""),
        }
    return jsonify({"goals": goals_progress})


@app.route("/api/profil_data")
def api_profil_data():
    profile     = load_user_profile()
    body_weight = load_body_weight()
    tendance    = get_tendance(body_weight)
    return jsonify({
        "profile":     profile,
        "body_weight": body_weight,
        "tendance":    tendance,
    })


@app.route("/api/nutrition_data")
def api_nutrition_data():
    settings = load_nutrition_settings()
    entries  = get_today_entries()
    totals   = get_today_totals()
    history  = get_recent_days(7)
    return jsonify({
        "settings": settings,
        "entries":  entries,
        "totals":   totals,
        "history":  history,
    })


@app.route("/api/hiit_data")
def api_hiit_data():
    hiit_log = load_hiit_log_local()
    total    = len(hiit_log)
    avg_rpe  = round(sum(e.get("rpe", 0) for e in hiit_log) / total, 1) if total else 0
    return jsonify({
        "hiit_log": hiit_log,
        "total":    total,
        "avg_rpe":  avg_rpe,
    })


@app.route("/api/notes_data")
def api_notes_data():
    sessions = load_sessions()
    total    = len(sessions)
    rpes     = [s.get("rpe") for s in sessions.values() if s.get("rpe")]
    avg_rpe  = round(sum(rpes) / len(rpes), 1) if rpes else 0
    return jsonify({
        "sessions": sessions,
        "total":    total,
        "avg_rpe":  avg_rpe,
    })


@app.route("/api/programme_data")
def api_programme_data():
    full_program = load_program()
    schedule     = get_week_schedule()
    inventory    = load_inventory()
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
    inventory_types   = {name: info.get("type", "machine")         for name, info in inv.items()}
    inventory_schemes = {name: info.get("default_scheme", "3x8-12") for name, info in inv.items()}
    exercise_order    = {seance: list(exs.keys()) for seance, exs in flat_program.items()}
    return jsonify({
        "full_program":      flat_program,
        "schedule":          schedule,
        "inventory":         list(inv.keys()),
        "inventory_types":   inventory_types,
        "inventory_schemes": inventory_schemes,
        "exercise_order":    exercise_order,
    })


@app.route("/api/inventaire_data")
def api_inventaire_data():
    import db as _db
    inventory = load_inventory()
    if inventory is None:
        return jsonify({"inventory": {}})
    return jsonify({"inventory": inventory})


@app.route("/api/historique_data")
def api_historique_data():
    import db as _db

    sessions = _db.get_workout_sessions(limit=500)
    all_history = _db.get_all_exercise_history()
    hiit_log = _db.get_hiit_logs(limit=100)

    # Build {date: [exo, ...]} from all exercise history
    ex_by_date = {}
    for ex_name, history in all_history.items():
        for entry in history:
            d = entry.get("date")
            if not d:
                continue
            ex_by_date.setdefault(d, []).append({
                "exercise": ex_name,
                "weight":   entry.get("weight", 0),
                "reps":     entry.get("reps", ""),
            })

    session_list = []
    for s in sessions:
        d = s.get("date")
        if not d:
            continue
        session_list.append({
            "date":    d,
            "rpe":     s.get("rpe"),
            "comment": s.get("comment", ""),
            "exos":    ex_by_date.get(d, []),
        })

    # Remove duplicate dates (morning + evening sessions on same day)
    seen = set()
    deduped = []
    for s in session_list:
        if s["date"] not in seen:
            seen.add(s["date"])
            deduped.append(s)

    return jsonify({
        "session_list": deduped[:60],
        "hiit_list":    hiit_log[:30],
    })


@app.route("/api/bodycomp_data")
def api_bodycomp_data():
    body_weight = load_body_weight()
    profile     = load_user_profile()
    tendance    = get_tendance(body_weight)
    return jsonify({
        "body_weight": body_weight,
        "profile":     profile,
        "tendance":    tendance,
    })


# ── Cardio ───────────────────────────────────────────────────

@app.route("/api/cardio_data")
def api_cardio_data():
    import db as _db
    log = _db.get_cardio_logs() or []
    return jsonify({"cardio_log": sorted(log, key=lambda x: x.get("date", ""), reverse=True)})

@app.route("/api/log_cardio", methods=["POST"])
def api_log_cardio():
    import db as _db
    data = request.get_json()
    entry = {
        "date":         data.get("date", date.today().isoformat()),
        "type":         data.get("type", "course"),
        "duration_min": data.get("duration_min"),
        "distance_km":  data.get("distance_km"),
        "avg_pace":     data.get("avg_pace"),
        "avg_hr":       data.get("avg_hr"),
        "cadence":      data.get("cadence"),
        "calories":     data.get("calories"),
        "rpe":          data.get("rpe"),
        "notes":        data.get("notes", ""),
    }
    _db.insert_cardio_log(entry)
    return jsonify({"ok": True})

@app.route("/api/delete_cardio", methods=["POST"])
def api_delete_cardio():
    import db as _db
    data = request.get_json()
    _db.delete_cardio_log(data.get("date", ""), data.get("type", ""))
    return jsonify({"ok": True})


# ── Récupération ──────────────────────────────────────────────

@app.route("/api/recovery_data")
def api_recovery_data():
    import db as _db
    log = _db.get_recovery_logs() or []
    return jsonify({"recovery_log": sorted(log, key=lambda x: x.get("date", ""), reverse=True)})

@app.route("/api/log_recovery", methods=["POST"])
def api_log_recovery():
    import db as _db
    data  = request.get_json()
    entry = {
        "date":          data.get("date", date.today().isoformat()),
        "sleep_hours":   data.get("sleep_hours"),
        "sleep_quality": data.get("sleep_quality"),
        "resting_hr":    data.get("resting_hr"),
        "hrv":           data.get("hrv"),
        "steps":         data.get("steps"),
        "soreness":      data.get("soreness"),
        "notes":         data.get("notes", ""),
    }
    _db.upsert_recovery_log(entry)
    return jsonify({"ok": True})

@app.route("/api/delete_recovery", methods=["POST"])
def api_delete_recovery():
    import db as _db
    data = request.get_json()
    _db.delete_recovery_log(data.get("date", ""))
    return jsonify({"ok": True})


# ── Health Dashboard ─────────────────────────────────────────

from health_data import get_daily_health_summary, get_weekly_health_summary

@app.route("/api/health/daily_summary")
def api_health_daily_summary():
    """
    Résumé santé unifié pour un jour donné.
    ?date=YYYY-MM-DD  (défaut : aujourd'hui)
    """
    target_date = request.args.get("date")
    return jsonify(get_daily_health_summary(target_date))


@app.route("/api/health/weekly_summary")
def api_health_weekly_summary():
    """
    Résumés des N derniers jours (du plus récent au plus ancien).
    ?days=7  (défaut : 7)
    """
    try:
        days = int(request.args.get("days", 7))
        days = max(1, min(days, 90))
    except ValueError:
        days = 7
    return jsonify(get_weekly_health_summary(days))


# ── Life Stress Engine ────────────────────────────────────────

from life_stress_engine import get_life_stress_score, get_recent_life_stress_trend, refresh_life_stress_score

@app.route("/api/life_stress/score")
def api_life_stress_score():
    """
    Life Stress Score pour un jour donné (0 = surmenage, 100 = récupération optimale).
    ?date=YYYY-MM-DD  (défaut : aujourd'hui)
    ?refresh=true     (force le recalcul)
    """
    target_date = request.args.get("date")
    force_refresh = request.args.get("refresh", "false").lower() == "true"
    if force_refresh:
        return jsonify(refresh_life_stress_score(target_date))
    return jsonify(get_life_stress_score(target_date))


@app.route("/api/life_stress/trend")
def api_life_stress_trend():
    """
    Tendance LSS sur les N derniers jours (du plus récent au plus ancien).
    ?days=7  (défaut : 7, max : 90)
    """
    try:
        days = int(request.args.get("days", 7))
        days = max(1, min(days, 90))
    except ValueError:
        days = 7
    return jsonify(get_recent_life_stress_trend(days))


# ── PSS — Perceived Stress Scale ─────────────────────────────

from pss import (
    save_pss_record, get_history as pss_get_history,
    check_due as pss_check_due, get_questions
)

@app.route("/api/pss/questions")
def api_pss_questions():
    """
    Retourne les questions PSS à afficher.
    ?short=true  → PSS-4 (4 questions, défaut : false)
    """
    is_short = request.args.get("short", "false").lower() == "true"
    return jsonify(get_questions(is_short))


@app.route("/api/pss/submit", methods=["POST"])
def api_pss_submit():
    """
    Soumet un questionnaire PSS et persiste le résultat.

    Body JSON :
    {
      "responses":       [int × 10 ou × 4],
      "is_short":        bool (défaut false),
      "notes":           str (optionnel),
      "triggers":        [str] (optionnel, max 2),
      "trigger_ratings": { "travail": 3 } (optionnel)
    }
    """
    data = request.get_json(silent=True) or {}
    responses = data.get("responses")
    if not responses:
        return jsonify({"error": "responses requis"}), 400

    try:
        record = save_pss_record(
            responses       = [int(r) for r in responses],
            is_short        = bool(data.get("is_short", False)),
            notes           = data.get("notes"),
            triggers        = data.get("triggers"),
            trigger_ratings = data.get("trigger_ratings"),
        )
        return jsonify(record), 201
    except ValueError as e:
        return jsonify({"error": str(e)}), 422
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/pss/history")
def api_pss_history():
    """
    Historique des enregistrements PSS.
    ?type=full|short  (défaut : tous)
    ?limit=20
    """
    pss_type = request.args.get("type")
    try:
        limit = int(request.args.get("limit", 20))
    except ValueError:
        limit = 20
    return jsonify(pss_get_history(pss_type, limit))


@app.route("/api/pss/check_due")
def api_pss_check_due():
    """
    Vérifie si un test PSS est dû.
    ?type=full|short  (défaut : full)
    """
    pss_type = request.args.get("type", "full")
    return jsonify(pss_check_due(pss_type))


@app.route("/api/pss/delete", methods=["POST"])
def api_pss_delete():
    """Supprime un enregistrement PSS par id. Body JSON: {"id": "..."}"""
    from db import get_json, set_json
    data = request.get_json() or {}
    record_id = data.get("id")
    if not record_id:
        return jsonify({"error": "id requis"}), 400
    records = get_json("pss_records", [])
    before = len(records)
    records = [r for r in records if r.get("id") != record_id]
    if len(records) == before:
        return jsonify({"error": "introuvable"}), 404
    set_json("pss_records", records)
    return jsonify({"success": True})


# ── Sommeil ──────────────────────────────────────────────────

from sleep import (
    save_sleep_entry, get_history as sleep_get_history,
    get_today as sleep_get_today, get_stats as sleep_get_stats,
    delete_entry as sleep_delete_entry
)

@app.route("/api/sleep/log", methods=["POST"])
def api_sleep_log():
    data = request.get_json() or {}
    bedtime   = data.get("bedtime")
    wake_time = data.get("wake_time")
    quality   = data.get("quality")
    if not bedtime or not wake_time or quality is None:
        return jsonify({"error": "bedtime, wake_time et quality requis"}), 400
    try:
        entry = save_sleep_entry(
            bedtime   = bedtime,
            wake_time = wake_time,
            quality   = int(quality),
            notes     = data.get("notes"),
        )
        return jsonify(entry)
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route("/api/sleep/history")
def api_sleep_history():
    try:
        limit  = int(request.args.get("limit", 20))
        offset = int(request.args.get("offset", 0))
    except ValueError:
        limit, offset = 20, 0
    return jsonify(sleep_get_history(limit, offset))

@app.route("/api/sleep/today")
def api_sleep_today():
    entry = sleep_get_today()
    return jsonify(entry if entry else {})

@app.route("/api/sleep/stats")
def api_sleep_stats():
    return jsonify(sleep_get_stats())

@app.route("/api/sleep/delete", methods=["POST"])
def api_sleep_delete():
    data = request.get_json() or {}
    record_id = data.get("id")
    if not record_id:
        return jsonify({"error": "id requis"}), 400
    if sleep_delete_entry(record_id):
        return jsonify({"success": True})
    return jsonify({"error": "introuvable"}), 404


# ── Santé Mentale ────────────────────────────────────────────

from mood import (
    EMOTIONS, save_mood_entry, get_history as mood_get_history,
    get_today_entry as mood_today_entry, check_due as mood_check_due,
    generate_insights as mood_insights,
)
from journal import (
    get_today_prompt, save_entry as journal_save,
    get_entries, search_entries, get_entry_count,
)
from breathwork import (
    TECHNIQUES, log_session as bw_log,
    get_history as bw_history, get_stats as bw_stats_fn,
)
from self_care import (
    get_habits, add_habit, delete_habit,
    log_today as sc_log, get_today_status, get_streaks,
)
from mental_health_dashboard import get_summary as mh_summary

# — Mood —

@app.route("/api/mood/emotions")
def api_mood_emotions():
    return jsonify(EMOTIONS)


@app.route("/api/mood/log", methods=["POST"])
def api_mood_log():
    data = request.get_json(silent=True) or {}
    score = data.get("score")
    if score is None:
        return jsonify({"error": "score requis (1-10)"}), 400
    try:
        entry = save_mood_entry(
            score    = int(score),
            emotions = data.get("emotions", []),
            notes    = data.get("notes"),
            triggers = data.get("triggers"),
        )
        return jsonify(entry), 201
    except ValueError as e:
        return jsonify({"error": str(e)}), 422


@app.route("/api/mood/history")
def api_mood_history():
    try:
        days   = int(request.args.get("days", 90))
        limit  = int(request.args.get("limit", 20))
        offset = int(request.args.get("offset", 0))
    except ValueError:
        days, limit, offset = 90, 20, 0
    return jsonify(mood_get_history(days, limit, offset))


@app.route("/api/mood/today")
def api_mood_today():
    entry = mood_today_entry()
    return jsonify(entry) if entry else jsonify(None)


@app.route("/api/mood/check_due")
def api_mood_check_due():
    return jsonify(mood_check_due())


@app.route("/api/mood/insights")
def api_mood_insights():
    try:
        days = int(request.args.get("days", 30))
    except ValueError:
        days = 30
    return jsonify(mood_insights(days))


# — Journal —

@app.route("/api/journal/today_prompt")
def api_journal_today_prompt():
    return jsonify({"prompt": get_today_prompt()})


@app.route("/api/journal/save", methods=["POST"])
def api_journal_save():
    data = request.get_json(silent=True) or {}
    prompt  = data.get("prompt", "")
    content = data.get("content", "")
    try:
        entry = journal_save(prompt, content)
        return jsonify(entry), 201
    except ValueError as e:
        return jsonify({"error": str(e)}), 422


@app.route("/api/journal/entries")
def api_journal_entries():
    try:
        limit  = int(request.args.get("limit", 20))
        offset = int(request.args.get("offset", 0))
    except ValueError:
        limit, offset = 20, 0
    return jsonify(get_entries(limit, offset))


@app.route("/api/journal/search")
def api_journal_search():
    q = request.args.get("q", "")
    return jsonify(search_entries(q))


# — Breathwork —

@app.route("/api/breathwork/techniques")
def api_breathwork_techniques():
    return jsonify(TECHNIQUES)


@app.route("/api/breathwork/log", methods=["POST"])
def api_breathwork_log():
    data = request.get_json(silent=True) or {}
    technique_id = data.get("technique_id")
    if not technique_id:
        return jsonify({"error": "technique_id requis"}), 400
    try:
        session = bw_log(
            technique_id = technique_id,
            duration_sec = int(data.get("duration_sec", 0)),
            cycles       = int(data.get("cycles", 0)),
        )
        return jsonify(session), 201
    except ValueError as e:
        return jsonify({"error": str(e)}), 422


@app.route("/api/breathwork/history")
def api_breathwork_history():
    try:
        days = int(request.args.get("days", 30))
    except ValueError:
        days = 30
    return jsonify(bw_history(days))


@app.route("/api/breathwork/stats")
def api_breathwork_stats():
    try:
        days = int(request.args.get("days", 7))
    except ValueError:
        days = 7
    return jsonify(bw_stats_fn(days))


# — Self-Care Habits —

@app.route("/api/self_care/habits")
def api_self_care_habits():
    return jsonify(get_habits())


@app.route("/api/self_care/habits", methods=["POST"])
def api_self_care_habits_add():
    data = request.get_json(silent=True) or {}
    name = data.get("name", "").strip()
    if not name:
        return jsonify({"error": "name requis"}), 400
    habit = add_habit(
        name     = name,
        icon     = data.get("icon", "star.fill"),
        category = data.get("category", "mental"),
    )
    return jsonify(habit), 201


@app.route("/api/self_care/habits/<habit_id>", methods=["DELETE"])
def api_self_care_habits_delete(habit_id: str):
    deleted = delete_habit(habit_id)
    if not deleted:
        return jsonify({"error": "Habitude introuvable"}), 404
    return jsonify({"deleted": habit_id})


@app.route("/api/self_care/log", methods=["POST"])
def api_self_care_log():
    data = request.get_json(silent=True) or {}
    habit_ids = data.get("habit_ids", [])
    return jsonify(sc_log(habit_ids))


@app.route("/api/self_care/today")
def api_self_care_today():
    return jsonify(get_today_status())


@app.route("/api/self_care/streaks")
def api_self_care_streaks():
    return jsonify(get_streaks())


# — Dashboard santé mentale —

@app.route("/api/mental_health/summary")
def api_mental_health_summary():
    try:
        days = int(request.args.get("days", 7))
    except ValueError:
        days = 7
    return jsonify(mh_summary(days))


# ── Lancement local ──────────────────────────────────────────

def find_free_port(start=5000, end=5100):
    for port in range(start, end):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            try:
                s.bind(("0.0.0.0", port))
                return port
            except OSError:
                continue
    raise RuntimeError("Aucun port libre")


if __name__ == "__main__":
    # PORT stocké dans l'env pour que le child du reloader utilise le même
    port = int(os.environ.setdefault("PORT", str(find_free_port())))
    url  = f"http://localhost:{port}"
    logger.info("TrainingOS → %s", url)
    # N'ouvre le navigateur que dans le processus principal (pas le child du reloader)
    if os.environ.get('WERKZEUG_RUN_MAIN') != 'true':
        Timer(1.0, lambda: webbrowser.open(url)).start()
    app.run(debug=True, use_reloader=True, host="0.0.0.0", port=port)