from db import get_json, set_json
from datetime import datetime
import uuid


def load_nutrition_log() -> dict:
    return get_json("nutrition_log", {})


def load_settings() -> dict:
    return get_json("nutrition_settings", {
        "limite_calories": 2200,
        "objectif_proteines": 160
    })


def save_settings(limite_calories: int, objectif_proteines: int):
    set_json("nutrition_settings", {
        "limite_calories": limite_calories,
        "objectif_proteines": objectif_proteines
    })


def get_today_entries() -> list:
    today = datetime.now().strftime("%Y-%m-%d")
    log = load_nutrition_log()
    return log.get(today, {}).get("entries", [])


def get_today_totals() -> dict:
    entries = get_today_entries()
    return {
        "calories":  round(sum(e.get("calories", 0) for e in entries)),
        "proteines": round(sum(e.get("proteines", 0) for e in entries), 1),
        "glucides":  round(sum(e.get("glucides", 0) for e in entries), 1),
        "lipides":   round(sum(e.get("lipides", 0) for e in entries), 1),
    }


def add_entry(nom: str, calories: float, proteines: float = 0,
              glucides: float = 0, lipides: float = 0) -> dict:
    today = datetime.now().strftime("%Y-%m-%d")
    log = load_nutrition_log()
    if today not in log:
        log[today] = {"entries": []}
    entry = {
        "id":        str(uuid.uuid4())[:8],
        "nom":       nom,
        "calories":  round(calories),
        "proteines": round(proteines, 1),
        "glucides":  round(glucides, 1),
        "lipides":   round(lipides, 1),
        "heure":     datetime.now().strftime("%H:%M")
    }
    log[today]["entries"].append(entry)
    set_json("nutrition_log", log)
    return entry


def delete_entry(entry_id: str) -> bool:
    today = datetime.now().strftime("%Y-%m-%d")
    log = load_nutrition_log()
    if today not in log:
        return False
    before = len(log[today]["entries"])
    log[today]["entries"] = [e for e in log[today]["entries"] if e["id"] != entry_id]
    if len(log[today]["entries"]) < before:
        set_json("nutrition_log", log)
        return True
    return False


def get_recent_days(n: int = 7) -> list:
    log = load_nutrition_log()
    days = sorted(log.keys(), reverse=True)[:n]
    result = []
    for day in days:
        entries = log[day].get("entries", [])
        total_cal = round(sum(e.get("calories", 0) for e in entries))
        result.append({"date": day, "calories": total_cal, "nb": len(entries)})
    return result
