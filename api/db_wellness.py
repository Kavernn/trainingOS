from __future__ import annotations
import logging
from typing import Dict, List, Optional
import db_core
from db_body import get_body_weight_logs, get_recovery_logs, get_cardio_logs
from db_sessions import get_workout_sessions, get_all_exercise_history
from db_profile import get_nutrition_entries_recent
from utils import _today_mtl


def get_mood_logs(days: int = 0, limit: int = 0) -> List[dict]:
    """Return mood log entries, newest first."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        from datetime import date as _date, timedelta
        q = db_core._client.table("mood_logs").select("*").order("date", desc=True)
        if days:
            cutoff = (_date.fromisoformat(_today_mtl()) - timedelta(days=days)).isoformat()
            q = q.gte("date", cutoff)
        if limit:
            q = q.limit(limit)
        resp = q.execute()
        return resp.data or []

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_mood_logs retry error: %s", e2)
                return []
        db_core.logger.error("get_mood_logs error: %s", e)
        return []


def insert_mood_log(entry: dict) -> Optional[dict]:
    """Insert a mood log entry. Returns saved record or None."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do() -> Optional[dict]:
        resp = db_core._client.table("mood_logs").insert(entry).execute()
        return resp.data[0] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("insert_mood_log retry error: %s", e2)
                return None
        db_core.logger.error("insert_mood_log error: %s", e)
        return None


# ---------------------------------------------------------------------------
# PSS records
# ---------------------------------------------------------------------------

def get_pss_records(pss_type: Optional[str] = None, limit: int = 0) -> List[dict]:
    """Return PSS records, newest first."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        q = db_core._client.table("pss_records").select("*").order("date", desc=True)
        if pss_type:
            q = q.eq("type", pss_type)
        if limit:
            q = q.limit(limit)
        resp = q.execute()
        return resp.data or []

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_pss_records retry error: %s", e2)
                return []
        db_core.logger.error("get_pss_records error: %s", e)
        return []


def insert_pss_record(entry: dict) -> Optional[dict]:
    """Upsert a PSS record. Returns saved record or None.

    Uses on_conflict="date,type" so resubmitting the same questionnaire
    on the same day updates the existing record instead of creating a duplicate.
    Requires migration 025_pss_unique_date_type.sql.
    """
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do() -> Optional[dict]:
        resp = db_core._client.table("pss_records").upsert(entry, on_conflict="date,type").execute()
        return resp.data[0] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("insert_pss_record retry error: %s", e2)
                return None
        db_core.logger.error("insert_pss_record error: %s", e)
        return None


# ---------------------------------------------------------------------------
# DASS-21 records

def get_dass_records(limit: int = 0) -> List[dict]:
    """Return DASS-21 records, newest first."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        q = db_core._client.table("dass_records").select("*").order("date", desc=True)
        if limit:
            q = q.limit(limit)
        resp = q.execute()
        return resp.data or []

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_dass_records retry error: %s", e2)
                return []
        db_core.logger.error("get_dass_records error: %s", e)
        return []


def insert_dass_record(entry: dict) -> Optional[dict]:
    """Upsert a DASS-21 record. On conflict on date — one record per day."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do() -> Optional[dict]:
        resp = db_core._client.table("dass_records").upsert(entry, on_conflict="date").execute()
        return resp.data[0] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("insert_dass_record retry error: %s", e2)
                return None
        db_core.logger.error("insert_dass_record error: %s", e)
        return None


# ---------------------------------------------------------------------------
# Sleep records — TABLE ARCHIVÉE, ne plus alimenter.
# Source de vérité sommeil : recovery_logs.sleep_hours (saisie manuelle).
# ---------------------------------------------------------------------------

def get_sleep_records(limit: int = 0, offset: int = 0) -> List[dict]:
    """Return sleep records, newest first."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        q = db_core._client.table("sleep_records").select("*").order("date", desc=True)
        if limit:
            q = q.range(offset, offset + limit - 1)
        resp = q.execute()
        return resp.data or []

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_sleep_records retry error: %s", e2)
                return []
        db_core.logger.error("get_sleep_records error: %s", e)
        return []


def upsert_sleep_record(entry: dict) -> Optional[dict]:
    """ARCHIVÉE — ne plus appeler. Source de vérité : recovery_logs."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do() -> Optional[dict]:
        resp = db_core._client.table("sleep_records").upsert(entry, on_conflict="date").execute()
        return resp.data[0] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("upsert_sleep_record retry error: %s", e2)
                return None
        db_core.logger.error("upsert_sleep_record error: %s", e)
        return None


def delete_sleep_record(record_id: str) -> bool:
    """Delete a sleep record by id."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        db_core._client.table("sleep_records").delete().eq("id", record_id).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("delete_sleep_record retry error: %s", e2)
                return False
        db_core.logger.error("delete_sleep_record error: %s", e)
        return False


# ---------------------------------------------------------------------------
# Journal entries
# ---------------------------------------------------------------------------

def get_journal_entries_all(limit: int = 100, offset: int = 0) -> List[dict]:
    """Return journal entries, newest first. Default LIMIT 100 to cap egress."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        q = db_core._client.table("journal_entries").select("*").order("date", desc=True)
        if limit:
            q = q.range(offset, offset + limit - 1)
        resp = q.execute()
        return resp.data or []

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_journal_entries_all retry error: %s", e2)
                return []
        db_core.logger.error("get_journal_entries_all error: %s", e)
        return []


def insert_journal_entry(entry: dict) -> Optional[dict]:
    """Insert a journal entry."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do() -> Optional[dict]:
        resp = db_core._client.table("journal_entries").insert(entry).execute()
        return resp.data[0] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("insert_journal_entry retry error: %s", e2)
                return None
        db_core.logger.error("insert_journal_entry error: %s", e)
        return None


def search_journal_entries_db(query: str) -> List[dict]:
    """Search journal entries by content or prompt (case-insensitive)."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        resp = (
            db_core._client.table("journal_entries")
            .select("*")
            .or_(f"content.ilike.%{query}%,prompt.ilike.%{query}%")
            .order("date", desc=True)
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
                db_core.logger.error("search_journal_entries_db retry error: %s", e2)
                return []
        db_core.logger.error("search_journal_entries_db error: %s", e)
        return []


def count_journal_entries_since(since_date: str) -> int:
    """Count journal entries on or after since_date."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return 0

    def _do() -> int:
        resp = (
            db_core._client.table("journal_entries")
            .select("id", count="exact")
            .gte("date", since_date)
            .execute()
        )
        return resp.count or 0

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("count_journal_entries_since retry error: %s", e2)
                return 0
        db_core.logger.error("count_journal_entries_since error: %s", e)
        return 0


# ---------------------------------------------------------------------------
# Breathwork sessions (wellness — by date)
# ---------------------------------------------------------------------------

def get_breathwork_sessions(days: int = 30) -> List[dict]:
    """Return breathwork sessions within last N days, newest first."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        from datetime import date as _date, timedelta
        cutoff = (_date.fromisoformat(_today_mtl()) - timedelta(days=days)).isoformat()
        resp = (
            db_core._client.table("breathwork_sessions")
            .select("*")
            .filter("technique_id", "not.is", "null")
            .gte("date", cutoff)
            .order("date", desc=True)
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
                db_core.logger.error("get_breathwork_sessions retry error: %s", e2)
                return []
        db_core.logger.error("get_breathwork_sessions error: %s", e)
        return []


def insert_breathwork_session(entry: dict) -> Optional[dict]:
    """Insert a breathwork session."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do() -> Optional[dict]:
        resp = db_core._client.table("breathwork_sessions").insert(entry).execute()
        return resp.data[0] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("insert_breathwork_session retry error: %s", e2)
                return None
        db_core.logger.error("insert_breathwork_session error: %s", e)
        return None


# ---------------------------------------------------------------------------
# Self-care habits + logs
# ---------------------------------------------------------------------------

def get_self_care_habits() -> List[dict]:
    """Return all self-care habits ordered by order_index."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        resp = db_core._client.table("self_care_habits").select("*").order("order_index").execute()
        return resp.data or []

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_self_care_habits retry error: %s", e2)
                return []
        db_core.logger.error("get_self_care_habits error: %s", e)
        return []


def upsert_self_care_habit(habit: dict) -> Optional[dict]:
    """Insert or update a self-care habit by id."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do() -> Optional[dict]:
        resp = db_core._client.table("self_care_habits").upsert(habit, on_conflict="id").execute()
        return resp.data[0] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("upsert_self_care_habit retry error: %s", e2)
                return None
        db_core.logger.error("upsert_self_care_habit error: %s", e)
        return None


def delete_self_care_habit(habit_id: str) -> bool:
    """Delete a self-care habit and all its log entries."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        db_core._client.table("self_care_logs").delete().eq("habit_id", habit_id).execute()
        db_core._client.table("self_care_habits").delete().eq("id", habit_id).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("delete_self_care_habit retry error: %s", e2)
                return False
        db_core.logger.error("delete_self_care_habit error: %s", e)
        return False


def get_self_care_log(days: int = 90) -> Dict[str, List[str]]:
    """Return {date: [habit_id, ...]} for last N days."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return {}

    def _do() -> Dict[str, List[str]]:
        from datetime import date as _date, timedelta
        cutoff = (_date.fromisoformat(_today_mtl()) - timedelta(days=days)).isoformat()
        resp = (
            db_core._client.table("self_care_logs")
            .select("date, habit_id")
            .gte("date", cutoff)
            .execute()
        )
        result: Dict[str, List[str]] = {}
        for row in (resp.data or []):
            result.setdefault(row["date"], []).append(row["habit_id"])
        return result

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_self_care_log retry error: %s", e2)
                return {}
        db_core.logger.error("get_self_care_log error: %s", e)
        return {}


def set_self_care_log_for_date(date: str, habit_ids: List[str]) -> bool:
    """Replace self-care log for a specific date."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        db_core._client.table("self_care_logs").delete().eq("date", date).execute()
        if habit_ids:
            rows = [{"date": date, "habit_id": hid} for hid in habit_ids]
            db_core._client.table("self_care_logs").insert(rows).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("set_self_care_log_for_date retry error: %s", e2)
                return False
        db_core.logger.error("set_self_care_log_for_date error: %s", e)
        return False


# ---------------------------------------------------------------------------
# Life stress scores
# ---------------------------------------------------------------------------

def get_life_stress_score_db(date: str) -> Optional[dict]:
    """Return cached life stress score for a date, or None."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do() -> Optional[dict]:
        resp = db_core._client.table("life_stress_scores").select("*").eq("date", date).limit(1).execute()
        rows = resp.data or []
        return rows[0] if rows else None

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.debug("get_life_stress_score_for_date(%s) retry error: %s", date, e2)
                return None
        db_core.logger.debug("get_life_stress_score_for_date(%s): %s", date, e)
        return None


def upsert_life_stress_score(entry: dict) -> bool:
    """Insert or update a life stress score entry."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        db_core._client.table("life_stress_scores").upsert(entry, on_conflict="date").execute()
        return True

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("upsert_life_stress_score retry error: %s", e2)
                return False
        db_core.logger.error("upsert_life_stress_score error: %s", e)
        return False


# ---------------------------------------------------------------------------
# Coach history
# ---------------------------------------------------------------------------

def get_coach_history(limit: int = 50) -> List[dict]:
    """Return coach history entries, newest first."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        resp = (
            db_core._client.table("coach_history")
            .select("*")
            .order("created_at", desc=True)
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
                db_core.logger.error("get_coach_history retry error: %s", e2)
                return []
        db_core.logger.error("get_coach_history error: %s", e)
        return []


def insert_coach_message(entry: dict) -> Optional[dict]:
    """Insert a coach history message."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do() -> Optional[dict]:
        resp = db_core._client.table("coach_history").insert(entry).execute()
        return resp.data[0] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("insert_coach_message retry error: %s", e2)
                return None
        db_core.logger.error("insert_coach_message error: %s", e)
        return None


# ---------------------------------------------------------------------------
# Goals archived
# ---------------------------------------------------------------------------

def get_goals_archived() -> List[str]:
    """Return list of archived exercise names."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> List[str]:
        resp = db_core._client.table("goals_archived").select("exercise_name").execute()
        return [r["exercise_name"] for r in (resp.data or [])]

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_goals_archived retry error: %s", e2)
                return []
        db_core.logger.error("get_goals_archived error: %s", e)
        return []


def add_goal_archived(exercise_name: str) -> bool:
    """Archive a goal by exercise name."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        db_core._client.table("goals_archived").upsert(
            {"exercise_name": exercise_name}, on_conflict="exercise_name"
        ).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("add_goal_archived retry error: %s", e2)
                return False
        db_core.logger.error("add_goal_archived error: %s", e)
        return False


def remove_goal_archived(exercise_name: str) -> bool:
    """Restore a goal (remove from archived)."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        db_core._client.table("goals_archived").delete().eq("exercise_name", exercise_name).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("remove_goal_archived retry error: %s", e2)
                return False
        db_core.logger.error("remove_goal_archived error: %s", e)
        return False


# ---------------------------------------------------------------------------
# Exercise current weight (smart progression pre-fill)
# ---------------------------------------------------------------------------

def update_exercise_current_weight(name: str, weight: float) -> bool:
    """Update current_weight for an exercise (used by SeanceView pre-fill)."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        resp = db_core._client.table("exercises").update({"current_weight": weight}).eq("name", name).execute()
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("update_exercise_current_weight retry error: %s", e2)
                return False
        db_core.logger.error("update_exercise_current_weight error: %s", e)
        return False


# ---------------------------------------------------------------------------
# Sessions with volume (for correlations)
# ---------------------------------------------------------------------------

def get_sessions_for_correlations(days: int = 60) -> Dict[str, dict]:
    """Return {date: {rpe, session_volume, energy_pre}} for the last N days."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return {}
    from datetime import date as _date, timedelta
    cutoff = (_date.fromisoformat(_today_mtl()) - timedelta(days=days)).isoformat()
    result: Dict[str, dict] = {}

    def _do_sessions() -> None:
        resp = (
            db_core._client.table("workout_sessions")
            .select("date, rpe, energy_pre")
            .gte("date", cutoff)
            .execute()
        )
        for row in (resp.data or []):
            d = str(row.get("date", ""))[:10]
            if d:
                result[d] = {"rpe": row.get("rpe"), "energy_pre": row.get("energy_pre")}

    def _do_volume() -> None:
        resp = (
            db_core._client.table("v_session_volume")
            .select("date, total_volume")
            .gte("date", cutoff)
            .execute()
        )
        for row in (resp.data or []):
            d = str(row.get("date", ""))[:10]
            if d:
                result.setdefault(d, {})["session_volume"] = row.get("total_volume")

    try:
        _do_sessions()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                _do_sessions()
            except Exception as e2:
                db_core.logger.error("get_sessions_for_correlations (sessions) retry error: %s", e2)
        else:
            db_core.logger.error("get_sessions_for_correlations (sessions) error: %s", e)

    try:
        _do_volume()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                _do_volume()
            except Exception as e2:
                db_core.logger.error("get_sessions_for_correlations (volume) retry error: %s", e2)
        else:
            db_core.logger.error("get_sessions_for_correlations (volume) error: %s", e)

    return result


# ---------------------------------------------------------------------------
# Smart Goals
# ---------------------------------------------------------------------------

SMART_GOAL_META: dict = {
    "body_fat":           {"label": "% Masse grasse",          "unit": "%",       "lower_is_better": True},
    "lean_mass":          {"label": "Masse maigre",             "unit": "lbs",     "lower_is_better": False},
    "waist_cm":           {"label": "Tour de taille",           "unit": "cm",      "lower_is_better": True},
    "weekly_volume":      {"label": "Volume hebdo",             "unit": "lbs",     "lower_is_better": False},
    "training_frequency": {"label": "Séances / semaine",        "unit": "séances", "lower_is_better": False},
    "protein_daily":      {"label": "Protéines / jour",         "unit": "g",       "lower_is_better": False},
    "nutrition_streak":   {"label": "Streak nutrition",         "unit": "jours",   "lower_is_better": False},
    # ── Types avancés ───────────────────────────────────────────────────────────
    "estimated_1rm":      {"label": "1RM estimé (meilleur exo)", "unit": "lbs",   "lower_is_better": False},
    "monthly_distance":   {"label": "Distance mensuelle cardio", "unit": "km",    "lower_is_better": False},
    "resting_hr":         {"label": "FC au repos",               "unit": "bpm",   "lower_is_better": True},
    "pss_avg":            {"label": "Stress PSS moyen",          "unit": "pts",   "lower_is_better": True},
    "sleep_streak":       {"label": "Streak sommeil",            "unit": "jours", "lower_is_better": False},
}


def get_smart_goals() -> List[dict]:
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        resp = db_core._client.table("smart_goals").select("*").order("created_at").execute()
        return resp.data or []

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_smart_goals retry error: %s", e2)
                return []
        db_core.logger.error("get_smart_goals error: %s", e)
        return []


def upsert_smart_goal(
    goal_type: str,
    target_value: float,
    initial_value: Optional[float] = None,
    target_date: Optional[str] = None,
    goal_id: Optional[str] = None,
) -> Optional[dict]:
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do() -> Optional[dict]:
        payload: dict = {"type": goal_type, "target_value": target_value}
        if goal_id:
            payload["id"] = goal_id
        if initial_value is not None:
            payload["initial_value"] = round(initial_value, 2)
        if target_date:
            payload["target_date"] = target_date
        resp = db_core._client.table("smart_goals").upsert(payload, on_conflict="id").execute()
        return resp.data[0] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("upsert_smart_goal retry error: %s", e2)
                return None
        db_core.logger.error("upsert_smart_goal error: %s", e)
        return None


def delete_smart_goal(goal_id: str) -> bool:
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        db_core._client.table("smart_goals").delete().eq("id", goal_id).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("delete_smart_goal retry error: %s", e2)
                return False
        db_core.logger.error("delete_smart_goal error: %s", e)
        return False


def compute_smart_goal_current(goal_type: str) -> Optional[float]:
    """Compute the current metric value for a smart goal type."""
    try:
        if goal_type == "body_fat":
            bw = get_body_weight_logs(limit=1)
            return bw[0].get("body_fat") if bw else None

        if goal_type == "lean_mass":
            bw = get_body_weight_logs(limit=1)
            if bw:
                w  = bw[0].get("weight") or 0
                bf = bw[0].get("body_fat") or 0
                return round(w * (1 - bf / 100), 1)
            return None

        if goal_type == "waist_cm":
            bw = get_body_weight_logs(limit=1)
            return bw[0].get("waist_cm") if bw else None

        if goal_type == "weekly_volume":
            vol = get_sessions_for_correlations(days=7)
            return round(sum(v.get("session_volume") or 0 for v in vol.values()), 0)

        if goal_type == "training_frequency":
            from datetime import date as _date, timedelta
            cutoff   = (_date.fromisoformat(_today_mtl()) - timedelta(days=7)).isoformat()
            sessions = get_workout_sessions(limit=50)
            return float(sum(1 for s in sessions if (s.get("date") or "") >= cutoff))

        if goal_type == "protein_daily":
            entries = get_nutrition_entries_recent(7)
            if not entries:
                return 0.0
            return round(sum(e.get("proteines") or 0 for e in entries) / len(entries), 1)

        if goal_type == "nutrition_streak":
            from datetime import date as _date, timedelta
            entries = get_nutrition_entries_recent(365)
            dates   = {e["date"] for e in entries if e.get("date")}
            streak, d = 0, _date.fromisoformat(_today_mtl())
            while d.isoformat() in dates:
                streak += 1
                d -= timedelta(days=1)
            return float(streak)

        # ── Types avancés ─────────────────────────────────────────────────────

        if goal_type == "estimated_1rm":
            # Best estimated 1RM across all exercises: weight * (1 + reps/30)
            history = get_all_exercise_history(cutoff_days=90)
            best = 0.0
            for logs in history.values():
                for entry in logs[:10]:  # check last 10 sessions per exercise
                    w = entry.get("weight") or 0
                    r = entry.get("reps") or ""
                    if not w:
                        continue
                    # Parse reps: "3x8", "8,8,6", "8"
                    import re as _re2
                    nums = [float(x) for x in _re2.findall(r"\d+(?:\.\d+)?", str(r))]
                    avg_reps = (sum(nums) / len(nums)) if nums else 0
                    if avg_reps > 0:
                        orm = w * (1 + avg_reps / 30.0)
                        if orm > best:
                            best = orm
            return round(best, 1) if best > 0 else None

        if goal_type == "monthly_distance":
            from datetime import date as _date, timedelta
            cutoff  = (_date.fromisoformat(_today_mtl()) - timedelta(days=30)).isoformat()
            logs    = get_cardio_logs(limit=200)
            total   = sum(float(e.get("distance_km") or 0) for e in logs
                          if (e.get("date") or "") >= cutoff)
            return round(total, 1) if total > 0 else None

        if goal_type == "resting_hr":
            # Use most recent recovery log resting_hr, fallback to wearable snapshot
            recs = get_recovery_logs(limit=7)
            for r in recs:
                hr = r.get("resting_hr")
                if hr:
                    return float(hr)
            return None

        if goal_type == "pss_avg":
            recs   = get_pss_records(limit=5)
            scores = [r.get("score") for r in recs if r.get("score") is not None]
            return round(sum(scores) / len(scores), 1) if scores else None

        if goal_type == "sleep_streak":
            from datetime import date as _date, timedelta
            recs  = get_sleep_records(limit=365)
            dates = {r["date"][:10] for r in recs if r.get("date")}
            streak, d = 0, _date.fromisoformat(_today_mtl())
            while d.isoformat() in dates:
                streak += 1
                d -= timedelta(days=1)
            return float(streak) if streak > 0 else None

    except Exception as e:
        db_core.logger.error("compute_smart_goal_current(%s) error: %s", goal_type, e)
    return None


def compute_smart_goal_progress(
    current: Optional[float],
    target: float,
    initial: Optional[float],
    lower_is_better: bool,
) -> float:
    """Return progress percentage 0–100."""
    if current is None or target == 0:
        return 0.0
    if lower_is_better:
        if initial and initial > target:
            p = (initial - current) / (initial - target) * 100
        else:
            p = 100.0 if current <= target else 0.0
    else:
        p = current / target * 100
    return round(min(max(p, 0), 100), 1)


# ---------------------------------------------------------------------------
# Generated programs (AI programme generator)
# ---------------------------------------------------------------------------

def save_generated_program(program_json: dict) -> str | None:
    """Insert a generated program. Returns its UUID or None on error."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do() -> str | None:
        resp = (
            db_core._client.table("generated_programs")
            .insert({"program_json": program_json, "status": "pending_approval"})
            .execute()
        )
        return resp.data[0]["id"] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("save_generated_program retry error: %s", e2)
                return None
        db_core.logger.error("save_generated_program error: %s", e)
        return None


def get_latest_generated_program() -> dict | None:
    """Return the most recent generated program row (any status), or None."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do() -> dict | None:
        resp = (
            db_core._client.table("generated_programs")
            .select("*")
            .order("generated_at", desc=True)
            .limit(1)
            .execute()
        )
        return resp.data[0] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_latest_generated_program retry error: %s", e2)
                return None
        db_core.logger.error("get_latest_generated_program error: %s", e)
        return None


def update_generated_program(gp_id: str, status: str, programme_id: str | None = None) -> bool:
    """Update status and optionally link to an approved programme."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        data: dict = {"status": status}
        if programme_id:
            data["programme_id"] = programme_id
        db_core._client.table("generated_programs").update(data).eq("id", gp_id).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("update_generated_program retry error: %s", e2)
                return False
        db_core.logger.error("update_generated_program error: %s", e)
        return False
