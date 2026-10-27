import db
import uuid
from datetime import datetime, timezone, timedelta
from utils import _today_mtl


# ── Settings ─────────────────────────────────────────────────────────────────

def load_settings() -> dict:
    raw = db.get_nutrition_settings()
    if not isinstance(raw, dict):
        raw = {}

    dtt_raw = raw.get("day_type_targets") or {}
    if isinstance(dtt_raw, str):
        import json as _json
        try:    dtt_raw = _json.loads(dtt_raw)
        except Exception: dtt_raw = {}

    def _target(key: str, default_cal: int, default_gluc: int) -> dict:
        t = dtt_raw.get(key) or {}
        return {
            "calories": int(t.get("calories") or default_cal),
            "glucides": int(t.get("glucides") or default_gluc),
        }

    # Préférer calorie_target calculé par le moteur TDEE s'il est présent
    cal  = (raw.get("calorie_target")
            or raw.get("limite_calories")
            or raw.get("calorie_limit")
            or 2400)
    prot = (raw.get("objectif_proteines")
            or raw.get("protein_target")
            or 180)

    return {
        "limite_calories":    int(cal),
        "objectif_proteines": int(prot),
        "glucides":           raw.get("glucides") or 235,
        "lipides":            raw.get("lipides")  or 75,
        "bmr_kcal":           raw.get("bmr_kcal"),
        "tdee_kcal":          raw.get("tdee_kcal"),
        "activity_factor":    raw.get("activity_factor"),
        "formula_used":       raw.get("formula_used"),
        "goal_phase":         raw.get("goal_phase"),
        "day_type_targets": {
            "light":    _target("light",    2200, 185),
            "moderate": _target("moderate", 2400, 235),
            "heavy":    _target("heavy",    2550, 270),
            "rest":     _target("rest",     2100, 160),
        },
        "nutrition_end_time": str(raw.get("nutrition_end_time") or "")[:5] or None,
    }


def save_settings(objectif_proteines=None, nutrition_end_time: str | None = None):
    """Patch minimal : seuls les champs explicitement passés sont écrits.
    Les colonnes legacy (calorie_limit, glucides, lipides, day_type_targets,
    glucides_target, lipides_target) ne sont plus touchées par le handler —
    cible calorique = adaptative (compute_target_calories), macros glucides/
    lipides retirées du suivi. Phase 2 B2.1."""
    patch: dict = {}
    if objectif_proteines is not None:
        patch["protein_target"] = int(objectif_proteines)
    if nutrition_end_time is not None:
        patch["nutrition_end_time"] = nutrition_end_time
    if patch:
        db.update_nutrition_settings(patch)


_HEAVY_SESSIONS = frozenset({
    "legs", "legs a", "legs b", "lower", "lower a", "lower b",
    "squat", "deadlift", "rdl", "hip thrust",
    "quad", "hamstring", "glute", "hinge",
})
_LIGHT_SESSIONS = frozenset({
    "upper", "upper a", "upper b",
    "push", "push a", "push b",
    "pull", "pull a", "pull b",
    "chest", "bench", "shoulders", "overhead", "ohp",
    "arms", "bicep", "tricep", "back",
})
_REST_KEYWORDS = frozenset({
    "repos", "rest", "recovery",
    "yoga", "stretch", "stretching", "mobilité", "mobilite",
    "off", "cardio léger", "light cardio",
    "active recovery", "marche",
})


def _get_day_intensity(date: str | None = None, *, strict: bool = False) -> tuple[str, str]:
    """Nutrition's classifier, using actual session then active planning for date.

    Historical planning is the current active programme, not a versioned archive.
    Strict callers must never turn failed planning reads into a moderate target.
    """
    try:
        from planner import load_program, sessions_for_date, get_today_date

        target_date = date or get_today_date()
        actual = db.get_workout_session_by_type(target_date, "morning")
        program = load_program()
        if strict and not program:
            raise ValueError("Programme actif indisponible")
        session_name = (actual or {}).get("session_name") or sessions_for_date(target_date, program)[0]

        if not session_name:
            return "rest", ""

        name = session_name.lower()

        # Preserve Nutrition classification rules (distinct from morning_brief).
        if any(k in name for k in _HEAVY_SESSIONS):
            return "heavy", session_name
        if any(k in name for k in _LIGHT_SESSIONS):
            return "light", session_name
        if any(k in name for k in _REST_KEYWORDS):
            return "rest", session_name

        # Only use program membership as fallback for ambiguous names
        if session_name not in program:
            return "rest", session_name

        return "moderate", session_name
    except Exception:
        if strict:
            raise
        return "moderate", ""


def resolve_daily_target(date: str) -> dict:
    """Calories = cible adaptative unique (tdee.compute_target_calories).
    Protéines = objectif fixe (settings). Glucides/lipides retirés du retour
    (phase B2.3 : plus consommés par le client, le suivi macros a été coupé)."""
    import math
    from datetime import date as calendar_date

    if calendar_date.fromisoformat(date).isoformat() != date:
        raise ValueError("Date invalide")
    day_type, session = _get_day_intensity(date, strict=True)
    settings = db.get_nutrition_settings()
    if not isinstance(settings, dict):
        raise ValueError("Réglages nutrition indisponibles")

    prot_raw = settings.get("objectif_proteines") or settings.get("protein_target")
    try:
        prot = float(prot_raw)
    except (TypeError, ValueError):
        raise ValueError("Cibles nutrition non configurées")
    if not math.isfinite(prot) or prot <= 0:
        raise ValueError("Cibles nutrition invalides")

    from tdee import compute_target_calories
    adaptive_cal = compute_target_calories(date)
    if adaptive_cal is None:
        raise ValueError("Historique TDEE insuffisant (<7j) — cible adaptative indisponible")

    return {
        "date": date, "day_type": day_type, "workout_label": session,
        "calories": float(adaptive_cal),
        "proteines": prot,
    }


# ── Entries ───────────────────────────────────────────────────────────────────

def get_today_entries() -> list:
    today = _today_mtl()
    return db.get_nutrition_entries(today)


def get_today_totals() -> dict:
    entries = get_today_entries()
    return {
        "calories":  round(sum(e.get("calories", 0) for e in entries)),
        "proteines": round(sum(e.get("proteines", 0) for e in entries), 1),
        "glucides":  round(sum(e.get("glucides",  0) for e in entries), 1),
        "lipides":   round(sum(e.get("lipides",   0) for e in entries), 1),
    }


def add_entry(nom: str, calories: float, proteines: float = 0,
              glucides: float = 0, lipides: float = 0, meal_type: str = None,
              source: str = "manual", date: str | None = None,
              pct_calories_declared: float | None = None,
              pct_proteines_declared: float | None = None,
              target_calories_snapshot: int | None = None,
              target_proteines_snapshot: int | None = None) -> dict:
    now_mtl = datetime.now(timezone.utc)
    try:
        from zoneinfo import ZoneInfo
        now_mtl = datetime.now(ZoneInfo("America/Montreal"))
    except Exception:
        pass
    if calories == 0 and (proteines > 0 or glucides > 0 or lipides > 0):
        calories = proteines * 4 + glucides * 4 + lipides * 9
    entry = {
        "id":        str(uuid.uuid4()),
        "date":      date or _today_mtl(),
        "nom":       nom,
        "calories":  round(calories),
        "proteines": round(proteines, 1),
        "glucides":  round(glucides,  1),
        "lipides":   round(lipides,   1),
        "heure":     now_mtl.strftime("%H:%M"),
        "source":    source,
    }
    if meal_type:
        entry["meal_type"] = meal_type
    if pct_calories_declared is not None:
        entry["pct_calories_declared"] = float(pct_calories_declared)
    if pct_proteines_declared is not None:
        entry["pct_proteines_declared"] = float(pct_proteines_declared)
    if target_calories_snapshot is not None:
        entry["target_calories_snapshot"] = int(target_calories_snapshot)
    if target_proteines_snapshot is not None:
        entry["target_proteines_snapshot"] = int(target_proteines_snapshot)
    return db.insert_nutrition_entry(entry)


def delete_entry(entry_id: str) -> bool:
    return db.delete_nutrition_entry(entry_id)


def get_recent_days(n: int = 7) -> list:
    return db.get_nutrition_entries_recent(n)


# ── Retroactive estimate ─────────────────────────────────────────────────────

_ESTIMATE_MAX_PCT = 200  # borne haute permissive (surestimation possible)


def replace_day_with_estimate(pct_calories: float, pct_proteines: float, *,
                              date: str | None = None, calories=None, proteines=None) -> dict:
    """Keep replacement semantics; explicit-date clients persist their visible estimate.

    Legacy percentage-only clients resolve the recovered day's configured target.
    All validation precedes the existing delete/insert sequence.
    """
    for name, v in (("pct_calories", pct_calories), ("pct_proteines", pct_proteines)):
        if not (0 <= v <= _ESTIMATE_MAX_PCT):
            raise ValueError(f"{name} hors bornes [0, {_ESTIMATE_MAX_PCT}] : {v}")

    from datetime import date as _date, timedelta
    yesterday = (_date.fromisoformat(_today_mtl()) - timedelta(days=1)).isoformat()

    if date is not None:
        if not isinstance(date, str) or _date.fromisoformat(date).isoformat() != date or date > yesterday:
            raise ValueError("La date doit être une journée passée")
        yesterday = date
    # Snapshots : écrits seulement si la cible du jour est résolue ici
    # (branche implicite). En explicite, le client fournit cal/prot directs,
    # on ne peut pas inférer quelle cible il avait affichée → NULL.
    target_cal_snapshot: int | None = None
    target_prot_snapshot: int | None = None

    if calories is not None or proteines is not None:
        import math
        if date is None:
            raise ValueError("Date requise pour une estimation explicite")
        try:
            cal, prot = float(calories), float(proteines)
        except (TypeError, ValueError):
            raise ValueError("Estimation invalide")
        if not (math.isfinite(cal) and math.isfinite(prot) and 0 <= cal <= 100000 and 0 <= prot <= 10000):
            raise ValueError("Estimation hors bornes")
    else:
        target = resolve_daily_target(yesterday)
        cal = round(target["calories"] * pct_calories / 100)
        prot = round(target["proteines"] * pct_proteines / 100, 1)
        target_cal_snapshot = int(round(target["calories"]))
        target_prot_snapshot = int(round(target["proteines"]))

    # Conversion 0-100 → ratio 0-1 côté backend uniquement (contrat API inchangé).
    pct_cal_ratio  = float(pct_calories)  / 100.0
    pct_prot_ratio = float(pct_proteines) / 100.0

    if not db.delete_nutrition_entries_for_date(yesterday):
        raise ValueError(
            f"delete_nutrition_entries_for_date({yesterday}) a échoué — "
            "état inchangé, réessaie plus tard"
        )

    try:
        entry = add_entry(
            nom="Estimation rétroactive",
            calories=cal, proteines=prot,
            source="estimated_percent", date=yesterday,
            pct_calories_declared=pct_cal_ratio,
            pct_proteines_declared=pct_prot_ratio,
            target_calories_snapshot=target_cal_snapshot,
            target_proteines_snapshot=target_prot_snapshot,
        )
    except Exception as e:
        raise ValueError(
            f"delete OK mais insert échoué pour {yesterday} — journée à 0 : {e}"
        ) from e

    return {
        "date":      yesterday,
        "calories":  cal,
        "proteines": prot,
        "entry":     entry,
    }
