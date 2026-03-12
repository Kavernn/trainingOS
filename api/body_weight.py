from db import get_json, set_json
from datetime import datetime

def load_body_weight() -> list:
    return get_json("body_weight", [])

def log_body_weight(poids: float, note: str = "", body_fat: float = None, waist_cm: float = None,
                    arms_cm: float = None, chest_cm: float = None,
                    thighs_cm: float = None, hips_cm: float = None):
    data  = load_body_weight()
    entry = {
        "date":  datetime.now().strftime("%Y-%m-%d"),
        "poids": poids,
        "note":  note
    }
    for key, val in [("body_fat", body_fat), ("waist_cm", waist_cm),
                     ("arms_cm", arms_cm), ("chest_cm", chest_cm),
                     ("thighs_cm", thighs_cm), ("hips_cm", hips_cm)]:
        if val is not None:
            entry[key] = val
    data.insert(0, entry)
    set_json("body_weight", data)

def get_tendance(body_weight: list) -> str:
    if len(body_weight) < 2:
        return "Pas assez de données"
    recent = body_weight[:3]
    older  = body_weight[3:6]
    if not older:
        return "Pas assez de données"
    avg_r = sum(e["poids"] for e in recent) / len(recent)
    avg_o = sum(e["poids"] for e in older)  / len(older)
    diff  = avg_r - avg_o
    if diff > 0.3:  return f"↑ +{diff:.1f} kg"
    if diff < -0.3: return f"↓ {diff:.1f} kg"
    return "→ Stable"

def afficher_historique_poids(): pass