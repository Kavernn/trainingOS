from db import get_json, set_json

def load_goals() -> dict:
    return get_json("goals", {})

def set_goal(exercise: str, weight: float, deadline=None, note: str = ""):
    goals              = load_goals()
    goals[exercise]    = {
        "goal_weight": weight,
        "deadline":    deadline,
        "note":        note,
        "achieved":    False
    }
    set_json("goals", goals)

def check_goals_achieved(weights: dict) -> list:
    goals    = load_goals()
    achieved = []
    updated  = False
    for ex, goal in goals.items():
        if goal.get("achieved"):
            continue
        current = weights.get(ex, {}).get("current_weight", 0) or 0
        if current >= goal["goal_weight"]:
            goals[ex]["achieved"] = True
            achieved.append(ex)
            updated = True
    if updated:
        set_json("goals", goals)
    return achieved

def get_progress_bar(current: float, goal: float) -> float:
    return min(current / goal * 100, 100) if goal else 0

def gerer_objectifs(weights): pass
def afficher_objectifs():     pass