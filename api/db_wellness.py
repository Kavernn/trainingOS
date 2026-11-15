from __future__ import annotations
import logging
from typing import Dict, List, Optional
import db_core
from db_body import get_body_weight_logs, get_recovery_logs, get_cardio_logs
from db_sessions import get_workout_sessions, get_all_exercise_history, get_exercise_prs
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
        # PostgREST returns empty data on conflict with no-change — treat as success
        return resp.data[0] if resp.data else entry

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
        resp = db_core._client.table("sleep_records").delete().eq("id", record_id).execute()
        return bool(resp.data)

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
    """Upsert breathwork session. started_at = clé d'idempotence (UNIQUE) :
    un replay retombe sur la ligne existante, pas de doublon."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do() -> Optional[dict]:
        resp = (
            db_core._client.table("breathwork_sessions")
            .upsert(entry, on_conflict="started_at", ignore_duplicates=True)
            .execute()
        )
        if resp.data:
            return resp.data[0]
        # PostgREST : conflit avec ignore_duplicates → data = []. Relire la ligne.
        existing = (
            db_core._client.table("breathwork_sessions")
            .select("*")
            .eq("started_at", entry["started_at"])
            .limit(1)
            .execute()
        )
        if not existing.data:
            raise RuntimeError(
                f"insert_breathwork_session: upsert sans data et aucune ligne trouvée pour started_at={entry['started_at']}"
            )
        return existing.data[0]

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
        # FK: self_care_logs.habit_id → self_care_habits.id (ON DELETE RESTRICT) → logs avant habit
        db_core._client.table("self_care_logs").delete().eq("habit_id", habit_id).execute()
        resp = db_core._client.table("self_care_habits").delete().eq("id", habit_id).execute()
        return bool(resp.data)

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
        resp = db_core._client.table("life_stress_scores").upsert(entry, on_conflict="date").execute()
        return bool(resp.data)

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




