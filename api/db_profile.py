from __future__ import annotations
import json
import logging
from typing import Dict, List, Optional
import db_core
from utils import _today_mtl


def get_profile() -> dict:
    """Return the single user_profile row as a dict."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return {}

    def _do() -> dict:
        resp = (
            db_core._client.table("user_profile")
            .select("*")
            .eq("id", 1)
            .limit(1)
            .execute()
        )
        return (resp.data[0] if resp and resp.data else None) or {}

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.warning("get_profile retry error: %s", e2)
                return {}
        db_core.logger.warning("get_profile error: %s", e)
        return {}


def update_profile(patch: dict) -> bool:
    """Update the user profile. Creates the row if it does not yet exist."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        payload = {**patch, "id": 1, "updated_at": db_core._now_iso()}
        resp = (
            db_core._client.table("user_profile")
            .upsert(payload, on_conflict="id")
            .execute()
        )
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("update_profile retry error: %s", e2)
                return False
        db_core.logger.error("update_profile error: %s", e)
        return False


def get_coach_memory() -> list:
    """Return the coach memory entries stored in user_profile."""
    profile = get_profile()
    raw = profile.get("coach_memory")
    if isinstance(raw, list):
        return raw
    if isinstance(raw, str):
        try:
            return json.loads(raw)
        except Exception:
            pass
    return []


def save_coach_memory(entries: list) -> bool:
    """Persist coach memory entries into user_profile.coach_memory."""
    return update_profile({"coach_memory": entries})


# ---------------------------------------------------------------------------
# Nutrition
# ---------------------------------------------------------------------------

def get_nutrition_settings() -> dict:
    """Return nutrition settings (single row, Supabase only)."""
    _default = {"calorie_limit": 2000, "protein_target": 150}
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return _default

    def _do() -> dict:
        resp = (
            db_core._client.table("nutrition_settings")
            .select("*")
            .eq("id", 1)
            .limit(1)
            .execute()
        )
        return (resp.data[0] if resp and resp.data else None) or _default

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.warning("get_nutrition_settings retry error: %s", e2)
                return _default
        db_core.logger.warning("get_nutrition_settings error: %s", e)
        return _default


def update_nutrition_settings(patch: dict) -> bool:
    """Update nutrition settings row (Supabase only)."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        raise RuntimeError("Supabase client not available")

    def _do() -> bool:
        payload = {**patch, "id": 1, "updated_at": db_core._now_iso()}
        resp = (
            db_core._client.table("nutrition_settings")
            .upsert(payload, on_conflict="id")
            .execute()
        )
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("update_nutrition_settings retry error: %s", e2)
                return False
        db_core.logger.error("update_nutrition_settings error: %s", e)
        return False


# ---------------------------------------------------------------------------
# Nutrition entries
# ---------------------------------------------------------------------------

def get_nutrition_entries(date: str) -> List[dict]:
    """Return nutrition entries for a specific date, ordered by insertion time."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        resp = (
            db_core._client.table("nutrition_entries")
            .select("id,date,nom,calories,proteines,glucides,lipides,heure")
            .eq("date", date)
            .order("heure")
            .execute()
        )
        return resp.data or []

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_nutrition_entries retry error: %s", e2)
                return []
        db_core.logger.error("get_nutrition_entries error: %s", e)
        return []


def get_nutrition_entries_recent(n: int = 7) -> List[dict]:
    """Return one summary row per day for the last n distinct days.

    Returns [{"date": ..., "calories": ..., "proteines": ..., "glucides": ..., "lipides": ..., "nb": ...}, ...] newest first.
    """
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        from datetime import date as _date, timedelta
        cutoff = (_date.fromisoformat(_today_mtl()) - timedelta(days=n * 2)).isoformat()
        resp = (
            db_core._client.table("nutrition_entries")
            .select("date, calories, proteines, glucides, lipides")
            .gte("date", cutoff)
            .order("date", desc=True)
            .execute()
        )
        rows = resp.data or []
        # Group by date, keep only n distinct days
        seen: dict = {}
        for row in rows:
            d = row["date"]
            if d not in seen:
                seen[d] = {"date": d, "calories": 0, "proteines": 0.0, "glucides": 0.0, "lipides": 0.0, "nb": 0}
            seen[d]["calories"]  += row.get("calories", 0)
            seen[d]["proteines"] += row.get("proteines", 0)
            seen[d]["glucides"]  += row.get("glucides", 0)
            seen[d]["lipides"]   += row.get("lipides", 0)
            seen[d]["nb"] += 1
        sorted_days = sorted(seen.values(), key=lambda x: x["date"], reverse=True)[:n]
        for day in sorted_days:
            day["calories"]  = round(day["calories"])
            day["proteines"] = round(day["proteines"], 1)
            day["glucides"]  = round(day["glucides"], 1)
            day["lipides"]   = round(day["lipides"], 1)
        return sorted_days

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_nutrition_entries_recent retry error: %s", e2)
                return []
        db_core.logger.error("get_nutrition_entries_recent error: %s", e)
        return []


def insert_nutrition_entry(data: dict) -> dict:
    """Insert a nutrition entry. Returns the saved entry (with id).

    Uses upsert on_conflict="id" so retries (network lag, double-tap) are safe:
    same UUID → same row, no calorie duplication.
    """
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return data

    def _do() -> dict:
        resp = db_core._client.table("nutrition_entries").upsert(data, on_conflict="id").execute()
        return resp.data[0] if resp.data else data

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("insert_nutrition_entry retry error: %s", e2)
                return data
        db_core.logger.error("insert_nutrition_entry error: %s", e)
        return data


def delete_nutrition_entry(entry_id: str) -> bool:
    """Delete a nutrition entry by id. Returns True on success."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        resp = db_core._client.table("nutrition_entries").delete().eq("id", entry_id).execute()
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("delete_nutrition_entry retry error: %s", e2)
                return False
        db_core.logger.error("delete_nutrition_entry error: %s", e)
        return False


def delete_nutrition_entries_for_date(date: str) -> bool:
    """Delete ALL nutrition entries for a specific date. Returns True on success
    (aussi True quand aucune entry n'existait — l'état cible est "veille vide").
    Returns False si offline / erreur DB — le caller doit fail loud dans ce cas.
    """
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        resp = db_core._client.table("nutrition_entries").delete().eq("date", date).execute()
        return resp.data is not None

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("delete_nutrition_entries_for_date retry error: %s", e2)
                return False
        db_core.logger.error("delete_nutrition_entries_for_date error: %s", e)
        return False


def update_nutrition_entry(entry_id: str, patch: dict) -> bool:
    """Update fields of a nutrition entry by id. Returns True on success."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        resp = db_core._client.table("nutrition_entries").update(patch).eq("id", entry_id).execute()
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("update_nutrition_entry retry error: %s", e2)
                return False
        db_core.logger.error("update_nutrition_entry error: %s", e)
        return False


# ---------------------------------------------------------------------------
# Hydration
# ---------------------------------------------------------------------------

def get_hydration_today() -> int:
    """Return total ml logged today (0 if none or offline)."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return 0
    from datetime import date
    today = _today_mtl()

    def _do() -> int:
        resp = (
            db_core._client.table("hydration_logs")
            .select("amount_ml")
            .eq("date", today)
            .execute()
        )
        return sum(int(r.get("amount_ml", 0)) for r in (resp.data or []))

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_hydration_today retry error: %s", e2)
                return 0
        db_core.logger.error("get_hydration_today error: %s", e)
        return 0


def log_hydration(amount_ml: int) -> None:
    """Insert a hydration entry for today."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return

    def _do() -> None:
        from datetime import date
        db_core._client.table("hydration_logs").insert({
            "date":      _today_mtl(),
            "amount_ml": amount_ml,
        }).execute()

    try:
        _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                _do()
            except Exception as e2:
                db_core.logger.error("log_hydration retry error: %s", e2)
        else:
            db_core.logger.error("log_hydration error: %s", e)


# ---------------------------------------------------------------------------
# Food catalog
# ---------------------------------------------------------------------------

def get_food_catalog() -> list:
    """Return all food catalog items."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> list:
        resp = db_core._client.table("food_catalog").select("*").limit(200).execute()
        return resp.data or []

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_food_catalog retry error: %s", e2)
                return []
        db_core.logger.error("get_food_catalog error: %s", e)
        return []


def save_food_catalog(items: list) -> bool:
    """Replace entire food catalog (delete-all + reinsert)."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        db_core._client.table("food_catalog").delete().neq("id", "").execute()
        if items:
            db_core._client.table("food_catalog").insert(items).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("save_food_catalog retry error: %s", e2)
                return False
        db_core.logger.error("save_food_catalog error: %s", e)
        return False


# ---------------------------------------------------------------------------
# Meal Templates
# ---------------------------------------------------------------------------

def get_meal_templates() -> list:
    """Return all meal templates ordered by name."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> list:
        resp = db_core._client.table("meal_templates").select("id, name, items").order("name").limit(50).execute()
        return resp.data or []

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_meal_templates retry error: %s", e2)
                return []
        db_core.logger.error("get_meal_templates error: %s", e)
        return []


def create_meal_template(name: str, items: list) -> dict | None:
    """Insert a new meal template; returns the created row."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do() -> dict | None:
        resp = db_core._client.table("meal_templates").insert({"name": name, "items": items}).execute()
        return resp.data[0] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("create_meal_template retry error: %s", e2)
                return None
        db_core.logger.error("create_meal_template error: %s", e)
        return None


def update_meal_template(template_id: str, name: str, items: list) -> bool:
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        db_core._client.table("meal_templates")\
            .update({"name": name, "items": items})\
            .eq("id", template_id)\
            .execute()
        return True

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("update_meal_template retry error: %s", e2)
                return False
        db_core.logger.error("update_meal_template error: %s", e)
        return False


def delete_meal_template(template_id: str) -> bool:
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        db_core._client.table("meal_templates").delete().eq("id", template_id).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("delete_meal_template retry error: %s", e2)
                return False
        db_core.logger.error("delete_meal_template error: %s", e)
        return False


# ---------------------------------------------------------------------------
# Deload state
# ---------------------------------------------------------------------------

def get_deload_state() -> dict:
    """Return the current deload state (single row)."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return {"active": False, "started_at": None, "reason": None}

    def _do() -> dict:
        resp = (
            db_core._client.table("deload_state")
            .select("*")
            .eq("id", 1)
            .single()
            .execute()
        )
        return resp.data or {"active": False, "started_at": None, "reason": None}

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_deload_state retry error: %s", e2)
                return {"active": False}
        db_core.logger.error("get_deload_state error: %s", e)
        return {"active": False}


def set_deload_state(
    active: bool,
    started_at: Optional[str] = None,
    reason: Optional[str] = None,
    duration_days: Optional[int] = None,
    last_completed: Optional[str] = None,
) -> bool:
    """Set the deload state row. Creates it if not yet present."""
    payload: dict = {"id": 1, "active": active}
    if started_at is not None:
        payload["started_at"] = started_at
    if reason is not None:
        payload["reason"] = reason
    if duration_days is not None:
        payload["duration_days"] = duration_days
    if last_completed is not None:
        payload["last_completed"] = last_completed

    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        resp = (
            db_core._client.table("deload_state")
            .upsert(payload, on_conflict="id")
            .execute()
        )
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("set_deload_state retry error: %s", e2)
                return False
        db_core.logger.error("set_deload_state error: %s", e)
        return False
