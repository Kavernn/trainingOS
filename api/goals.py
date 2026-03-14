import db


def load_goals() -> dict:
    try:
        result = db.get_goals()
        if isinstance(result, dict):
            return result
    except Exception:
        pass
    return db.get_json("goals", {}) or {}


def set_goal(exercise: str, weight: float, deadline=None, note: str = ""):
    # Try domain method
    try:
        db.set_goal(exercise, weight, target_date=deadline)
    except Exception:
        pass
    # Always persist to KV for consistency
    goals = db.get_json("goals", {}) or {}
    goals[exercise] = {
        "goal_weight": weight,
        "deadline":    deadline,
        "note":        note,
        "achieved":    False
    }
    db.set_json("goals", goals)


def check_goals_achieved(weights: dict) -> list:
    goals    = load_goals()
    achieved = []
    updated  = False
    for ex, goal in goals.items():
        if not isinstance(goal, dict):
            continue
        if goal.get("achieved"):
            continue
        current = weights.get(ex, {}).get("current_weight", 0) or 0
        if current >= goal["goal_weight"]:
            goals[ex]["achieved"] = True
            achieved.append(ex)
            updated = True
    if updated:
        db.set_json("goals", goals)
    return achieved


def get_progress_bar(current: float, goal: float) -> float:
    return min(current / goal * 100, 100) if goal else 0


def gerer_objectifs(weights): pass
def afficher_objectifs():     pass
