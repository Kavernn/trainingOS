import db
import uuid
from datetime import datetime, timezone, timedelta


def _today_mtl() -> str:
    """Return today's date in Montreal/Eastern timezone."""
    try:
        from zoneinfo import ZoneInfo
        return datetime.now(ZoneInfo("America/Montreal")).strftime("%Y-%m-%d")
    except Exception:
        pass
    try:
        import pytz
        return datetime.now(pytz.timezone("America/Montreal")).strftime("%Y-%m-%d")
    except Exception:
        pass
    # DST-aware fallback
    utc = datetime.now(timezone.utc)
    from datetime import timedelta as td
    def nth_sunday(y, m, n):
        first = datetime(y, m, 1)
        return first + td(days=(6 - first.weekday()) % 7 + 7 * (n - 1))
    y = utc.year
    dst_start = nth_sunday(y, 3,  2).replace(hour=7, tzinfo=timezone.utc)
    dst_end   = nth_sunday(y, 11, 1).replace(hour=6, tzinfo=timezone.utc)
    offset = -4 if dst_start <= utc < dst_end else -5
    return (utc + td(hours=offset)).strftime("%Y-%m-%d")


# ── Settings ─────────────────────────────────────────────────────────────────

def load_settings() -> dict:
    raw = db.get_nutrition_settings()
    if not isinstance(raw, dict):
        raw = {}
    # Normalize column names — table may use either FR or EN naming
    return {
        "limite_calories":    raw.get("limite_calories")    or raw.get("calorie_limit")    or 2200,
        "objectif_proteines": raw.get("objectif_proteines") or raw.get("protein_target")   or 160,
        "glucides":           raw.get("glucides") or 0,
        "lipides":            raw.get("lipides")  or 0,
    }


def save_settings(limite_calories: int, objectif_proteines: int,
                  glucides: float = 0, lipides: float = 0):
    db.update_nutrition_settings({
        "calorie_limit":  limite_calories,
        "protein_target": objectif_proteines,
        "glucides":       glucides,
        "lipides":        lipides,
    })


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
              source: str = "manual") -> dict:
    now_mtl = datetime.now(timezone.utc)
    try:
        from zoneinfo import ZoneInfo
        now_mtl = datetime.now(ZoneInfo("America/Montreal"))
    except Exception:
        pass
    entry = {
        "id":        str(uuid.uuid4())[:8],
        "date":      _today_mtl(),
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
