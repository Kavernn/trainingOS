from __future__ import annotations
import logging
from typing import Dict, Optional
import db_core


def get_exercises() -> Dict[str, dict] | None:
    """Return {name: {id, type, category, ...}} from the exercises table (source unique).

    Returns {} if the table is genuinely empty.
    Returns None on connection/query error — callers must treat None as "unknown state,
    do NOT overwrite existing data with defaults".
    """
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do() -> Dict[str, dict] | None:
        rows: list = []
        page_size = 1000
        start = 0
        while True:
            resp = db_core._client.table("exercises").select("id, name, type, category, pattern, level, default_scheme, load_profile, muscles, increment, bar_weight, tracking_type, rest_seconds, tips, muscle_group, muscle_specific, secondary_muscles, movement_pattern, weight_type, equipment, alternate_name").is_("deleted_at", "null").order("name").range(start, start + page_size - 1).execute()
            batch = resp.data or []
            rows.extend(batch)
            if len(batch) < page_size:
                break
            start += page_size
        return {row["name"]: row for row in rows}

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_exercises retry error: %s", e2)
                return None
        db_core.logger.error("get_exercises error: %s", e)
        return None  # Signal unavailability — do NOT overwrite with defaults


def get_exercise_by_name(name: str) -> Optional[dict]:
    """Return a single exercise row by name, or None."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do() -> Optional[dict]:
        resp = db_core._client.table("exercises").select("id, name, type, category, default_scheme, load_profile, muscles, increment, tips, level, pattern, tracking_type").eq("name", name).is_("deleted_at", "null").single().execute()
        return resp.data

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.debug("get_exercise_by_name(%s) retry error: %s", name, e2)
                return None
        db_core.logger.debug("get_exercise_by_name(%s) error: %s", name, e)
        return None


def get_exercise_id(name: str) -> Optional[str]:
    """Return the UUID of an exercise by name, or None if not found."""
    # fallback to KV during migration
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do() -> Optional[str]:
        resp = db_core._client.table("exercises").select("id").eq("name", name).single().execute()
        return resp.data["id"] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.debug("get_exercise_id(%s) retry error: %s", name, e2)
                return None
        db_core.logger.debug("get_exercise_id(%s) error: %s", name, e)
        return None  # fallback to KV during migration


def update_program_scheme_for_exercise(exercise_id: str, new_scheme: str) -> bool:
    """Update scheme in all program_block_exercises rows that reference this exercise.

    Called after api_save_exercise() updates exercises.default_scheme so the
    programme immediately reflects the new prescription on next session load.
    """
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        resp = db_core._client.table("program_block_exercises").update({"scheme": new_scheme}).eq("exercise_id", exercise_id).execute()
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("update_program_scheme_for_exercise retry error: %s", e2)
                return False
        db_core.logger.error("update_program_scheme_for_exercise error: %s", e)
        return False


def get_exercise_id_include_deleted(name: str) -> Optional[str]:
    """Return the UUID of an exercise by name, including soft-deleted rows.

    Used internally before cleaning up program_block_exercises on soft delete.
    """
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do() -> Optional[str]:
        resp = db_core._client.table("exercises").select("id").eq("name", name).limit(1).execute()
        return resp.data[0]["id"] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.debug("get_exercise_id_include_deleted(%s) retry error: %s", name, e2)
                return None
        db_core.logger.debug("get_exercise_id_include_deleted(%s) error: %s", name, e)
        return None


def get_or_create_exercise_id(name: str) -> Optional[str]:
    """Return exercise UUID; reactivate soft-deleted rows instead of creating duplicates.

    Priority:
    1. Active exercise with this name → return id
    2. Soft-deleted exercise with this name → clear deleted_at, return id (preserves history)
    3. No row → create new minimal exercise row
    """
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None
    clean_name = (name or "").strip()
    if not clean_name:
        return None

    # 1 — active row
    existing_id = get_exercise_id(clean_name)
    if existing_id:
        return existing_id

    # 2 — soft-deleted row: reactivate to preserve exercise_logs history
    soft_deleted_found = False
    try:
        resp = (
            db_core._client.table("exercises")
            .select("id")
            .eq("name", clean_name)
            .not_.is_("deleted_at", "null")
            .limit(1)
            .execute()
        )
        if resp.data:
            soft_deleted_found = True
            ex_id = resp.data[0]["id"]
            reactivation_resp = db_core._client.table("exercises").update({"deleted_at": None}).eq("id", ex_id).execute()
            if reactivation_resp.data:
                db_core.logger.info("get_or_create_exercise_id: reactivated soft-deleted exercise %r (%s)", clean_name, ex_id)
                return ex_id
            db_core.logger.warning("get_or_create_exercise_id: reactivation 0 rows for %r (%s)", clean_name, ex_id)
    except Exception as e:
        db_core.logger.warning("get_or_create_exercise_id soft-delete check failed for %r: %s", clean_name, e)

    if soft_deleted_found:
        # Ligne soft-deleted confirmée mais réactivation échouée — pas de doublon
        return None

    # 3 — create new (atteint uniquement si aucune ligne soft-deleted trouvée)
    try:
        created = upsert_exercise({"name": clean_name})
        return created.get("id") if isinstance(created, dict) else None
    except Exception as e:
        db_core.logger.error("get_or_create_exercise_id(%s) error: %s", clean_name, e)
        return None


def upsert_exercise(data: dict) -> dict:
    """Insert or update an exercise by name. data must include 'name'. Returns saved record."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return data
    name = data.get("name", "")

    def _do() -> dict:
        resp = db_core._client.table("exercises").upsert(data, on_conflict="name").execute()
        if resp.data:
            return resp.data[0]
        db_core.logger.error("upsert_exercise upsert found no row for %s", name)
        return data

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("upsert_exercise retry error: %s", e2)
                return data
        db_core.logger.error("upsert_exercise error: %s", e)
        return data


def rename_exercise_table(old_name: str, new_name: str) -> bool:
    """Rename an exercise in the exercises table. Returns True on success."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        resp = db_core._client.table("exercises").update({"name": new_name}).eq("name", old_name).is_("deleted_at", "null").execute()
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("rename_exercise_table retry error: %s", e2)
                return False
        db_core.logger.error("rename_exercise_table error: %s", e)
        return False


def delete_exercise_by_name(name: str) -> bool:
    """Soft-delete an exercise by name. Returns True if a row was found and marked.

    Sets deleted_at = now() on the exercises row (preserving exercise_logs history).
    Hard-deletes from program_block_exercises so it disappears from the programme.
    """
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        resp = db_core._client.table("exercises").update({"deleted_at": "now()"}).eq("name", name).is_("deleted_at", "null").execute()
        if not resp.data:
            return False
        ex_id = get_exercise_id_include_deleted(name)
        if ex_id:
            db_core._client.table("program_block_exercises").delete().eq("exercise_id", ex_id).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("delete_exercise_by_name retry error: %s", e2)
                return False
        db_core.logger.error("delete_exercise_by_name error: %s", e)
        return False


def get_exercise_use_counts() -> dict:
    """Return {exercise_id: count} — number of exercise_log rows per exercise (cap 5000 rows)."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return {}

    def _do() -> dict:
        resp = db_core._client.table("exercise_logs").select("exercise_id").limit(5000).execute()
        counts: dict = {}
        for row in (resp.data or []):
            eid = row.get("exercise_id")
            if eid:
                counts[eid] = counts.get(eid, 0) + 1
        return counts

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_exercise_use_counts retry error: %s", e2)
                return {}
        db_core.logger.error("get_exercise_use_counts error: %s", e)
        return {}
