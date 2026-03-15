import db


def load_inventory() -> dict:
    """Returns {name: {type, default_scheme, increment, bar_weight, ...}}

    Merges the relational exercises table (ExerciseDB) with the KV 'inventory'
    key (custom/user exercises). KV takes precedence so renamed or user-added
    exercises are always visible even if the relational upsert failed.
    """
    result = {}
    try:
        rel = db.get_exercises()
        if isinstance(rel, dict):
            result.update(rel)
    except Exception:
        pass
    try:
        kv = db.get_json("inventory", {}) or {}
        if isinstance(kv, dict):
            result.update(kv)   # KV overrides — has the freshest custom data
    except Exception:
        pass
    return result


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


def rename_inventory_exercise(old_name: str, new_name: str, info: dict = None):
    """Rename an exercise in both the relational table and the KV store."""
    # Relational: targeted rename (no full upsert)
    try:
        db.rename_exercise_table(old_name, new_name)
    except Exception:
        pass
    # KV: load, rename key, save
    inv = db.get_json("inventory", {}) or {}
    if old_name in inv:
        inv[new_name] = info if info is not None else inv.pop(old_name)
        if old_name in inv:
            del inv[old_name]
    elif new_name not in inv:
        inv[new_name] = info or {"type": "machine", "increment": 5, "default_scheme": "3x8-12"}
    db.set_json("inventory", inv)


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
