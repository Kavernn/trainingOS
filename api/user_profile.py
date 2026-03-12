from db import get_json, set_json

def load_user_profile() -> dict:
    return get_json("user_profile", {}) or {}

def save_user_profile(data: dict) -> bool:
    return set_json("user_profile", data)

def setup_user_profile(): pass