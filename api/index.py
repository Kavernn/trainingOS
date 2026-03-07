# api/index.py
from __future__ import annotations
import os, sys, json, socket, webbrowser
from threading import Timer
from datetime import datetime, date
from pathlib import Path

# Charge le .env pour le dev local (no-op sur Vercel)
try:
    from dotenv import load_dotenv
    load_dotenv(Path(__file__).parent.parent / '.env')
except ImportError:
    pass

# ✅ Ajoute /api au path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from flask import Flask, render_template, jsonify, request, redirect, url_for, send_from_directory
from werkzeug.utils import secure_filename

from planner      import get_today, get_week_schedule, get_suggested_weights_for_today, load_program, save_program
from hiit         import get_hiit_str
from log_workout  import load_weights, save_weights, log_single_exercise
from inventory    import load_inventory, save_inventory, calculate_plates
from sessions     import load_sessions, log_session
from user_profile import load_user_profile, save_user_profile
from progression  import estimate_1rm, should_increase, next_weight, parse_reps, progression_status
from deload       import analyser_deload, load_deload_state
from goals        import load_goals, check_goals_achieved, get_progress_bar, set_goal
from body_weight  import load_body_weight, log_body_weight, get_tendance
from db           import get_json, set_json
from db           import _ON_VERCEL

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
app.secret_key = os.getenv("SECRET_KEY", "trainingos-secret-change-in-prod")

UPLOAD_FOLDER      = os.path.join(BASE_DIR, "static", "uploads")
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'gif'}
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER
RAPID_API_KEY = os.getenv("X_RAPIDAPI_KEY")


# ── Helpers ─────────────────────────────────────────────────

def get_current_week() -> int:
    START_DATE = date(2026, 3, 3)
    delta      = date.today() - START_DATE
    return max(1, (delta.days // 7) + 1)


def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS


def load_hiit_log_local() -> list:
    return get_json("hiit_log", [])


def save_hiit_log_local(hiit_log: list):
    set_json("hiit_log", hiit_log)


# ── Pages HTML ───────────────────────────────────────────────

@app.route("/")
def index():
    weights      = load_weights()
    profile      = load_user_profile()
    suggestions  = get_suggested_weights_for_today(weights)
    goals        = load_goals()
    full_program = load_program()
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

    return render_template("index.html",
        today        = get_today(),
        week         = get_current_week(),
        profile      = profile,
        suggestions  = suggestions,
        goals        = goals_progress,
        schedule     = get_week_schedule(),
        full_program = full_program,
        deload_state = deload_state,
        sessions     = sessions,
        weights      = weights,
        hiit_log     = load_hiit_log_local(),
        now          = datetime.now().strftime("%A")
    )


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
    today_date = datetime.now().strftime("%Y-%m-%d")

    if today in ['HIIT 1', 'HIIT 2', 'Yoga', 'Recovery']:
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

            exercises.append({
                "name":    ex,
                "scheme":  scheme,
                "current": current,
                "display": display,
                "type":    ex_type,
                "plates":  plates_needed,
                "history": data.get("history", [])[:3],
                "1rm":     data.get("history", [{}])[0].get("1rm", 0) if data.get("history") else 0
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

    return render_template("seance_speciale.html",
                           session_type=session_type,
                           protocole=protocole,
                           week=week,
                           hiit_log=load_hiit_log_local(),
                           now=datetime.now().strftime("%Y-%m-%d")
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
        now  = datetime.now().strftime("%Y-%m-%d"),
        week = datetime.now().isocalendar()[1]
    )


@app.route("/xp")
def xp():
    return render_template("xp.html",
        weights   = load_weights(),
        sessions  = load_sessions(),
        hiit_log  = load_hiit_log_local(),
        inventory = load_inventory(),
        now       = datetime.now().strftime("%Y-%m-%d"),
        week      = datetime.now().isocalendar()[1]
    )


@app.route("/bodycomp")
def bodycomp():
    bw = load_body_weight()
    return render_template("bodycomp.html",
        body_weight = bw,
        profile     = load_user_profile(),
        tendance    = get_tendance(bw) if bw else "Pas de données",
        now         = datetime.now().strftime("%Y-%m-%d"),
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
        now       = datetime.now().strftime("%Y-%m-%d"),
        week      = datetime.now().isocalendar()[1]
    )


@app.route("/planificateur")
def planificateur():
    return render_template("planificateur.html",
        weights      = load_weights(),
        sessions     = load_sessions(),
        hiit_log     = load_hiit_log_local(),
        full_program = load_program(),
        now          = datetime.now().strftime("%Y-%m-%d"),
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
        now         = datetime.now().strftime("%Y-%m-%d")
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

        if not exercise or not reps_str:
            return jsonify({"error": "Données manquantes"}), 400

        weights   = load_weights()
        reps_list = parse_reps(reps_str)
        reps      = ",".join(map(str, reps_list))
        status    = progression_status(reps, exercise)
        increase  = should_increase(reps, exercise)
        new_w     = next_weight(exercise, weight) if increase else weight
        onerm     = estimate_1rm(weight, reps)

        history_entry = {
            "date":   datetime.now().strftime("%Y-%m-%d"),
            "weight": round(weight, 1),
            "reps":   reps,
            "note":   f"+{new_w - weight:.1f}" if increase else "stagné",
            "1rm":    onerm
        }

        if exercise not in weights:
            weights[exercise] = {"history": []}

        weights[exercise].setdefault("history", []).insert(0, history_entry)
        weights[exercise]["history"]        = weights[exercise]["history"][:20]
        weights[exercise]["current_weight"] = round(new_w, 1)
        weights[exercise]["last_reps"]      = reps
        weights[exercise]["last_logged"]    = datetime.now().strftime("%Y-%m-%d %H:%M")

        save_weights(weights)
        achieved = check_goals_achieved(weights)

        return jsonify({
            "success":    True,
            "status":     status,
            "increase":   increase,
            "new_weight": new_w,
            "1rm":        onerm,
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
            save_weights(weights)

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

        # Remove from sessions
        sessions = load_sessions()
        sessions.pop(date, None)
        from sessions import save_sessions
        save_sessions(sessions)

        # Remove matching history entries from weights
        weights = load_weights()
        for ex in weights:
            history = weights[ex].get("history", [])
            weights[ex]["history"] = [e for e in history if e.get("date") != date]
            # Recalculate current values from remaining history
            remaining = weights[ex]["history"]
            if remaining:
                most_recent = max(remaining, key=lambda e: e.get("date", ""))
                weights[ex]["current_weight"] = most_recent["weight"]
                weights[ex]["last_reps"]      = most_recent["reps"]
        save_weights(weights)

        return jsonify({"success": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/log_session", methods=["POST"])
def api_log_session():
    try:
        data    = request.get_json()
        # Utilise la date locale du client si fournie (évite le décalage UTC/EST)
        today   = data.get("date") or datetime.now().strftime("%Y-%m-%d")
        rpe     = data.get("rpe")
        comment = data.get("comment", "")
        exos    = data.get("exos", [])
        log_session(today, rpe, comment, exos)
        return jsonify({"success": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/log_hiit", methods=["POST"])
def api_log_hiit():
    data     = request.json
    week     = get_current_week()
    hiit_log = load_hiit_log_local()

    entry = {
        "date":               data.get("date") or datetime.now().strftime("%Y-%m-%d"),
        "week":               week,
        "session_type":       data.get("session_type", "HIIT"),
        "rounds_planifies":   data.get("rounds", 0),
        "rounds_completes":   data.get("rounds", 0),
        "vitesse_max":        data.get("speed"),
        "vitesse_croisiere":  data.get("vitesse_croisiere"),
        "rpe":                data.get("rpe"),
        "feeling":            data.get("feeling", "—"),
        "comment":            data.get("comment", "")
    }

    hiit_log.insert(0, entry)
    save_hiit_log_local(hiit_log)
    return jsonify({"success": True})


@app.route("/api/delete_hiit", methods=["POST"])
def api_delete_hiit():
    data     = request.json
    index    = data.get("index")
    hiit_log = load_hiit_log_local()

    if 0 <= index < len(hiit_log):
        hiit_log.pop(index)
        save_hiit_log_local(hiit_log)
        return jsonify({"success": True})

    return jsonify({"error": "Index introuvable"}), 400


@app.route("/api/hiit/edit", methods=["POST"])
def api_hiit_edit():
    try:
        data     = request.get_json()
        index    = data.get("index")
        hiit_log = load_hiit_log_local()

        if index is None or not (0 <= index < len(hiit_log)):
            return jsonify({"error": "Index introuvable"}), 400

        entry = hiit_log[index]
        for field in ("rpe", "feeling", "comment", "rounds_completes",
                      "vitesse_max", "vitesse_croisiere", "duration"):
            if field in data:
                entry[field] = data[field]

        save_hiit_log_local(hiit_log)
        return jsonify({"success": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/save_exercise", methods=["POST"])
def api_save_exercise():
    data = request.json
    original_name = data.get("original_name", "")
    name = data.get("name", "").strip()

    if not name:
        return jsonify({"error": "Nom manquant"}), 400

    inv = load_inventory()

    # Gestion du renommage
    if original_name and original_name != name and original_name in inv:
        del inv[original_name]

    # --- RECHERCHE AUTOMATIQUE DU GIF ---
    # On récupère le GIF actuel s'il existe pour ne pas le perdre
    existing_gif = inv.get(name, {}).get("gif_url")
    gif_url = data.get("gif_url") or existing_gif

    # Si on n'a toujours pas de GIF et qu'on a une clé API, on cherche
    if not gif_url and RAPID_API_KEY:
        try:
            api_url = f"https://exercisedb.p.rapidapi.com/exercises/name/{name.lower()}"
            headers = {
                "X-RapidAPI-Key": RAPID_API_KEY,
                "X-RapidAPI-Host": "exercisedb.p.rapidapi.com"
            }
            # On limite à 1 résultat pour économiser le quota
            response = requests.get(api_url, headers=headers, params={"limit": "1"}, timeout=5)
            if response.status_code == 200:
                res_json = response.json()
                if res_json and len(res_json) > 0:
                    gif_url = res_json[0].get("gifUrl")
        except Exception as e:
            print(f"Erreur ExerciseDB : {e}")

    # Mise à jour du dictionnaire avec tes champs existants + le GIF
    inv[name] = {
        "type": data.get("type", "machine"),
        "increment": float(data.get("increment", 5)),
        "bar_weight": float(data.get("bar_weight", 0)),
        "default_scheme": data.get("default_scheme", "3x8-12"),
        "muscles": data.get("muscles", []),
        "tips": data.get("tips", ""),
        "category": data.get("category", ""),
        "pattern": data.get("pattern", ""),
        "level": data.get("level", ""),
        "gif_url": gif_url  # Ajout du lien vers la démo
    }

    # Sauvegarde via db.py (Supabase)
    success = save_inventory(inv)

    if not success:
        return jsonify({"success": False, "error": "Erreur de sauvegarde Supabase"}), 500

    # Si renommage, mettre à jour le programme partout
    if original_name and original_name != name:
        program = load_program()
        changed = False
        for jour, exos in program.items():
            if original_name in exos:
                exos[name] = exos.pop(original_name)
                changed = True
        if changed:
            save_program(program)

    return jsonify({"success": True, "gif_url": gif_url})


@app.route("/api/delete_exercise", methods=["POST"])
def api_delete_exercise():
    name = request.json.get("name")
    inv  = load_inventory()

    if name not in inv:
        return jsonify({"error": "Exercice introuvable"}), 404

    del inv[name]
    save_inventory(inv)
    return jsonify({"success": True})


@app.route("/api/programme", methods=["POST"])
def api_programme():
    data    = request.json
    action  = data.get("action")
    jour    = data.get("jour")
    program = load_program()

    if jour not in program:
        return jsonify({"error": "Jour invalide"}), 400

    if action == "add":
        exercise = data.get("exercise")
        scheme   = data.get("scheme", "3x8-12")
        if exercise in program[jour]:
            return jsonify({"error": "Déjà dans le programme"}), 400
        program[jour][exercise] = scheme

    elif action == "remove":
        exercise = data.get("exercise")
        if exercise in program[jour]:
            del program[jour][exercise]

    elif action == "scheme":
        exercise = data.get("exercise")
        scheme   = data.get("scheme")
        if exercise in program[jour]:
            program[jour][exercise] = scheme

    elif action == "replace":
        old_ex = data.get("old_exercise")
        new_ex = data.get("new_exercise")
        scheme = data.get("scheme", "3x8-12")
        if old_ex in program[jour]:
            del program[jour][old_ex]
        program[jour][new_ex] = scheme

    elif action == "reorder":
        ordre         = data.get("ordre", [])
        ancien        = program[jour]
        program[jour] = {ex: ancien[ex] for ex in ordre if ex in ancien}

    save_program(program)
    return jsonify({"success": True})


@app.route("/api/update_profile", methods=["POST"])
def api_update_profile():
    ok = save_user_profile(request.json)
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
        data  = request.get_json()
        poids = float(data.get("poids", 0))
        note  = data.get("note", "")
        if not poids:
            return jsonify({"error": "Poids invalide"}), 400
        log_body_weight(poids, note)
        return jsonify({"success": True, "poids": poids})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/body_weight/delete", methods=["POST"])
def api_delete_body_weight():
    try:
        data  = request.get_json()
        date  = data.get("date", "")
        poids = float(data.get("poids", 0))
        entries = load_body_weight()
        # Supprime la première entrée qui correspond à la date ET au poids
        new_entries = [e for e in entries if not (e.get("date") == date and float(e.get("poids", 0)) == poids)]
        if len(new_entries) == len(entries):
            return jsonify({"success": False, "error": "Entrée introuvable"}), 404
        set_json("body_weight", new_entries)
        return jsonify({"success": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 500


@app.route("/api/ai/coach", methods=["POST"])
def api_ai_coach():
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
        return jsonify({"response": message.content[0].text})
    except _anthropic.AuthenticationError:
        return jsonify({"error": "Clé ANTHROPIC_API_KEY invalide"}), 500
    except Exception as e:
        return jsonify({"error": str(e)}), 500


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
    print(f"🚀 TrainingOS → {url}")
    # N'ouvre le navigateur que dans le processus principal (pas le child du reloader)
    if os.environ.get('WERKZEUG_RUN_MAIN') != 'true':
        Timer(1.0, lambda: webbrowser.open(url)).start()
    app.run(debug=True, use_reloader=True, host="0.0.0.0", port=port)