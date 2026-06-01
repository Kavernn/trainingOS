from __future__ import annotations
import logging
from typing import Dict, List, Optional
import db_core
from db_exercises import get_or_create_exercise_id


def get_body_weight_logs(limit: int = 100) -> List[dict]:
    """Return body weight log entries, newest first.
    weight field is in lbs (not kg).
    """
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        resp = (
            db_core._client.table("body_weight_logs")
            .select("*")
            .order("date", desc=True)
            .limit(limit)
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
                db_core.logger.error("get_body_weight_logs retry error: %s", e2)
                return []
        db_core.logger.error("get_body_weight_logs error: %s", e)
        return []


def upsert_body_weight(
    date: str,
    weight: float,   # unit: lbs (not kg)
    note: str = "",
    body_fat: Optional[float] = None,
    waist_cm: Optional[float] = None,
    neck_cm: Optional[float] = None,
    arms_cm: Optional[float] = None,
    chest_cm: Optional[float] = None,
    thighs_cm: Optional[float] = None,
    hips_cm: Optional[float] = None,
) -> bool:
    """Insert or update a body weight log entry for the given date."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        payload: dict = {"date": date, "weight": weight, "note": note}
        for field, val in [("body_fat", body_fat), ("waist_cm", waist_cm),
                           ("neck_cm", neck_cm), ("arms_cm", arms_cm),
                           ("chest_cm", chest_cm),
                           ("thighs_cm", thighs_cm), ("hips_cm", hips_cm)]:
            if val is not None:
                payload[field] = val
        resp = (
            db_core._client.table("body_weight_logs")
            .upsert(payload, on_conflict="date")
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
                db_core.logger.error("upsert_body_weight retry error: %s", e2)
                return False
        db_core.logger.error("upsert_body_weight error: %s", e)
        return False


def log_body_weight_wearable(date: str, poids: float, body_fat: Optional[float] = None) -> bool:
    """Push Apple Watch body composition into body_weight_logs.
    Only inserts if no entry already exists for that date (manual wins).
    """
    existing = get_body_weight_logs(limit=365)
    if any(e.get("date") == date for e in existing):
        return False  # manual entry present, don't overwrite
    return upsert_body_weight(date, weight=poids, body_fat=body_fat)


def delete_body_weight(date: str) -> bool:
    """Delete a body weight log entry by date."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        db_core._client.table("body_weight_logs").delete().eq("date", date).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("delete_body_weight retry error: %s", e2)
                return False
        db_core.logger.error("delete_body_weight error: %s", e)
        return False


# ---------------------------------------------------------------------------
# HIIT logs
# ---------------------------------------------------------------------------

def get_hiit_logs(limit: int = 100) -> List[dict]:
    """Return HIIT log entries, newest first."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        resp = (
            db_core._client.table("hiit_logs")
            .select("*")
            .order("date", desc=True)
            .order("logged_at", desc=True)
            .limit(limit)
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
                db_core.logger.error("get_hiit_logs retry error: %s", e2)
                return []
        db_core.logger.error("get_hiit_logs error: %s", e)
        return []


def insert_hiit_log(data: dict) -> dict:
    """Insert a new HIIT log entry. Returns the inserted record."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return data

    def _do() -> dict:
        resp = db_core._client.table("hiit_logs").insert(data).execute()
        return resp.data[0] if resp.data else data

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("insert_hiit_log retry error: %s", e2)
                return data
        db_core.logger.error("insert_hiit_log error: %s", e)
        return data


def update_hiit_log(hiit_id: str, patch: dict) -> bool:
    """Update a HIIT log entry by its UUID. Returns True on success."""
    # fallback to KV during migration
    if db_core._client is None or db_core.MODE == "OFFLINE":
        db_core.logger.warning("update_hiit_log: UUID-based update not supported in KV fallback")
        return False

    def _do() -> bool:
        resp = db_core._client.table("hiit_logs").update(patch).eq("id", hiit_id).execute()
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("update_hiit_log retry error: %s", e2)
                return False  # fallback to KV during migration not feasible by UUID
        db_core.logger.error("update_hiit_log error: %s", e)
        return False  # fallback to KV during migration not feasible by UUID


def delete_hiit_log_by_id(hiit_id: str) -> bool:
    """Delete a HIIT log entry by its UUID. Returns True on success."""
    # fallback to KV during migration
    if db_core._client is None or db_core.MODE == "OFFLINE":
        db_core.logger.warning("delete_hiit_log_by_id: UUID-based deletion not supported in KV fallback")
        return False

    def _do() -> bool:
        resp = db_core._client.table("hiit_logs").delete().eq("id", hiit_id).execute()
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("delete_hiit_log_by_id retry error: %s", e2)
                return False  # fallback to KV during migration not feasible by UUID
        db_core.logger.error("delete_hiit_log_by_id error: %s", e)
        return False  # fallback to KV during migration not feasible by UUID


# ---------------------------------------------------------------------------
# Recovery logs
# ---------------------------------------------------------------------------

def get_recovery_logs(limit: int = 100) -> List[dict]:
    """Return recovery log entries, newest first."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []
    def _fetch():
        return (
            db_core._client.table("recovery_logs")
            .select("date, sleep_hours, sleep_quality, resting_hr, hrv, steps, soreness, fatigue_perceived, active_energy, hr_morning, hr_post_workout, hr_evening, energy_pre, source, notes")
            .order("date", desc=True)
            .limit(limit)
            .execute()
        )
    try:
        return _fetch().data or []
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _fetch().data or []
            except Exception as e2:
                db_core.logger.error("get_recovery_logs retry error: %s", e2)
                return []
        db_core.logger.error("get_recovery_logs error: %s", e)
        return []


def upsert_recovery_log(data: dict) -> bool:
    """Insert or update a recovery log by date. data must include 'date'."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        resp = (
            db_core._client.table("recovery_logs")
            .upsert(data, on_conflict="date")
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
                db_core.logger.error("upsert_recovery_log retry error: %s", e2)
                return False
        db_core.logger.error("upsert_recovery_log error: %s", e)
        return False


def merge_recovery_wearable(target_date: str, wearable: dict) -> bool:
    """Merge HealthKit/Apple Watch data into recovery_logs for target_date.

    Only fills in fields that are not already set (manual entries take priority).
    Never overwrites: sleep_quality, soreness, notes.
    """
    WEARABLE_KEYS = ("steps", "sleep_hours", "resting_hr", "hrv", "active_energy",
                     "hr_morning", "hr_post_workout", "hr_evening")
    # Cumulative metrics grow throughout the day — always update from HealthKit
    # unless the entry was manually entered by the user.
    CUMULATIVE_KEYS = {"steps", "active_energy"}

    existing_list = get_recovery_logs(limit=365)
    existing      = next((e for e in existing_list if e.get("date") == target_date), {})

    merged          = dict(existing)
    merged["date"]  = target_date
    # Keep source=manual if the entry was manually created, otherwise mark healthkit
    if not existing:
        merged["source"] = "healthkit"

    is_manual = existing.get("source") == "manual"
    for key in WEARABLE_KEYS:
        if key not in wearable:
            continue
        if merged.get(key) is None:
            merged[key] = wearable[key]
        elif key in CUMULATIVE_KEYS and not is_manual:
            # Always take the latest HealthKit value for cumulative metrics
            merged[key] = wearable[key]

    return upsert_recovery_log(merged)


def delete_recovery_log(date: str) -> bool:
    """Delete a recovery log entry by date. Returns True on success."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        resp = db_core._client.table("recovery_logs").delete().eq("date", date).execute()
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("delete_recovery_log retry error: %s", e2)
                return False
        db_core.logger.error("delete_recovery_log error: %s", e)
        return False


# ---------------------------------------------------------------------------
# Goals
# ---------------------------------------------------------------------------

def get_goals() -> Dict[str, dict]:
    """Return {exercise_name: {target_weight, target_date, id}}.

    'achieved' is NOT stored — derive it by comparing target_weight
    against get_exercise_history(name, limit=1)[0]['weight'].
    """
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return {}

    def _do() -> Dict[str, dict]:
        resp = (
            db_core._client.table("goals")
            .select("id, target_weight, target_date, exercises(name)")
            .execute()
        )
        rows = resp.data or []
        return {
            r["exercises"]["name"]: {
                "id": r["id"],
                "target_weight": r["target_weight"],
                "target_date": r["target_date"],
            }
            for r in rows
            if r.get("exercises")
        }

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_goals retry error: %s", e2)
                return {}
        db_core.logger.error("get_goals error: %s", e)
        return {}


def set_goal(
    exercise_name: str,
    target_weight: float,
    target_date: Optional[str] = None,
) -> bool:
    """Create or update a goal for an exercise. Returns True on success."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        exercise_id = get_or_create_exercise_id(exercise_name)
        if not exercise_id:
            db_core.logger.warning("set_goal: exercise '%s' not found/created", exercise_name)
            return False
        payload: dict = {"exercise_id": exercise_id, "target_weight": target_weight}
        if target_date:
            payload["target_date"] = target_date
        resp = (
            db_core._client.table("goals")
            .upsert(payload, on_conflict="exercise_id")
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
                db_core.logger.error("set_goal retry error: %s", e2)
                return False
        db_core.logger.error("set_goal error: %s", e)
        return False


# ---------------------------------------------------------------------------
# Cardio logs
# ---------------------------------------------------------------------------

def get_cardio_logs(limit: int = 100) -> List[dict]:
    """Return cardio log entries, newest first."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        resp = (
            db_core._client.table("cardio_logs")
            .select("*")
            .order("date", desc=True)
            .limit(limit)
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
                db_core.logger.error("get_cardio_logs retry error: %s", e2)
                return []
        db_core.logger.error("get_cardio_logs error: %s", e)
        return []


def insert_cardio_log(data: dict) -> bool:
    """Insert a new cardio log entry. Returns True on success."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        resp = db_core._client.table("cardio_logs").insert(data).execute()
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("insert_cardio_log retry error: %s", e2)
                return False
        db_core.logger.error("insert_cardio_log error: %s", e)
        return False


def delete_cardio_log(date: str, type_: str) -> bool:
    """Delete a cardio log entry by date and type. Returns True on success."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        resp = (
            db_core._client.table("cardio_logs")
            .delete()
            .eq("date", date)
            .eq("type", type_)
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
                db_core.logger.error("delete_cardio_log retry error: %s", e2)
                return False
        db_core.logger.error("delete_cardio_log error: %s", e)
        return False


def get_readiness_history(days: int = 28) -> list:
    """Return historical readiness scores. No persistence table yet — always cold-start."""
    return []
