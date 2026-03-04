# flask_app.py
import os
from werkzeug.utils import secure_filename
from flask import Flask, render_template, jsonify, request, redirect, url_for, flash
from datetime import datetime


from pathlib import Path

# ─────────────────────────────────────────────────────────────
# Imports de tes modules
# ─────────────────────────────────────────────────────────────
from planner import get_today, get_week_schedule, get_suggested_weights_for_today, load_program
from hiit import get_hiit_str
from log_workout import load_weights, save_weights, log_single_exercise
from inventory import load_inventory
from sessions import load_sessions, log_session
from stats import load_hiit_log
from user_profile import load_user_profile
from progression import estimate_1rm, should_increase, next_weight, parse_reps, progression_status
from deload import analyser_deload, load_deload_state
from goals import load_goals, check_goals_achieved, get_progress_bar
from body_weight import load_body_weight, log_body_weight, get_tendance

app = Flask(__name__)
app.secret_key = "super-secret-key-change-me-in-production"  # À changer en prod !!!

# Helper pour calculer la semaine depuis ta date de début
def get_current_week() -> int:
    from datetime import date
    START_DATE = date(2026, 3, 3)
    delta = date.today() - START_DATE
    return max(1, (delta.days // 7) + 1)


# ─────────────────────────────────────────────────────────────
# ROUTES PAGES (HTML)
# ─────────────────────────────────────────────────────────────

@app.route("/")
def index():
    from stats import compute_frequence_hebdo
    from stats import get_frequence_hebdo_data
    from hiit import load_hiit_log
    hiit_log = load_hiit_log()

    weights = load_weights()
    profile = load_user_profile()
    suggestions = get_suggested_weights_for_today(weights)
    goals = load_goals()
    full_program = load_program()
    inventory = load_inventory()
    from inventory import calculate_plates
    freq_labels, freq_values = get_frequence_hebdo_data(weights, hiit_log)
    moyenne = sum(freq_values) / len(freq_values) if freq_values else 0
    # Correction : on récupère l'état du deload ici
    deload_state = load_deload_state()

    # Progression objectifs
    goals_progress = {}
    for ex, goal in goals.items():
        current = weights.get(ex, {}).get("current_weight", 0) or 0
        goals_progress[ex] = {
            "current": current,
            "goal": goal["goal_weight"],
            "bar": get_progress_bar(current, goal["goal_weight"]),
            "achieved": goal.get("achieved", False),
            "since": deload_state.get("since", "")  # Optionnel : pour l'affichage
        }

        plates_data = {}
        for session_name, exercises in full_program.items():
            if isinstance(exercises, dict):  # Protection si c'est un dictionnaire d'exos
                for ex_name in exercises:
                    if ex_name not in plates_data:
                        ex_info = inventory.get(ex_name, {})
                        weight_data = weights.get(ex_name, {})
                        current = weight_data.get("current_weight", 0) or 0

                        if ex_info.get("type") == "barbell" and current > 0:
                            bar_w = ex_info.get("bar_weight", 45.0)
                            plates_data[ex_name] = calculate_plates(current, bar_w)

    return render_template("index.html",
                           today=get_today(),
                           week=get_current_week(),
                           profile=profile,
                           suggestions=suggestions,
                           goals=goals_progress,
                           freq_labels=freq_labels,
                           freq_values=freq_values,
                           freq_moyenne=round(moyenne, 1),
                           schedule=get_week_schedule(),
                           full_program=full_program,
                           deload_state=deload_state,  # On injecte la variable ici
                           now=datetime.now().strftime("%A")
                           )

def get_plates(total_weight: float, bar_weight: float = 45.0) -> list:
    """ Calcule les plaques par côté et retourne une liste de nombres (float). """
    if total_weight <= bar_weight:
        return []

    side_weight = (total_weight - bar_weight) / 2
    plates = [45, 35, 25, 10, 5, 2.5]
    result = []

    # On utilise un arrondi pour éviter les bugs de virgule flottante
    temp_weight = round(float(side_weight), 2)

    for plate in plates:
        while temp_weight >= plate:
            result.append(plate)
            temp_weight = round(temp_weight - plate, 2)

    return result


# ─────────────────────────────────────────────────────────────
# ROUTE SÉANCE (corrigée et avec calcul des disques)
# ─────────────────────────────────────────────────────────────
@app.route("/inventaire")
def inventaire():
    inv = load_inventory()
    return render_template("inventaire.html", inventory=inv)


@app.route("/api/save_exercise", methods=["POST"])
def api_save_exercise():
    from inventory import save_inventory
    data          = request.json
    original_name = data.get("original_name", "")
    name          = data.get("name", "").strip()

    if not name:
        return jsonify({"error": "Nom manquant"}), 400

    inv = load_inventory()

    # Si renommage → supprime l'ancien
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

@app.route("/programme")
def programme():
    program   = load_program()
    inv       = load_inventory()
    today     = get_today()
    return render_template("programme.html",
        program   = program,
        inventory = inv,
        today     = today
    )


@app.route("/api/programme", methods=["POST"])
def api_programme():
    from planner import save_program
    data     = request.json
    action   = data.get("action")
    jour     = data.get("jour")
    program  = load_program()

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

    save_program(program)
    return jsonify({"success": True})


# Configure le dossier de téléchargement et les extensions autorisées
UPLOAD_FOLDER = 'static/uploads'
ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'gif'}
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER


def allowed_file(filename):
    return '.' in filename and \
        filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

import os
from werkzeug.utils import secure_filename
@app.route("/api/update_profile_photo", methods=["POST"])
def api_update_profile_photo():
    if 'photo' not in request.files:
        return jsonify({"success": False, "error": "Fichier manquant"}), 400

    file = request.files['photo']
    if file.filename == '':
        return jsonify({"success": False, "error": "Aucun fichier sélectionné"}), 400

    if file:
        filename = secure_filename(file.filename)
        upload_path = os.path.join('static', 'uploads')

        # Créer le dossier s'il n'existe pas
        os.makedirs(upload_path, exist_ok=True)

        full_path = os.path.join(upload_path, filename)
        file.save(full_path)

        # Sauvegarde dans le profil utilisateur
        profile = load_user_profile()
        profile['photo'] = filename
        from user_profile import save_user_profile
        save_user_profile(profile)

        return jsonify({
            "success": True,
            "photo_url": url_for('static', filename='uploads/' + filename)
        })
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
@app.route("/api/log_hiit", methods=["POST"])
def api_log_hiit():
    from log_workout import log_hiit_session
    data    = request.json
    week    = get_current_week()
    import json
    from pathlib import Path
    HIIT_FILE = Path(__file__).parent / "data" / "hiit_log.json"

    hiit_log = []
    if HIIT_FILE.exists():
        with open(HIIT_FILE) as f:
            hiit_log = json.load(f)

    entry = {
        "date":             datetime.now().strftime("%Y-%m-%d"),
        "week":             week,
        "rounds_planifiés": data.get("rounds", 0),
        "rounds_complétés": data.get("rounds", 0),
        "vitesse_max":      data.get("speed"),
        "rpe":              data.get("rpe"),
        "feeling":          data.get("feeling", "—"),
        "comment":          data.get("comment", "")
    }

    hiit_log.insert(0, entry)
    with open(HIIT_FILE, "w") as f:
        json.dump(hiit_log, f, indent=2, ensure_ascii=False)

    return jsonify({"success": True})


@app.route("/seance")
def seance():
    # 1. Chargement des données
    weights = load_weights()
    today = get_today()
    program = load_program()
    inv = load_inventory()

    # On utilise ta fonction de inventory.py
    from inventory import calculate_plates

    exercises = []
    if today in program:
        for ex, scheme in program[today].items():
            # 2. Récupération des infos spécifiques à l'exercice
            data = weights.get(ex, {})
            ex_info = inv.get(ex, {})

            current = data.get("current_weight", 0) or 0
            ex_type = ex_info.get("type", "machine")
            bar_w = ex_info.get("bar_weight", 45.0)

            # 3. Logique d'affichage (Display)
            if ex_type == "barbell" and current:
                display = f"{(current - bar_w) / 2:.1f} lbs par côté"
            elif ex_type == "dumbbell" and current:
                display = f"{current / 2:.1f} lbs par haltère"
            else:
                display = f"{current:.1f} lbs" if current else "À définir"

            # 4. Calcul des disques pour le Plate Calculator
            plates_needed = []
            if ex_type == "barbell" and current > bar_w:
                plates_needed = calculate_plates(current, bar_w)

            # 5. Construction du dictionnaire envoyé au HTML
            exercises.append({
                "name": ex,
                "scheme": scheme,
                "current": current,
                "display": display,
                "type": ex_type,
                "plates": plates_needed,
                "history": data.get("history", [])[:3],
                "1rm": data.get("history", [{}])[0].get("1rm", 0) if data.get("history") else 0
            })

    # 6. Envoi au template
    return render_template("seance.html",
                           today=today,
                           exercises=exercises,
                           is_hiit="HIIT" in today,
                           hiit_str=get_hiit_str(get_current_week()) if "HIIT" in today else "",
                           week=get_current_week())

@app.route("/historique")
def historique():
    weights = load_weights()
    inv = load_inventory()

    exercices = []
    for ex, data in weights.items():
        if ex == "sessions":
            continue
        info = inv.get(ex, {})
        exercices.append({
            "name": ex,
            "type": info.get("type", "—"),
            "muscles": info.get("muscles", []),
            "history": data.get("history", [])[:10],
            "current": data.get("current_weight", 0)
        })

    return render_template("historique.html", exercices=exercices)

@app.route("/hiit")
def hiit_historique():
    from pathlib import Path
    import json
    hiit_file = Path(__file__).parent / "data" / "hiit_log.json"
    hiit_log  = []
    if hiit_file.exists():
        with open(hiit_file) as f:
            hiit_log = json.load(f)

    return render_template("hiit.html", hiit_log=hiit_log)
@app.route("/objectifs")
def objectifs():
    weights = load_weights()
    goals = load_goals()

    goals_data = []
    for ex, goal in goals.items():
        current = weights.get(ex, {}).get("current_weight", 0) or 0
        pct = min(current / goal["goal_weight"] * 100, 100) if goal["goal_weight"] else 0
        goals_data.append({
            "exercise": ex,
            "current": current,
            "goal": goal["goal_weight"],
            "pct": round(pct, 1),
            "achieved": goal.get("achieved", False),
            "deadline": goal.get("deadline", ""),
        })

    return render_template("objectifs.html", goals=goals_data)

@app.route("/stats")
def stats():
    """Page dashboard stats."""
    weights      = load_weights()
    hiit_log_raw = []
    from pathlib import Path
    import json
    hiit_file = Path(__file__).parent / "data" / "hiit_log.json"
    if hiit_file.exists():
        with open(hiit_file) as f:
            hiit_log_raw = json.load(f)

    sessions    = load_sessions()
    body_weight = load_body_weight()

    return render_template("stats.html",
        weights     = weights,
        sessions    = sessions,
        hiit_log    = hiit_log_raw,
        body_weight = body_weight,
        now         = datetime.now().strftime("%Y-%m-%d")
    )
@app.route("/profil")
def profil():
    profile = load_user_profile()
    body_weight = load_body_weight()
    tendance = get_tendance(body_weight) if body_weight else "Pas de données"

    return render_template("profil.html",
        profile=profile,
        body_weight=body_weight[:7] if body_weight else [],
        tendance=tendance
    )


# ─────────────────────────────────────────────────────────────
# API ROUTES (pour le frontend JS)
# ─────────────────────────────────────────────────────────────
@app.route("/api/delete_hiit", methods=["POST"])
def api_delete_hiit():
    import json
    from pathlib import Path
    hiit_file = Path(__file__).parent / "data" / "hiit_log.json"

    data = request.json
    index = data.get("index")

    if hiit_file.exists():
        with open(hiit_file, "r", encoding="utf-8") as f:
            hiit_log = json.load(f)

        if 0 <= index < len(hiit_log):
            hiit_log.pop(index)  # Supprime l'entrée à l'index donné

            with open(hiit_file, "w", encoding="utf-8") as f:
                json.dump(hiit_log, f, indent=2, ensure_ascii=False)
            return jsonify({"success": True})

    return jsonify({"error": "Fichier ou index introuvable"}), 400
@app.route("/api/log", methods=["POST"])
def api_log():
    try:
        data = request.get_json()
        exercise = data.get("exercise")
        weight = float(data.get("weight", 0))
        reps_str = data.get("reps", "")

        if not exercise or not reps_str:
            return jsonify({"error": "Données manquantes"}), 400

        weights = load_weights()
        ex_data = weights.get(exercise, {})

        reps_list = parse_reps(reps_str)
        reps = ",".join(map(str, reps_list))
        status = progression_status(reps, exercise)
        increase = should_increase(reps, exercise)
        new_w = next_weight(exercise, weight) if increase else weight
        onerm = estimate_1rm(weight, reps)

        history_entry = {
            "date": datetime.now().strftime("%Y-%m-%d"),
            "weight": round(weight, 1),
            "reps": reps,
            "note": f"+{new_w - weight:.1f}" if increase else "stagné",
            "1rm": onerm
        }

        if exercise not in weights:
            weights[exercise] = {"history": []}

        weights[exercise].setdefault("history", []).insert(0, history_entry)
        weights[exercise]["history"] = weights[exercise]["history"][:20]
        weights[exercise]["current_weight"] = round(new_w, 1)
        weights[exercise]["last_reps"] = reps
        weights[exercise]["last_logged"] = datetime.now().strftime("%Y-%m-%d %H:%M")

        save_weights(weights)

        # Vérifie objectifs
        achieved = check_goals_achieved(weights)

        return jsonify({
            "success": True,
            "status": status,
            "increase": increase,
            "new_weight": new_w,
            "1rm": onerm,
            "achieved": achieved
        })

    except Exception as e:
        return jsonify({"error": str(e)}), 500
@app.route("/api/update_profile", methods=["POST"])
def api_update_profile():
    from user_profile import save_user_profile
    data = request.json
    save_user_profile(data)
    return jsonify({"success": True})

@app.route("/api/log_session", methods=["POST"])
def api_log_session():
    try:
        data = request.get_json()
        today = datetime.now().strftime("%Y-%m-%d")
        rpe = data.get("rpe")
        comment = data.get("comment", "")
        exos = data.get("exos", [])

        log_session(today, rpe, comment, exos)
        return jsonify({"success": True})
    except Exception as e:
        return jsonify({"error": str(e)}), 500

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
        data = request.get_json()
        poids = float(data.get("poids", 0))
        note = data.get("note", "")

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

import socket
import webbrowser
from threading import Timer

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
    url = f"http://localhost:{port}"
    print(f"🚀 TrainingOS Flask démarré → {url}")

    # Ouvre le navigateur après un petit délai
    Timer(1.0, lambda: webbrowser.open(url)).start()

    # Note : reloader désactivé pour garder le port trouvé
    app.run(debug=True, use_reloader=False, host="0.0.0.0", port=port)
