# flask_app.py
import os
import json
import socket
import webbrowser
from threading import Timer
from pathlib import Path
from datetime import datetime, date
from werkzeug.utils import secure_filename
from flask import Flask, render_template, jsonify, request, redirect, url_for

from planner import get_today, get_week_schedule, get_suggested_weights_for_today, load_program
from hiit import get_hiit_str
from log_workout import load_weights, save_weights, log_single_exercise
from inventory import load_inventory
from sessions import load_sessions, log_session
from user_profile import load_user_profile
from progression import estimate_1rm, should_increase, next_weight, parse_reps, progression_status
from deload import analyser_deload, load_deload_state
from goals import load_goals, check_goals_achieved, get_progress_bar
from body_weight import load_body_weight, log_body_weight, get_tendance

app = Flask(__name__)
app.secret_key = "super-secret-key-change-me-in-production"

UPLOAD_FOLDER      = 'static/uploads'
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'gif'}
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER
HIIT_FILE = Path(__file__).parent / "data" / "hiit_log.json"


def get_current_week() -> int:
    START_DATE = date(2026, 3, 3)
    delta = date.today() - START_DATE
    return max(1, (delta.days // 7) + 1)


def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS


def get_plates(total_weight: float, bar_weight: float = 45.0) -> list:
    if total_weight <= bar_weight:
        return []
    side_weight  = (total_weight - bar_weight) / 2
    plates       = [45, 35, 25, 10, 5, 2.5]
    result       = []
    temp_weight  = round(float(side_weight), 2)
    for plate in plates:
        while temp_weight >= plate:
            result.append(plate)
            temp_weight = round(temp_weight - plate, 2)
    return result


def load_hiit_log_local():
    if HIIT_FILE.exists():
        with open(HIIT_FILE, encoding="utf-8") as f:
            return json.load(f)
    return []


# ─────────────────────────────────────────────────────────────
# PAGES HTML
# ─────────────────────────────────────────────────────────────

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
    weights = load_weights()
    today   = get_today()

    if today in ['HIIT 1', 'HIIT 2', 'Yoga', 'Recovery']:
        return redirect(url_for('seance_speciale', session_type=today))

    program = load_program()
    inv     = load_inventory()
    from inventory import calculate_plates

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
        today     = today,
        exercises = exercises,
        is_hiit   = "HIIT" in today,
        hiit_str  = get_hiit_str(get_current_week()) if "HIIT" in today else "",
        week      = get_current_week()
    )


@app.route("/seance_speciale/<path:session_type>")
def seance_speciale(session_type):
    week = get_current_week()
    if week <= 4:
        protocole = {"rounds": 8,  "sprint_spd": 13.0, "jog_spd": 6.5, "duree": 20}
    elif week <= 8:
        protocole = {"rounds": 10, "sprint_spd": 13.0, "jog_spd": 6.5, "duree": 25}
    elif week <= 12:
        protocole = {"rounds": 12, "sprint_spd": 13.0, "jog_spd": 6.5, "duree": 28}
    elif week <= 16:
        protocole = {"rounds": 8,  "sprint_spd": 14.0, "jog_spd": 7.0, "duree": 20}
    else:
        protocole = {"rounds": 10, "sprint_spd": 14.0, "jog_spd": 7.0, "duree": 25}

    return render_template("seance_speciale.html",
        session_type = session_type,
        protocole    = protocole,
        week         = week,
        now          = datetime.now().strftime("%Y-%m-%d")
    )


@app.route("/historique")
def historique():
    weights   = load_weights()
    inv       = load_inventory()
    exercices = []
    for ex, data in weights.items():
        if ex == "sessions":
            continue
        info = inv.get(ex, {})
        exercices.append({
            "name":    ex,
            "type":    info.get("type", "—"),
            "muscles": info.get("muscles", []),
            "history": data.get("history", [])[:10],
            "current": data.get("current_weight", 0)
        })
    return render_template("historique.html", exercices=exercices)


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


@app.route("/stats")
def stats():
    weights  = load_weights()
    sessions = load_sessions()
    bw       = load_body_weight()
    return render_template("stats.html",
        weights     = weights,
        sessions    = sessions,
        hiit_log    = load_hiit_log_local(),
        body_weight = bw,
        inventory = load_inventory(),
        now         = datetime.now().strftime("%Y-%m-%d")
    )


@app.route("/profil")
def profil():
    profile     = load_user_profile()
    body_weight = load_body_weight()
    tendance    = get_tendance(body_weight) if body_weight else "Pas de données"
    return render_template("profil.html",
        profile     = profile,
        body_weight = body_weight[:7] if body_weight else [],
        tendance    = tendance
    )


# ─────────────────────────────────────────────────────────────
# API ROUTES
# ─────────────────────────────────────────────────────────────

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


@app.route('/sw.js')
def service_worker():
    from flask import send_from_directory
    return send_from_directory('static', 'sw.js',
        mimetype='application/javascript')
@app.route("/api/log_session", methods=["POST"])
def api_log_session():
    try:
        data    = request.get_json()
        today   = datetime.now().strftime("%Y-%m-%d")
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
        "date":             datetime.now().strftime("%Y-%m-%d"),
        "week":             week,
        "rounds_planifies": data.get("rounds", 0),
        "rounds_completes": data.get("rounds", 0),
        "vitesse_max":      data.get("speed"),
        "rpe":              data.get("rpe"),
        "feeling":          data.get("feeling", "—"),
        "comment":          data.get("comment", "")
    }

    hiit_log.insert(0, entry)
    with open(HIIT_FILE, "w", encoding="utf-8") as f:
        json.dump(hiit_log, f, indent=2, ensure_ascii=False)

    return jsonify({"success": True})


@app.route("/api/delete_hiit", methods=["POST"])
def api_delete_hiit():
    data     = request.json
    index    = data.get("index")
    hiit_log = load_hiit_log_local()

    if 0 <= index < len(hiit_log):
        hiit_log.pop(index)
        with open(HIIT_FILE, "w", encoding="utf-8") as f:
            json.dump(hiit_log, f, indent=2, ensure_ascii=False)
        return jsonify({"success": True})

    return jsonify({"error": "Index introuvable"}), 400


@app.route("/api/save_exercise", methods=["POST"])
def api_save_exercise():
    from inventory import save_inventory
    data          = request.json
    original_name = data.get("original_name", "")
    name          = data.get("name", "").strip()

    if not name:
        return jsonify({"error": "Nom manquant"}), 400

    inv = load_inventory()
    if original_name and original_name != name and original_name in inv:
        del inv[original_name]

    inv[name] = {
        "type":           data.get("type", "machine"),
        "increment":      float(data.get("increment", 5)),
        "bar_weight":     float(data.get("bar_weight", 0)),
        "default_scheme": data.get("default_scheme", "3x8-12"),
        "muscles":        data.get("muscles", []),
        "tips":           data.get("tips", "")
    }

    save_inventory(inv)
    return jsonify({"success": True})


@app.route("/api/delete_exercise", methods=["POST"])
def api_delete_exercise():
    from inventory import save_inventory
    name = request.json.get("name")
    inv  = load_inventory()

    if name not in inv:
        return jsonify({"error": "Exercice introuvable"}), 404

    del inv[name]
    save_inventory(inv)
    return jsonify({"success": True})


@app.route("/api/programme", methods=["POST"])
def api_programme():
    from planner import save_program
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
        ordre  = data.get("ordre", [])
        ancien = program[jour]
        program[jour] = {ex: ancien[ex] for ex in ordre if ex in ancien}

    save_program(program)
    return jsonify({"success": True})


@app.route("/api/update_profile", methods=["POST"])
def api_update_profile():
    from user_profile import save_user_profile
    data = request.json
    save_user_profile(data)
    return jsonify({"success": True})


@app.route("/api/update_profile_photo", methods=["POST"])
def api_update_profile_photo():
    if 'photo' not in request.files:
        return jsonify({"success": False, "error": "Fichier manquant"}), 400

    file = request.files['photo']
    if file.filename == '':
        return jsonify({"success": False, "error": "Aucun fichier sélectionné"}), 400

    if file:
        filename    = secure_filename(file.filename)
        upload_path = os.path.join('static', 'uploads')
        os.makedirs(upload_path, exist_ok=True)
        file.save(os.path.join(upload_path, filename))

        profile = load_user_profile()
        profile['photo'] = filename
        from user_profile import save_user_profile
        save_user_profile(profile)

        return jsonify({
            "success":   True,
            "photo_url": url_for('static', filename='uploads/' + filename)
        })


@app.route("/api/set_goal", methods=["POST"])
def api_set_goal():
    from goals import set_goal
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
    weights = load_weights()
    rapport = analyser_deload(weights)
    return jsonify(rapport)


# ─────────────────────────────────────────────────────────────
# LANCEMENT
# ─────────────────────────────────────────────────────────────

def find_free_port(start_port=5000, max_port=5100):
    for port in range(start_port, max_port):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            try:
                s.bind(("0.0.0.0", port))
                return port
            except OSError:
                continue
    raise RuntimeError(f"Aucun port libre trouvé entre {start_port} et {max_port}")


if __name__ == "__main__":
    port = find_free_port()
    url  = f"http://localhost:{port}"
    print(f"🚀 TrainingOS Flask démarré → {url}")
    Timer(1.0, lambda: webbrowser.open(url)).start()
    app.run(debug=True, use_reloader=False, host="0.0.0.0", port=port)