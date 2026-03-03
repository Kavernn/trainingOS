# flask_app.py
from flask import Flask, render_template, jsonify, request, redirect, url_for
from datetime import datetime

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

# ─────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────

def get_current_week() -> int:
    from datetime import date
    START_DATE = date(2026, 3, 3)
    delta = date.today() - START_DATE
    return max(1, (delta.days // 7) + 1)


# ─────────────────────────────────────────────────────────────
# ROUTES PRINCIPALES
# ─────────────────────────────────────────────────────────────

@app.route("/")
def index():
    """Page principale — séance du jour."""
    weights      = load_weights()
    today        = get_today()
    week         = get_current_week()
    profile      = load_user_profile()
    suggestions  = get_suggested_weights_for_today(weights)
    deload_state = load_deload_state()
    goals        = load_goals()
    schedule     = get_week_schedule()

    # Progression objectifs
    goals_progress = {}
    for ex, goal in goals.items():
        data    = weights.get(ex, {})
        current = data.get("current_weight", data.get("weight", 0)) or 0
        goals_progress[ex] = {
            "current":  current,
            "goal":     goal["goal_weight"],
            "bar":      get_progress_bar(current, goal["goal_weight"]),
            "achieved": goal.get("achieved", False)
        }

    return render_template("index.html",
        today        = today,
        week         = week,
        profile      = profile,
        suggestions  = suggestions,
        deload_state = deload_state,
        goals        = goals_progress,
        schedule     = schedule,
        now          = datetime.now().strftime("%Y-%m-%d")
    )


@app.route("/seance")
def seance():
    """Page de log de séance."""
    weights  = load_weights()
    today    = get_today()
    program  = load_program()
    inv      = load_inventory()

    exercises = []
    if today in program:
        for ex, scheme in program[today].items():
            data    = weights.get(ex, {})
            ex_info = inv.get(ex, {})
            current = data.get("current_weight", data.get("weight", 0)) or 0

            # Calcul affichage poids
            ex_type  = ex_info.get("type", "machine")
            bar_w    = ex_info.get("bar_weight", 45.0)
            if ex_type == "barbell" and current:
                display = f"{(current - bar_w) / 2:.1f} par côté"
            elif ex_type == "dumbbell" and current:
                display = f"{current / 2:.1f} par haltère"
            else:
                display = f"{current:.1f} lbs" if current else "À définir"

            # Historique récent
            history = data.get("history", [])[:3]

            exercises.append({
                "name":    ex,
                "scheme":  scheme,
                "current": current,
                "display": display,
                "type":    ex_type,
                "history": history,
                "1rm":     history[0].get("1rm", 0) if history else 0
            })

    return render_template("seance.html",
        today     = today,
        exercises = exercises,
        is_hiit   = "HIIT" in today,
        hiit_str  = get_hiit_str(get_current_week()) if "HIIT" in today else "",
        week      = get_current_week()
    )


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
        body_weight = body_weight
    )


@app.route("/historique")
def historique():
    """Page historique des exercices."""
    weights = load_weights()
    inv     = load_inventory()

    exercices = []
    for ex, data in weights.items():
        if ex == "sessions":
            continue
        info    = inv.get(ex, {})
        history = data.get("history", [])
        exercices.append({
            "name":    ex,
            "type":    info.get("type", "—"),
            "muscles": info.get("muscles", []),
            "history": history[:10],
            "current": data.get("current_weight", 0)
        })

    return render_template("historique.html", exercices=exercices)


@app.route("/objectifs")
def objectifs():
    """Page objectifs personnels."""
    weights = load_weights()
    goals   = load_goals()

    goals_data = []
    for ex, goal in goals.items():
        data    = weights.get(ex, {})
        current = data.get("current_weight", data.get("weight", 0)) or 0
        pct     = min(current / goal["goal_weight"] * 100, 100) if goal["goal_weight"] else 0
        goals_data.append({
            "exercise":  ex,
            "current":   current,
            "goal":      goal["goal_weight"],
            "pct":       round(pct, 1),
            "achieved":  goal.get("achieved", False),
            "deadline":  goal.get("deadline", ""),
            "note":      goal.get("note", ""),
            "achieved_on": goal.get("achieved_on", "")
        })

    return render_template("objectifs.html", goals=goals_data)


@app.route("/profil")
def profil():
    """Page profil utilisateur."""
    profile     = load_user_profile()
    body_weight = load_body_weight()
    tendance    = get_tendance(body_weight) if body_weight else "Pas de données"

    return render_template("profil.html",
        profile     = profile,
        body_weight = body_weight[:7],
        tendance    = tendance
    )


# ─────────────────────────────────────────────────────────────
# API ROUTES (JSON)
# ─────────────────────────────────────────────────────────────

@app.route("/api/today")
def api_today():
    weights = load_weights()
    return jsonify({
        "today":       get_today(),
        "week":        get_current_week(),
        "suggestions": get_suggested_weights_for_today(weights),
        "deload":      load_deload_state()
    })


@app.route("/api/log", methods=["POST"])
def api_log():
    """Log un exercice via POST JSON."""
    data     = request.json
    exercise = data.get("exercise")
    weight   = float(data.get("weight", 0))
    reps_str = data.get("reps", "")

    if not exercise or not reps_str:
        return jsonify({"error": "Données manquantes"}), 400

    weights   = load_weights()
    ex_data   = weights.get(exercise, {})
    today     = datetime.now().strftime("%Y-%m-%d")

    reps_list = parse_reps(reps_str)
    reps      = ",".join(map(str, reps_list))
    status    = progression_status(reps, exercise)
    increase  = should_increase(reps, exercise)
    new_w     = next_weight(exercise, weight) if increase else weight
    onerm     = estimate_1rm(weight, reps)

    history_entry = {
        "date":   today,
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

    # Vérifie objectifs
    achieved = check_goals_achieved(weights)

    return jsonify({
        "success":   True,
        "status":    status,
        "increase":  increase,
        "new_weight": new_w,
        "1rm":       onerm,
        "achieved":  achieved
    })


@app.route("/api/log_session", methods=["POST"])
def api_log_session():
    """Sauvegarde le RPE et commentaire d'une séance."""
    data    = request.json
    today   = datetime.now().strftime("%Y-%m-%d")
    rpe     = data.get("rpe")
    comment = data.get("comment", "")
    exos    = data.get("exos", [])

    log_session(today, rpe, comment, exos)
    return jsonify({"success": True})


@app.route("/api/body_weight", methods=["POST"])
def api_body_weight():
    """Log le poids corporel."""
    data  = request.json
    poids = float(data.get("poids", 0))
    note  = data.get("note", "")

    if not poids:
        return jsonify({"error": "Poids invalide"}), 400

    log_body_weight(poids, note)
    return jsonify({"success": True, "poids": poids})


@app.route("/api/weights")
def api_weights():
    """Retourne tous les poids."""
    return jsonify(load_weights())


@app.route("/api/inventory")
def api_inventory():
    """Retourne l'inventaire."""
    return jsonify(load_inventory())


@app.route("/api/sessions")
def api_sessions():
    """Retourne les sessions."""
    return jsonify(load_sessions())


@app.route("/api/deload")
def api_deload():
    """Analyse deload."""
    weights = load_weights()
    rapport = analyser_deload(weights)
    return jsonify(rapport)


# ─────────────────────────────────────────────────────────────
# LANCEMENT
# ─────────────────────────────────────────────────────────────

if __name__ == "__main__":
    print("\n💪 TrainingOS Web — http://localhost:5000\n")
    app.run(debug=True, host="0.0.0.0", port=5000)