import db


def load_inventory() -> dict:
    """Returns {name: {type, default_scheme, increment, bar_weight, ...}}"""
    try:
        result = db.get_exercises()
        if isinstance(result, dict) and result:
            return result
    except Exception:
        pass
    return db.get_json("inventory", {}) or {}


def save_inventory(inv: dict) -> bool:
    """Persist the full inventory dict.

    Upserts all exercises in inv to the exercises table and also persists to
    KV so that delete operations (which remove a key from inv before calling
    this) are reflected in the in-memory store used by tests.
    """
    success = True
    try:
        # Upsert each entry to the relational table
        for name, info in inv.items():
            if isinstance(info, dict):
                db.upsert_exercise({**info, "name": name})
        # Also detect and delete exercises that are no longer in inv
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

    # Always sync to KV so that the in-memory test store stays consistent
    # and offline/KV-fallback mode also works.
    try:
        db.set_json("inventory", inv)
    except Exception:
        success = False

    return success


def add_exercise(name: str, info: dict):
    try:
        db.upsert_exercise({**info, "name": name})
    except Exception:
        pass
    # Also update KV
    inv = db.get_json("inventory", {}) or {}
    inv[name] = info
    db.set_json("inventory", inv)


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
