import db
import uuid
from datetime import datetime


# ── Settings ─────────────────────────────────────────────────────────────────

def load_settings() -> dict:
    raw = db.get_nutrition_settings()
    if not isinstance(raw, dict):
        raw = {}
    # Normalize column names — table may use either FR or EN naming
    return {
        "limite_calories":    raw.get("limite_calories")    or raw.get("calorie_limit")    or 2200,
        "objectif_proteines": raw.get("objectif_proteines") or raw.get("protein_target")   or 160,
    }


def save_settings(limite_calories: int, objectif_proteines: int):
    db.update_nutrition_settings({
        "limite_calories":    limite_calories,
        "objectif_proteines": objectif_proteines,
    })


# ── Entries ───────────────────────────────────────────────────────────────────

def get_today_entries() -> list:
    today = datetime.now().strftime("%Y-%m-%d")
    return db.get_nutrition_entries(today)


def get_today_totals() -> dict:
    entries = get_today_entries()
    return {
        "calories":  round(sum(e.get("calories", 0) for e in entries)),
        "proteines": round(sum(e.get("proteines", 0) for e in entries), 1),
        "glucides":  round(sum(e.get("glucides",  0) for e in entries), 1),
        "lipides":   round(sum(e.get("lipides",   0) for e in entries), 1),
    }


def add_entry(nom: str, calories: float, proteines: float = 0,
              glucides: float = 0, lipides: float = 0) -> dict:
    today = datetime.now().strftime("%Y-%m-%d")
    entry = {
        "id":        str(uuid.uuid4())[:8],
        "date":      today,
        "nom":       nom,
        "calories":  round(calories),
        "proteines": round(proteines, 1),
        "glucides":  round(glucides,  1),
        "lipides":   round(lipides,   1),
        "heure":     datetime.now().strftime("%H:%M"),
    }
    return db.insert_nutrition_entry(entry)


def delete_entry(entry_id: str) -> bool:
    return db.delete_nutrition_entry(entry_id)


def get_recent_days(n: int = 7) -> list:
    return db.get_nutrition_entries_recent(n)
