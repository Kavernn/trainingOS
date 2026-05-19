from __future__ import annotations
import os, json, sqlite3, threading, logging
from typing import Any, Dict, List, Optional, Tuple
from datetime import datetime, timezone

logger = logging.getLogger("trainingos.db")

# Modes:
#   ONLINE  : lecture/écriture Supabase; miroir local SQLite (dirty=0)
#   OFFLINE : lecture/écriture SQLite uniquement (dirty=1)
#   HYBRID  : tente Supabase, fallback SQLite; en cas d'échec réseau, dirty=1
MODE = os.getenv("APP_DATA_MODE", "ONLINE").upper()  # ONLINE | OFFLINE | HYBRID
_SUPABASE_URL = os.getenv("SUPABASE_URL")
_SUPABASE_KEY = os.getenv("SUPABASE_ANON_KEY")
# Détecter Vercel pour éviter tout write local en prod (FS readonly)
_ON_VERCEL = bool(os.getenv("VERCEL") or os.getenv("VERCEL_ENV"))

# Emplacement du SQLite local (fichier persistant en local, jamais utilisé sur Vercel)
_DEFAULT_LOCAL_DB = os.getenv("APP_LOCAL_DB", os.path.join(os.path.dirname(__file__), "..", ".local_kv.db"))

# Client Supabase (si accessible)
_client = None
if MODE != "OFFLINE":
    try:
        from supabase import Client, create_client
        if _SUPABASE_URL and _SUPABASE_KEY:
            _client: Client = create_client(_SUPABASE_URL, _SUPABASE_KEY)
        else:
            if MODE == "ONLINE":
                # Pas de credentials → bascule HYBRID pour autoriser cache local
                MODE = "HYBRID"
    except BaseException:
        # Supabase SDK indisponible (incl. pyo3 panics) → on retombe HYBRID/OFFLINE
        if MODE == "ONLINE":
            MODE = "HYBRID"


def _reconnect() -> bool:
    """Recreate the Supabase client after a server-disconnected error."""
    global _client
    if not (_SUPABASE_URL and _SUPABASE_KEY):
        return False
    try:
        from supabase import create_client
        _client = create_client(_SUPABASE_URL, _SUPABASE_KEY)
        logger.info("Supabase reconnected")
        return True
    except Exception as e:
        logger.error("Supabase reconnect failed: %s", e)
        return False


def _is_disconnect(e: Exception) -> bool:
    return "disconnected" in str(e).lower() or "server disconnected" in str(e).lower()

# ---------------------------------------------------------------------------
# SQLite local (kv_local: key TEXT PK, value TEXT JSON, updated_at TEXT ISO, dirty INT)
# ---------------------------------------------------------------------------
_SQL_LOCK = threading.RLock()
_CONN: Optional[sqlite3.Connection] = None


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _ensure_sqlite():
    global _CONN
    if _ON_VERCEL:
        return  # pas de SQLite en production Vercel
    if _CONN is None:
        path = os.path.abspath(_DEFAULT_LOCAL_DB)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        _CONN = sqlite3.connect(path, check_same_thread=False)
        _CONN.execute("""
        create table if not exists kv_local (
            key text primary key,
            value text not null,
            updated_at text not null,
            dirty integer not null default 0
        )
        """)
        _CONN.commit()


def _sqlite_get(key: str) -> Tuple[Optional[Any], Optional[str], int]:
    if _ON_VERCEL:
        return None, None, 0
    _ensure_sqlite()
    with _SQL_LOCK:
        cur = _CONN.execute("select value, updated_at, dirty from kv_local where key=?", (key,))
        row = cur.fetchone()
        if not row:
            return None, None, 0
        try:
            val = json.loads(row[0])
        except Exception:
            logger.warning("_sqlite_get: corrupt JSON for key, returning None")
            val = None
        return val, row[1], int(row[2])


def _sqlite_set(key: str, value: Any, dirty: int):
    if _ON_VERCEL:
        return
    _ensure_sqlite()
    with _SQL_LOCK:
        _CONN.execute(
            "insert into kv_local(key, value, updated_at, dirty) values(?,?,?,?) "
            "on conflict(key) do update set value=excluded.value, updated_at=excluded.updated_at, dirty=excluded.dirty",
            (key, json.dumps(value, ensure_ascii=False), _now_iso(), dirty),
        )
        _CONN.commit()






def client():
    """Retourne le client Supabase si disponible (sinon None)"""
    return _client




# ===========================================================================
# RELATIONAL TABLE METHODS
# Domain-specific methods that query the new normalized tables directly.
# Each method falls back to the KV layer when _client is None or MODE==OFFLINE.
# ===========================================================================

# ---------------------------------------------------------------------------
# Exercises  (replaces inventory KV)
# ---------------------------------------------------------------------------

def get_exercises() -> Dict[str, dict] | None:
    """Return {name: {id, type, category, ...}} from the exercises table (source unique).

    Returns {} if the table is genuinely empty.
    Returns None on connection/query error — callers must treat None as "unknown state,
    do NOT overwrite existing data with defaults".
    """
    if _client is None or MODE == "OFFLINE":
        return None

    def _do() -> Dict[str, dict] | None:
        rows: list = []
        page_size = 1000
        start = 0
        while True:
            resp = _client.table("exercises").select("*").is_("deleted_at", "null").order("name").range(start, start + page_size - 1).execute()
            batch = resp.data or []
            rows.extend(batch)
            if len(batch) < page_size:
                break
            start += page_size
        return {row["name"]: row for row in rows}

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_exercises retry error: %s", e2)
                return None
        logger.error("get_exercises error: %s", e)
        return None  # Signal unavailability — do NOT overwrite with defaults


def get_exercise_by_name(name: str) -> Optional[dict]:
    """Return a single exercise row by name, or None."""
    if _client is None or MODE == "OFFLINE":
        return None

    def _do() -> Optional[dict]:
        resp = _client.table("exercises").select("*").eq("name", name).is_("deleted_at", "null").single().execute()
        return resp.data

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.debug("get_exercise_by_name(%s) retry error: %s", name, e2)
                return None
        logger.debug("get_exercise_by_name(%s) error: %s", name, e)
        return None


def get_exercise_id(name: str) -> Optional[str]:
    """Return the UUID of an exercise by name, or None if not found."""
    # fallback to KV during migration
    if _client is None or MODE == "OFFLINE":
        return None

    def _do() -> Optional[str]:
        resp = _client.table("exercises").select("id").eq("name", name).single().execute()
        return resp.data["id"] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.debug("get_exercise_id(%s) retry error: %s", name, e2)
                return None
        logger.debug("get_exercise_id(%s) error: %s", name, e)
        return None  # fallback to KV during migration


def update_program_scheme_for_exercise(exercise_id: str, new_scheme: str) -> bool:
    """Update scheme in all program_block_exercises rows that reference this exercise.

    Called after api_save_exercise() updates exercises.default_scheme so the
    programme immediately reflects the new prescription on next session load.
    """
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        _client.table("program_block_exercises").update({"scheme": new_scheme}).eq("exercise_id", exercise_id).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("update_program_scheme_for_exercise retry error: %s", e2)
                return False
        logger.error("update_program_scheme_for_exercise error: %s", e)
        return False


def get_exercise_id_include_deleted(name: str) -> Optional[str]:
    """Return the UUID of an exercise by name, including soft-deleted rows.

    Used internally before cleaning up program_block_exercises on soft delete.
    """
    if _client is None or MODE == "OFFLINE":
        return None

    def _do() -> Optional[str]:
        resp = _client.table("exercises").select("id").eq("name", name).limit(1).execute()
        return resp.data[0]["id"] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.debug("get_exercise_id_include_deleted(%s) retry error: %s", name, e2)
                return None
        logger.debug("get_exercise_id_include_deleted(%s) error: %s", name, e)
        return None


def get_or_create_exercise_id(name: str) -> Optional[str]:
    """Return exercise UUID; reactivate soft-deleted rows instead of creating duplicates.

    Priority:
    1. Active exercise with this name → return id
    2. Soft-deleted exercise with this name → clear deleted_at, return id (preserves history)
    3. No row → create new minimal exercise row
    """
    if _client is None or MODE == "OFFLINE":
        return None
    clean_name = (name or "").strip()
    if not clean_name:
        return None

    # 1 — active row
    existing_id = get_exercise_id(clean_name)
    if existing_id:
        return existing_id

    # 2 — soft-deleted row: reactivate to preserve exercise_logs history
    try:
        resp = (
            _client.table("exercises")
            .select("id")
            .eq("name", clean_name)
            .not_.is_("deleted_at", "null")
            .limit(1)
            .execute()
        )
        if resp.data:
            ex_id = resp.data[0]["id"]
            _client.table("exercises").update({"deleted_at": None}).eq("id", ex_id).execute()
            logger.info("get_or_create_exercise_id: reactivated soft-deleted exercise %r (%s)", clean_name, ex_id)
            return ex_id
    except Exception as e:
        logger.warning("get_or_create_exercise_id soft-delete check failed for %r: %s", clean_name, e)

    # 3 — create new
    try:
        created = upsert_exercise({"name": clean_name})
        return created.get("id") if isinstance(created, dict) else None
    except Exception as e:
        logger.error("get_or_create_exercise_id(%s) error: %s", clean_name, e)
        return None


def upsert_exercise(data: dict) -> dict:
    """Insert or update an exercise by name. data must include 'name'. Returns saved record."""
    if _client is None or MODE == "OFFLINE":
        return data
    name = data.get("name", "")

    def _do() -> dict:
        try:
            resp = _client.table("exercises").insert(data).execute()
            if resp.data:
                return resp.data[0]
        except Exception as insert_err:
            logger.error("upsert_exercise INSERT error for %s: %s", name, insert_err)
        resp = _client.table("exercises").update(data).eq("name", name).execute()
        if resp.data:
            return resp.data[0]
        logger.error("upsert_exercise UPDATE found no row for %s", name)
        return data

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("upsert_exercise retry error: %s", e2)
                return data
        logger.error("upsert_exercise error: %s", e)
        return data


def rename_exercise_table(old_name: str, new_name: str) -> bool:
    """Rename an exercise in the exercises table. Returns True on success."""
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        resp = _client.table("exercises").update({"name": new_name}).eq("name", old_name).is_("deleted_at", "null").execute()
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("rename_exercise_table retry error: %s", e2)
                return False
        logger.error("rename_exercise_table error: %s", e)
        return False



def delete_exercise_by_name(name: str) -> bool:
    """Soft-delete an exercise by name. Returns True if a row was found and marked.

    Sets deleted_at = now() on the exercises row (preserving exercise_logs history).
    Hard-deletes from program_block_exercises so it disappears from the programme.
    """
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        resp = _client.table("exercises").update({"deleted_at": "now()"}).eq("name", name).is_("deleted_at", "null").execute()
        if not resp.data:
            return False
        ex_id = get_exercise_id_include_deleted(name)
        if ex_id:
            _client.table("program_block_exercises").delete().eq("exercise_id", ex_id).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("delete_exercise_by_name retry error: %s", e2)
                return False
        logger.error("delete_exercise_by_name error: %s", e)
        return False



# ---------------------------------------------------------------------------
# Workout sessions
# ---------------------------------------------------------------------------

def get_workout_sessions(limit: int = 100, offset: int = 0) -> List[dict]:
    """Return list of workout sessions ordered by date DESC.

    Uses DB-level LIMIT/OFFSET so callers never fetch more rows than needed.
    """
    if _client is None or MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        resp = (
            _client.table("workout_sessions")
            .select("*")
            .order("date", desc=True)
            .range(offset, offset + limit - 1)
            .execute()
        )
        return resp.data or []

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_workout_sessions retry error: %s", e2)
                return []
        logger.error("get_workout_sessions error: %s", e)
        return []


def get_total_session_count() -> int:
    """Count all completed sessions (all-time) — lightweight, no payload."""
    if _client is None or MODE == "OFFLINE":
        return 0
    try:
        resp = (
            _client.table("workout_sessions")
            .select("id", count="exact")
            .or_("completed.eq.true,rpe.not.is.null")
            .execute()
        )
        return resp.count or 0
    except Exception as e:
        logger.error("get_total_session_count error: %s", e)
        return 0


def get_all_time_volume_lbs() -> float:
    """Sum all session volume from v_session_volume view."""
    if _client is None or MODE == "OFFLINE":
        return 0.0
    try:
        resp = (
            _client.table("v_session_volume")
            .select("total_volume")
            .execute()
        )
        return round(sum(float(r.get("total_volume") or 0) for r in (resp.data or [])), 0)
    except Exception as e:
        logger.error("get_all_time_volume_lbs error: %s", e)
        return 0.0


def get_session_streaks() -> dict:
    """Return current and all-time longest workout streak."""
    from datetime import date as _date, timedelta
    if _client is None or MODE == "OFFLINE":
        return {"current": 0, "longest": 0}
    try:
        resp = (
            _client.table("workout_sessions")
            .select("date")
            .or_("completed.eq.true,rpe.not.is.null")
            .order("date")
            .execute()
        )
        dates = sorted(set(r["date"] for r in (resp.data or []) if r.get("date")))
    except Exception as e:
        logger.error("get_session_streaks error: %s", e)
        return {"current": 0, "longest": 0}

    if not dates:
        return {"current": 0, "longest": 0}

    all_set = set(dates)
    current = 0
    d = _date.today()
    if d.isoformat() not in all_set:
        d -= timedelta(days=1)
    while current < 365:
        if d.isoformat() in all_set:
            current += 1
            d -= timedelta(days=1)
        else:
            break

    longest = run = 0
    prev = None
    for d_str in dates:
        d_obj = _date.fromisoformat(d_str)
        run = run + 1 if (prev and (d_obj - prev).days == 1) else 1
        longest = max(longest, run)
        prev = d_obj

    return {"current": current, "longest": longest}


def get_workout_session(date: str) -> Optional[dict]:
    """Return a single workout session by date (is_second=False), or None."""
    if _client is None or MODE == "OFFLINE":
        return None

    def _do() -> Optional[dict]:
        resp = (
            _client.table("workout_sessions")
            .select("*")
            .eq("date", date)
            .eq("session_type", "morning")
            .limit(1)
            .execute()
        )
        return resp.data[0] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.debug("get_workout_session(%s) retry error: %s", date, e2)
                return None
        logger.debug("get_workout_session(%s) error: %s", date, e)
        return None


def get_or_create_workout_session(date: str) -> dict:
    """Return the workout session for *date*, creating a minimal stub if none exists."""
    existing = get_workout_session(date)
    if existing:
        return existing
    return create_workout_session(date)


def get_workout_session_second(date: str) -> Optional[dict]:
    """Return the second (is_second=True) workout session for a date, or None."""
    if _client is None or MODE == "OFFLINE":
        return None

    def _do() -> Optional[dict]:
        resp = (
            _client.table("workout_sessions")
            .select("*")
            .eq("date", date)
            .eq("is_second", True)
            .single()
            .execute()
        )
        return resp.data

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.debug("get_workout_session_second(%s) retry error: %s", date, e2)
                return None
        logger.debug("get_workout_session_second(%s) error: %s", date, e)
        return None


def get_or_create_workout_session_second(date: str) -> dict:
    """Return the second session for *date*, creating a stub if none exists."""
    existing = get_workout_session_second(date)
    if existing:
        return existing
    return create_workout_session(date, is_second=True, session_type="evening")


def get_workout_session_bonus(date: str) -> Optional[dict]:
    """Return the bonus (session_type='bonus') workout session for a date, or None."""
    if _client is None or MODE == "OFFLINE":
        return None

    def _do() -> Optional[dict]:
        resp = (
            _client.table("workout_sessions")
            .select("*")
            .eq("date", date)
            .eq("session_type", "bonus")
            .limit(1)
            .execute()
        )
        return resp.data[0] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.debug("get_workout_session_bonus(%s) retry error: %s", date, e2)
                return None
        logger.debug("get_workout_session_bonus(%s) error: %s", date, e)
        return None


def get_or_create_workout_session_bonus(date: str) -> dict:
    """Return the bonus session for *date*, creating a stub if none exists."""
    existing = get_workout_session_bonus(date)
    if existing:
        return existing
    return create_workout_session(date, session_type="bonus")


def create_workout_session(
    date: str,
    rpe=None,
    comment=None,
    duration_min=None,
    energy_pre=None,
    is_second: bool = False,
    session_type: str = "morning",
    session_name: str | None = None,
) -> dict:
    """Insert a new workout session row. Returns the created record."""
    payload: dict = {"date": date, "is_second": is_second, "session_type": session_type}
    if rpe is not None:
        payload["rpe"] = int(round(float(rpe)))
    if duration_min is not None:
        payload["duration_min"] = int(float(duration_min))
    if energy_pre is not None:
         payload["energy_pre"] = int(float(energy_pre))
    
    if comment is not None:
        payload["comment"] = comment
    if session_name is not None:
        payload["session_name"] = session_name

    if _client is None or MODE == "OFFLINE":
        return {}

    def _do() -> dict:
        resp = _client.table("workout_sessions").insert(payload).execute()
        return resp.data[0] if resp.data else payload

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("create_workout_session retry error: %s", e2)
                return {}
        logger.error("create_workout_session error: %s", e)
        return {}


def complete_workout_session(date: str, patch: Optional[dict] = None) -> bool:
    """Mark a workout session as completed and persist session metadata."""
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        # Warn when completing a session that has no exercise logs — likely a
        # crash-during-write scenario where exercise data was lost.
        try:
            session_row = (
                _client.table("workout_sessions")
                .select("id")
                .eq("date", date)
                .eq("session_type", "morning")
                .single()
                .execute()
            )
            if session_row.data:
                log_check = (
                    _client.table("exercise_logs")
                    .select("id", count="exact")
                    .eq("session_id", session_row.data["id"])
                    .limit(1)
                    .execute()
                )
                if (log_check.count or 0) == 0:
                    logger.warning(
                        "complete_workout_session: completing session %s on %s with zero exercise_logs",
                        session_row.data["id"], date,
                    )
        except Exception:
            pass  # guard should never block completion

        data = {"completed": True}
        if patch:
            for k, v in patch.items():
                if k not in ("rpe", "comment", "duration_min", "energy_pre", "session_name"):
                    continue
                if v is None:
                    continue
                if k == "rpe":
                    data[k] = int(round(float(v)))
                elif k in ("duration_min", "energy_pre"):
                    data[k] = int(float(v))
                else:
                    data[k] = v
        resp = (
            _client.table("workout_sessions")
            .update(data)
            .eq("date", date)
            .eq("session_type", "morning")
            .execute()
        )
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("complete_workout_session retry error: %s", e2)
                return False
        logger.error("complete_workout_session error: %s", e)
        return False


def complete_workout_session_bonus(date: str, patch: Optional[dict] = None) -> bool:
    """Mark a bonus session as completed and persist session metadata."""
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        data = {"completed": True}
        if patch:
            for k, v in patch.items():
                if k not in ("rpe", "comment", "duration_min", "energy_pre", "session_name"):
                    continue
                if v is None:
                    continue
                if k == "rpe":
                    data[k] = int(round(float(v)))
                elif k in ("duration_min", "energy_pre"):
                    data[k] = int(float(v))
                else:
                    data[k] = v
        resp = (
            _client.table("workout_sessions")
            .update(data)
            .eq("date", date)
            .eq("session_type", "bonus")
            .execute()
        )
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("complete_workout_session_bonus retry error: %s", e2)
                return False
        logger.error("complete_workout_session_bonus error: %s", e)
        return False


def update_workout_session_bonus(date: str, patch: dict) -> bool:
    """Update fields on a bonus session. Returns True on success."""
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        resp = (
            _client.table("workout_sessions")
            .update(patch)
            .eq("date", date)
            .eq("session_type", "bonus")
            .execute()
        )
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("update_workout_session_bonus retry error: %s", e2)
                return False
        logger.error("update_workout_session_bonus error: %s", e)
        return False


def delete_workout_session_by_type(date: str, session_type: str = "morning") -> bool:
    """Delete a single session row by date + session_type."""
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        resp = (
            _client.table("workout_sessions")
            .delete()
            .eq("date", date)
            .eq("session_type", session_type)
            .execute()
        )
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("delete_workout_session_by_type retry error: %s", e2)
                return False
        logger.error("delete_workout_session_by_type error: %s", e)
        return False


def delete_exercise_logs_for_session(session_id: str) -> bool:
    """Delete all exercise_logs for a given session_id."""
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        _client.table("exercise_logs").delete().eq("session_id", session_id).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("delete_exercise_logs_for_session retry error: %s", e2)
                return False
        logger.error("delete_exercise_logs_for_session error: %s", e)
        return False


def upsert_exercise_log_direct(
    session_id: str,
    exercise_name: str,
    weight: float,
    reps: str,
    sets_json: list | None = None,
    rpe: float | None = None,
    pain_zone: str | None = None,
) -> bool:
    """Insert/update an exercise_log row using session_id directly (bypasses date lookup)."""
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        exercise_id = get_or_create_exercise_id(exercise_name)
        if not exercise_id:
            logger.warning("upsert_exercise_log_direct: exercise '%s' unavailable", exercise_name)
            return False
        payload = {
            "session_id": session_id,
            "exercise_id": exercise_id,
            "weight": weight,
            "reps": reps,
        }
        if sets_json is not None:
            payload["sets_json"] = sets_json
        if rpe is not None:
            payload["rpe"] = round(float(rpe), 1)
        if pain_zone:
            payload["pain_zone"] = pain_zone
        resp = (
            _client.table("exercise_logs")
            .upsert(payload, on_conflict="session_id,exercise_id")
            .execute()
        )
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("upsert_exercise_log_direct retry error: %s", e2)
                return False
        logger.error("upsert_exercise_log_direct error: %s", e)
        return False


def get_exercise_history_grouped_by_session(session_ids: list | None = None) -> dict:
    """Return exercise history keyed by workout_sessions.id (UUID string).

    Paginates through exercise_logs to bypass Supabase's 1000-row default cap.
    Returns: {session_id: [{"exercise": name, "weight": w, "reps": r}, ...]}
    """
    if _client is None or MODE == "OFFLINE":
        return {}
    result: dict = {}
    page_size = 1000
    offset = 0

    def _do() -> dict:
        nonlocal result, offset
        result = {}
        offset = 0
        while True:
            q = (
                _client.table("exercise_logs")
                .select("weight, reps, session_id, exercises(name)")
                .range(offset, offset + page_size - 1)
            )
            if session_ids:
                q = q.in_("session_id", session_ids)
            resp = q.execute()
            rows = resp.data or []
            for r in rows:
                sid = r.get("session_id")
                name = (r.get("exercises") or {}).get("name")
                if not sid or not name:
                    continue
                result.setdefault(sid, []).append({
                    "exercise": name,
                    "weight":   r.get("weight", 0),
                    "reps":     r.get("reps", ""),
                })
            if len(rows) < page_size:
                break
            offset += page_size
        return result

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_exercise_history_grouped_by_session retry error: %s", e2)
                return result  # return partial data rather than empty
        logger.error("get_exercise_history_grouped_by_session error: %s", e)
        return result  # return partial data rather than empty


def update_workout_session_by_type(date: str, session_type: str, patch: dict) -> bool:
    """Update fields on a workout session identified by date + session_type."""
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        resp = (
            _client.table("workout_sessions")
            .update(patch)
            .eq("date", date)
            .eq("session_type", session_type)
            .execute()
        )
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("update_workout_session_by_type(%s,%s) retry error: %s", date, session_type, e2)
                return False
        logger.error("update_workout_session_by_type(%s,%s) error: %s", date, session_type, e)
        return False

INT_FIELDS = {"duration_min", "energy_pre", "rpe"}  # rpe is SMALLINT in DB
DECIMAL_FIELDS: set = set()

def update_workout_session(date: str, patch: dict) -> bool:
    """Update fields on a workout session by date. Returns True on success."""
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        cleaned = {}

        for k, v in patch.items():
            if v is None:
                cleaned[k] = None
            elif k in INT_FIELDS:
                cleaned[k] = int(float(v))
            elif k in DECIMAL_FIELDS:
                cleaned[k] = round(float(v), 1)
            else:
                cleaned[k] = v

        resp = (
            _client.table("workout_sessions")
            .update(cleaned)
            .eq("date", date)
            .eq("session_type", "morning")
            .execute()
        )

        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("update_workout_session retry error: %s", e2)
                return False
        logger.error("update_workout_session error: %s", e)
        return False


def delete_workout_session(date: str) -> bool:
    """Delete a workout session and its exercise_logs (cascade). Returns True on success."""
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        resp = _client.table("workout_sessions").delete().eq("date", date).execute()
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("delete_workout_session retry error: %s", e2)
                return False
        logger.error("delete_workout_session error: %s", e)
        return False


# ---------------------------------------------------------------------------
# Exercise logs
# ---------------------------------------------------------------------------

def get_exercise_history(exercise_name: str, limit: int = 50) -> List[dict]:
    """Return [{date, weight, reps, session_id}] newest first."""
    if _client is None or MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        ex_id = get_exercise_id(exercise_name)
        if not ex_id:
            return []
        resp = (
            _client.table("exercise_logs")
            .select("weight, reps, sets_json, session_id, workout_sessions(date)")
            .eq("exercise_id", ex_id)
            .order("workout_sessions(date)", desc=True)
            .limit(limit)
            .execute()
        )
        rows = resp.data or []
        return [
            {
                "date":       r["workout_sessions"]["date"],
                "weight":     r["weight"],
                "reps":       r["reps"],
                "sets_json":  r.get("sets_json"),
                "session_id": r["session_id"],
            }
            for r in rows
            if r.get("workout_sessions")
        ]

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_exercise_history(%s) retry error: %s", exercise_name, e2)
                return []
        logger.error("get_exercise_history(%s) error: %s", exercise_name, e)
        return []


def get_all_exercise_history() -> dict:
    """Return {exercise_name: [{date, weight, reps}]} for all exercises in one query.

    Used by load_weights() to avoid N+1 per-exercise queries.
    Paginates to bypass Supabase's 1000-row default cap.
    """
    if _client is None or MODE == "OFFLINE":
        return {}
    page_size = 1000

    def _do() -> dict:
        result: dict = {}
        offset = 0
        while True:
            resp = (
                _client.table("exercise_logs")
                .select("weight, reps, sets_json, exercises(name), workout_sessions(date)")
                .range(offset, offset + page_size - 1)
                .execute()
            )
            rows = resp.data or []
            for r in rows:
                name = (r.get("exercises") or {}).get("name")
                date = (r.get("workout_sessions") or {}).get("date")
                if not name or not date:
                    continue
                entry = {"date": date, "weight": r.get("weight"), "reps": r.get("reps")}
                sets_json = r.get("sets_json")
                if sets_json:
                    entry["sets"] = sets_json
                result.setdefault(name, []).append(entry)
            if len(rows) < page_size:
                break
            offset += page_size
        # Sort each exercise history newest-first
        for name in result:
            result[name].sort(key=lambda x: x.get("date", ""), reverse=True)
        return result

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_all_exercise_history retry error: %s", e2)
                return {}
        logger.error("get_all_exercise_history error: %s", e)
        return {}


def get_exercise_history_bulk(exercise_names: list[str], limit_per: int = 20) -> dict:
    """Return {exercise_name: [{date, weight, reps, sets_json}]} for a subset of exercises.

    This is a performance-critical helper for /api/seance_data: we only need
    today's exercises, not the full training history for every exercise.
    """
    if _client is None or MODE == "OFFLINE":
        return {}
    names = [n for n in exercise_names if isinstance(n, str) and n.strip()]
    if not names:
        return {}

    def _do() -> dict:
        ex_rows = (
            _client.table("exercises")
            .select("id,name")
            .in_("name", names)
            .is_("deleted_at", "null")
            .execute()
        ).data or []
        id_to_name = {r["id"]: r["name"] for r in ex_rows if r.get("id") and r.get("name")}
        ex_ids = list(id_to_name.keys())
        if not ex_ids:
            return {}

        resp = (
            _client.table("exercise_logs")
            .select("exercise_id, weight, reps, sets_json, workout_sessions(date)")
            .in_("exercise_id", ex_ids)
            .order("workout_sessions(date)", desc=True)
            .execute()
        )
        rows = resp.data or []
        result: dict[str, list[dict]] = {id_to_name[i]: [] for i in ex_ids if i in id_to_name}
        for r in rows:
            ex_id = r.get("exercise_id")
            name = id_to_name.get(ex_id)
            if not name:
                continue
            d = (r.get("workout_sessions") or {}).get("date")
            if not d:
                continue
            lst = result.setdefault(name, [])
            if len(lst) >= limit_per:
                continue
            entry = {"date": d, "weight": r.get("weight"), "reps": r.get("reps")}
            if r.get("sets_json"):
                entry["sets"] = r.get("sets_json")
            lst.append(entry)
        return result

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_exercise_history_bulk retry error: %s", e2)
                return {}
        logger.error("get_exercise_history_bulk error: %s", e)
        return {}


def get_session_exercise_logs(session_date: str) -> List[dict]:
    """Return [{exercise_name, weight, reps}] for a given session date."""
    if _client is None or MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        session = get_workout_session(session_date)
        if not session:
            return []
        session_id = session["id"]
        resp = (
            _client.table("exercise_logs")
            .select("weight, reps, exercises(name)")
            .eq("session_id", session_id)
            .execute()
        )
        rows = resp.data or []
        return [
            {
                "exercise_name": r["exercises"]["name"],
                "weight": r["weight"],
                "reps": r["reps"],
            }
            for r in rows
            if r.get("exercises")
        ]

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_session_exercise_logs(%s) retry error: %s", session_date, e2)
                return []
        logger.error("get_session_exercise_logs(%s) error: %s", session_date, e)
        return []


def get_previous_session_by_name(current_date: str, session_name: str) -> Optional[dict]:
    """Return the most recent workout_session with session_name strictly before current_date."""
    if _client is None or MODE == "OFFLINE":
        return None

    def _do() -> Optional[dict]:
        resp = (
            _client.table("workout_sessions")
            .select("*")
            .eq("session_name", session_name)
            .lt("date", current_date)
            .order("date", desc=True)
            .limit(1)
            .execute()
        )
        return resp.data[0] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_previous_session_by_name(%s,%s) retry error: %s", current_date, session_name, e2)
                return None
        logger.error("get_previous_session_by_name(%s,%s) error: %s", current_date, session_name, e)
        return None


def get_workout_session_by_type(date: str, session_type: str) -> Optional[dict]:
    """Return workout session for date + session_type, or None."""
    if _client is None or MODE == "OFFLINE":
        return None

    def _do() -> Optional[dict]:
        resp = (
            _client.table("workout_sessions")
            .select("*")
            .eq("date", date)
            .eq("session_type", session_type)
            .limit(1)
            .execute()
        )
        return resp.data[0] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_workout_session_by_type(%s,%s) retry error: %s", date, session_type, e2)
                return None
        logger.error("get_workout_session_by_type(%s,%s) error: %s", date, session_type, e)
        return None


def get_exercise_logs_for_session_with_names(session_id: str) -> List[dict]:
    """Return [{exercise_name, weight, reps, sets_json}] for a session_id."""
    if _client is None or MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        resp = (
            _client.table("exercise_logs")
            .select("weight, reps, sets_json, exercises(name)")
            .eq("session_id", session_id)
            .execute()
        )
        rows = resp.data or []
        return [
            {
                "exercise_name": r["exercises"]["name"],
                "weight": r["weight"],
                "reps": r["reps"],
                "sets_json": r.get("sets_json") or [],
            }
            for r in rows
            if r.get("exercises")
        ]

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_exercise_logs_for_session_with_names(%s) retry error: %s", session_id, e2)
                return []
        logger.error("get_exercise_logs_for_session_with_names(%s) error: %s", session_id, e)
        return []


def get_exercise_logs_since(cutoff_date: str) -> List[dict]:
    """Return exercise logs since cutoff_date (inclusive) with muscles info.

    Returns [{exercise_name, muscles, sets_json, rpe, date}] sorted date desc.
    Used by muscle_volume.compute_weekly_hard_sets().
    """
    if _client is None or MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        resp = (
            _client.table("exercise_logs")
            .select("sets_json, exercises(name, muscles), workout_sessions(date, rpe)")
            .gte("workout_sessions.date", cutoff_date)
            .execute()
        )
        rows = resp.data or []
        result = []
        for r in rows:
            ex  = r.get("exercises") or {}
            ses = r.get("workout_sessions") or {}
            if not ex.get("name") or not ses.get("date"):
                continue
            result.append({
                "exercise_name": ex["name"],
                "muscles":       ex.get("muscles") or [],
                "sets_json":     r.get("sets_json") or [],
                "rpe":           ses.get("rpe"),
                "date":          ses["date"],
            })
        return result

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_exercise_logs_since(%s) retry error: %s", cutoff_date, e2)
                return []
        logger.error("get_exercise_logs_since(%s) error: %s", cutoff_date, e)
        return []


def get_previous_session_by_exercises(ref_date: str, session_type: str, exercise_names: list) -> Optional[dict]:
    """
    Find the most recent session before ref_date whose exercise_logs contain
    the most overlap with exercise_names.  Used as fallback when session_name
    is NULL (sessions logged before migration 010).

    Three queries: exercise IDs → session IDs with overlap count → session rows.
    Returns the most recent session with ≥40% exercise overlap, or the most
    recent session among the candidates if none reaches the threshold.
    """
    if not exercise_names or _client is None or MODE == "OFFLINE":
        return None

    def _do() -> Optional[dict]:
        # 1. Resolve exercise names → IDs
        ex_resp = (
            _client.table("exercises")
            .select("id")
            .in_("name", exercise_names)
            .is_("deleted_at", "null")
            .execute()
        )
        ex_ids = [e["id"] for e in (ex_resp.data or [])]
        if not ex_ids:
            return None

        # 2. Find session IDs that have any of those exercises
        logs_resp = (
            _client.table("exercise_logs")
            .select("session_id, exercise_id")
            .in_("exercise_id", ex_ids)
            .limit(1000)
            .execute()
        )
        session_counts: dict = {}
        for log in (logs_resp.data or []):
            sid = log["session_id"]
            session_counts[sid] = session_counts.get(sid, 0) + 1
        if not session_counts:
            return None

        # 3. Filter to sessions of the right type before ref_date
        sessions_resp = (
            _client.table("workout_sessions")
            .select("id, date, session_type, session_name")
            .in_("id", list(session_counts.keys()))
            .eq("session_type", session_type)
            .lt("date", ref_date)
            .order("date", desc=True)
            .limit(10)
            .execute()
        )
        candidates = sessions_resp.data or []
        if not candidates:
            return None

        threshold = max(1, len(exercise_names) * 0.4)
        for s in candidates:
            if session_counts.get(s["id"], 0) >= threshold:
                return s
        return candidates[0]

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_previous_session_by_exercises(%s) retry error: %s", ref_date, e2)
                return None
        logger.error("get_previous_session_by_exercises(%s) error: %s", ref_date, e)
        return None


def get_previous_session_of_type(current_date: str, session_type: str) -> Optional[dict]:
    """Return the most recent workout_session of session_type strictly before current_date."""
    if _client is None or MODE == "OFFLINE":
        return None

    def _do() -> Optional[dict]:
        resp = (
            _client.table("workout_sessions")
            .select("*")
            .eq("session_type", session_type)
            .lt("date", current_date)
            .order("date", desc=True)
            .limit(1)
            .execute()
        )
        return resp.data[0] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_previous_session_of_type(%s,%s) retry error: %s", current_date, session_type, e2)
                return None
        logger.error("get_previous_session_of_type(%s,%s) error: %s", current_date, session_type, e)
        return None


def get_exercise_info(exercise_name: str) -> Optional[dict]:
    """Return exercise row (category, load_profile, default_scheme) from exercises table."""
    if _client is None or MODE == "OFFLINE":
        return None

    def _do() -> Optional[dict]:
        resp = (
            _client.table("exercises")
            .select("name, category, load_profile, default_scheme")
            .eq("name", exercise_name)
            .is_("deleted_at", "null")
            .limit(1)
            .execute()
        )
        return resp.data[0] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_exercise_info(%s) retry error: %s", exercise_name, e2)
                return None
        logger.error("get_exercise_info(%s) error: %s", exercise_name, e)
        return None


def get_exercises_info_bulk(exercise_names: list[str]) -> dict[str, dict]:
    """Batch fetch exercise info (category, load_profile, default_scheme) for multiple exercises.

    Returns: {exercise_name: {category, load_profile, default_scheme}}
    """
    if _client is None or MODE == "OFFLINE":
        return {}
    names = [n for n in exercise_names if isinstance(n, str) and n.strip()]
    if not names:
        return {}

    def _do() -> dict[str, dict]:
        resp = (
            _client.table("exercises")
            .select("name, category, load_profile, default_scheme")
            .in_("name", names)
            .is_("deleted_at", "null")
            .execute()
        )
        return {row["name"]: row for row in (resp.data or []) if row.get("name")}

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_exercises_info_bulk retry error: %s", e2)
                return {}
        logger.error("get_exercises_info_bulk error: %s", e)
        return {}


def update_exercise_default_scheme(exercise_name: str, default_scheme: str) -> bool:
    """Update exercises.default_scheme for an exercise."""
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        _client.table("exercises").update({"default_scheme": default_scheme}).eq("name", exercise_name).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("update_exercise_default_scheme(%s) retry error: %s", exercise_name, e2)
                return False
        logger.error("update_exercise_default_scheme(%s) error: %s", exercise_name, e)
        return False


def normalize_schemes_max_sets(max_sets: int = 3) -> int:
    """Cap set count to max_sets for every exercise whose default_scheme has more.
    e.g. '4x5' → '3x5', '5x3' → '3x3'. Returns number of exercises updated."""
    import re
    if _client is None or MODE == "OFFLINE":
        return 0

    def _do() -> int:
        rows = (_client.table("exercises").select("name,default_scheme").is_("deleted_at", "null").execute().data or [])
        updated = 0
        for row in rows:
            scheme = (row.get("default_scheme") or "").strip()
            m = re.match(r'^(\d+)(x.+)$', scheme, re.IGNORECASE)
            if m and int(m.group(1)) > max_sets:
                new_scheme = f"{max_sets}{m.group(2)}"
                _client.table("exercises").update({"default_scheme": new_scheme}).eq("name", row["name"]).execute()
                updated += 1
        return updated

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("normalize_schemes_max_sets retry error: %s", e2)
                return 0
        logger.error("normalize_schemes_max_sets error: %s", e)
        return 0


def bulk_set_rest_seconds(seconds: int) -> bool:
    """Set rest_seconds = seconds for every exercise in the inventory."""
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        _client.table("exercises").update({"rest_seconds": seconds}).neq("name", "").is_("deleted_at", "null").execute()
        return True

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("bulk_set_rest_seconds retry error: %s", e2)
                return False
        logger.error("bulk_set_rest_seconds error: %s", e)
        return False


def upsert_exercise_log(
    session_date: str, exercise_name: str, weight: float, reps: str, sets_json: list | None = None
) -> bool:
    """Insert or update an exercise log entry. Resolves IDs internally. Returns True on success."""
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        exercise_id = get_or_create_exercise_id(exercise_name)
        if not exercise_id:
            logger.warning("upsert_exercise_log: exercise '%s' unavailable", exercise_name)
            return False
        session = get_workout_session(session_date)
        if not session:
            logger.warning("upsert_exercise_log: no session for date %s", session_date)
            return False
        session_id = session["id"]
        payload = {
            "session_id": session_id,
            "exercise_id": exercise_id,
            "weight": weight,
            "reps": reps,
        }
        if sets_json is not None:
            payload["sets_json"] = sets_json
        resp = (
            _client.table("exercise_logs")
            .upsert(payload, on_conflict="session_id,exercise_id")
            .execute()
        )
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("upsert_exercise_log retry error: %s", e2)
                return False
        logger.error("upsert_exercise_log error: %s", e)
        return False


def upsert_exercise_log_by_type(
    session_date: str,
    session_type: str,
    exercise_name: str,
    weight: float,
    reps: str,
    sets_json: list | None = None,
) -> bool:
    """Insert/update an exercise log entry by date + session_type."""
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        exercise_id = get_or_create_exercise_id(exercise_name)
        if not exercise_id:
            logger.warning("upsert_exercise_log_by_type: exercise '%s' unavailable", exercise_name)
            return False
        session = get_workout_session_by_type(session_date, session_type)
        if not session:
            logger.warning("upsert_exercise_log_by_type: no session for date=%s type=%s", session_date, session_type)
            return False
        payload = {
            "session_id": session["id"],
            "exercise_id": exercise_id,
            "weight": weight,
            "reps": reps,
        }
        if sets_json is not None:
            payload["sets_json"] = sets_json
        resp = (
            _client.table("exercise_logs")
            .upsert(payload, on_conflict="session_id,exercise_id")
            .execute()
        )
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("upsert_exercise_log_by_type retry error: %s", e2)
                return False
        logger.error("upsert_exercise_log_by_type error: %s", e)
        return False


def delete_exercise_log_entry(session_date: str, exercise_name: str) -> bool:
    """Delete a single exercise_log entry by date + exercise name."""
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        session = get_workout_session(session_date)
        if not session:
            return False
        exercise_id = get_exercise_id(exercise_name)
        if not exercise_id:
            return False
        _client.table("exercise_logs") \
            .delete() \
            .eq("session_id", session["id"]) \
            .eq("exercise_id", exercise_id) \
            .execute()
        return True

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("delete_exercise_log_entry retry error: %s", e2)
                return False
        logger.error("delete_exercise_log_entry error: %s", e)
        return False


def delete_exercise_log_entry_by_type(session_date: str, session_type: str, exercise_name: str) -> bool:
    """Delete one exercise_log entry by date + session_type + exercise name."""
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        session = get_workout_session_by_type(session_date, session_type)
        if not session:
            return False
        exercise_id = get_exercise_id(exercise_name)
        if not exercise_id:
            return False
        _client.table("exercise_logs") \
            .delete() \
            .eq("session_id", session["id"]) \
            .eq("exercise_id", exercise_id) \
            .execute()
        return True

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("delete_exercise_log_entry_by_type retry error: %s", e2)
                return False
        logger.error("delete_exercise_log_entry_by_type error: %s", e)
        return False


def delete_session_exercise_logs(session_date: str) -> bool:
    """Delete all exercise_logs for a given session date. Returns True on success."""
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        session = get_workout_session(session_date)
        if not session:
            return False
        session_id = session["id"]
        _client.table("exercise_logs").delete().eq("session_id", session_id).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("delete_session_exercise_logs retry error: %s", e2)
                return False
        logger.error("delete_session_exercise_logs error: %s", e)
        return False


# ---------------------------------------------------------------------------
# Body weight
# ---------------------------------------------------------------------------

def get_body_weight_logs(limit: int = 100) -> List[dict]:
    """Return body weight log entries, newest first.
    weight field is in lbs (not kg).
    """
    if _client is None or MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        resp = (
            _client.table("body_weight_logs")
            .select("*")
            .order("date", desc=True)
            .limit(limit)
            .execute()
        )
        return resp.data or []

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_body_weight_logs retry error: %s", e2)
                return []
        logger.error("get_body_weight_logs error: %s", e)
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
    if _client is None or MODE == "OFFLINE":
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
            _client.table("body_weight_logs")
            .upsert(payload, on_conflict="date")
            .execute()
        )
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("upsert_body_weight retry error: %s", e2)
                return False
        logger.error("upsert_body_weight error: %s", e)
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
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        _client.table("body_weight_logs").delete().eq("date", date).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("delete_body_weight retry error: %s", e2)
                return False
        logger.error("delete_body_weight error: %s", e)
        return False


# ---------------------------------------------------------------------------
# HIIT logs
# ---------------------------------------------------------------------------

def get_hiit_logs(limit: int = 100) -> List[dict]:
    """Return HIIT log entries, newest first."""
    if _client is None or MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        resp = (
            _client.table("hiit_logs")
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
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_hiit_logs retry error: %s", e2)
                return []
        logger.error("get_hiit_logs error: %s", e)
        return []


def insert_hiit_log(data: dict) -> dict:
    """Insert a new HIIT log entry. Returns the inserted record."""
    if _client is None or MODE == "OFFLINE":
        return data

    def _do() -> dict:
        resp = _client.table("hiit_logs").insert(data).execute()
        return resp.data[0] if resp.data else data

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("insert_hiit_log retry error: %s", e2)
                return data
        logger.error("insert_hiit_log error: %s", e)
        return data


def update_hiit_log(hiit_id: str, patch: dict) -> bool:
    """Update a HIIT log entry by its UUID. Returns True on success."""
    # fallback to KV during migration
    if _client is None or MODE == "OFFLINE":
        logger.warning("update_hiit_log: UUID-based update not supported in KV fallback")
        return False

    def _do() -> bool:
        resp = _client.table("hiit_logs").update(patch).eq("id", hiit_id).execute()
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("update_hiit_log retry error: %s", e2)
                return False  # fallback to KV during migration not feasible by UUID
        logger.error("update_hiit_log error: %s", e)
        return False  # fallback to KV during migration not feasible by UUID


def delete_hiit_log_by_id(hiit_id: str) -> bool:
    """Delete a HIIT log entry by its UUID. Returns True on success."""
    # fallback to KV during migration
    if _client is None or MODE == "OFFLINE":
        logger.warning("delete_hiit_log_by_id: UUID-based deletion not supported in KV fallback")
        return False

    def _do() -> bool:
        resp = _client.table("hiit_logs").delete().eq("id", hiit_id).execute()
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("delete_hiit_log_by_id retry error: %s", e2)
                return False  # fallback to KV during migration not feasible by UUID
        logger.error("delete_hiit_log_by_id error: %s", e)
        return False  # fallback to KV during migration not feasible by UUID


# ---------------------------------------------------------------------------
# Recovery logs
# ---------------------------------------------------------------------------

def get_recovery_logs(limit: int = 100) -> List[dict]:
    """Return recovery log entries, newest first."""
    if _client is None or MODE == "OFFLINE":
        return []
    def _fetch():
        return (
            _client.table("recovery_logs")
            .select("*")
            .order("date", desc=True)
            .limit(limit)
            .execute()
        )
    try:
        return _fetch().data or []
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _fetch().data or []
            except Exception as e2:
                logger.error("get_recovery_logs retry error: %s", e2)
                return []
        logger.error("get_recovery_logs error: %s", e)
        return []


def upsert_recovery_log(data: dict) -> bool:
    """Insert or update a recovery log by date. data must include 'date'."""
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        resp = (
            _client.table("recovery_logs")
            .upsert(data, on_conflict="date")
            .execute()
        )
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("upsert_recovery_log retry error: %s", e2)
                return False
        logger.error("upsert_recovery_log error: %s", e)
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
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        resp = _client.table("recovery_logs").delete().eq("date", date).execute()
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("delete_recovery_log retry error: %s", e2)
                return False
        logger.error("delete_recovery_log error: %s", e)
        return False


# ---------------------------------------------------------------------------
# Goals
# ---------------------------------------------------------------------------

def get_goals() -> Dict[str, dict]:
    """Return {exercise_name: {target_weight, target_date, id}}.

    'achieved' is NOT stored — derive it by comparing target_weight
    against get_exercise_history(name, limit=1)[0]['weight'].
    """
    if _client is None or MODE == "OFFLINE":
        return {}

    def _do() -> Dict[str, dict]:
        resp = (
            _client.table("goals")
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
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_goals retry error: %s", e2)
                return {}
        logger.error("get_goals error: %s", e)
        return {}


def set_goal(
    exercise_name: str,
    target_weight: float,
    target_date: Optional[str] = None,
) -> bool:
    """Create or update a goal for an exercise. Returns True on success."""
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        exercise_id = get_or_create_exercise_id(exercise_name)
        if not exercise_id:
            logger.warning("set_goal: exercise '%s' not found/created", exercise_name)
            return False
        payload: dict = {"exercise_id": exercise_id, "target_weight": target_weight}
        if target_date:
            payload["target_date"] = target_date
        resp = (
            _client.table("goals")
            .upsert(payload, on_conflict="exercise_id")
            .execute()
        )
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("set_goal retry error: %s", e2)
                return False
        logger.error("set_goal error: %s", e)
        return False


# ---------------------------------------------------------------------------
# Cardio logs
# ---------------------------------------------------------------------------

def get_cardio_logs(limit: int = 100) -> List[dict]:
    """Return cardio log entries, newest first."""
    if _client is None or MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        resp = (
            _client.table("cardio_logs")
            .select("*")
            .order("date", desc=True)
            .limit(limit)
            .execute()
        )
        return resp.data or []

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_cardio_logs retry error: %s", e2)
                return []
        logger.error("get_cardio_logs error: %s", e)
        return []


def insert_cardio_log(data: dict) -> bool:
    """Insert a new cardio log entry. Returns True on success."""
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        resp = _client.table("cardio_logs").insert(data).execute()
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("insert_cardio_log retry error: %s", e2)
                return False
        logger.error("insert_cardio_log error: %s", e)
        return False


def delete_cardio_log(date: str, type_: str) -> bool:
    """Delete a cardio log entry by date and type. Returns True on success."""
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        resp = (
            _client.table("cardio_logs")
            .delete()
            .eq("date", date)
            .eq("type", type_)
            .execute()
        )
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("delete_cardio_log retry error: %s", e2)
                return False
        logger.error("delete_cardio_log error: %s", e)
        return False


# ---------------------------------------------------------------------------
# User profile
# ---------------------------------------------------------------------------

def get_profile() -> dict:
    """Return the single user_profile row as a dict."""
    if _client is None or MODE == "OFFLINE":
        return {}

    def _do() -> dict:
        resp = (
            _client.table("user_profile")
            .select("*")
            .eq("id", 1)
            .limit(1)
            .execute()
        )
        return (resp.data[0] if resp and resp.data else None) or {}

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.warning("get_profile retry error: %s", e2)
                return {}
        logger.warning("get_profile error: %s", e)
        return {}


def update_profile(patch: dict) -> bool:
    """Update the user profile. Creates the row if it does not yet exist."""
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        payload = {**patch, "id": 1, "updated_at": _now_iso()}
        resp = (
            _client.table("user_profile")
            .upsert(payload, on_conflict="id")
            .execute()
        )
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("update_profile retry error: %s", e2)
                return False
        logger.error("update_profile error: %s", e)
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
    if _client is None or MODE == "OFFLINE":
        return _default

    def _do() -> dict:
        resp = (
            _client.table("nutrition_settings")
            .select("*")
            .eq("id", 1)
            .limit(1)
            .execute()
        )
        return (resp.data[0] if resp and resp.data else None) or _default

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.warning("get_nutrition_settings retry error: %s", e2)
                return _default
        logger.warning("get_nutrition_settings error: %s", e)
        return _default


def update_nutrition_settings(patch: dict) -> bool:
    """Update nutrition settings row (Supabase only)."""
    if _client is None or MODE == "OFFLINE":
        raise RuntimeError("Supabase client not available")

    def _do() -> bool:
        payload = {**patch, "id": 1, "updated_at": _now_iso()}
        resp = (
            _client.table("nutrition_settings")
            .upsert(payload, on_conflict="id")
            .execute()
        )
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("update_nutrition_settings retry error: %s", e2)
                return False
        logger.error("update_nutrition_settings error: %s", e)
        return False


# ---------------------------------------------------------------------------
# Nutrition entries
# ---------------------------------------------------------------------------

def get_nutrition_entries(date: str) -> List[dict]:
    """Return nutrition entries for a specific date, ordered by insertion time."""
    if _client is None or MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        resp = (
            _client.table("nutrition_entries")
            .select("*")
            .eq("date", date)
            .order("heure")
            .execute()
        )
        return resp.data or []

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_nutrition_entries retry error: %s", e2)
                return []
        logger.error("get_nutrition_entries error: %s", e)
        return []


def get_nutrition_entries_recent(n: int = 7) -> List[dict]:
    """Return one summary row per day for the last n distinct days.

    Returns [{"date": ..., "calories": ..., "proteines": ..., "nb": ...}, ...] newest first.
    """
    if _client is None or MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        from datetime import date as _date, timedelta
        cutoff = (_date.today() - timedelta(days=n * 2)).isoformat()
        resp = (
            _client.table("nutrition_entries")
            .select("date, calories, proteines")
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
                seen[d] = {"date": d, "calories": 0, "proteines": 0.0, "nb": 0}
            seen[d]["calories"]  += row.get("calories", 0)
            seen[d]["proteines"] += row.get("proteines", 0)
            seen[d]["nb"] += 1
        sorted_days = sorted(seen.values(), key=lambda x: x["date"], reverse=True)[:n]
        for day in sorted_days:
            day["calories"]  = round(day["calories"])
            day["proteines"] = round(day["proteines"], 1)
        return sorted_days

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_nutrition_entries_recent retry error: %s", e2)
                return []
        logger.error("get_nutrition_entries_recent error: %s", e)
        return []


def insert_nutrition_entry(data: dict) -> dict:
    """Insert a nutrition entry. Returns the saved entry (with id).

    Uses upsert on_conflict="id" so retries (network lag, double-tap) are safe:
    same UUID → same row, no calorie duplication.
    """
    if _client is None or MODE == "OFFLINE":
        return data

    def _do() -> dict:
        resp = _client.table("nutrition_entries").upsert(data, on_conflict="id").execute()
        return resp.data[0] if resp.data else data

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("insert_nutrition_entry retry error: %s", e2)
                return data
        logger.error("insert_nutrition_entry error: %s", e)
        return data


def delete_nutrition_entry(entry_id: str) -> bool:
    """Delete a nutrition entry by id. Returns True on success."""
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        resp = _client.table("nutrition_entries").delete().eq("id", entry_id).execute()
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("delete_nutrition_entry retry error: %s", e2)
                return False
        logger.error("delete_nutrition_entry error: %s", e)
        return False


def update_nutrition_entry(entry_id: str, patch: dict) -> bool:
    """Update fields of a nutrition entry by id. Returns True on success."""
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        resp = _client.table("nutrition_entries").update(patch).eq("id", entry_id).execute()
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("update_nutrition_entry retry error: %s", e2)
                return False
        logger.error("update_nutrition_entry error: %s", e)
        return False


# ---------------------------------------------------------------------------
# Hydration
# ---------------------------------------------------------------------------

def get_hydration_today() -> int:
    """Return total ml logged today (0 if none or offline)."""
    if _client is None or MODE == "OFFLINE":
        return 0
    from datetime import date
    today = date.today().isoformat()

    def _do() -> int:
        resp = (
            _client.table("hydration_logs")
            .select("amount_ml")
            .eq("date", today)
            .execute()
        )
        return sum(int(r.get("amount_ml", 0)) for r in (resp.data or []))

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_hydration_today retry error: %s", e2)
                return 0
        logger.error("get_hydration_today error: %s", e)
        return 0


def log_hydration(amount_ml: int) -> None:
    """Insert a hydration entry for today."""
    if _client is None or MODE == "OFFLINE":
        return

    def _do() -> None:
        from datetime import date
        _client.table("hydration_logs").insert({
            "date":      date.today().isoformat(),
            "amount_ml": amount_ml,
        }).execute()

    try:
        _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                _do()
            except Exception as e2:
                logger.error("log_hydration retry error: %s", e2)
        else:
            logger.error("log_hydration error: %s", e)


# ---------------------------------------------------------------------------
# Food catalog
# ---------------------------------------------------------------------------

def get_food_catalog() -> list:
    """Return all food catalog items."""
    if _client is None or MODE == "OFFLINE":
        return []

    def _do() -> list:
        resp = _client.table("food_catalog").select("*").execute()
        return resp.data or []

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_food_catalog retry error: %s", e2)
                return []
        logger.error("get_food_catalog error: %s", e)
        return []


def save_food_catalog(items: list) -> bool:
    """Replace entire food catalog (delete-all + reinsert)."""
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        _client.table("food_catalog").delete().neq("id", "").execute()
        if items:
            _client.table("food_catalog").insert(items).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("save_food_catalog retry error: %s", e2)
                return False
        logger.error("save_food_catalog error: %s", e)
        return False


# ---------------------------------------------------------------------------
# Meal Templates
# ---------------------------------------------------------------------------

def get_meal_templates() -> list:
    """Return all meal templates ordered by name."""
    if _client is None or MODE == "OFFLINE":
        return []

    def _do() -> list:
        resp = _client.table("meal_templates").select("*").order("name").execute()
        return resp.data or []

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_meal_templates retry error: %s", e2)
                return []
        logger.error("get_meal_templates error: %s", e)
        return []


def create_meal_template(name: str, items: list) -> dict | None:
    """Insert a new meal template; returns the created row."""
    if _client is None or MODE == "OFFLINE":
        return None

    def _do() -> dict | None:
        resp = _client.table("meal_templates").insert({"name": name, "items": items}).execute()
        return resp.data[0] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("create_meal_template retry error: %s", e2)
                return None
        logger.error("create_meal_template error: %s", e)
        return None


def update_meal_template(template_id: str, name: str, items: list) -> bool:
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        _client.table("meal_templates")\
            .update({"name": name, "items": items})\
            .eq("id", template_id)\
            .execute()
        return True

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("update_meal_template retry error: %s", e2)
                return False
        logger.error("update_meal_template error: %s", e)
        return False


def delete_meal_template(template_id: str) -> bool:
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        _client.table("meal_templates").delete().eq("id", template_id).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("delete_meal_template retry error: %s", e2)
                return False
        logger.error("delete_meal_template error: %s", e)
        return False


# ---------------------------------------------------------------------------
# Deload state
# ---------------------------------------------------------------------------

def get_deload_state() -> dict:
    """Return the current deload state (single row)."""
    if _client is None or MODE == "OFFLINE":
        return {"active": False, "started_at": None, "reason": None}

    def _do() -> dict:
        resp = (
            _client.table("deload_state")
            .select("*")
            .eq("id", 1)
            .single()
            .execute()
        )
        return resp.data or {"active": False, "started_at": None, "reason": None}

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_deload_state retry error: %s", e2)
                return {"active": False}
        logger.error("get_deload_state error: %s", e)
        return {"active": False}


def set_deload_state(
    active: bool,
    started_at: Optional[str] = None,
    reason: Optional[str] = None,
) -> bool:
    """Set the deload state row. Creates it if not yet present."""
    payload: dict = {"id": 1, "active": active}
    if started_at is not None:
        payload["started_at"] = started_at
    if reason is not None:
        payload["reason"] = reason

    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        resp = (
            _client.table("deload_state")
            .upsert(payload, on_conflict="id")
            .execute()
        )
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("set_deload_state retry error: %s", e2)
                return False
        logger.error("set_deload_state error: %s", e)
        return False


# ---------------------------------------------------------------------------
# Program relational tables
# (program_sessions, program_blocks, program_block_exercises, weekly_schedule)
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# Programs management
# ---------------------------------------------------------------------------

def ensure_schema_migrations() -> bool:
    """Check that migration 002_multi_programs has been applied.

    Returns True if schema is up-to-date.
    Logs a clear error with instructions if migration is missing.
    """
    if _client is None or MODE == "OFFLINE":
        return True

    def _do() -> bool:
        _client.table("weekly_schedule").select("day_name, slot").limit(1).execute()
        _client.table("programs").select("id").limit(1).execute()
        _client.table("program_sessions").select("id, program_id").limit(1).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error(
                    "⚠️  Schema migration required! Run docs/migrations/002_multi_programs.sql "
                    "in your Supabase SQL Editor. Error: %s", e2
                )
                return False
        logger.error(
            "⚠️  Schema migration required! Run docs/migrations/002_multi_programs.sql "
            "in your Supabase SQL Editor. Error: %s", e
        )
        return False


def get_all_programs() -> list:
    """Return [{id, name, created_at}, ...] ordered by created_at ASC."""
    if _client is None or MODE == "OFFLINE":
        return []

    def _do() -> list:
        resp = _client.table("programs").select("id, name, created_at").order("created_at").execute()
        return resp.data or []

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_all_programs retry error: %s", e2)
                return []
        logger.error("get_all_programs error: %s", e)
        return []


def get_active_program_id() -> str | None:
    """Return the active program_id.

    Priority:
    1. user_profile.active_program_id (explicit user choice)
    2. weekly_schedule morning slot (legacy schedule-based detection)
    3. Oldest program (default fallback)
    """
    if _client is None or MODE == "OFFLINE":
        return get_default_program_id()

    # 1. Explicit choice stored in user_profile
    try:
        profile = get_profile()
        pid = profile.get("active_program_id")
        if pid:
            return str(pid)
    except Exception:
        pass

    # 2. Schedule-based detection
    def _do() -> str | None:
        resp = (
            _client.table("weekly_schedule")
            .select("program_sessions(program_id)")
            .eq("slot", "morning")
            .not_.is_("session_id", "null")
            .limit(1)
            .execute()
        )
        for row in (resp.data or []):
            sess = row.get("program_sessions") or {}
            pid = sess.get("program_id")
            if pid:
                return str(pid)
        return None

    try:
        result = _do()
        if result is not None:
            return result
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                result = _do()
                if result is not None:
                    return result
            except Exception as e2:
                logger.error("get_active_program_id retry error: %s", e2)
        else:
            logger.error("get_active_program_id error: %s", e)
    return get_default_program_id()


def set_active_program_id(program_id: str) -> bool:
    """Persist the user's active programme choice in user_profile."""
    return update_profile({"active_program_id": program_id})


def get_session_override() -> dict | None:
    """Return today's session override if it exists and matches today's date.

    Returns {"date": "2026-05-15", "session": "Push B"} or None.
    """
    import json as _json
    from datetime import date
    profile = get_profile()
    raw = profile.get("session_override")
    if not raw:
        return None
    try:
        override = _json.loads(raw) if isinstance(raw, str) else raw
        if isinstance(override, dict) and override.get("date") == date.today().isoformat():
            return override
    except Exception:
        pass
    return None


def set_session_override(session: str | None) -> bool:
    """Store (or clear) a session override for today.

    Pass session=None to clear the override.
    """
    import json as _json
    from datetime import date
    if session is None:
        return update_profile({"session_override": None})
    payload = {"date": date.today().isoformat(), "session": session}
    return update_profile({"session_override": _json.dumps(payload)})


def get_default_program_id() -> str | None:
    """Return the UUID of the first (oldest) program, or None if none exist."""
    programs = get_all_programs()
    return programs[0]["id"] if programs else None


def create_program(name: str) -> str | None:
    """Insert a new program. Returns its UUID or None on error."""
    if _client is None or MODE == "OFFLINE":
        return None

    def _do() -> str | None:
        resp = _client.table("programs").insert({"name": name}).execute()
        return resp.data[0]["id"] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("create_program retry error: %s", e2)
                return None
        logger.error("create_program error: %s", e)
        return None


def rename_program(program_id: str, new_name: str) -> bool:
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        _client.table("programs").update({"name": new_name}).eq("id", program_id).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("rename_program retry error: %s", e2)
                return False
        logger.error("rename_program error: %s", e)
        return False


def delete_program(program_id: str) -> bool:
    """Delete a program — sessions cascade via FK."""
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        _client.table("programs").delete().eq("id", program_id).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("delete_program retry error: %s", e2)
                return False
        logger.error("delete_program error: %s", e)
        return False


def get_cycle_start_date() -> str | None:
    """Return cycle_start_date (YYYY-MM-DD) of the default program, or None."""
    if _client is None or MODE == "OFFLINE":
        return None

    def _do() -> str | None:
        program_id = get_default_program_id()
        if not program_id:
            return None
        resp = (_client.table("programs")
                .select("cycle_start_date")
                .eq("id", program_id)
                .single()
                .execute())
        val = (resp.data or {}).get("cycle_start_date")
        return str(val)[:10] if val else None

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_cycle_start_date retry error: %s", e2)
                return None
        logger.error("get_cycle_start_date error: %s", e)
        return None


def set_cycle_start_date(date_str: str) -> bool:
    """Set cycle_start_date on the default program. date_str = 'YYYY-MM-DD'."""
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        program_id = get_default_program_id()
        if not program_id:
            return False
        _client.table("programs").update({"cycle_start_date": date_str}).eq("id", program_id).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("set_cycle_start_date retry error: %s", e2)
                return False
        logger.error("set_cycle_start_date error: %s", e)
        return False


def get_all_session_names() -> list[str]:
    """Return all session names across all programs (for schedule pickers)."""
    if _client is None or MODE == "OFFLINE":
        return []

    def _do() -> list[str]:
        resp = _client.table("program_sessions").select("name").order("name").execute()
        return [r["name"] for r in (resp.data or [])]

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_all_session_names retry error: %s", e2)
                return []
        logger.error("get_all_session_names error: %s", e)
        return []


def get_full_program(program_id: str | None = None) -> dict | None:
    """Return {session_name: {"blocks": [{"type", "order", "exercises": {name: scheme}}]}}.

    If program_id is None, uses the first/oldest program.
    Compatible with the block format used by planner.py / blocks.py.
    Returns {} if relational tables are genuinely empty (no sessions).
    Returns None if the relational layer is unavailable or a network/query error occurs —
    callers must treat None as "unknown state, do NOT overwrite existing data".
    """
    if _client is None or MODE == "OFFLINE":
        return None

    def _do() -> dict | None:
        q = _client.table("program_sessions").select("id, name, order_index")
        if program_id:
            q = q.eq("program_id", program_id)
        sessions = (q.order("order_index").execute().data) or []
        if not sessions:
            return {}
        program: dict = {}
        for session in sessions:
            sid, sname = session["id"], session["name"]
            blocks_data = (_client.table("program_blocks")
                           .select("id, type, order_index, hiit_config")
                           .eq("session_id", sid).order("order_index")
                           .execute().data) or []
            built_blocks = []
            for block in blocks_data:
                bid   = block["id"]
                btype = block.get("type", "strength")
                border = block.get("order_index", 0)
                if btype == "strength":
                    ex_rows = (_client.table("program_block_exercises")
                               .select("scheme, order_index, exercises(name)")
                               .eq("block_id", bid).order("order_index")
                               .execute().data) or []
                    exercises = {
                        (r.get("exercises") or {}).get("name"): r.get("scheme", "3x8-12")
                        for r in ex_rows if (r.get("exercises") or {}).get("name")
                    }
                    built_blocks.append({"type": "strength", "order": border, "exercises": exercises})
                else:
                    built_blocks.append({"type": btype, "order": border,
                                         "hiit_config": block.get("hiit_config") or {}})
            program[sname] = {"blocks": built_blocks}
        return program

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_full_program retry error: %s", e2)
                return None
        logger.error("get_full_program error: %s", e)
        return None


def get_session_supersets(program_id: str | None = None) -> dict:
    """Return superset structure for all sessions of a program.

    Shape: {session_name: {"SS1": {"A": ex_name, "B": ex_name, "rest": int}, ...}}
    Only exercises with superset_group set are included.
    Returns {} on error or if no superset data exists.
    """
    if _client is None or MODE == "OFFLINE":
        return {}

    def _do() -> dict:
        q = _client.table("program_sessions").select("id, name")
        if program_id:
            q = q.eq("program_id", program_id)
        sessions = (q.order("order_index").execute().data) or []
        result: dict = {}
        for session in sessions:
            sid, sname = session["id"], session["name"]
            blocks = (_client.table("program_blocks")
                      .select("id").eq("session_id", sid).eq("type", "strength")
                      .execute().data) or []
            ss_map: dict = {}
            for block in blocks:
                bid = block["id"]
                rows = (_client.table("program_block_exercises")
                        .select("superset_group, superset_position, rest_after_superset, exercises(name)")
                        .eq("block_id", bid)
                        .not_.is_("superset_group", "null")
                        .order("order_index")
                        .execute().data) or []
                for row in rows:
                    grp     = row.get("superset_group")
                    pos     = row.get("superset_position")
                    ex_name = (row.get("exercises") or {}).get("name")
                    if not grp or not ex_name:
                        continue
                    if grp not in ss_map:
                        ss_map[grp] = {}
                    if pos == 1:
                        ss_map[grp]["A"] = ex_name
                    elif pos == 2:
                        ss_map[grp]["B"] = ex_name
                        ss_map[grp]["rest"] = 120
            if ss_map:
                result[sname] = ss_map
        return result

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_session_supersets retry error: %s", e2)
                return {}
        logger.error("get_session_supersets error: %s", e)
        return {}


def save_full_program(program: dict, program_id: str | None = None) -> bool:
    """Persist {session_name: {"blocks": [...]}} to relational tables.

    If program_id is None, uses the first/oldest program.
    For each session: upsert program_sessions, upsert program_blocks,
    delete + reinsert program_block_exercises.
    Returns True on full success, False on any error.
    """
    if _client is None or MODE == "OFFLINE":
        return False
    if program_id is None:
        program_id = get_default_program_id()

    def _do() -> bool:
        for order_idx, (session_name, session_def) in enumerate(program.items()):
            # Upsert session (conflict on program_id + name after migration)
            upsert_data: dict = {"name": session_name, "order_index": order_idx}
            if program_id:
                upsert_data["program_id"] = program_id
            sess_resp = (
                _client.table("program_sessions")
                .upsert(upsert_data, on_conflict="program_id,name")
                .execute()
            )
            # Fetch session id
            q = _client.table("program_sessions").select("id").eq("name", session_name)
            if program_id:
                q = q.eq("program_id", program_id)
            sess_row = q.single().execute()
            if not sess_row.data:
                logger.error("save_full_program: session %s not found after upsert", session_name)
                continue
            session_id = sess_row.data["id"]

            blocks = session_def.get("blocks", [])
            for block in sorted(blocks, key=lambda b: b.get("order", 0)):
                btype = block.get("type", "strength")
                border = block.get("order", 0)
                hiit_cfg = block.get("hiit_config", {})

                # Upsert block (match by session_id + type + order_index)
                existing_block = (
                    _client.table("program_blocks")
                    .select("id")
                    .eq("session_id", session_id)
                    .eq("type", btype)
                    .eq("order_index", border)
                    .execute()
                )
                if existing_block.data:
                    block_id = existing_block.data[0]["id"]
                    _client.table("program_blocks").update({"hiit_config": hiit_cfg}).eq("id", block_id).execute()
                else:
                    block_resp = (
                        _client.table("program_blocks")
                        .insert({"session_id": session_id, "type": btype, "order_index": border, "hiit_config": hiit_cfg})
                        .execute()
                    )
                    block_id = block_resp.data[0]["id"] if block_resp.data else None

                if not block_id or btype != "strength":
                    continue

                exercises = block.get("exercises", {})

                # Safety guard: never wipe a block that has exercises when saving 0
                # (would silently delete all exercises from program_block_exercises)
                if not exercises:
                    existing_count_resp = (
                        _client.table("program_block_exercises")
                        .select("id", count="exact")
                        .eq("block_id", block_id)
                        .execute()
                    )
                    existing_count = existing_count_resp.count  # None on query error
                    if existing_count is None or existing_count > 0:
                        logger.warning(
                            "save_full_program: refusing to save 0 exercises over %d existing for block %s — skipping",
                            existing_count, block_id,
                        )
                        continue

                # Clear existing exercises for this block then reinsert
                _client.table("program_block_exercises").delete().eq("block_id", block_id).execute()

                for ex_order, (ex_name, scheme) in enumerate(exercises.items()):
                    ex_id_resp = (
                        _client.table("exercises")
                        .select("id")
                        .eq("name", ex_name)
                        .execute()
                    )
                    if not ex_id_resp.data:
                        # Auto-create exercise in inventory with defaults so nothing is lost
                        ins = _client.table("exercises").insert({
                            "name": ex_name,
                            "type": "machine",
                            "category": "strength",
                            "increment": 5.0,
                            "default_scheme": scheme,
                        }).execute()
                        if not ins.data:
                            logger.warning("save_full_program: could not create exercise '%s', skipping", ex_name)
                            continue
                        ex_id = ins.data[0]["id"]
                    else:
                        ex_id = ex_id_resp.data[0]["id"]
                    _client.table("program_block_exercises").insert({
                        "block_id": block_id,
                        "exercise_id": ex_id,
                        "scheme": scheme,
                        "order_index": ex_order,
                    }).execute()

        return True

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("save_full_program retry error: %s", e2)
                return False
        logger.error("save_full_program error: %s", e)
        return False


def delete_program_session(name: str) -> bool:
    """Delete a programme session and all its data (blocks, exercises, schedule refs)."""
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        resp = _client.table("program_sessions").select("id").eq("name", name).limit(1).execute()
        if not resp.data:
            return True  # already gone
        session_id = resp.data[0]["id"]
        # Clear schedule references first (FK)
        _client.table("weekly_schedule").delete().eq("session_id", session_id).execute()
        # Fetch and delete block exercises, then blocks
        blocks_resp = _client.table("program_blocks").select("id").eq("session_id", session_id).execute()
        for block in (blocks_resp.data or []):
            _client.table("program_block_exercises").delete().eq("block_id", block["id"]).execute()
        _client.table("program_blocks").delete().eq("session_id", session_id).execute()
        _client.table("program_sessions").delete().eq("id", session_id).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("delete_program_session retry error: %s", e2)
                return False
        logger.error("delete_program_session error: %s", e)
        return False


def get_relational_week_schedule() -> dict:
    """Return {"Lun": "Push A", "Mar": "Pull A", ...} from weekly_schedule JOIN program_sessions.

    Days with no session assigned are omitted.
    Returns {} if relational layer is unavailable.
    """
    if _client is None or MODE == "OFFLINE":
        return {}

    def _do() -> dict:
        resp = (
            _client.table("weekly_schedule")
            .select("day_name, program_sessions(name)")
            .eq("slot", "morning")
            .execute()
        )
        result: dict = {}
        for row in (resp.data or []):
            session = row.get("program_sessions")
            if session and session.get("name"):
                result[row["day_name"]] = session["name"]
            else:
                # Explicit Repos — must be included so callers don't fall back to hardcoded SCHEDULE
                result[row["day_name"]] = "Repos"
        return result

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_relational_week_schedule retry error: %s", e2)
                return {}
        logger.error("get_relational_week_schedule error: %s", e)
        return {}


def set_relational_week_schedule(schedule: dict) -> bool:
    """Upsert weekly_schedule. schedule = {"Lun": "Push A", "Mar": None, ...}.

    None / missing session_name clears the day (session_id = NULL).
    Returns True on success.
    """
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        active_pid = get_active_program_id()
        for day_name, session_name in schedule.items():
            session_id = None
            if session_name:
                q = (
                    _client.table("program_sessions")
                    .select("id")
                    .eq("name", session_name)
                )
                if active_pid:
                    q = q.eq("program_id", active_pid)
                sess_resp = q.execute()
                if sess_resp.data:
                    session_id = sess_resp.data[0]["id"]
                else:
                    logger.warning(
                        "set_relational_week_schedule: session '%s' not found "
                        "(program_id=%s) — day '%s' will be cleared",
                        session_name, active_pid, day_name,
                    )
            _client.table("weekly_schedule").upsert(
                {"day_name": day_name, "session_id": session_id, "slot": "morning"},
                on_conflict="day_name,slot",
            ).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("set_relational_week_schedule retry error: %s", e2)
                return False
        logger.error("set_relational_week_schedule error: %s", e)
        return False


def get_evening_week_schedule() -> dict:
    """Return {"Lun": "Core", ...} for slot='evening' from weekly_schedule."""
    if _client is None or MODE == "OFFLINE":
        return {}

    def _do() -> dict:
        resp = (
            _client.table("weekly_schedule")
            .select("day_name, program_sessions(name)")
            .eq("slot", "evening")
            .execute()
        )
        result: dict = {}
        for row in (resp.data or []):
            session = row.get("program_sessions")
            if session and session.get("name"):
                result[row["day_name"]] = session["name"]
        return result

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_evening_week_schedule retry error: %s", e2)
                return {}
        logger.error("get_evening_week_schedule error: %s", e)
        return {}


def set_evening_week_schedule(schedule: dict) -> bool:
    """Upsert weekly_schedule for slot='evening'. None clears the day."""
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        active_pid = get_active_program_id()
        for day_name, session_name in schedule.items():
            session_id = None
            if session_name:
                q = (
                    _client.table("program_sessions")
                    .select("id")
                    .eq("name", session_name)
                )
                if active_pid:
                    q = q.eq("program_id", active_pid)
                sess_resp = q.execute()
                if sess_resp.data:
                    session_id = sess_resp.data[0]["id"]
            _client.table("weekly_schedule").upsert(
                {"day_name": day_name, "session_id": session_id, "slot": "evening"},
                on_conflict="day_name,slot",
            ).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("set_evening_week_schedule retry error: %s", e2)
                return False
        logger.error("set_evening_week_schedule error: %s", e)
        return False


# ---------------------------------------------------------------------------
# Mood logs
# ---------------------------------------------------------------------------

def get_mood_logs(days: int = 0, limit: int = 0) -> List[dict]:
    """Return mood log entries, newest first."""
    if _client is None or MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        from datetime import date as _date, timedelta
        q = _client.table("mood_logs").select("*").order("date", desc=True)
        if days:
            cutoff = (_date.today() - timedelta(days=days)).isoformat()
            q = q.gte("date", cutoff)
        if limit:
            q = q.limit(limit)
        resp = q.execute()
        return resp.data or []

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_mood_logs retry error: %s", e2)
                return []
        logger.error("get_mood_logs error: %s", e)
        return []


def insert_mood_log(entry: dict) -> Optional[dict]:
    """Insert a mood log entry. Returns saved record or None."""
    if _client is None or MODE == "OFFLINE":
        return None

    def _do() -> Optional[dict]:
        resp = _client.table("mood_logs").insert(entry).execute()
        return resp.data[0] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("insert_mood_log retry error: %s", e2)
                return None
        logger.error("insert_mood_log error: %s", e)
        return None


# ---------------------------------------------------------------------------
# PSS records
# ---------------------------------------------------------------------------

def get_pss_records(pss_type: Optional[str] = None, limit: int = 0) -> List[dict]:
    """Return PSS records, newest first."""
    if _client is None or MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        q = _client.table("pss_records").select("*").order("date", desc=True)
        if pss_type:
            q = q.eq("type", pss_type)
        if limit:
            q = q.limit(limit)
        resp = q.execute()
        return resp.data or []

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_pss_records retry error: %s", e2)
                return []
        logger.error("get_pss_records error: %s", e)
        return []


def insert_pss_record(entry: dict) -> Optional[dict]:
    """Upsert a PSS record. Returns saved record or None.

    Uses on_conflict="date,type" so resubmitting the same questionnaire
    on the same day updates the existing record instead of creating a duplicate.
    Requires migration 025_pss_unique_date_type.sql.
    """
    if _client is None or MODE == "OFFLINE":
        return None

    def _do() -> Optional[dict]:
        resp = _client.table("pss_records").upsert(entry, on_conflict="date,type").execute()
        return resp.data[0] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("insert_pss_record retry error: %s", e2)
                return None
        logger.error("insert_pss_record error: %s", e)
        return None


# ---------------------------------------------------------------------------
# Sleep records
# ---------------------------------------------------------------------------

def get_sleep_records(limit: int = 0, offset: int = 0) -> List[dict]:
    """Return sleep records, newest first."""
    if _client is None or MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        q = _client.table("sleep_records").select("*").order("date", desc=True)
        if limit:
            q = q.range(offset, offset + limit - 1)
        resp = q.execute()
        return resp.data or []

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_sleep_records retry error: %s", e2)
                return []
        logger.error("get_sleep_records error: %s", e)
        return []


def upsert_sleep_record(entry: dict) -> Optional[dict]:
    """Insert or replace sleep record for a date (on_conflict=date)."""
    if _client is None or MODE == "OFFLINE":
        return None

    def _do() -> Optional[dict]:
        resp = _client.table("sleep_records").upsert(entry, on_conflict="date").execute()
        return resp.data[0] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("upsert_sleep_record retry error: %s", e2)
                return None
        logger.error("upsert_sleep_record error: %s", e)
        return None


def delete_sleep_record(record_id: str) -> bool:
    """Delete a sleep record by id."""
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        _client.table("sleep_records").delete().eq("id", record_id).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("delete_sleep_record retry error: %s", e2)
                return False
        logger.error("delete_sleep_record error: %s", e)
        return False


# ---------------------------------------------------------------------------
# Journal entries
# ---------------------------------------------------------------------------

def get_journal_entries_all(limit: int = 0, offset: int = 0) -> List[dict]:
    """Return journal entries, newest first."""
    if _client is None or MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        q = _client.table("journal_entries").select("*").order("date", desc=True)
        if limit:
            q = q.range(offset, offset + limit - 1)
        resp = q.execute()
        return resp.data or []

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_journal_entries_all retry error: %s", e2)
                return []
        logger.error("get_journal_entries_all error: %s", e)
        return []


def insert_journal_entry(entry: dict) -> Optional[dict]:
    """Insert a journal entry."""
    if _client is None or MODE == "OFFLINE":
        return None

    def _do() -> Optional[dict]:
        resp = _client.table("journal_entries").insert(entry).execute()
        return resp.data[0] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("insert_journal_entry retry error: %s", e2)
                return None
        logger.error("insert_journal_entry error: %s", e)
        return None


def search_journal_entries_db(query: str) -> List[dict]:
    """Search journal entries by content or prompt (case-insensitive)."""
    if _client is None or MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        resp = (
            _client.table("journal_entries")
            .select("*")
            .or_(f"content.ilike.%{query}%,prompt.ilike.%{query}%")
            .order("date", desc=True)
            .execute()
        )
        return resp.data or []

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("search_journal_entries_db retry error: %s", e2)
                return []
        logger.error("search_journal_entries_db error: %s", e)
        return []


def count_journal_entries_since(since_date: str) -> int:
    """Count journal entries on or after since_date."""
    if _client is None or MODE == "OFFLINE":
        return 0

    def _do() -> int:
        resp = (
            _client.table("journal_entries")
            .select("id", count="exact")
            .gte("date", since_date)
            .execute()
        )
        return resp.count or 0

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("count_journal_entries_since retry error: %s", e2)
                return 0
        logger.error("count_journal_entries_since error: %s", e)
        return 0


# ---------------------------------------------------------------------------
# Breathwork sessions
# ---------------------------------------------------------------------------

def get_breathwork_sessions(days: int = 30) -> List[dict]:
    """Return breathwork sessions within last N days, newest first."""
    if _client is None or MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        from datetime import date as _date, timedelta
        cutoff = (_date.today() - timedelta(days=days)).isoformat()
        resp = (
            _client.table("breathwork_sessions")
            .select("*")
            .gte("date", cutoff)
            .order("date", desc=True)
            .execute()
        )
        return resp.data or []

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_breathwork_sessions retry error: %s", e2)
                return []
        logger.error("get_breathwork_sessions error: %s", e)
        return []


def insert_breathwork_session(entry: dict) -> Optional[dict]:
    """Insert a breathwork session."""
    if _client is None or MODE == "OFFLINE":
        return None

    def _do() -> Optional[dict]:
        resp = _client.table("breathwork_sessions").insert(entry).execute()
        return resp.data[0] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("insert_breathwork_session retry error: %s", e2)
                return None
        logger.error("insert_breathwork_session error: %s", e)
        return None


# ---------------------------------------------------------------------------
# Self-care habits + logs
# ---------------------------------------------------------------------------

def get_self_care_habits() -> List[dict]:
    """Return all self-care habits ordered by order_index."""
    if _client is None or MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        resp = _client.table("self_care_habits").select("*").order("order_index").execute()
        return resp.data or []

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_self_care_habits retry error: %s", e2)
                return []
        logger.error("get_self_care_habits error: %s", e)
        return []


def upsert_self_care_habit(habit: dict) -> Optional[dict]:
    """Insert or update a self-care habit by id."""
    if _client is None or MODE == "OFFLINE":
        return None

    def _do() -> Optional[dict]:
        resp = _client.table("self_care_habits").upsert(habit, on_conflict="id").execute()
        return resp.data[0] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("upsert_self_care_habit retry error: %s", e2)
                return None
        logger.error("upsert_self_care_habit error: %s", e)
        return None


def delete_self_care_habit(habit_id: str) -> bool:
    """Delete a self-care habit and all its log entries."""
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        _client.table("self_care_logs").delete().eq("habit_id", habit_id).execute()
        _client.table("self_care_habits").delete().eq("id", habit_id).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("delete_self_care_habit retry error: %s", e2)
                return False
        logger.error("delete_self_care_habit error: %s", e)
        return False


def get_self_care_log(days: int = 90) -> Dict[str, List[str]]:
    """Return {date: [habit_id, ...]} for last N days."""
    if _client is None or MODE == "OFFLINE":
        return {}

    def _do() -> Dict[str, List[str]]:
        from datetime import date as _date, timedelta
        cutoff = (_date.today() - timedelta(days=days)).isoformat()
        resp = (
            _client.table("self_care_logs")
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
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_self_care_log retry error: %s", e2)
                return {}
        logger.error("get_self_care_log error: %s", e)
        return {}


def set_self_care_log_for_date(date: str, habit_ids: List[str]) -> bool:
    """Replace self-care log for a specific date."""
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        _client.table("self_care_logs").delete().eq("date", date).execute()
        if habit_ids:
            rows = [{"date": date, "habit_id": hid} for hid in habit_ids]
            _client.table("self_care_logs").insert(rows).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("set_self_care_log_for_date retry error: %s", e2)
                return False
        logger.error("set_self_care_log_for_date error: %s", e)
        return False


# ---------------------------------------------------------------------------
# Life stress scores
# ---------------------------------------------------------------------------

def get_life_stress_score_db(date: str) -> Optional[dict]:
    """Return cached life stress score for a date, or None."""
    if _client is None or MODE == "OFFLINE":
        return None

    def _do() -> Optional[dict]:
        resp = _client.table("life_stress_scores").select("*").eq("date", date).single().execute()
        return resp.data

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.debug("get_life_stress_score_for_date(%s) retry error: %s", date, e2)
                return None
        logger.debug("get_life_stress_score_for_date(%s): %s", date, e)
        return None


def upsert_life_stress_score(entry: dict) -> bool:
    """Insert or update a life stress score entry."""
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        _client.table("life_stress_scores").upsert(entry, on_conflict="date").execute()
        return True

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("upsert_life_stress_score retry error: %s", e2)
                return False
        logger.error("upsert_life_stress_score error: %s", e)
        return False


# ---------------------------------------------------------------------------
# Coach history
# ---------------------------------------------------------------------------

def get_coach_history(limit: int = 50) -> List[dict]:
    """Return coach history entries, newest first."""
    if _client is None or MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        resp = (
            _client.table("coach_history")
            .select("*")
            .order("created_at", desc=True)
            .limit(limit)
            .execute()
        )
        return resp.data or []

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_coach_history retry error: %s", e2)
                return []
        logger.error("get_coach_history error: %s", e)
        return []


def insert_coach_message(entry: dict) -> Optional[dict]:
    """Insert a coach history message."""
    if _client is None or MODE == "OFFLINE":
        return None

    def _do() -> Optional[dict]:
        resp = _client.table("coach_history").insert(entry).execute()
        return resp.data[0] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("insert_coach_message retry error: %s", e2)
                return None
        logger.error("insert_coach_message error: %s", e)
        return None


# ---------------------------------------------------------------------------
# Goals archived
# ---------------------------------------------------------------------------

def get_goals_archived() -> List[str]:
    """Return list of archived exercise names."""
    if _client is None or MODE == "OFFLINE":
        return []

    def _do() -> List[str]:
        resp = _client.table("goals_archived").select("exercise_name").execute()
        return [r["exercise_name"] for r in (resp.data or [])]

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_goals_archived retry error: %s", e2)
                return []
        logger.error("get_goals_archived error: %s", e)
        return []


def add_goal_archived(exercise_name: str) -> bool:
    """Archive a goal by exercise name."""
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        _client.table("goals_archived").upsert(
            {"exercise_name": exercise_name}, on_conflict="exercise_name"
        ).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("add_goal_archived retry error: %s", e2)
                return False
        logger.error("add_goal_archived error: %s", e)
        return False


def remove_goal_archived(exercise_name: str) -> bool:
    """Restore a goal (remove from archived)."""
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        _client.table("goals_archived").delete().eq("exercise_name", exercise_name).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("remove_goal_archived retry error: %s", e2)
                return False
        logger.error("remove_goal_archived error: %s", e)
        return False


# ---------------------------------------------------------------------------
# Exercise current weight (smart progression pre-fill)
# ---------------------------------------------------------------------------

def update_exercise_current_weight(name: str, weight: float) -> bool:
    """Update current_weight for an exercise (used by SeanceView pre-fill)."""
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        resp = _client.table("exercises").update({"current_weight": weight}).eq("name", name).execute()
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("update_exercise_current_weight retry error: %s", e2)
                return False
        logger.error("update_exercise_current_weight error: %s", e)
        return False


# ---------------------------------------------------------------------------
# Sessions with volume (for correlations)
# ---------------------------------------------------------------------------

def get_sessions_for_correlations(days: int = 60) -> Dict[str, dict]:
    """Return {date: {rpe, session_volume, energy_pre}} for the last N days."""
    if _client is None or MODE == "OFFLINE":
        return {}
    from datetime import date as _date, timedelta
    cutoff = (_date.today() - timedelta(days=days)).isoformat()
    result: Dict[str, dict] = {}

    def _do_sessions() -> None:
        resp = (
            _client.table("workout_sessions")
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
            _client.table("v_session_volume")
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
        if _is_disconnect(e) and _reconnect():
            try:
                _do_sessions()
            except Exception as e2:
                logger.error("get_sessions_for_correlations (sessions) retry error: %s", e2)
        else:
            logger.error("get_sessions_for_correlations (sessions) error: %s", e)

    try:
        _do_volume()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                _do_volume()
            except Exception as e2:
                logger.error("get_sessions_for_correlations (volume) retry error: %s", e2)
        else:
            logger.error("get_sessions_for_correlations (volume) error: %s", e)

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
    if _client is None or MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        resp = _client.table("smart_goals").select("*").order("created_at").execute()
        return resp.data or []

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_smart_goals retry error: %s", e2)
                return []
        logger.error("get_smart_goals error: %s", e)
        return []


def upsert_smart_goal(
    goal_type: str,
    target_value: float,
    initial_value: Optional[float] = None,
    target_date: Optional[str] = None,
    goal_id: Optional[str] = None,
) -> Optional[dict]:
    if _client is None or MODE == "OFFLINE":
        return None

    def _do() -> Optional[dict]:
        payload: dict = {"type": goal_type, "target_value": target_value}
        if goal_id:
            payload["id"] = goal_id
        if initial_value is not None:
            payload["initial_value"] = round(initial_value, 2)
        if target_date:
            payload["target_date"] = target_date
        resp = _client.table("smart_goals").upsert(payload, on_conflict="id").execute()
        return resp.data[0] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("upsert_smart_goal retry error: %s", e2)
                return None
        logger.error("upsert_smart_goal error: %s", e)
        return None


def delete_smart_goal(goal_id: str) -> bool:
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        _client.table("smart_goals").delete().eq("id", goal_id).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("delete_smart_goal retry error: %s", e2)
                return False
        logger.error("delete_smart_goal error: %s", e)
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
            cutoff   = (_date.today() - timedelta(days=7)).isoformat()
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
            streak, d = 0, _date.today()
            while d.isoformat() in dates:
                streak += 1
                d -= timedelta(days=1)
            return float(streak)

        # ── Types avancés ─────────────────────────────────────────────────────

        if goal_type == "estimated_1rm":
            # Best estimated 1RM across all exercises: weight * (1 + reps/30)
            history = get_all_exercise_history()
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
            cutoff  = (_date.today() - timedelta(days=30)).isoformat()
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
            streak, d = 0, _date.today()
            while d.isoformat() in dates:
                streak += 1
                d -= timedelta(days=1)
            return float(streak) if streak > 0 else None

    except Exception as e:
        logger.error("compute_smart_goal_current(%s) error: %s", goal_type, e)
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
    if _client is None or MODE == "OFFLINE":
        return None

    def _do() -> str | None:
        resp = (
            _client.table("generated_programs")
            .insert({"program_json": program_json, "status": "pending_approval"})
            .execute()
        )
        return resp.data[0]["id"] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("save_generated_program retry error: %s", e2)
                return None
        logger.error("save_generated_program error: %s", e)
        return None


def get_latest_generated_program() -> dict | None:
    """Return the most recent generated program row (any status), or None."""
    if _client is None or MODE == "OFFLINE":
        return None

    def _do() -> dict | None:
        resp = (
            _client.table("generated_programs")
            .select("*")
            .order("generated_at", desc=True)
            .limit(1)
            .execute()
        )
        return resp.data[0] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_latest_generated_program retry error: %s", e2)
                return None
        logger.error("get_latest_generated_program error: %s", e)
        return None


def update_generated_program(gp_id: str, status: str, programme_id: str | None = None) -> bool:
    """Update status and optionally link to an approved programme."""
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        data: dict = {"status": status}
        if programme_id:
            data["programme_id"] = programme_id
        _client.table("generated_programs").update(data).eq("id", gp_id).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("update_generated_program retry error: %s", e2)
                return False
        logger.error("update_generated_program error: %s", e)
        return False


# ---------------------------------------------------------------------------
# Analytics — stats expansion
# ---------------------------------------------------------------------------

def get_weekly_tonnage(weeks: int = 8) -> list[dict]:
    """Return weekly volume from v_weekly_volume, last N weeks, oldest first."""
    if _client is None or MODE == "OFFLINE":
        return []

    def _do() -> list[dict]:
        from datetime import date as _date, timedelta
        cutoff = (_date.today() - timedelta(weeks=weeks)).isoformat()
        resp = (
            _client.table("v_weekly_volume")
            .select("week_start, total_volume, session_count")
            .gte("week_start", cutoff)
            .order("week_start")
            .execute()
        )
        return [
            {
                "week_start": str(r["week_start"])[:10],
                "total_volume": float(r.get("total_volume") or 0),
                "session_count": int(r.get("session_count") or 0),
            }
            for r in (resp.data or [])
        ]

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_weekly_tonnage retry: %s", e2)
                return []
        logger.error("get_weekly_tonnage error: %s", e)
        return []


def get_pattern_volume(days: int = 28) -> dict:
    """Return volume (lbs×reps) per movement pattern for the last N days."""
    try:
        from weights import load_weights
        from inventory import load_inventory
        from datetime import date as _date, timedelta
        cutoff = (_date.today() - timedelta(days=days)).isoformat()
        weights = load_weights()
        inventory = load_inventory() or {}
        pattern_vol: dict[str, float] = {}
        for name, data in weights.items():
            pattern = (inventory.get(name) or {}).get("pattern") or ""
            if not pattern:
                continue
            for entry in (data.get("history") or []):
                if str(entry.get("date", "")) < cutoff:
                    continue
                vol = float(entry.get("exercise_volume") or 0)
                pattern_vol[pattern] = pattern_vol.get(pattern, 0.0) + vol
        return {k: round(v) for k, v in pattern_vol.items()}
    except Exception as e:
        logger.error("get_pattern_volume error: %s", e)
        return {}


def get_programme_compliance(weeks: int = 8) -> list[dict]:
    """Return planned vs completed sessions per ISO week for the last N weeks."""
    if _client is None or MODE == "OFFLINE":
        return []

    def _do() -> list[dict]:
        from datetime import date as _date, timedelta, datetime as _dt
        # Planned sessions per week (count non-null session_id in weekly_schedule)
        sched_resp = _client.table("weekly_schedule").select("session_id").execute()
        planned_per_week = sum(1 for r in (sched_resp.data or []) if r.get("session_id"))
        if planned_per_week == 0:
            planned_per_week = 4

        # Completed sessions in last N weeks
        cutoff = (_date.today() - timedelta(weeks=weeks)).isoformat()
        sess_resp = (
            _client.table("workout_sessions")
            .select("date, completed")
            .gte("date", cutoff)
            .eq("completed", True)
            .execute()
        )
        week_counts: dict[str, int] = {}
        for s in (sess_resp.data or []):
            d = str(s.get("date", ""))[:10]
            try:
                dt = _dt.strptime(d, "%Y-%m-%d")
                monday = (dt - timedelta(days=dt.weekday())).strftime("%Y-%m-%d")
            except Exception:
                continue
            week_counts[monday] = week_counts.get(monday, 0) + 1

        today = _date.today()
        result = []
        for w in range(weeks):
            monday = today - timedelta(days=today.weekday()) - timedelta(weeks=weeks - 1 - w)
            ws = monday.strftime("%Y-%m-%d")
            result.append({"week_start": ws, "planned": planned_per_week, "done": week_counts.get(ws, 0)})
        return result

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_programme_compliance retry: %s", e2)
                return []
        logger.error("get_programme_compliance error: %s", e)
        return []


def get_one_rm_trend(days: int = 84) -> dict:
    """Return estimated 1RM trend per compound exercise (push/pull/hinge/squat patterns)."""
    try:
        from weights import load_weights
        from inventory import load_inventory
        from datetime import date as _date, timedelta
        cutoff = (_date.today() - timedelta(days=days)).isoformat()
        weights = load_weights()
        inventory = load_inventory() or {}
        compound_patterns = {"squat", "hinge", "push", "pull"}
        result: dict[str, list[dict]] = {}
        for name, data in weights.items():
            pattern = (inventory.get(name) or {}).get("pattern") or ""
            if pattern not in compound_patterns:
                continue
            points = []
            for entry in (data.get("history") or []):
                d = str(entry.get("date", ""))[:10]
                if not d or d < cutoff:
                    continue
                orm = entry.get("1rm") or entry.get("oneRM")
                if orm:
                    points.append({"date": d, "one_rm": round(float(orm), 1)})
            if len(points) >= 2:
                points.sort(key=lambda x: x["date"])
                result[name] = points
        # Top 6 by data density
        return dict(sorted(result.items(), key=lambda x: len(x[1]), reverse=True)[:6])
    except Exception as e:
        logger.error("get_one_rm_trend error: %s", e)
        return {}


def get_hiit_completion(weeks: int = 8) -> list[dict]:
    """Return HIIT sessions with completion rate (rounds_completed/rounds_planned)."""
    if _client is None or MODE == "OFFLINE":
        return []

    def _do() -> list[dict]:
        from datetime import date as _date, timedelta
        cutoff = (_date.today() - timedelta(weeks=weeks)).isoformat()
        resp = (
            _client.table("hiit_logs")
            .select("date, session_type, rounds_planned, rounds_completed, rpe")
            .gte("date", cutoff)
            .order("date")
            .execute()
        )
        result = []
        for r in (resp.data or []):
            planned   = int(r.get("rounds_planned") or 0)
            completed = int(r.get("rounds_completed") or 0)
            result.append({
                "date":             str(r.get("date", ""))[:10],
                "session_type":     r.get("session_type"),
                "rounds_planned":   planned,
                "rounds_completed": completed,
                "rate":             round(completed / planned, 2) if planned > 0 else 0.0,
                "rpe":              r.get("rpe"),
            })
        return result

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_hiit_completion retry: %s", e2)
                return []
        logger.error("get_hiit_completion error: %s", e)
        return []


def get_nutrition_daily_full(days: int = 60) -> list[dict]:
    """Return daily aggregates of all macros for the last N days."""
    if _client is None or MODE == "OFFLINE":
        return []

    def _do() -> list[dict]:
        from datetime import date as _date, timedelta
        cutoff = (_date.today() - timedelta(days=days)).isoformat()
        resp = (
            _client.table("nutrition_entries")
            .select("date, calories, proteines, glucides, lipides")
            .gte("date", cutoff)
            .order("date", desc=True)
            .execute()
        )
        seen: dict[str, dict] = {}
        for row in (resp.data or []):
            d = str(row.get("date", ""))[:10]
            if d not in seen:
                seen[d] = {"date": d, "calories": 0.0, "proteines": 0.0, "glucides": 0.0, "lipides": 0.0}
            seen[d]["calories"]  += float(row.get("calories") or 0)
            seen[d]["proteines"] += float(row.get("proteines") or 0)
            seen[d]["glucides"]  += float(row.get("glucides") or 0)
            seen[d]["lipides"]   += float(row.get("lipides") or 0)
        return sorted(seen.values(), key=lambda x: x["date"])

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_nutrition_daily_full retry: %s", e2)
                return []
        logger.error("get_nutrition_daily_full error: %s", e)
        return []


def get_macros_by_day_type(days: int = 60) -> dict:
    """Return average macros on training days vs rest days for the last N days."""
    try:
        nutr_days = get_nutrition_daily_full(days)
        sessions_raw = get_workout_sessions(limit=days + 10)
        workout_dates = {
            str(s.get("date", ""))[:10]
            for s in sessions_raw
            if s.get("completed") or s.get("rpe") is not None
        }
        training: list[dict] = []
        rest: list[dict] = []
        for d in nutr_days:
            if d["calories"] == 0 and d["proteines"] == 0:
                continue
            bucket = training if d["date"] in workout_dates else rest
            bucket.append(d)

        def _avg(b: list[dict]) -> Optional[dict]:
            if not b:
                return None
            n = len(b)
            return {
                "avg_cal":   round(sum(x["calories"]  for x in b) / n),
                "avg_prot":  round(sum(x["proteines"] for x in b) / n, 1),
                "avg_carbs": round(sum(x["glucides"]  for x in b) / n, 1),
                "avg_fat":   round(sum(x["lipides"]   for x in b) / n, 1),
            }

        return {
            "training":   _avg(training),
            "rest":       _avg(rest),
            "n_training": len(training),
            "n_rest":     len(rest),
        }
    except Exception as e:
        logger.error("get_macros_by_day_type error: %s", e)
        return {}


def get_protein_weight_ratio(days: int = 60) -> list[dict]:
    """Return protein/bodyweight ratio per day for days with both logged.

    weight is always stored in lbs — the iOS app hardcodes the input label as
    "POIDS (LBS)" and converts HealthKit kg values via / 0.453592 before sending.
    ratio unit is therefore g_protein / lbs_bodyweight.
    """
    try:
        from datetime import date as _date, timedelta
        cutoff = (_date.today() - timedelta(days=days)).isoformat()
        nutr_days = get_nutrition_daily_full(days)
        bw_logs = get_body_weight_logs(limit=200)
        bw_map = {str(e.get("date", ""))[:10]: float(e.get("weight") or 0) for e in bw_logs if e.get("weight")}
        result = []
        for d in nutr_days:
            date = d["date"]
            if date < cutoff:
                continue
            prot = d["proteines"]
            weight = bw_map.get(date)
            if prot > 0 and weight and weight > 0:
                result.append({"date": date, "ratio": round(prot / weight, 3), "prot_g": round(prot, 1), "weight": weight})
        return result
    except Exception as e:
        logger.error("get_protein_weight_ratio error: %s", e)
        return []


def get_mood_trend(days: int = 60) -> list[dict]:
    """Return mood score + life stress score per day for the last N days."""
    try:
        from datetime import date as _date, timedelta
        cutoff = (_date.today() - timedelta(days=days)).isoformat()
        mood_logs = get_mood_logs(days=days)
        mood_map: dict[str, int] = {
            str(m.get("date", ""))[:10]: int(m["score"])
            for m in mood_logs if m.get("score") is not None
        }
        stress_map: dict[str, float] = {}
        if _client is not None and MODE != "OFFLINE":
            try:
                resp = (
                    _client.table("life_stress_scores")
                    .select("date, score")
                    .gte("date", cutoff)
                    .order("date")
                    .execute()
                )
                for r in (resp.data or []):
                    d = str(r.get("date", ""))[:10]
                    if r.get("score") is not None:
                        stress_map[d] = float(r["score"])
            except Exception as e2:
                logger.warning("get_mood_trend stress query: %s", e2)
        all_dates = sorted(set(mood_map) | set(stress_map))
        return [
            {"date": d, "mood_score": mood_map.get(d), "life_stress_score": stress_map.get(d)}
            for d in all_dates if d >= cutoff
        ]
    except Exception as e:
        logger.error("get_mood_trend error: %s", e)
        return []


def _get_session_volume_map(days: int = 200) -> dict[str, float]:
    """Return {date: total_volume} from v_session_volume view."""
    if _client is None or MODE == "OFFLINE":
        return {}
    try:
        from datetime import date as _date, timedelta
        cutoff = (_date.today() - timedelta(days=days)).isoformat()
        resp = (
            _client.table("v_session_volume")
            .select("date, total_volume")
            .gte("date", cutoff)
            .execute()
        )
        vol_map: dict[str, float] = {}
        for r in (resp.data or []):
            d = str(r.get("date", ""))[:10]
            vol = float(r.get("total_volume") or 0)
            if d and vol > 0:
                vol_map[d] = vol_map.get(d, 0.0) + vol
        return vol_map
    except Exception as e:
        logger.error("_get_session_volume_map error: %s", e)
        return {}


def get_soreness_volume_scatter() -> list[dict]:
    """Return scatter pairs: (volume_J-1, soreness_J) for correlation analysis."""
    try:
        from datetime import date as _date, timedelta
        recovery = get_recovery_logs(limit=200)
        vol_map = _get_session_volume_map(200)
        result = []
        for r in recovery:
            soreness = r.get("soreness")
            d = str(r.get("date", ""))[:10]
            if not d or soreness is None:
                continue
            try:
                prev_date = (_date.fromisoformat(d) - timedelta(days=1)).isoformat()
            except Exception:
                continue
            prev_vol = vol_map.get(prev_date)
            if prev_vol and prev_vol > 0:
                result.append({"x": round(prev_vol), "y": float(soreness), "date": d})
        return result
    except Exception as e:
        logger.error("get_soreness_volume_scatter error: %s", e)
        return []


def get_sleep_volume_scatter() -> list[dict]:
    """Return scatter pairs: (sleep_quality_J-1, volume_J) for correlation analysis."""
    try:
        from datetime import date as _date, timedelta
        recovery = get_recovery_logs(limit=200)
        vol_map = _get_session_volume_map(200)
        result = []
        for r in recovery:
            sleep_q = r.get("sleep_quality")
            d = str(r.get("date", ""))[:10]
            if not d or sleep_q is None:
                continue
            try:
                next_date = (_date.fromisoformat(d) + timedelta(days=1)).isoformat()
            except Exception:
                continue
            next_vol = vol_map.get(next_date)
            if next_vol and next_vol > 0:
                result.append({"x": float(sleep_q), "y": round(next_vol), "date": next_date})
        return result
    except Exception as e:
        logger.error("get_sleep_volume_scatter error: %s", e)
        return []


def get_rpe_progression() -> dict:
    """Return average weight progression % per RPE bucket (<7 / 7-8 / 8-9 / 9-10)."""
    try:
        from weights import load_weights
        sessions_raw = get_workout_sessions(limit=365)
        rpe_by_date: dict[str, float] = {
            str(s.get("date", ""))[:10]: float(s["rpe"])
            for s in sessions_raw if s.get("rpe") is not None
        }

        def _bucket(rpe: float) -> str:
            if rpe < 7: return "<7"
            if rpe < 8: return "7-8"
            if rpe < 9: return "8-9"
            return "9-10"

        weights = load_weights()
        buckets: dict[str, list[float]] = {"<7": [], "7-8": [], "8-9": [], "9-10": []}
        for data in weights.values():
            hist = sorted(data.get("history") or [], key=lambda x: str(x.get("date", "")))
            for i in range(len(hist) - 1):
                d = str(hist[i].get("date", ""))[:10]
                rpe = rpe_by_date.get(d)
                if rpe is None:
                    continue
                w0 = float(hist[i].get("weight") or 0)
                w1 = float(hist[i + 1].get("weight") or 0)
                if w0 > 0 and w1 > 0:
                    buckets[_bucket(rpe)].append((w1 - w0) / w0 * 100)

        return {
            b: (round(sum(v) / len(v), 2) if v else None)
            for b, v in buckets.items()
        }
    except Exception as e:
        logger.error("get_rpe_progression error: %s", e)
        return {}


def get_rir_by_exercise() -> list[dict]:
    """Return average RIR (Reps In Reserve) per exercise from sets_json."""
    if _client is None or MODE == "OFFLINE":
        return []

    def _do() -> list[dict]:
        import json as _json
        logs_resp = (
            _client.table("exercise_logs")
            .select("exercise_id, sets_json")
            .not_.is_("sets_json", "null")
            .limit(500)
            .execute()
        )
        ex_resp = _client.table("exercises").select("id, name").execute()
        ex_names = {str(r["id"]): r["name"] for r in (ex_resp.data or [])}
        rir_data: dict[str, list[int]] = {}
        for row in (logs_resp.data or []):
            ex_id = str(row.get("exercise_id", ""))
            sets = row.get("sets_json") or []
            if isinstance(sets, str):
                try:
                    sets = _json.loads(sets)
                except Exception:
                    continue
            for s in (sets or []):
                rir = s.get("rir")
                if rir is not None:
                    rir_data.setdefault(ex_id, []).append(int(rir))
        result = [
            {"exercise": ex_names.get(eid, eid), "avg_rir": round(sum(rs) / len(rs), 1), "n_sets": len(rs)}
            for eid, rs in rir_data.items()
        ]
        result.sort(key=lambda x: x["n_sets"], reverse=True)
        return result[:20]

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_rir_by_exercise retry: %s", e2)
                return []
        logger.error("get_rir_by_exercise error: %s", e)
        return []


def get_self_care_compliance(days: int = 30) -> dict:
    """Return self-care compliance rate and daily counts for the last N days."""
    try:
        from datetime import date as _date, timedelta
        cutoff = (_date.today() - timedelta(days=days)).isoformat()
        sc_log = get_self_care_log(days=days)
        habits = get_self_care_habits()
        total_habits = len(habits)
        if total_habits == 0:
            return {"rate_30d": 0.0, "daily": []}
        total_done = 0
        total_possible = 0
        daily = []
        for d_str in sorted(sc_log):
            if d_str < cutoff:
                continue
            done = len(sc_log[d_str])
            total_done += done
            total_possible += total_habits
            daily.append({"date": d_str, "count": done})
        rate = round(total_done / total_possible, 3) if total_possible > 0 else 0.0
        return {"rate_30d": rate, "daily": daily}
    except Exception as e:
        logger.error("get_self_care_compliance error: %s", e)
        return {"rate_30d": 0.0, "daily": []}


def get_self_care_streaks_computed() -> list[dict]:
    """Compute current and longest streak for each self-care habit."""
    try:
        from datetime import date as _date, timedelta
        habits = get_self_care_habits()
        sc_log = get_self_care_log(days=365)
        habit_dates: dict[str, set[str]] = {}
        for date_str, habit_ids in sc_log.items():
            for hid in habit_ids:
                habit_dates.setdefault(hid, set()).add(date_str)
        today = _date.today()
        result = []
        for h in habits:
            hid = h.get("id", "")
            dates = habit_dates.get(hid, set())
            # Current streak
            current, d = 0, today
            while d.isoformat() in dates:
                current += 1
                d -= timedelta(days=1)
            # Longest streak
            sorted_dates = sorted(dates)
            longest, run, prev = 0, 0, None
            for ds in sorted_dates:
                try:
                    cur_date = _date.fromisoformat(ds)
                except Exception:
                    continue
                run = (run + 1) if (prev is not None and (cur_date - prev).days == 1) else 1
                longest = max(longest, run)
                prev = cur_date
            result.append({
                "habit_id":       hid,
                "habit_name":     h.get("name", ""),
                "habit_icon":     h.get("icon", ""),
                "current_streak": current,
                "longest_streak": longest,
            })
        result.sort(key=lambda x: x["current_streak"], reverse=True)
        return result
    except Exception as e:
        logger.error("get_self_care_streaks_computed error: %s", e)
        return []


# ---------------------------------------------------------------------------
# Pain journal
# ---------------------------------------------------------------------------

def get_pain_journal(limit: int = 100) -> list[dict]:
    """Return exercise_logs with pain_zone != null, newest first."""
    if _client is None or MODE == "OFFLINE":
        return []

    def _do() -> list[dict]:
        resp = (
            _client.table("exercise_logs")
            .select("pain_zone, weight, reps, workout_sessions(date, session_name), exercises(name)")
            .not_.is_("pain_zone", "null")
            .order("workout_sessions(date)", desc=True)
            .limit(limit)
            .execute()
        )
        rows = resp.data or []
        result = []
        for r in rows:
            sess = r.get("workout_sessions") or {}
            ex   = r.get("exercises") or {}
            result.append({
                "date":         sess.get("date"),
                "session_name": sess.get("session_name"),
                "exercise":     ex.get("name"),
                "pain_zone":    r.get("pain_zone"),
                "weight":       r.get("weight"),
                "reps":         r.get("reps"),
            })
        return result

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_pain_journal retry error: %s", e2)
                return []
        logger.error("get_pain_journal error: %s", e)
        return []


def get_sessions_with_energy_pre(days: int = 90) -> list[dict]:
    """Return [{date, energy_pre, rpe, session_volume}] for correlation analysis."""
    if _client is None or MODE == "OFFLINE":
        return []
    from datetime import date as _date, timedelta
    cutoff = (_date.today() - timedelta(days=days)).isoformat()

    def _do() -> list[dict]:
        resp = (
            _client.table("workout_sessions")
            .select("date, energy_pre, rpe")
            .gte("date", cutoff)
            .not_.is_("energy_pre", "null")
            .execute()
        )
        rows = resp.data or []
        # Get volume from v_session_volume
        vol_resp = (
            _client.table("v_session_volume")
            .select("date, total_volume")
            .gte("date", cutoff)
            .execute()
        )
        vol_by_date = {str(r["date"])[:10]: r.get("total_volume") for r in (vol_resp.data or [])}
        result = []
        for r in rows:
            d = str(r.get("date", ""))[:10]
            result.append({
                "date":           d,
                "energy_pre":     r.get("energy_pre"),
                "rpe":            r.get("rpe"),
                "session_volume": vol_by_date.get(d),
            })
        return result

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_sessions_with_energy_pre retry error: %s", e2)
                return []
        logger.error("get_sessions_with_energy_pre error: %s", e)
        return []


def get_exercise_logs_with_category(days: int = 90) -> list[dict]:
    """Return exercise_logs with exercise category for push/pull ratio computation."""
    if _client is None or MODE == "OFFLINE":
        return []
    from datetime import date as _date, timedelta
    cutoff = (_date.today() - timedelta(days=days)).isoformat()

    def _do() -> list[dict]:
        resp = (
            _client.table("exercise_logs")
            .select("weight, reps, sets_json, workout_sessions(date), exercises(name, category, load_profile)")
            .gte("workout_sessions(date)", cutoff)
            .execute()
        )
        rows = resp.data or []
        result = []
        for r in rows:
            sess = r.get("workout_sessions") or {}
            ex   = r.get("exercises") or {}
            d = str(sess.get("date", ""))[:10]
            if not d:
                continue
            result.append({
                "date":         d,
                "exercise":     ex.get("name"),
                "category":     ex.get("category"),
                "load_profile": ex.get("load_profile"),
                "weight":       r.get("weight", 0),
                "reps":         r.get("reps", ""),
                "sets_json":    r.get("sets_json"),
            })
        return result

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_exercise_logs_with_category retry error: %s", e2)
                return []
        logger.error("get_exercise_logs_with_category error: %s", e)
        return []


# ── Daily Ritual ─────────────────────────────────────────────────────────────

def get_ritual_today(date_str: str) -> Optional[dict]:
    """Return today's daily_ritual row or None."""
    if _client is None or MODE == "OFFLINE":
        return None

    def _do() -> Optional[dict]:
        resp = (
            _client.table("daily_ritual")
            .select("*")
            .eq("date", date_str)
            .limit(1)
            .execute()
        )
        return resp.data[0] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_ritual_today retry: %s", e2)
                return None
        logger.error("get_ritual_today error: %s", e)
        return None


def upsert_ritual(data: dict) -> bool:
    """Insert or update a daily_ritual row by date."""
    if _client is None or MODE == "OFFLINE":
        return False

    def _do() -> bool:
        resp = (
            _client.table("daily_ritual")
            .upsert(data, on_conflict="date")
            .execute()
        )
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("upsert_ritual retry: %s", e2)
                return False
        logger.error("upsert_ritual error: %s", e)
        return False


def get_ritual_history(limit: int = 365) -> List[dict]:
    """Return all ritual rows ordered by date DESC."""
    if _client is None or MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        resp = (
            _client.table("daily_ritual")
            .select("date, outcome, intention, carry_count, carried_from")
            .order("date", desc=True)
            .limit(limit)
            .execute()
        )
        return resp.data or []

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_ritual_history retry: %s", e2)
                return []
        logger.error("get_ritual_history error: %s", e)
        return []


def get_ritual_demons() -> List[dict]:
    """Return all survived (unresolved) intentions, oldest first."""
    if _client is None or MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        resp = (
            _client.table("daily_ritual")
            .select("date, intention, carry_count, carried_from, truth")
            .eq("outcome", "survived")
            .order("date", desc=False)
            .execute()
        )
        return resp.data or []

    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_ritual_demons retry: %s", e2)
                return []
        logger.error("get_ritual_demons error: %s", e)
        return []


# ── War Room ──────────────────────────────────────────────────────────────────

def get_war_room_config() -> Optional[dict]:
    if _client is None or MODE == "OFFLINE":
        return None
    def _do():
        resp = _client.table("war_room_config").select("*").eq("id", 1).maybe_single().execute()
        return resp.data
    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_war_room_config retry: %s", e2)
                return None
        logger.error("get_war_room_config error: %s", e)
        return None


def upsert_war_room_config(data: dict) -> bool:
    if _client is None or MODE == "OFFLINE":
        return False
    payload = {**data, "id": 1}
    def _do():
        _client.table("war_room_config").upsert(payload, on_conflict="id").execute()
        return True
    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("upsert_war_room_config retry: %s", e2)
                return False
        logger.error("upsert_war_room_config error: %s", e)
        return False


def get_war_room_battles(limit: int = 90) -> List[dict]:
    if _client is None or MODE == "OFFLINE":
        return []
    def _do():
        resp = (
            _client.table("war_room_battles")
            .select("id, date, status, notes, created_at")
            .order("date", desc=True)
            .limit(limit)
            .execute()
        )
        return resp.data or []
    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_war_room_battles retry: %s", e2)
                return []
        logger.error("get_war_room_battles error: %s", e)
        return []


def upsert_war_room_battle(data: dict) -> bool:
    if _client is None or MODE == "OFFLINE":
        return False
    def _do():
        _client.table("war_room_battles").upsert(data, on_conflict="date").execute()
        return True
    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("upsert_war_room_battle retry: %s", e2)
                return False
        logger.error("upsert_war_room_battle error: %s", e)
        return False


def get_war_room_triggers(limit: int = 90) -> List[dict]:
    if _client is None or MODE == "OFFLINE":
        return []
    def _do():
        resp = (
            _client.table("war_room_triggers")
            .select("id, date, logged_at, context, context_note, intensity, yielded, held_with")
            .order("logged_at", desc=True)
            .limit(limit)
            .execute()
        )
        return resp.data or []
    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_war_room_triggers retry: %s", e2)
                return []
        logger.error("get_war_room_triggers error: %s", e)
        return []


def insert_war_room_trigger(data: dict) -> Optional[dict]:
    if _client is None or MODE == "OFFLINE":
        return None
    def _do():
        resp = _client.table("war_room_triggers").insert(data).execute()
        return (resp.data or [None])[0]
    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("insert_war_room_trigger retry: %s", e2)
                return None
        logger.error("insert_war_room_trigger error: %s", e)
        return None


def get_war_room_arsenal() -> List[dict]:
    if _client is None or MODE == "OFFLINE":
        return []
    def _do():
        resp = (
            _client.table("war_room_arsenal")
            .select("id, label, category, use_count, last_used_at, sort_order, active")
            .eq("active", True)
            .execute()
        )
        return resp.data or []
    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_war_room_arsenal retry: %s", e2)
                return []
        logger.error("get_war_room_arsenal error: %s", e)
        return []


def insert_war_room_arsenal_item(data: dict) -> Optional[dict]:
    if _client is None or MODE == "OFFLINE":
        return None
    def _do():
        resp = _client.table("war_room_arsenal").insert(data).execute()
        return (resp.data or [None])[0]
    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("insert_war_room_arsenal_item retry: %s", e2)
                return None
        logger.error("insert_war_room_arsenal_item error: %s", e)
        return None


def delete_war_room_arsenal_item(item_id: str) -> bool:
    if _client is None or MODE == "OFFLINE":
        return False
    def _do():
        resp = _client.table("war_room_arsenal").update({"active": False}).eq("id", item_id).execute()
        return bool(resp.data)
    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("delete_war_room_arsenal_item retry: %s", e2)
                return False
        logger.error("delete_war_room_arsenal_item error: %s", e)
        return False


def increment_arsenal_use(item_id: str) -> bool:
    if _client is None or MODE == "OFFLINE":
        return False
    def _do():
        row = _client.table("war_room_arsenal").select("use_count").eq("id", item_id).maybe_single().execute()
        current = (row.data or {}).get("use_count", 0)
        _client.table("war_room_arsenal").update({
            "use_count":    current + 1,
            "last_used_at": datetime.now(timezone.utc).isoformat(),
        }).eq("id", item_id).execute()
        return True
    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("increment_arsenal_use retry: %s", e2)
                return False
        logger.error("increment_arsenal_use error: %s", e)
        return False


# ── Spirit Pillar ─────────────────────────────────────────────────────────────

def get_spirit_config() -> Optional[dict]:
    if _client is None or MODE == "OFFLINE":
        return None
    def _do():
        resp = _client.table("spirit_config").select("*").eq("id", 1).maybe_single().execute()
        return resp.data
    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_spirit_config retry: %s", e2)
                return None
        logger.error("get_spirit_config error: %s", e)
        return None


def upsert_spirit_config(data: dict) -> bool:
    if _client is None or MODE == "OFFLINE":
        return False
    payload = {**data, "id": 1}
    def _do():
        _client.table("spirit_config").upsert(payload, on_conflict="id").execute()
        return True
    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("upsert_spirit_config retry: %s", e2)
                return False
        logger.error("upsert_spirit_config error: %s", e)
        return False


def log_breathwork_session(data: dict) -> Optional[dict]:
    if _client is None or MODE == "OFFLINE":
        return None
    def _do():
        resp = _client.table("breathwork_sessions").insert(data).execute()
        return (resp.data or [None])[0]
    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("log_breathwork_session retry: %s", e2)
                return None
        logger.error("log_breathwork_session error: %s", e)
        return None


def get_breathwork_sessions(limit: int = 60) -> List[dict]:
    if _client is None or MODE == "OFFLINE":
        return []
    def _do():
        resp = (
            _client.table("breathwork_sessions")
            .select("id, protocol, duration_sec, cycles, started_at, triggered_from")
            .order("started_at", desc=True)
            .limit(limit)
            .execute()
        )
        return resp.data or []
    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_breathwork_sessions retry: %s", e2)
                return []
        logger.error("get_breathwork_sessions error: %s", e)
        return []


def log_meditation_session(data: dict) -> Optional[dict]:
    if _client is None or MODE == "OFFLINE":
        return None
    def _do():
        resp = _client.table("meditation_sessions").insert(data).execute()
        return (resp.data or [None])[0]
    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("log_meditation_session retry: %s", e2)
                return None
        logger.error("log_meditation_session error: %s", e)
        return None


def get_meditation_sessions(limit: int = 60) -> List[dict]:
    if _client is None or MODE == "OFFLINE":
        return []
    def _do():
        resp = (
            _client.table("meditation_sessions")
            .select("id, planned_sec, actual_sec, bell_interval, started_at, completed")
            .order("started_at", desc=True)
            .limit(limit)
            .execute()
        )
        return resp.data or []
    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_meditation_sessions retry: %s", e2)
                return []
        logger.error("get_meditation_sessions error: %s", e)
        return []


def save_spirit_journal_entry(data: dict) -> bool:
    if _client is None or MODE == "OFFLINE":
        return False
    def _do():
        _client.table("spirit_journal").upsert(data, on_conflict="date").execute()
        return True
    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("save_spirit_journal_entry retry: %s", e2)
                return False
        logger.error("save_spirit_journal_entry error: %s", e)
        return False


def get_spirit_journal_entries(limit: int = 30) -> List[dict]:
    if _client is None or MODE == "OFFLINE":
        return []
    def _do():
        resp = (
            _client.table("spirit_journal")
            .select("id, date")
            .order("date", desc=True)
            .limit(limit)
            .execute()
        )
        return resp.data or []
    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_spirit_journal_entries retry: %s", e2)
                return []
        logger.error("get_spirit_journal_entries error: %s", e)
        return []


def get_spirit_journal_entry(entry_date: str) -> Optional[dict]:
    if _client is None or MODE == "OFFLINE":
        return None
    def _do():
        resp = (
            _client.table("spirit_journal")
            .select("id, date, grateful_for, conquered, haunting, created_at")
            .eq("date", entry_date)
            .maybe_single()
            .execute()
        )
        return resp.data
    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_spirit_journal_entry retry: %s", e2)
                return None
        logger.error("get_spirit_journal_entry error: %s", e)
        return None


# ─────────────────────────────────────────────
# Oath
# ─────────────────────────────────────────────

def get_current_oath() -> Optional[dict]:
    if _client is None or MODE == "OFFLINE":
        return None
    def _do():
        resp = (
            _client.table("oaths")
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
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_current_oath retry: %s", e2)
                return None
        logger.error("get_current_oath error: %s", e)
        return None


def get_oath_versions() -> List[dict]:
    if _client is None or MODE == "OFFLINE":
        return []
    def _do():
        resp = (
            _client.table("oaths")
            .select("id, text, version, word_count, written_at, superseded_at")
            .order("written_at", desc=True)
            .execute()
        )
        return resp.data or []
    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_oath_versions retry: %s", e2)
                return []
        logger.error("get_oath_versions error: %s", e)
        return []


def save_oath(text: str, word_count: int) -> Optional[dict]:
    if _client is None or MODE == "OFFLINE":
        return None
    from datetime import datetime, timezone
    now_iso = datetime.now(timezone.utc).isoformat()
    def _do():
        # Find current version number
        existing = get_current_oath()
        next_version = (existing["version"] + 1) if existing else 1
        # Supersede current oath
        if existing:
            _client.table("oaths").update({"superseded_at": now_iso}).eq("id", existing["id"]).execute()
        # Insert new oath
        resp = (
            _client.table("oaths")
            .insert({"text": text, "version": next_version, "word_count": word_count})
            .execute()
        )
        return resp.data[0] if resp.data else None
    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("save_oath retry: %s", e2)
                return None
        logger.error("save_oath error: %s", e)
        return None


def log_oath_recall(oath_id: str, trigger: str) -> None:
    if _client is None or MODE == "OFFLINE":
        return
    def _do():
        payload: dict = {"trigger": trigger}
        if oath_id:
            payload["oath_id"] = oath_id
        _client.table("oath_recalls").insert(payload).execute()
    try:
        _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                _do()
            except Exception as e2:
                logger.error("log_oath_recall retry: %s", e2)
        logger.error("log_oath_recall error: %s", e)


def get_oath_recalls(limit: int = 20) -> List[dict]:
    if _client is None or MODE == "OFFLINE":
        return []
    def _do():
        resp = (
            _client.table("oath_recalls")
            .select("id, oath_id, trigger, shown_at")
            .order("shown_at", desc=True)
            .limit(limit)
            .execute()
        )
        return resp.data or []
    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_oath_recalls retry: %s", e2)
                return []
        logger.error("get_oath_recalls error: %s", e)
        return []


# ─────────────────────────────────────────────
# Spirit breathwork (renamed to avoid conflict with wellness breathwork)
# ─────────────────────────────────────────────

def get_breathwork_sessions_spirit(limit: int = 500) -> List[dict]:
    """Spirit breathwork sessions (breathwork_sessions table)."""
    if _client is None or MODE == "OFFLINE":
        return []
    def _do():
        resp = (
            _client.table("breathwork_sessions")
            .select("id, protocol, duration_sec, cycles, started_at")
            .order("started_at", desc=True)
            .limit(limit)
            .execute()
        )
        return resp.data or []
    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_breathwork_sessions_spirit retry: %s", e2)
                return []
        logger.error("get_breathwork_sessions_spirit error: %s", e)
        return []


# ─────────────────────────────────────────────
# Seasons
# ─────────────────────────────────────────────

def get_next_season_number() -> int:
    if _client is None or MODE == "OFFLINE":
        return 1
    try:
        resp = _client.table("seasons").select("number").order("number", desc=True).limit(1).execute()
        if resp.data:
            return (resp.data[0].get("number") or 0) + 1
        return 1
    except Exception as e:
        logger.error("get_next_season_number error: %s", e)
        return 1


def get_active_season() -> Optional[dict]:
    if _client is None or MODE == "OFFLINE":
        return None
    def _do():
        resp = (
            _client.table("seasons")
            .select("*")
            .eq("status", "active")
            .order("created_at", desc=True)
            .limit(1)
            .execute()
        )
        return resp.data[0] if resp.data else None
    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_active_season retry: %s", e2)
                return None
        logger.error("get_active_season error: %s", e)
        return None


def get_all_seasons() -> List[dict]:
    if _client is None or MODE == "OFFLINE":
        return []
    def _do():
        resp = (
            _client.table("seasons")
            .select("*")
            .order("number", desc=True)
            .execute()
        )
        return resp.data or []
    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_all_seasons retry: %s", e2)
                return []
        logger.error("get_all_seasons error: %s", e)
        return []


def get_season_by_id(season_id: str) -> Optional[dict]:
    if _client is None or MODE == "OFFLINE":
        return None
    def _do():
        resp = (
            _client.table("seasons")
            .select("*")
            .eq("id", season_id)
            .maybe_single()
            .execute()
        )
        return resp.data
    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_season_by_id retry: %s", e2)
                return None
        logger.error("get_season_by_id error: %s", e)
        return None


def create_season(number: int, started_at: str) -> Optional[dict]:
    if _client is None or MODE == "OFFLINE":
        return None
    def _do():
        resp = (
            _client.table("seasons")
            .insert({"number": number, "started_at": started_at, "status": "active"})
            .execute()
        )
        return resp.data[0] if resp.data else None
    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("create_season retry: %s", e2)
                return None
        logger.error("create_season error: %s", e)
        return None


def save_season_snapshot(season_id: str, snap_type: str, data: dict) -> Optional[dict]:
    if _client is None or MODE == "OFFLINE":
        return None
    import json as _json
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
        resp = _client.table("season_snapshots").insert(payload).execute()
        return resp.data[0] if resp.data else None
    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("save_season_snapshot retry: %s", e2)
                return None
        logger.error("save_season_snapshot error: %s", e)
        return None


def close_season(season_id: str, ended_at: str, generated_title: str, dominant_arc: str) -> Optional[dict]:
    if _client is None or MODE == "OFFLINE":
        return None
    def _do():
        resp = (
            _client.table("seasons")
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
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("close_season retry: %s", e2)
                return None
        logger.error("close_season error: %s", e)
        return None


def update_season(season_id: str, fields: dict) -> Optional[dict]:
    if _client is None or MODE == "OFFLINE":
        return None
    def _do():
        resp = (
            _client.table("seasons")
            .update(fields)
            .eq("id", season_id)
            .execute()
        )
        return resp.data[0] if resp.data else None
    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("update_season retry: %s", e2)
                return None
        logger.error("update_season error: %s", e)
        return None


def get_season_snapshots(season_id: str) -> List[dict]:
    if _client is None or MODE == "OFFLINE":
        return []
    def _do():
        resp = (
            _client.table("season_snapshots")
            .select("*")
            .eq("season_id", season_id)
            .order("captured_at", desc=False)
            .execute()
        )
        return resp.data or []
    try:
        return _do()
    except Exception as e:
        if _is_disconnect(e) and _reconnect():
            try:
                return _do()
            except Exception as e2:
                logger.error("get_season_snapshots retry: %s", e2)
                return []
        logger.error("get_season_snapshots error: %s", e)
        return []


def get_prev_season_had_reset(current_season_id: str) -> bool:
    """Return True if the previous completed season had at least one War Room reset."""
    if _client is None or MODE == "OFFLINE":
        return False
    try:
        current = get_season_by_id(current_season_id)
        if not current:
            return False
        current_num = current.get("number", 1)
        if current_num <= 1:
            return False
        resp = (
            _client.table("seasons")
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
        logger.error("get_prev_season_had_reset error: %s", e)
        return False


# ── Coach — Spirit metadata (counts only, zero content) ───────────────────────

def get_spirit_metadata(days: int = 7) -> dict:
    """Return Spirit pillar metadata for the last N days.
    Counts and dates only — journal content is never queried or returned."""
    from datetime import date as _date, timedelta as _td
    today = _date.today()
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
    if _client is None or MODE == "OFFLINE":
        return result
    try:
        resp = _client.table("breathwork_sessions").select("started_at").gte("started_at", cutoff + "T00:00:00").execute()
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
        logger.error("get_spirit_metadata breathwork error: %s", e)
    try:
        resp = _client.table("meditation_sessions").select("started_at").gte("started_at", cutoff + "T00:00:00").eq("completed", True).execute()
        med_dates: set[str] = set()
        for row in (resp.data or []):
            d = str(row.get("started_at") or "")[:10]
            if d >= cutoff:
                med_dates.add(d)
        result["meditation_count"] = len(resp.data or [])
        result["days_with_meditation"] = sorted(med_dates)
    except Exception as e:
        logger.error("get_spirit_metadata meditation error: %s", e)
    try:
        resp = _client.table("spirit_journal").select("date").gte("date", cutoff).execute()
        jrn_dates = [str(row.get("date") or "")[:10] for row in (resp.data or []) if row.get("date")]
        result["journal_count"] = len(jrn_dates)
        result["days_with_journal"] = sorted(jrn_dates)
    except Exception as e:
        logger.error("get_spirit_metadata journal error: %s", e)
    return result


def get_war_room_coach_context() -> Optional[dict]:
    """Return War Room stats for coach context.
    NEVER includes trigger content, arsenal text, or pattern analysis."""
    from datetime import date as _date, timedelta as _td
    if _client is None or MODE == "OFFLINE":
        return None
    try:
        config = get_war_room_config() or {}
        battles = get_war_room_battles(limit=180)
        cutoff = (_date.today() - _td(days=90)).isoformat()
        recent = [b for b in battles if b.get("date", "") >= cutoff]
        victories = sum(1 for b in recent if b.get("status") == "victory")
        total = len(recent)
        lost = [b for b in battles if b.get("status") == "lost"]
        last_reset_date = lost[0].get("date") if lost else None
        days_since_reset: Optional[int] = None
        if last_reset_date:
            try:
                days_since_reset = (_date.today() - _date.fromisoformat(last_reset_date)).days
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
        logger.error("get_war_room_coach_context error: %s", e)
        return None


def get_coach_war_room_shared() -> bool:
    """Return whether user has opted in to sharing War Room data with the coach."""
    return bool(get_profile().get("coach_war_room_shared", False))


def set_coach_war_room_shared(value: bool) -> bool:
    """Toggle War Room sharing with the coach."""
    return update_profile({"coach_war_room_shared": value})
