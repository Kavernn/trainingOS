from db import get_json, set_json

def load_inventory() -> dict:
    return get_json("inventory", {})

def save_inventory(inv: dict) -> bool:
    return set_json("inventory", inv)

def add_exercise(name: str, info: dict):
    inv      = load_inventory()
    inv[name] = info
    save_inventory(inv)

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