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
                    neck_cm: float = None, arms_cm: float = None, chest_cm: float = None,
                    thighs_cm: float = None, hips_cm: float = None):
    today = datetime.now().strftime("%Y-%m-%d")
    db.upsert_body_weight(
        today, poids,
        note=note or "",
        body_fat=body_fat,
        waist_cm=waist_cm,
        neck_cm=neck_cm,
        arms_cm=arms_cm,
        chest_cm=chest_cm,
        thighs_cm=thighs_cm,
        hips_cm=hips_cm,
    )


def get_tendance(body_weight: list) -> str:
    # body_weight est ordonné du plus récent au plus ancien
    entries = [e for e in body_weight if e.get("poids") is not None]
    if len(entries) < 2:
        return "Pas assez de données"

    recent7 = entries[:7]
    older7  = entries[7:14]

    avg_recent = sum(e["poids"] for e in recent7) / len(recent7)

    if not older7:
        return "→ Stable"

    avg_older = sum(e["poids"] for e in older7) / len(older7)
    diff = avg_recent - avg_older

    if diff > 0.5:   return f"↑ +{diff:.1f} lbs"
    if diff < -0.5:  return f"↓ {diff:.1f} lbs"
    return "→ Stable"


def afficher_historique_poids(): pass
