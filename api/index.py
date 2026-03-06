# api/index.py
from __future__ import annotations
import os, sys, json, socket, webbrowser
from threading import Timer
from datetime import datetime, date
from pathlib import Path

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
        today    = today,
        exercises = exercises,
        is_hiit  = "HIIT" in today,
        hiit_str = get_hiit_str(get_current_week()) if "HIIT" in today else "",
        week     = get_current_week()
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
                           now=datetime.now().strftime("%Y-%m-%d")
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


@app.route("/timer")
def timer():
    return render_template("timer.html",
        now  = datetime.now().strftime("%Y-%m-%d"),
        week = datetime.now().isocalendar()[1]
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
        "date":               datetime.now().strftime("%Y-%m-%d"),
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


import os
import requests
from flask import request, jsonify

# Assure-toi que cette variable est bien configurée dans ton Vercel
RAPID_API_KEY = os.getenv("X_RAPIDAPI_KEY")


@app.route("/api/save_exercise", methods=["POST"])
def api_save_exercise():
    from inventory import save_inventory, load_inventory
    import os
    import requests
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
        from db import set_json
        set_json("body_weight", new_entries)
        return jsonify({"success": True})
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
    return send_from_directory(
        os.path.join(BASE_DIR, "static"),
        "sw.js",
        mimetype="application/javascript"
    )


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
    port = find_free_port()
    url  = f"http://localhost:{port}"
    print(f"🚀 TrainingOS → {url}")
    Timer(1.0, lambda: webbrowser.open(url)).start()
    app.run(debug=True, use_reloader=False, host="0.0.0.0", port=port)