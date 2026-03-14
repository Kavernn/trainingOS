import db


def load_user_profile() -> dict:
    try:
        result = db.get_profile()
        if isinstance(result, dict) and result:
            return result
    except Exception:
        pass
    return db.get_json("user_profile", {}) or {}


def save_user_profile(data: dict) -> bool:
    # Try domain method
    try:
        db.update_profile(data)
    except Exception:
        pass
    # Always persist to KV
    return db.set_json("user_profile", data)


def setup_user_profile(): pass
