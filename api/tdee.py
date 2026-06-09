"""
tdee.py — Moteur BMR/TDEE + macros relatives au poids + diète adaptative.

BMR :
  Mifflin-St Jeor (Frankenfield et al. 2005) — données de base
  Katch-McArdle                               — si body_fat% disponible

Activité auto-calculée depuis workout_sessions (4 semaines) :
  0 séances/sem   → 1.200 (sédentaire)
  ≤2 séances/sem  → 1.375
  ≤4 séances/sem  → 1.550
  ≤6 séances/sem  → 1.725
  7+  séances/sem → 1.900

Macros relatives (Helms et al. 2014, Slater & Phillips 2011) :
  Protéines : 2.0 g/kg (maintien/cut/recomp) | 2.2 g/kg (bulk)
  Lipides   : 0.7 g/kg minimum physiologique
  Glucides  : reste calorique

Diète adaptative (Helms et al. 2014, Hall & Guo 2017) :
  Moving average 7j, ajustement ±150 kcal si hors cible ±0.25 kg/sem
"""
from __future__ import annotations

from typing import Optional
import db
from utils import _today_mtl

_LBS_TO_KG = 0.453592

_ACTIVITY_MAP = [
    (0.0,        1.200),
    (2.0,        1.375),
    (4.0,        1.550),
    (6.0,        1.725),
    (float("inf"), 1.900),
]


# ── Activité ──────────────────────────────────────────────────────────────────

def _sessions_per_week() -> float:
    """Séances complétées sur les 28 derniers jours → fréquence hebdo."""
    from datetime import date, timedelta
    sessions = db.get_workout_sessions(limit=28) or []
    cutoff   = (date.fromisoformat(_today_mtl()) - timedelta(days=28)).isoformat()
    recent   = [s for s in sessions if (s.get("date") or "") >= cutoff and s.get("completed")]
    return len(recent) / 4.0


def _activity_factor(sessions_per_week: float) -> float:
    for threshold, factor in _ACTIVITY_MAP:
        if sessions_per_week <= threshold:
            return factor
    return 1.900


# ── BMR ───────────────────────────────────────────────────────────────────────

def compute_bmr(weight_kg: float, height_cm: float, age: int,
                sex: str, body_fat_pct: Optional[float] = None) -> dict:
    """
    Retourne {bmr: int, formula_used: str}.
    Préfère Katch-McArdle si body_fat_pct est valide (5–50 %).
    """
    if body_fat_pct is not None and 5.0 <= float(body_fat_pct) <= 50.0:
        lbm = weight_kg * (1.0 - float(body_fat_pct) / 100.0)
        bmr = 370.0 + 21.6 * lbm
        return {"bmr": round(bmr), "formula_used": "katch_mcArdle"}

    # Mifflin-St Jeor
    bmr = 10.0 * weight_kg + 6.25 * height_cm - 5.0 * age
    bmr += 5.0 if sex.lower() in ("m", "male") else -161.0
    return {"bmr": round(bmr), "formula_used": "mifflin_st_jeor"}


# ── TDEE + macros ─────────────────────────────────────────────────────────────

def compute_tdee(profile: dict) -> dict:
    """
    Calcule TDEE complet depuis user_profile.
    Retourne dict prêt à merger dans nutrition_settings, ou {} si profil incomplet.
    """
    weight_lbs = profile.get("weight")
    weight_kg  = float(weight_lbs) * _LBS_TO_KG if weight_lbs else None
    height_cm  = float(profile.get("height") or 0) or None
    age        = int(profile.get("age") or 0) or None
    sex        = str(profile.get("sex") or "m")
    goal       = str(profile.get("goal") or "maintain")
    body_fat   = profile.get("body_fat")

    if not all([weight_kg, height_cm, age]):
        return {}

    spw      = _sessions_per_week()
    af       = _activity_factor(spw)
    bmr_data = compute_bmr(weight_kg, height_cm, age, sex, body_fat)
    bmr      = bmr_data["bmr"]
    tdee     = round(bmr * af)

    goal_adj = {"bulk": +300, "cut": -400, "recomp": -200, "maintain": 0}
    calorie_target = tdee + goal_adj.get(goal, 0)

    macros = compute_macro_targets(weight_kg, calorie_target, goal, body_fat)

    return {
        "bmr_kcal":          bmr,
        "tdee_kcal":         tdee,
        "activity_factor":   round(af, 3),
        "sessions_per_week": round(spw, 1),
        "formula_used":      bmr_data["formula_used"],
        "calorie_target":    calorie_target,
        "goal_phase":        goal,
        **macros,
    }


def compute_macro_targets(weight_kg: float, calorie_target: int,
                          goal: str = "maintain",
                          body_fat_pct: Optional[float] = None) -> dict:
    """
    Macros weight-relative.
    Protéines (Stokes et al. 2018, Helms et al. 2014) :
      Si body_fat valide (5–50%) → calcul sur LBM (plus précis pour les surpoids)
        bulk  : 2.4 g/kg LBM | autres : 2.2 g/kg LBM
      Sinon → poids total
        bulk  : 2.2 g/kg | autres : 2.0 g/kg
    Lipides   : max(0.7 g/kg, 20 % des calories)
    Glucides  : reste calorique
    """
    if body_fat_pct is not None and 5.0 <= float(body_fat_pct) <= 50.0:
        lbm_kg          = weight_kg * (1.0 - float(body_fat_pct) / 100.0)
        prot_factor     = 2.4 if goal == "bulk" else 2.2
        protein_g       = round(lbm_kg * prot_factor)
        protein_basis   = "lbm"
    else:
        lbm_kg          = None
        prot_factor     = 2.2 if goal == "bulk" else 2.0
        protein_g       = round(weight_kg * prot_factor)
        protein_basis   = "total_weight"

    fat_min_gkg = weight_kg * 0.7
    fat_min_cal = calorie_target * 0.20 / 9.0
    fat_g       = round(max(fat_min_gkg, fat_min_cal))
    remaining   = calorie_target - protein_g * 4 - fat_g * 9
    carbs_g     = round(max(0, remaining / 4))

    return {
        "objectif_proteines": protein_g,
        "lipides":            fat_g,
        "glucides":           carbs_g,
        "protein_g_per_kg":   prot_factor,
        "protein_basis":      protein_basis,
        "fat_g_per_kg":       round(fat_g / weight_kg, 2),
    }


def compute_dynamic_day_targets(weight_kg: float, tdee: int) -> dict:
    """Cibles caloriques + glucides par type de journée, relatives au poids."""
    return {
        "light":    {"calories": round(tdee * 0.90), "glucides": round(weight_kg * 2.5)},
        "moderate": {"calories": tdee,               "glucides": round(weight_kg * 3.5)},
        "heavy":    {"calories": round(tdee * 1.05), "glucides": round(weight_kg * 5.0)},
        "rest":     {"calories": round(tdee * 0.85), "glucides": round(weight_kg * 1.5)},
    }


# ── Diète adaptative ──────────────────────────────────────────────────────────

def check_weight_progress(goal: str, calorie_target: int) -> dict | None:
    """
    Évalue l'évolution du poids sur 14 jours (moving average 7j vs 7j précédents).
    Propose ±150 kcal si la progression s'écarte de ±0.25 kg/sem.
    Retourne None si données insuffisantes (<14 entrées).

    Références : Helms et al. 2014 ; Hall & Guo 2017.
    """
    from datetime import date, timedelta

    logs = db.get_body_weight_logs(limit=21) or []
    if len(logs) < 14:
        return None

    sorted_logs = sorted(logs, key=lambda x: x.get("date", ""))
    recent_7 = [float(x["weight"]) for x in sorted_logs[-7:] if x.get("weight")]
    prev_7   = [float(x["weight"]) for x in sorted_logs[-14:-7] if x.get("weight")]

    if len(recent_7) < 5 or len(prev_7) < 5:
        return None

    avg_recent = sum(recent_7) / len(recent_7)
    avg_prev   = sum(prev_7)   / len(prev_7)
    delta_kg   = (avg_recent - avg_prev) * _LBS_TO_KG

    if goal == "bulk":
        if delta_kg < 0.25:
            return {"adjust_kcal": +150, "delta_kg_per_week": round(delta_kg, 2),
                    "reason": f"Prise de masse stagnante ({delta_kg:+.2f} kg/sem — cible ≥ +0.25)"}
        if delta_kg > 1.0:
            return {"adjust_kcal": -150, "delta_kg_per_week": round(delta_kg, 2),
                    "reason": f"Progression trop rapide ({delta_kg:+.2f} kg/sem — risque prise grasse)"}

    if goal == "cut":
        if delta_kg > -0.25:
            return {"adjust_kcal": -150, "delta_kg_per_week": round(delta_kg, 2),
                    "reason": f"Perte trop lente ({delta_kg:+.2f} kg/sem — cible ≤ -0.25)"}
        if delta_kg < -1.0:
            return {"adjust_kcal": +150, "delta_kg_per_week": round(delta_kg, 2),
                    "reason": f"Perte trop rapide ({delta_kg:+.2f} kg/sem — risque perte musculaire)"}

    return {"adjust_kcal": 0, "delta_kg_per_week": round(delta_kg, 2),
            "reason": "Progression conforme à l'objectif"}


# ── Réalisme des objectifs ────────────────────────────────────────────────────

# Bornes physiologiques (natty, intermédiaire) — Helms et al. 2014 ; Hall & Guo 2017
_GOAL_LIMITS = {
    # (surplus_kcal_min, surplus_kcal_max, gain_lbs_month_max)
    "bulk":    (200,  500, 2.0),
    # (deficit_kcal_min, deficit_kcal_max, loss_lbs_month_max)
    "cut":     (300,  750, 4.0),
    # recomp : léger déficit — pas de borne dure sur la balance
    "recomp":  (-200, 0,   None),
    "maintain": (0,   0,   None),
}


def check_goal_realism(profile: dict, tdee_data: dict) -> dict:
    """
    Vérifie que l'objectif et le surplus/déficit calorique restent dans les
    limites physiologiques natty (Helms et al. 2014).

    Retourne :
      {
        "ok":       bool,
        "warnings": [str],   # liste vide si tout est OK
        "limits":   dict,    # surplus/déficit recommandés
      }

    Références :
      Gain masse maigre : 0.5–2 lbs/mois (natty intermédiaire) → surplus ≤ 500 kcal
      Perte grasse saine : 0.5–1% BF/mois → déficit 300–750 kcal (≤ 1 kg/sem)
      Déficit > 750 kcal → risque catabolisme musculaire (Helms et al. 2014)
      Surplus > 500 kcal → risque prise de gras excessive (Hall & Guo 2017)
    """
    goal           = str(profile.get("goal") or "maintain")
    calorie_target = int(tdee_data.get("calorie_target") or 0)
    tdee_kcal      = int(tdee_data.get("tdee_kcal") or 0)
    warnings: list[str] = []

    if tdee_kcal <= 0:
        return {"ok": True, "warnings": [], "limits": {}}

    delta = calorie_target - tdee_kcal  # positif = surplus, négatif = déficit

    if goal == "bulk":
        surplus_min, surplus_max, _ = _GOAL_LIMITS["bulk"]
        if delta < surplus_min:
            warnings.append(
                f"Surplus trop faible ({delta:+d} kcal) — vise +{surplus_min}–{surplus_max} kcal "
                f"pour maximiser la prise de masse maigre (Helms et al. 2014)."
            )
        elif delta > surplus_max:
            warnings.append(
                f"Surplus excessif ({delta:+d} kcal > +{surplus_max} kcal) — "
                f"au-delà de +{surplus_max} kcal le gain supplémentaire est majoritairement du gras "
                f"(Hall & Guo 2017). Réduis à +{surplus_min}–{surplus_max} kcal."
            )

    elif goal == "cut":
        deficit_min, deficit_max, _ = _GOAL_LIMITS["cut"]
        deficit_abs = abs(delta)
        if deficit_abs < deficit_min:
            warnings.append(
                f"Déficit trop faible ({delta:+d} kcal) — vise −{deficit_min}–{deficit_max} kcal "
                f"pour une perte de gras efficace sans perte musculaire (Helms et al. 2014)."
            )
        elif deficit_abs > deficit_max:
            warnings.append(
                f"Déficit excessif ({delta:+d} kcal < −{deficit_max} kcal) — "
                f"risque de catabolisme musculaire au-delà de −{deficit_max} kcal/j "
                f"(Helms et al. 2014). Remonte à −{deficit_min}–{deficit_max} kcal."
            )

    elif goal == "recomp":
        if delta > 0:
            warnings.append(
                f"Recomposition : surplus détecté ({delta:+d} kcal). "
                f"Vise un léger déficit (−100 à −200 kcal) pour optimiser le ratio perte/gain."
            )
        elif delta < -300:
            warnings.append(
                f"Recomposition : déficit trop marqué ({delta:+d} kcal). "
                f"Limite à −200 kcal pour préserver la synthèse musculaire."
            )

    limits = {
        "bulk":    {"surplus_min": 200,  "surplus_max": 500},
        "cut":     {"deficit_min": 300,  "deficit_max": 750},
        "recomp":  {"deficit_min": 100,  "deficit_max": 200},
        "maintain": {},
    }.get(goal, {})

    return {"ok": len(warnings) == 0, "warnings": warnings, "limits": limits}
