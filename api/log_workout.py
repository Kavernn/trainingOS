from db import get_json, set_json, append_json_list
from datetime import datetime

def load_weights() -> dict:
    return get_json("weights", {})

def save_weights(weights: dict):
    set_json("weights", weights)

def log_single_exercise(exercise, weight, reps, note="", one_rm=0):
    weights = load_weights()
    if exercise not in weights:
        weights[exercise] = {"history": [], "current_weight": 0}
    entry = {
        "date":   datetime.now().strftime("%Y-%m-%d"),
        "weight": weight,
        "reps":   reps,
        "note":   note,
        "1rm":    one_rm
    }
    weights[exercise].setdefault("history", []).insert(0, entry)
    weights[exercise]["history"]        = weights[exercise]["history"][:20]
    weights[exercise]["current_weight"] = weight
    weights[exercise]["last_reps"]      = reps
    save_weights(weights)

def show_exercise_history(exercise): pass
def log_hiit_session(*a, **k):       pass
def show_hiit_history():             pass