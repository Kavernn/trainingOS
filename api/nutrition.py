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


def save_settings(limite_calories: int, objectif_proteines: int,
                  glucides: float = 235, lipides: float = 75,
                  day_type_targets: dict | None = None,
                  nutrition_end_time: str | None = None):
    patch: dict = {
        "calorie_limit":   limite_calories,
        "protein_target":  objectif_proteines,
        "glucides":        glucides,
        "lipides":         lipides,
        "glucides_target": int(glucides),
        "lipides_target":  int(lipides),
    }
    if day_type_targets is not None:
        patch["day_type_targets"] = day_type_targets
    if nutrition_end_time is not None:
        patch["nutrition_end_time"] = nutrition_end_time
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


def _get_day_intensity() -> tuple[str, str]:
    """Return (intensity, session_name).

    Intensity: 'light' | 'moderate' | 'heavy' | 'rest'.
    Session name: actual session started today, or today's scheduled session.
    Order: pattern match first, then program membership for rest detection.
    """
    try:
        from planner import load_program, get_today, get_today_date

        # Prefer the session actually started today over the schedule
        actual = db.get_workout_session_by_type(get_today_date(), "morning")
        session_name = (actual or {}).get("session_name") or get_today()

        if not session_name:
            return "rest", ""

        name = session_name.lower()

        # Pattern match first — before any program lookup
        if any(k in name for k in _HEAVY_SESSIONS):
            return "heavy", session_name
        if any(k in name for k in _LIGHT_SESSIONS):
            return "light", session_name
        if any(k in name for k in _REST_KEYWORDS):
            return "rest", session_name

        # Only use program membership as fallback for ambiguous names
        program = load_program()
        if session_name not in program:
            return "rest", session_name

        return "moderate", session_name
    except Exception:
        return "moderate", ""


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
              source: str = "manual", date: str | None = None) -> dict:
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
    return db.insert_nutrition_entry(entry)


def delete_entry(entry_id: str) -> bool:
    return db.delete_nutrition_entry(entry_id)


def get_recent_days(n: int = 7) -> list:
    return db.get_nutrition_entries_recent(n)


# ── Retroactive estimate ─────────────────────────────────────────────────────

_ESTIMATE_MAX_PCT = 200  # borne haute permissive (surestimation possible)


def replace_day_with_estimate(pct_calories: float, pct_proteines: float) -> dict:
    """Remplace le total nutrition de la VEILLE (MTL) par une estimation en %
    des cibles courantes. Delete-all-yesterday PUIS insert, bundlé côté domaine.

    Fail loud :
      - pct hors [0, _ESTIMATE_MAX_PCT] → ValueError.
      - delete échoue → ValueError, aucun insert, état inchangé.
      - insert échoue après delete réussi → ValueError explicite,
        journée à 0 et le caller doit le savoir.
    """
    for name, v in (("pct_calories", pct_calories), ("pct_proteines", pct_proteines)):
        if not (0 <= v <= _ESTIMATE_MAX_PCT):
            raise ValueError(f"{name} hors bornes [0, {_ESTIMATE_MAX_PCT}] : {v}")

    from datetime import date as _date, timedelta
    yesterday = (_date.fromisoformat(_today_mtl()) - timedelta(days=1)).isoformat()

    settings    = load_settings()
    cal_target  = settings["limite_calories"]
    prot_target = settings["objectif_proteines"]
    cal  = round(cal_target  * pct_calories  / 100)
    prot = round(prot_target * pct_proteines / 100, 1)

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
