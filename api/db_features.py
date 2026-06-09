from __future__ import annotations
from datetime import datetime, timezone, date as _date, timedelta as _td
from utils import _today_mtl
from typing import Dict, List, Optional
import db_core
from db_profile import get_profile, update_profile


# ── Daily Ritual ─────────────────────────────────────────────────────────────

def get_ritual_today(date_str: str) -> Optional[dict]:
    """Return today's daily_ritual row or None."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do() -> Optional[dict]:
        resp = (
            db_core._client.table("daily_ritual")
            .select("*")
            .eq("date", date_str)
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
                db_core.logger.error("get_ritual_today retry: %s", e2)
                return None
        db_core.logger.error("get_ritual_today error: %s", e)
        return None


def upsert_ritual(data: dict) -> bool:
    """Insert or update a daily_ritual row by date."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        resp = (
            db_core._client.table("daily_ritual")
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
                db_core.logger.error("upsert_ritual retry: %s", e2)
                return False
        db_core.logger.error("upsert_ritual error: %s", e)
        return False


def get_ritual_history(limit: int = 365) -> List[dict]:
    """Return all ritual rows ordered by date DESC."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        resp = (
            db_core._client.table("daily_ritual")
            .select("date, outcome, intention, carry_count, carried_from")
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
                db_core.logger.error("get_ritual_history retry: %s", e2)
                return []
        db_core.logger.error("get_ritual_history error: %s", e)
        return []


def get_ritual_demons() -> List[dict]:
    """Return all survived (unresolved) intentions, oldest first."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        cutoff = (_date.fromisoformat(_today_mtl()) - _td(days=180)).isoformat()
        resp = (
            db_core._client.table("daily_ritual")
            .select("date, intention, carry_count, carried_from, truth")
            .eq("outcome", "survived")
            .gte("date", cutoff)
            .order("date", desc=False)
            .limit(100)
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
                db_core.logger.error("get_ritual_demons retry: %s", e2)
                return []
        db_core.logger.error("get_ritual_demons error: %s", e)
        return []


def get_ritual_routine_history(limit: int = 180) -> List[dict]:
    """Return daily_ritual rows with routine checklist columns, oldest first."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        resp = (
            db_core._client.table("daily_ritual")
            .select(
                "date, routine_completed_at, routine_no_food, routine_dim_lights, "
                "routine_shower, routine_connection, routine_deconnect, "
                "routine_priorities_done, routine_bedtime_ok"
            )
            .order("date", desc=False)
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
                db_core.logger.error("get_ritual_routine_history retry: %s", e2)
                return []
        db_core.logger.error("get_ritual_routine_history error: %s", e)
        return []


def get_ritual_history_full(limit: int = 90, offset: int = 0) -> List[dict]:
    """Return full ritual history with all fields for biography view."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        resp = (
            db_core._client.table("daily_ritual")
            .select("date, outcome, intention, truth, carry_count, carried_from, reflection, morning_at, evening_at, tomorrow_intention")
            .order("date", desc=True)
            .range(offset, offset + limit - 1)
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
                db_core.logger.error("get_ritual_history_full retry: %s", e2)
                return []
        db_core.logger.error("get_ritual_history_full error: %s", e)
        return []


def count_ritual_entries() -> int:
    """Return total number of ritual entries for pagination."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return 0

    def _do() -> int:
        resp = (
            db_core._client.table("daily_ritual")
            .select("date", count="exact")
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
                db_core.logger.error("count_ritual_entries retry: %s", e2)
                return 0
        db_core.logger.error("count_ritual_entries error: %s", e)
        return 0


# ── Ritual Engagements ───────────────────────────────────────────────────────

def get_engagements_for_date(date_str: str) -> List[dict]:
    """Return all engagements for a given target date, ordered by sort_order."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        resp = (
            db_core._client.table("ritual_engagements")
            .select("*")
            .eq("date", date_str)
            .order("sort_order")
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
                db_core.logger.error("get_engagements_for_date retry: %s", e2)
                return []
        db_core.logger.error("get_engagements_for_date error: %s", e)
        return []


def create_engagements(date_str: str, texts: List[str]) -> List[dict]:
    """Replace all engagements for a date with the provided texts."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        db_core._client.table("ritual_engagements").delete().eq("date", date_str).execute()
        clean = [t.strip() for t in texts if t.strip()]
        if not clean:
            return []
        rows = [{"date": date_str, "text": t, "sort_order": i} for i, t in enumerate(clean)]
        resp = db_core._client.table("ritual_engagements").insert(rows).execute()
        return resp.data or []

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("create_engagements retry: %s", e2)
                return []
        db_core.logger.error("create_engagements error: %s", e)
        return []


def update_engagement_status(engagement_id: str, status: str) -> bool:
    """Set the status (done/notdone) on a single engagement row."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False
    from datetime import datetime, timezone as _tz
    now_iso = datetime.now(_tz.utc).isoformat()

    def _do() -> bool:
        resp = (
            db_core._client.table("ritual_engagements")
            .update({"status": status, "updated_at": now_iso})
            .eq("id", engagement_id)
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
                db_core.logger.error("update_engagement_status retry: %s", e2)
                return False
        db_core.logger.error("update_engagement_status error: %s", e)
        return False


# ── War Room ──────────────────────────────────────────────────────────────────

def get_war_room_config() -> Optional[dict]:
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do():
        resp = db_core._client.table("war_room_config").select("id, war_start_date, substance_label, integration_phoenix, integration_readiness, integration_ai_coach").eq("id", 1).limit(1).execute()
        return resp.data[0] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_war_room_config retry: %s", e2)
                return None
        db_core.logger.error("get_war_room_config error: %s", e)
        return None


def upsert_war_room_config(data: dict) -> bool:
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False
    payload = {**data, "id": 1}

    def _do():
        db_core._client.table("war_room_config").upsert(payload, on_conflict="id").execute()
        return True

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("upsert_war_room_config retry: %s", e2)
                return False
        db_core.logger.error("upsert_war_room_config error: %s", e)
        return False


def get_war_room_battles(limit: int = 90) -> List[dict]:
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do():
        resp = (
            db_core._client.table("war_room_battles")
            .select("id, date, status, notes, created_at")
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
                db_core.logger.error("get_war_room_battles retry: %s", e2)
                return []
        db_core.logger.error("get_war_room_battles error: %s", e)
        return []


def upsert_war_room_battle(data: dict) -> bool:
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do():
        db_core._client.table("war_room_battles").upsert(data, on_conflict="date").execute()
        return True

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("upsert_war_room_battle retry: %s", e2)
                return False
        db_core.logger.error("upsert_war_room_battle error: %s", e)
        return False


def get_war_room_triggers(limit: int = 90) -> List[dict]:
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do():
        resp = (
            db_core._client.table("war_room_triggers")
            .select("id, date, logged_at, context, context_note, intensity, yielded, held_with")
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
                db_core.logger.error("get_war_room_triggers retry: %s", e2)
                return []
        db_core.logger.error("get_war_room_triggers error: %s", e)
        return []


def insert_war_room_trigger(data: dict) -> Optional[dict]:
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do():
        resp = db_core._client.table("war_room_triggers").insert(data).execute()
        return (resp.data or [None])[0]

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("insert_war_room_trigger retry: %s", e2)
                return None
        db_core.logger.error("insert_war_room_trigger error: %s", e)
        return None


def get_war_room_today_status(today: str) -> dict:
    _empty = {"has_result": False, "has_temptation": False,
              "result_logged_at": None, "temptation_logged_at": None}
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return _empty

    def _do():
        b = (db_core._client.table("war_room_battles")
             .select("created_at").eq("date", today).limit(1).execute())
        battle = (b.data or [None])[0]

        t = (db_core._client.table("war_room_triggers")
             .select("logged_at").eq("date", today).limit(1).execute())
        trigger = (t.data or [None])[0]

        return {
            "has_result":           battle is not None,
            "has_temptation":       trigger is not None,
            "result_logged_at":     battle["created_at"] if battle else None,
            "temptation_logged_at": trigger["logged_at"] if trigger else None,
        }

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_war_room_today_status retry: %s", e2)
                return _empty
        db_core.logger.error("get_war_room_today_status error: %s", e)
        return _empty


def get_war_room_arsenal() -> List[dict]:
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do():
        resp = (
            db_core._client.table("war_room_arsenal")
            .select("id, label, category, use_count, last_used_at, sort_order, active")
            .eq("active", True)
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
                db_core.logger.error("get_war_room_arsenal retry: %s", e2)
                return []
        db_core.logger.error("get_war_room_arsenal error: %s", e)
        return []


def insert_war_room_arsenal_item(data: dict) -> Optional[dict]:
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do():
        resp = db_core._client.table("war_room_arsenal").insert(data).execute()
        return (resp.data or [None])[0]

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("insert_war_room_arsenal_item retry: %s", e2)
                return None
        db_core.logger.error("insert_war_room_arsenal_item error: %s", e)
        return None


def delete_war_room_arsenal_item(item_id: str) -> bool:
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do():
        resp = db_core._client.table("war_room_arsenal").update({"active": False}).eq("id", item_id).execute()
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("delete_war_room_arsenal_item retry: %s", e2)
                return False
        db_core.logger.error("delete_war_room_arsenal_item error: %s", e)
        return False


def increment_arsenal_use(item_id: str) -> bool:
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do():
        row = db_core._client.table("war_room_arsenal").select("use_count").eq("id", item_id).maybe_single().execute()
        current = (row.data or {}).get("use_count", 0)
        db_core._client.table("war_room_arsenal").update({
            "use_count":    current + 1,
            "last_used_at": datetime.now(timezone.utc).isoformat(),
        }).eq("id", item_id).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("increment_arsenal_use retry: %s", e2)
                return False
        db_core.logger.error("increment_arsenal_use error: %s", e)
        return False


# ── Spirit Pillar ─────────────────────────────────────────────────────────────

def get_spirit_config() -> Optional[dict]:
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do():
        resp = db_core._client.table("spirit_config").select("id, integration_phoenix").eq("id", 1).maybe_single().execute()
        return resp.data

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_spirit_config retry: %s", e2)
                return None
        db_core.logger.error("get_spirit_config error: %s", e)
        return None


def upsert_spirit_config(data: dict) -> bool:
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False
    payload = {**data, "id": 1}

    def _do():
        db_core._client.table("spirit_config").upsert(payload, on_conflict="id").execute()
        return True

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("upsert_spirit_config retry: %s", e2)
                return False
        db_core.logger.error("upsert_spirit_config error: %s", e)
        return False


def log_breathwork_session(data: dict) -> Optional[dict]:
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do():
        resp = db_core._client.table("breathwork_sessions").insert(data).execute()
        return (resp.data or [None])[0]

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("log_breathwork_session retry: %s", e2)
                return None
        db_core.logger.error("log_breathwork_session error: %s", e)
        return None


def get_breathwork_sessions(limit: int = 60) -> List[dict]:
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do():
        resp = (
            db_core._client.table("breathwork_sessions")
            .select("id, protocol, duration_sec, cycles, started_at, triggered_from")
            .order("started_at", desc=True)
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
                db_core.logger.error("get_breathwork_sessions retry: %s", e2)
                return []
        db_core.logger.error("get_breathwork_sessions error: %s", e)
        return []


def log_meditation_session(data: dict) -> Optional[dict]:
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do():
        resp = db_core._client.table("meditation_sessions").insert(data).execute()
        return (resp.data or [None])[0]

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("log_meditation_session retry: %s", e2)
                return None
        db_core.logger.error("log_meditation_session error: %s", e)
        return None


def get_meditation_sessions(limit: int = 60) -> List[dict]:
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do():
        resp = (
            db_core._client.table("meditation_sessions")
            .select("id, planned_sec, actual_sec, bell_interval, started_at, completed")
            .order("started_at", desc=True)
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
                db_core.logger.error("get_meditation_sessions retry: %s", e2)
                return []
        db_core.logger.error("get_meditation_sessions error: %s", e)
        return []


def save_spirit_journal_entry(data: dict) -> bool:
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do():
        db_core._client.table("spirit_journal").upsert(data, on_conflict="date").execute()
        return True

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("save_spirit_journal_entry retry: %s", e2)
                return False
        db_core.logger.error("save_spirit_journal_entry error: %s", e)
        return False


def get_spirit_journal_entries(limit: int = 30) -> List[dict]:
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do():
        resp = (
            db_core._client.table("spirit_journal")
            .select("id, date")
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
                db_core.logger.error("get_spirit_journal_entries retry: %s", e2)
                return []
        db_core.logger.error("get_spirit_journal_entries error: %s", e)
        return []


def get_spirit_journal_entry(entry_date: str) -> Optional[dict]:
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do():
        resp = (
            db_core._client.table("spirit_journal")
            .select("id, date, grateful_for, conquered, haunting, created_at")
            .eq("date", entry_date)
            .maybe_single()
            .execute()
        )
        return resp.data

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_spirit_journal_entry retry: %s", e2)
                return None
        db_core.logger.error("get_spirit_journal_entry error: %s", e)
        return None


# ── Oath ──────────────────────────────────────────────────────────────────────

def get_current_oath() -> Optional[dict]:
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do():
        resp = (
            db_core._client.table("oaths")
            .select("id, text, version, word_count, written_at, superseded_at")
            .is_("superseded_at", "null")
            .order("written_at", desc=True)
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
                db_core.logger.error("get_current_oath retry: %s", e2)
                return None
        db_core.logger.error("get_current_oath error: %s", e)
        return None


def get_oath_versions() -> List[dict]:
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do():
        resp = (
            db_core._client.table("oaths")
            .select("id, text, version, word_count, written_at, superseded_at")
            .order("written_at", desc=True)
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
                db_core.logger.error("get_oath_versions retry: %s", e2)
                return []
        db_core.logger.error("get_oath_versions error: %s", e)
        return []


def save_oath(text: str, word_count: int) -> Optional[dict]:
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None
    now_iso = datetime.now(timezone.utc).isoformat()

    def _do():
        existing = get_current_oath()
        next_version = (existing["version"] + 1) if existing else 1
        if existing:
            db_core._client.table("oaths").update({"superseded_at": now_iso}).eq("id", existing["id"]).execute()
        resp = (
            db_core._client.table("oaths")
            .insert({"text": text, "version": next_version, "word_count": word_count})
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
                db_core.logger.error("save_oath retry: %s", e2)
                return None
        db_core.logger.error("save_oath error: %s", e)
        return None


def log_oath_recall(oath_id: str, trigger: str) -> None:
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return

    def _do():
        payload: dict = {"trigger": trigger}
        if oath_id:
            payload["oath_id"] = oath_id
        db_core._client.table("oath_recalls").insert(payload).execute()

    try:
        _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                _do()
            except Exception as e2:
                db_core.logger.error("log_oath_recall retry: %s", e2)
        db_core.logger.error("log_oath_recall error: %s", e)


def get_oath_recalls(limit: int = 20) -> List[dict]:
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do():
        resp = (
            db_core._client.table("oath_recalls")
            .select("id, oath_id, trigger, shown_at")
            .order("shown_at", desc=True)
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
                db_core.logger.error("get_oath_recalls retry: %s", e2)
                return []
        db_core.logger.error("get_oath_recalls error: %s", e)
        return []


# ── Spirit breathwork (renamed to avoid conflict with wellness breathwork) ────

def get_breathwork_sessions_spirit(limit: int = 500) -> List[dict]:
    """Spirit breathwork sessions (breathwork_sessions table)."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do():
        resp = (
            db_core._client.table("breathwork_sessions")
            .select("id, protocol, duration_sec, cycles, started_at")
            .order("started_at", desc=True)
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
                db_core.logger.error("get_breathwork_sessions_spirit retry: %s", e2)
                return []
        db_core.logger.error("get_breathwork_sessions_spirit error: %s", e)
        return []


# ── Seasons ───────────────────────────────────────────────────────────────────

def get_next_season_number() -> int:
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return 1
    try:
        resp = db_core._client.table("seasons").select("number").order("number", desc=True).limit(1).execute()
        if resp.data:
            return (resp.data[0].get("number") or 0) + 1
        return 1
    except Exception as e:
        db_core.logger.error("get_next_season_number error: %s", e)
        return 1


def get_active_season() -> Optional[dict]:
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do():
        resp = (
            db_core._client.table("seasons")
            .select("id, number, status, started_at, ended_at, generated_title, custom_title, dominant_arc, personal_note")
            .eq("status", "active")
            .order("created_at", desc=True)
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
                db_core.logger.error("get_active_season retry: %s", e2)
                return None
        db_core.logger.error("get_active_season error: %s", e)
        return None


def get_all_seasons() -> List[dict]:
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do():
        resp = (
            db_core._client.table("seasons")
            .select("id, number, status, started_at, ended_at, generated_title, custom_title, dominant_arc, personal_note")
            .order("number", desc=True)
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
                db_core.logger.error("get_all_seasons retry: %s", e2)
                return []
        db_core.logger.error("get_all_seasons error: %s", e)
        return []


def get_season_by_id(season_id: str) -> Optional[dict]:
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do():
        resp = (
            db_core._client.table("seasons")
            .select("id, number, status, started_at, ended_at, generated_title, custom_title, dominant_arc, personal_note")
            .eq("id", season_id)
            .maybe_single()
            .execute()
        )
        return resp.data

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_season_by_id retry: %s", e2)
                return None
        db_core.logger.error("get_season_by_id error: %s", e)
        return None


def create_season(number: int, started_at: str) -> Optional[dict]:
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do():
        resp = (
            db_core._client.table("seasons")
            .insert({"number": number, "started_at": started_at, "status": "active"})
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
                db_core.logger.error("create_season retry: %s", e2)
                return None
        db_core.logger.error("create_season error: %s", e)
        return None


def save_season_snapshot(season_id: str, snap_type: str, data: dict) -> Optional[dict]:
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None
    payload = {
        "season_id":   season_id,
        "type":        snap_type,
        "weight_lbs":            data.get("weight_lbs"),
        "body_fat_pct":          data.get("body_fat_pct"),
        "phoenix_avg":           data.get("phoenix_avg"),
        "phoenix_workout_avg":   data.get("phoenix_workout_avg"),
        "phoenix_stress_avg":    data.get("phoenix_stress_avg"),
        "phoenix_nutrition_avg": data.get("phoenix_nutrition_avg"),
        "phoenix_resilience_avg":data.get("phoenix_resilience_avg"),
        "phoenix_spirit_avg":    data.get("phoenix_spirit_avg"),
        "pss_score":             data.get("pss_score"),
        "war_room_streak":       data.get("war_room_streak"),
        "top_prs":               data.get("top_prs"),
        "ritual_completion_rate":data.get("ritual_completion_rate"),
        "avg_sleep_hrs":         data.get("avg_sleep_hrs"),
        "avg_calories":          data.get("avg_calories"),
        "avg_protein_g":         data.get("avg_protein_g"),
        "breathwork_sessions_total": data.get("breathwork_sessions_total"),
        "meditation_minutes_total":  data.get("meditation_minutes_total"),
        "journal_entries_total":     data.get("journal_entries_total"),
    }
    payload = {k: v for k, v in payload.items() if v is not None}

    def _do():
        resp = db_core._client.table("season_snapshots").insert(payload).execute()
        return resp.data[0] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("save_season_snapshot retry: %s", e2)
                return None
        db_core.logger.error("save_season_snapshot error: %s", e)
        return None


def close_season(season_id: str, ended_at: str, generated_title: str, dominant_arc: str) -> Optional[dict]:
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do():
        resp = (
            db_core._client.table("seasons")
            .update({
                "status":          "completed",
                "ended_at":        ended_at,
                "generated_title": generated_title,
                "dominant_arc":    dominant_arc,
            })
            .eq("id", season_id)
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
                db_core.logger.error("close_season retry: %s", e2)
                return None
        db_core.logger.error("close_season error: %s", e)
        return None


def update_season(season_id: str, fields: dict) -> Optional[dict]:
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do():
        resp = (
            db_core._client.table("seasons")
            .update(fields)
            .eq("id", season_id)
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
                db_core.logger.error("update_season retry: %s", e2)
                return None
        db_core.logger.error("update_season error: %s", e)
        return None


def get_season_snapshots(season_id: str) -> List[dict]:
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do():
        resp = (
            db_core._client.table("season_snapshots")
            .select("id, season_id, type, captured_at, weight_lbs, body_fat_pct, phoenix_avg, phoenix_workout_avg, phoenix_stress_avg, phoenix_nutrition_avg, phoenix_resilience_avg, phoenix_spirit_avg, pss_score, war_room_streak, top_prs, ritual_completion_rate, avg_sleep_hrs, avg_calories, breathwork_sessions_total, meditation_minutes_total, journal_entries_total")
            .eq("season_id", season_id)
            .order("captured_at", desc=False)
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
                db_core.logger.error("get_season_snapshots retry: %s", e2)
                return []
        db_core.logger.error("get_season_snapshots error: %s", e)
        return []


def get_prev_season_had_reset(current_season_id: str) -> bool:
    """Return True if the previous completed season had at least one War Room reset."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False
    try:
        current = get_season_by_id(current_season_id)
        if not current:
            return False
        current_num = current.get("number", 1)
        if current_num <= 1:
            return False
        resp = (
            db_core._client.table("seasons")
            .select("id, started_at, ended_at")
            .eq("number", current_num - 1)
            .eq("status", "completed")
            .maybe_single()
            .execute()
        )
        prev = resp.data
        if not prev:
            return False
        battles = get_war_room_battles(limit=500)
        start = prev.get("started_at", "")
        end   = prev.get("ended_at", "")
        period = sorted(
            [b for b in battles if start <= b.get("date", "") <= end],
            key=lambda x: x.get("date", "")
        )
        streak = 0
        for b in period:
            if b.get("status") == "victory":
                streak += 1
            else:
                if streak > 0:
                    return True
                streak = 0
        return False
    except Exception as e:
        db_core.logger.error("get_prev_season_had_reset error: %s", e)
        return False


# ── Coach — Spirit metadata (counts only, zero content) ──────────────────────

def get_spirit_metadata(days: int = 7) -> dict:
    """Return Spirit pillar metadata for the last N days.
    Counts and dates only — journal content is never queried or returned."""
    today = _date.fromisoformat(_today_mtl())
    cutoff = (today - _td(days=days)).isoformat()
    result: dict = {
        "breathwork_count": 0,
        "meditation_count": 0,
        "journal_count": 0,
        "breathwork_streak": 0,
        "days_with_breathwork": [],
        "days_with_meditation": [],
        "days_with_journal": [],
    }
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return result
    try:
        resp = db_core._client.table("breathwork_sessions").select("started_at").gte("started_at", cutoff + "T00:00:00").execute()
        bw_dates: set[str] = set()
        for row in (resp.data or []):
            d = str(row.get("started_at") or "")[:10]
            if d >= cutoff:
                bw_dates.add(d)
        result["breathwork_count"] = len(resp.data or [])
        result["days_with_breathwork"] = sorted(bw_dates)
        streak = 0
        d = today
        while d.isoformat() in bw_dates:
            streak += 1
            d -= _td(days=1)
        result["breathwork_streak"] = streak
    except Exception as e:
        db_core.logger.error("get_spirit_metadata breathwork error: %s", e)
    try:
        resp = db_core._client.table("meditation_sessions").select("started_at").gte("started_at", cutoff + "T00:00:00").eq("completed", True).execute()
        med_dates: set[str] = set()
        for row in (resp.data or []):
            d = str(row.get("started_at") or "")[:10]
            if d >= cutoff:
                med_dates.add(d)
        result["meditation_count"] = len(resp.data or [])
        result["days_with_meditation"] = sorted(med_dates)
    except Exception as e:
        db_core.logger.error("get_spirit_metadata meditation error: %s", e)
    try:
        resp = db_core._client.table("spirit_journal").select("date").gte("date", cutoff).execute()
        jrn_dates = [str(row.get("date") or "")[:10] for row in (resp.data or []) if row.get("date")]
        result["journal_count"] = len(jrn_dates)
        result["days_with_journal"] = sorted(jrn_dates)
    except Exception as e:
        db_core.logger.error("get_spirit_metadata journal error: %s", e)
    return result


def get_war_room_coach_context() -> Optional[dict]:
    """Return War Room stats for coach context.
    NEVER includes trigger content, arsenal text, or pattern analysis."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None
    try:
        config = get_war_room_config() or {}
        battles = get_war_room_battles(limit=180)
        cutoff = (_date.fromisoformat(_today_mtl()) - _td(days=90)).isoformat()
        recent = [b for b in battles if b.get("date", "") >= cutoff]
        victories = sum(1 for b in recent if b.get("status") == "victory")
        total = len(recent)
        lost = [b for b in battles if b.get("status") == "lost"]
        last_reset_date = lost[0].get("date") if lost else None
        days_since_reset: Optional[int] = None
        if last_reset_date:
            try:
                days_since_reset = (_date.fromisoformat(_today_mtl()) - _date.fromisoformat(last_reset_date)).days
            except Exception:
                pass
        return {
            "streak":           int(config.get("victory_streak") or 0),
            "best_streak":      int(config.get("best_streak") or 0),
            "victories":        victories,
            "total_battles":    total,
            "last_reset_date":  last_reset_date,
            "days_since_reset": days_since_reset,
        }
    except Exception as e:
        db_core.logger.error("get_war_room_coach_context error: %s", e)
        return None


def _next_month_str(month_prefix: str) -> str:
    """Return first day of the next month as 'YYYY-MM-DD'."""
    year, month = int(month_prefix[:4]), int(month_prefix[5:7])
    if month == 12:
        return f"{year + 1}-01-01"
    return f"{year}-{month + 1:02d}-01"


def get_adherence_active_days(pillar: str, month_prefix: str) -> int:
    """Count distinct days this month with ≥1 entry for the given pillar.

    Pillars: 'body' | 'mind' | 'fuel' | 'spirit'
    month_prefix: 'YYYY-MM'
    """
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return 0

    dates: set[str] = set()
    next_m = _next_month_str(month_prefix)

    def _collect_date_col(table: str, col: str, is_timestamptz: bool = False) -> None:
        try:
            if is_timestamptz:
                resp = (db_core._client.table(table).select(col)
                        .gte(col, f"{month_prefix}-01")
                        .lt(col, next_m)
                        .execute())
            else:
                resp = (db_core._client.table(table).select(col)
                        .gte(col, f"{month_prefix}-01")
                        .lt(col, next_m)
                        .execute())
            for r in (resp.data or []):
                val = r.get(col)
                if val:
                    dates.add(str(val)[:10])
        except Exception as e:
            db_core.logger.warning("get_adherence_active_days(%s/%s) query error: %s", pillar, table, e)

    if pillar == "body":
        try:
            resp = (db_core._client.table("workout_sessions").select("date")
                    .gte("date", f"{month_prefix}-01")
                    .lt("date", next_m)
                    .eq("completed", True)
                    .execute())
            for r in (resp.data or []):
                if r.get("date"):
                    dates.add(str(r["date"])[:10])
        except Exception as e:
            db_core.logger.warning("get_adherence_active_days(body/workout) error: %s", e)
        _collect_date_col("body_weight_logs", "date")

    elif pillar == "mind":
        _collect_date_col("recovery_logs", "date")
        try:
            resp = (db_core._client.table("pss_records").select("recorded_at")
                    .gte("recorded_at", f"{month_prefix}-01")
                    .lt("recorded_at", next_m)
                    .execute())
            for r in (resp.data or []):
                if r.get("recorded_at"):
                    dates.add(str(r["recorded_at"])[:10])
        except Exception as e:
            db_core.logger.warning("get_adherence_active_days(mind/pss) error: %s", e)

    elif pillar == "fuel":
        _collect_date_col("nutrition_entries", "date")

    elif pillar == "spirit":
        _collect_date_col("breathwork_sessions", "started_at", is_timestamptz=True)
        _collect_date_col("meditation_sessions", "started_at", is_timestamptz=True)

    return len(dates)


def get_current_1rm_estimates() -> list[dict]:
    """Return [{name, estimated_1rm}] from v_exercise_current for all exercises with a valid 1RM."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> list[dict]:
        resp = (
            db_core._client.table("v_exercise_current")
            .select("exercise_name, estimated_1rm")
            .not_.is_("estimated_1rm", "null")
            .execute()
        )
        return [
            {"name": r["exercise_name"], "estimated_1rm": float(r["estimated_1rm"])}
            for r in (resp.data or [])
            if r.get("exercise_name") and r.get("estimated_1rm")
        ]

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_current_1rm_estimates retry: %s", e2)
                return []
        db_core.logger.error("get_current_1rm_estimates error: %s", e)
        return []


def get_coach_war_room_shared() -> bool:
    """Return whether user has opted in to sharing War Room data with the coach."""
    return bool(get_profile().get("coach_war_room_shared", False))


def set_coach_war_room_shared(value: bool) -> bool:
    """Toggle War Room sharing with the coach."""
    return update_profile({"coach_war_room_shared": value})
