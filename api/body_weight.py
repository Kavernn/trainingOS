import db
import math
from datetime import datetime
from typing import Optional
from utils import _now_mtl


def compute_navy_bf(
    waist_cm: float,
    neck_cm: float,
    height_cm: float,
    sex: str,
    hips_cm: Optional[float] = None,
) -> Optional[float]:
    """US Navy body fat formula (Hodgdon & Beckett 1984).

    Men:   %BF = 86.010 × log10(waist - neck) - 70.041 × log10(height) + 36.76
    Women: %BF = 163.205 × log10(waist + hips - neck) - 97.684 × log10(height) - 78.387

    All measurements in cm. Returns None if measurements are invalid or insufficient.
    """
    try:
        if sex.lower() in ("m", "male"):
            diff = waist_cm - neck_cm
            if diff <= 0 or height_cm <= 0:
                return None
            bf = 86.010 * math.log10(diff) - 70.041 * math.log10(height_cm) + 36.76
        else:
            if not hips_cm:
                return None
            diff = waist_cm + hips_cm - neck_cm
            if diff <= 0 or height_cm <= 0:
                return None
            bf = 163.205 * math.log10(diff) - 97.684 * math.log10(height_cm) - 78.387
        return round(max(3.0, min(50.0, bf)), 1)
    except (ValueError, ZeroDivisionError):
        return None


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
    today = _now_mtl().strftime("%Y-%m-%d")

    # Auto-calculate body fat via Navy formula when measurements present but BF not provided
    if body_fat is None and waist_cm and neck_cm:
        profile   = db.get_profile() or {}
        height_cm = float(profile.get("height") or 0) or None
        sex       = str(profile.get("sex") or "m")
        if height_cm:
            body_fat = compute_navy_bf(waist_cm, neck_cm, height_cm, sex, hips_cm)

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
