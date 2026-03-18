import db


def load_goals() -> dict:
    result = db.get_goals()
    return result if isinstance(result, dict) else {}


def set_goal(exercise: str, weight: float, deadline=None, note: str = ""):
    db.set_goal(exercise, weight, target_date=deadline)


def check_goals_achieved(weights: dict) -> list:
    goals    = load_goals()
    achieved = []
    for ex, goal in goals.items():
        if not isinstance(goal, dict):
            continue
        current = weights.get(ex, {}).get("current_weight", 0) or 0
        if current >= (goal.get("goal_weight") or goal.get("target_weight") or 0):
            achieved.append(ex)
    return achieved


def get_progress_bar(current: float, goal: float) -> float:
    return min(current / goal * 100, 100) if goal else 0


def gerer_objectifs(weights): pass
def afficher_objectifs():     pass
