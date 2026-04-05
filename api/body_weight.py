import db
from datetime import datetime


def load_body_weight() -> list:
    result = db.get_body_weight_logs()
    if not isinstance(result, list):
        return []
    # Normalize 'weight' → 'poids' to match iOS CodingKey and get_tendance()
    normalized = []
    for row in result:
        if isinstance(row, dict):
            entry = dict(row)
            if "weight" in entry and "poids" not in entry:
                entry["poids"] = entry.pop("weight")
            normalized.append(entry)
    return normalized


def log_body_weight(poids: float, note: str = "", body_fat: float = None, waist_cm: float = None,
                    arms_cm: float = None, chest_cm: float = None,
                    thighs_cm: float = None, hips_cm: float = None):
    today = datetime.now().strftime("%Y-%m-%d")
    db.upsert_body_weight(
        today, poids,
        note=note or "",
        body_fat=body_fat,
        waist_cm=waist_cm,
        arms_cm=arms_cm,
        chest_cm=chest_cm,
        thighs_cm=thighs_cm,
        hips_cm=hips_cm,
    )


def get_tendance(body_weight: list) -> str:
    if len(body_weight) < 2:
        return "Pas assez de données"
    # Filter out likely lbs entries (>150 when profile uses kg)
    kg_entries = [e for e in body_weight if e.get("poids", 0) <= 150]
    if len(kg_entries) < 2:
        return "Pas assez de données"
    recent = kg_entries[:3]
    older  = kg_entries[3:6]
    if not older:
        return "Pas assez de données"
    avg_r = sum(e["poids"] for e in recent) / len(recent)
    avg_o = sum(e["poids"] for e in older)  / len(older)
    diff  = avg_r - avg_o
    if diff > 0.3:  return f"↑ +{diff:.1f} kg"
    if diff < -0.3: return f"↓ {diff:.1f} kg"
    return "→ Stable"


def afficher_historique_poids(): pass
