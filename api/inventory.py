import db


def load_inventory() -> dict:
    """Returns {name: {type, default_scheme, increment, bar_weight, ...}}

    Source unique : table Supabase `exercises`.
    Le KV "inventory" n'est plus utilisé — il était une béquille de migration.
    """
    try:
        result = db.get_exercises()
        if isinstance(result, dict):
            return result
    except Exception:
        pass
    return {}


def save_inventory(inv: dict) -> bool:
    """Persist the full inventory dict to the exercises table (source unique)."""
    success = True
    try:
        for name, info in inv.items():
            if isinstance(info, dict):
                db.upsert_exercise({**info, "name": name})
        # Delete exercises removed from inv
        try:
            current = db.get_exercises()
            if isinstance(current, dict):
                for name in list(current.keys()):
                    if name not in inv:
                        db.delete_exercise_by_name(name)
        except Exception:
            pass
    except Exception:
        success = False
    return success


def rename_inventory_exercise(old_name: str, new_name: str, info: dict = None):
    """Rename an exercise in the Supabase exercises table.
    If old_name doesn't exist yet (never upserted), insert new_name directly.
    """
    renamed = db.rename_exercise_table(old_name, new_name)
    if not renamed:
        # old_name not in Supabase — upsert new_name directly
        entry = info or {"type": "machine", "increment": 5, "default_scheme": "3x8-12"}
        db.upsert_exercise({**entry, "name": new_name})


def add_exercise(name: str, info: dict):
    """Insert or update an exercise in the Supabase exercises table."""
    db.upsert_exercise({**info, "name": name})


def calculate_plates(total: float, bar: float = 45.0) -> list:
    if total <= bar:
        return []
    side   = (total - bar) / 2
    plates = [45, 35, 25, 10, 5, 2.5]
    result = []
    temp   = round(float(side), 2)
    for p in plates:
        while temp >= p:
            result.append(p)
            temp = round(temp - p, 2)
    return result
