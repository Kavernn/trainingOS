import db


def load_user_profile() -> dict:
    result = db.get_profile()
    return result if isinstance(result, dict) and result else {}


def save_user_profile(data: dict) -> bool:
    return db.update_profile(data)


def setup_user_profile(): pass
