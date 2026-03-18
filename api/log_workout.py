import db
from datetime import datetime

def log_single_exercise(exercise, weight, reps, note="", one_rm=0):
    today = datetime.now().strftime("%Y-%m-%d")
    db.get_or_create_workout_session(today)
    db.upsert_exercise_log(today, exercise, weight, str(reps))

def show_exercise_history(exercise): pass
def log_hiit_session(*a, **k):       pass
def show_hiit_history():             pass
