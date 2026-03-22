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
_TABLE = "kv"

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


def _sqlite_all_dirty() -> Dict[str, Dict[str, Any]]:
    if _ON_VERCEL:
        return {}
    _ensure_sqlite()
    with _SQL_LOCK:
        cur = _CONN.execute("select key, value, updated_at from kv_local where dirty=1")
        out = {}
        for key, val, ts in cur.fetchall():
            try:
                out[key] = {"value": json.loads(val), "updated_at": ts}
            except Exception:
                out[key] = {"value": None, "updated_at": ts}
        return out


def _sqlite_upsert_clean(key: str, value: Any, updated_at_iso: Optional[str] = None):
    """Enregistre en local avec dirty=0 (miroir d'un succès distant)."""
    if _ON_VERCEL:
        return
    _ensure_sqlite()
    with _SQL_LOCK:
        _CONN.execute(
            "insert into kv_local(key, value, updated_at, dirty) values(?,?,?,0) "
            "on conflict(key) do update set value=excluded.value, updated_at=excluded.updated_at, dirty=0",
            (key, json.dumps(value, ensure_ascii=False), updated_at_iso or _now_iso()),
        )
        _CONN.commit()


# ---------------------------------------------------------------------------
# Supabase helpers
# ---------------------------------------------------------------------------
def _get_online(key: str) -> Tuple[Optional[Any], Optional[str]]:
    if not _client:
        return None, None
    try:
        resp = _client.table(_TABLE).select("value,updated_at").eq("key", key).single().execute()
        data = getattr(resp, "data", None)
        if not data:
            return None, None
        return data.get("value"), data.get("updated_at")
    except Exception as e:
        logger.debug("GET error for key %s: %s", key, e)
        return None, None


def _set_online(key: str, value: Any) -> Tuple[bool, Optional[str]]:
    if not _client:
        logger.warning("Supabase client not initialized")
        return False, None
    try:
        payload = {"key": key, "value": value}
        logger.debug("Upsert attempt for key: %s", key)

        resp = _client.table(_TABLE).upsert(payload).execute()

        if hasattr(resp, 'data') and len(resp.data) > 0:
            updated_at = resp.data[0].get("updated_at")
            logger.debug("Supabase upsert success for key: %s", key)
            return True, updated_at

        logger.debug("Upsert sent for key: %s (no data returned)", key)
        return True, _now_iso()

    except Exception as e:
        logger.error("Supabase error for key %s: %s — %s", key, type(e).__name__, e)
        return False, None


# ---------------------------------------------------------------------------
# API publique utilisée par tes modules (KV — preserved as-is)
# ---------------------------------------------------------------------------
def get_json(key: str, default: Any = None) -> Any:
    """
    Lecture offline-first:
      - ONLINE/HYBRID: tente Supabase; si KO → lit SQLite; sinon default
      - OFFLINE: lit SQLite; sinon default
    Mets à jour le cache local (clean) quand on lit depuis Supabase.
    """
    if MODE == "OFFLINE":
        val, _, _ = _sqlite_get(key)
        return default if val is None else val

    # ONLINE/HYBRID
    value, updated_at = _get_online(key)
    if value is not None:
        # Miroir local clean
        _sqlite_upsert_clean(key, value, updated_at_iso=updated_at)
        return value

    # Fallback local
    val, _, _ = _sqlite_get(key)
    if val is not None:
        return val

    return default


def set_json(key: str, value: Any) -> bool:
    """
    Écriture offline-first:
      - ONLINE: upsert Supabase; si OK → local clean; sinon → local dirty
      - HYBRID: tente Supabase; si KO → local dirty
      - OFFLINE: local dirty (persiste en SQLite) pour synchro ultérieure
    """
    if MODE == "ONLINE" and _client:
        ok, updated_at = _set_online(key, value)
        if ok:
            _sqlite_upsert_clean(key, value, updated_at_iso=updated_at)
            return True
        # Basculer en local dirty si échec réseau ponctuel
        _sqlite_set(key, value, dirty=1)
        return False

    # HYBRID: tente remote, sinon local dirty
    if MODE == "HYBRID" and _client:
        ok, updated_at = _set_online(key, value)
        if ok:
            _sqlite_upsert_clean(key, value, updated_at_iso=updated_at)
            return True
        _sqlite_set(key, value, dirty=1)
        return False

    # OFFLINE: écriture locale dirty
    _sqlite_set(key, value, dirty=1)
    return False


def update_json(key: str, patch: Dict[str, Any]) -> Any:
    base = get_json(key, {}) or {}
    if not isinstance(base, dict):
        base = {}
    base.update(patch)
    set_json(key, base)
    return base


def append_json_list(key: str, entry: Any, max_items: Optional[int] = None) -> list:
    arr = get_json(key, []) or []
    if not isinstance(arr, list):
        arr = []
    arr.insert(0, entry)
    if max_items:
        arr = arr[:max_items]
    set_json(key, arr)
    return arr


def client():
    """Retourne le client Supabase si disponible (sinon None)"""
    return _client


# ---------------------------------------------------------------------------
# Synchronisation manuelle: à appeler quand tu repasses ONLINE
# ---------------------------------------------------------------------------
def _compare_ts(ts_local: Optional[str], ts_remote: Optional[str]) -> int:
    """
    Compare des timestamps ISO (UTC). Retourne:
      -1 si local < remote
       0 si égal/incomparables
      +1 si local > remote
    """
    if not ts_local or not ts_remote:
        return 0
    try:
        a = datetime.fromisoformat(ts_local.replace("Z", "+00:00"))
        b = datetime.fromisoformat(ts_remote.replace("Z", "+00:00"))
        if a < b: return -1
        if a > b: return +1
        return 0
    except Exception:
        return 0


def sync_now(verbose: bool = True) -> Dict[str, str]:
    """
    Pousse toutes les lignes locales dirty vers Supabase.
    Règle de conflit: Last-Write-Wins via updated_at.
      - Si local.updated_at >= remote.updated_at (ou remote absent) → push local
      - Sinon → pull remote (local devient clean)
    Retourne un dict {key: action} avec action ∈ {pushed, pulled, skipped, error}.
    """
    actions: Dict[str, str] = {}
    if _ON_VERCEL:
        if verbose: logger.info("[sync] Ignoré: environnement Vercel (ONLINE uniquement).")
        return actions
    if not _client:
        if verbose: logger.info("[sync] Pas de client Supabase disponible.")
        return actions

    dirty_map = _sqlite_all_dirty()
    if verbose: logger.info("[sync] Dirty keys: %s", list(dirty_map.keys()))

    for key, local in dirty_map.items():
        local_val = local["value"]
        local_ts  = local["updated_at"]

        remote_val, remote_ts = _get_online(key)

        try:
            # Décision LWW
            if remote_val is None or _compare_ts(local_ts, remote_ts) >= 0:
                ok, updated_at = _set_online(key, local_val)
                if ok:
                    _sqlite_upsert_clean(key, local_val, updated_at_iso=updated_at)
                    actions[key] = "pushed"
                else:
                    actions[key] = "error"
            else:
                # Remote plus récent → pull
                _sqlite_upsert_clean(key, remote_val, updated_at_iso=remote_ts)
                actions[key] = "pulled"
        except Exception:
            actions[key] = "error"

    if verbose:
        for k, a in actions.items():
            logger.info("[sync] %s: %s", k, a)
    return actions


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
    try:
        rows: list = []
        page_size = 1000
        start = 0
        while True:
            resp = _client.table("exercises").select("*").order("name").range(start, start + page_size - 1).execute()
            batch = resp.data or []
            rows.extend(batch)
            if len(batch) < page_size:
                break
            start += page_size
        return {row["name"]: row for row in rows}
    except Exception as e:
        logger.error("get_exercises error: %s", e)
        return None  # Signal unavailability — do NOT overwrite with defaults


def get_exercise_by_name(name: str) -> Optional[dict]:
    """Return a single exercise row by name, or None."""
    if _client is None or MODE == "OFFLINE":
        return None
    try:
        resp = _client.table("exercises").select("*").eq("name", name).single().execute()
        return resp.data
    except Exception as e:
        logger.debug("get_exercise_by_name(%s) error: %s", name, e)
        return None


def get_exercise_id(name: str) -> Optional[str]:
    """Return the UUID of an exercise by name, or None if not found."""
    # fallback to KV during migration
    if _client is None or MODE == "OFFLINE":
        return None
    try:
        resp = _client.table("exercises").select("id").eq("name", name).single().execute()
        return resp.data["id"] if resp.data else None
    except Exception as e:
        logger.debug("get_exercise_id(%s) error: %s", name, e)
        return None  # fallback to KV during migration


def upsert_exercise(data: dict) -> dict:
    """Insert or update an exercise by name. data must include 'name'. Returns saved record."""
    if _client is None or MODE == "OFFLINE":
        return data
    name = data.get("name", "")
    try:
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
    except Exception as e:
        logger.error("upsert_exercise error: %s", e)
        return data


def rename_exercise_table(old_name: str, new_name: str) -> bool:
    """Rename an exercise in the exercises table. Returns True on success."""
    if _client is None or MODE == "OFFLINE":
        return False
    try:
        resp = _client.table("exercises").update({"name": new_name}).eq("name", old_name).execute()
        return bool(resp.data)
    except Exception as e:
        logger.error("rename_exercise_table error: %s", e)
        return False



def delete_exercise_by_name(name: str) -> bool:
    """Hard-delete an exercise by name. Returns True if a row was deleted.

    CASCADE removes all associated exercise_logs and program_block_exercises rows.
    """
    if _client is None or MODE == "OFFLINE":
        return False
    try:
        resp = _client.table("exercises").delete().eq("name", name).execute()
        return bool(resp.data)
    except Exception as e:
        logger.error("delete_exercise_by_name error: %s", e)
        return False



# ---------------------------------------------------------------------------
# Workout sessions
# ---------------------------------------------------------------------------

def get_workout_sessions(limit: int = 100) -> List[dict]:
    """Return list of workout sessions ordered by date DESC."""
    # fallback to KV during migration
    if _client is None or MODE == "OFFLINE":
        sessions = get_json("sessions", {})
        result = []
        for d in sorted(sessions.keys(), reverse=True)[:limit]:
            entry = sessions[d].copy()
            entry["date"] = d
            result.append(entry)
        return result
    try:
        resp = (
            _client.table("workout_sessions")
            .select("*")
            .order("date", desc=True)
            .limit(limit)
            .execute()
        )
        return resp.data or []
    except Exception as e:
        logger.error("get_workout_sessions error: %s", e)
        # fallback to KV during migration
        sessions = get_json("sessions", {})
        result = []
        for d in sorted(sessions.keys(), reverse=True)[:limit]:
            entry = sessions[d].copy()
            entry["date"] = d
            result.append(entry)
        return result


def get_workout_session(date: str) -> Optional[dict]:
    """Return a single workout session by date (is_second=False), or None."""
    # fallback to KV during migration
    if _client is None or MODE == "OFFLINE":
        sessions = get_json("sessions", {})
        entry = sessions.get(date)
        if entry:
            return {**entry, "date": date}
        return None
    try:
        resp = (
            _client.table("workout_sessions")
            .select("*")
            .eq("date", date)
            .eq("is_second", False)
            .single()
            .execute()
        )
        return resp.data
    except Exception as e:
        logger.debug("get_workout_session(%s) error: %s", date, e)
        # fallback to KV during migration
        sessions = get_json("sessions", {})
        entry = sessions.get(date)
        if entry:
            return {**entry, "date": date}
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
    try:
        resp = (
            _client.table("workout_sessions")
            .select("*")
            .eq("date", date)
            .eq("is_second", True)
            .single()
            .execute()
        )
        return resp.data
    except Exception as e:
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
    try:
        resp = (
            _client.table("workout_sessions")
            .select("*")
            .eq("date", date)
            .eq("session_type", "bonus")
            .limit(1)
            .execute()
        )
        return resp.data[0] if resp.data else None
    except Exception as e:
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
) -> dict:
    """Insert a new workout session row. Returns the created record."""
    payload: dict = {"date": date, "is_second": is_second, "session_type": session_type}
    if rpe is not None:
        payload["rpe"] = int(rpe)
    if comment is not None:
        payload["comment"] = comment
    if duration_min is not None:
        payload["duration_min"] = int(duration_min)
    if energy_pre is not None:
        payload["energy_pre"] = int(energy_pre)

    # fallback to KV during migration
    if _client is None or MODE == "OFFLINE":
        sessions = get_json("sessions", {})
        entry = {k: v for k, v in payload.items() if k != "date"}
        entry["logged_at"] = _now_iso()
        sessions[date] = entry
        set_json("sessions", sessions)
        return {**entry, "date": date}
    try:
        resp = _client.table("workout_sessions").insert(payload).execute()
        return resp.data[0] if resp.data else payload
    except Exception as e:
        logger.error("create_workout_session error: %s", e)
        # fallback to KV during migration
        sessions = get_json("sessions", {})
        entry = {k: v for k, v in payload.items() if k != "date"}
        entry["logged_at"] = _now_iso()
        sessions[date] = entry
        set_json("sessions", sessions)
        return {**entry, "date": date}


def complete_workout_session(date: str) -> bool:
    """Mark a workout session as completed (user tapped Terminer)."""
    if _client is None or MODE == "OFFLINE":
        sessions = get_json("sessions", {})
        if date in sessions:
            sessions[date]["completed"] = True
            set_json("sessions", sessions)
            return True
        return False
    try:
        resp = (
            _client.table("workout_sessions")
            .update({"completed": True})
            .eq("date", date)
            .eq("is_second", False)
            .execute()
        )
        return bool(resp.data)
    except Exception as e:
        logger.error("complete_workout_session error: %s", e)
        return False


def complete_workout_session_bonus(date: str) -> bool:
    """Mark a bonus session as completed."""
    if _client is None or MODE == "OFFLINE":
        return False
    try:
        resp = (
            _client.table("workout_sessions")
            .update({"completed": True})
            .eq("date", date)
            .eq("session_type", "bonus")
            .execute()
        )
        return bool(resp.data)
    except Exception as e:
        logger.error("complete_workout_session_bonus error: %s", e)
        return False


def update_workout_session_bonus(date: str, patch: dict) -> bool:
    """Update fields on a bonus session. Returns True on success."""
    if _client is None or MODE == "OFFLINE":
        return False
    try:
        resp = (
            _client.table("workout_sessions")
            .update(patch)
            .eq("date", date)
            .eq("session_type", "bonus")
            .execute()
        )
        return bool(resp.data)
    except Exception as e:
        logger.error("update_workout_session_bonus error: %s", e)
        return False


def delete_workout_session_by_type(date: str, session_type: str = "morning") -> bool:
    """Delete a single session row by date + session_type."""
    if _client is None or MODE == "OFFLINE":
        if session_type == "morning":
            sessions = get_json("sessions", {})
            if date in sessions:
                del sessions[date]
                set_json("sessions", sessions)
                return True
        return False
    try:
        resp = (
            _client.table("workout_sessions")
            .delete()
            .eq("date", date)
            .eq("session_type", session_type)
            .execute()
        )
        return bool(resp.data)
    except Exception as e:
        logger.error("delete_workout_session_by_type error: %s", e)
        return False


def delete_exercise_logs_for_session(session_id: str) -> bool:
    """Delete all exercise_logs for a given session_id."""
    if _client is None or MODE == "OFFLINE":
        return False
    try:
        _client.table("exercise_logs").delete().eq("session_id", session_id).execute()
        return True
    except Exception as e:
        logger.error("delete_exercise_logs_for_session error: %s", e)
        return False


def upsert_exercise_log_direct(session_id: str, exercise_name: str, weight: float, reps: str) -> bool:
    """Insert/update an exercise_log row using session_id directly (bypasses date lookup)."""
    if _client is None or MODE == "OFFLINE":
        return False
    try:
        exercise_id = get_exercise_id(exercise_name)
        if not exercise_id:
            logger.warning("upsert_exercise_log_direct: exercise '%s' not found", exercise_name)
            return False
        payload = {
            "session_id": session_id,
            "exercise_id": exercise_id,
            "weight": weight,
            "reps": reps,
        }
        resp = (
            _client.table("exercise_logs")
            .upsert(payload, on_conflict="session_id,exercise_id")
            .execute()
        )
        return bool(resp.data)
    except Exception as e:
        logger.error("upsert_exercise_log_direct error: %s", e)
        return False


def get_exercise_history_grouped_by_session() -> dict:
    """Return exercise history keyed by workout_sessions.id (UUID string).

    Returns: {session_id: [{"exercise": name, "weight": w, "reps": r}, ...]}
    """
    if _client is None or MODE == "OFFLINE":
        return {}
    try:
        resp = (
            _client.table("exercise_logs")
            .select("weight, reps, session_id, exercises(name)")
            .execute()
        )
        rows = resp.data or []
        result: dict = {}
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
        return result
    except Exception as e:
        logger.error("get_exercise_history_grouped_by_session error: %s", e)
        return {}


def update_workout_session(date: str, patch: dict) -> bool:
    """Update fields on a workout session by date. Returns True on success."""
    # fallback to KV during migration
    if _client is None or MODE == "OFFLINE":
        sessions = get_json("sessions", {})
        if date in sessions:
            sessions[date].update(patch)
            set_json("sessions", sessions)
            return True
        return False
    try:
        resp = (
            _client.table("workout_sessions")
            .update(patch)
            .eq("date", date)
            .eq("is_second", False)
            .execute()
        )
        return bool(resp.data)
    except Exception as e:
        logger.error("update_workout_session error: %s", e)
        # fallback to KV during migration
        sessions = get_json("sessions", {})
        if date in sessions:
            sessions[date].update(patch)
            set_json("sessions", sessions)
            return True
        return False


def delete_workout_session(date: str) -> bool:
    """Delete a workout session and its exercise_logs (cascade). Returns True on success."""
    # fallback to KV during migration
    if _client is None or MODE == "OFFLINE":
        sessions = get_json("sessions", {})
        if date in sessions:
            del sessions[date]
            set_json("sessions", sessions)
            return True
        return False
    try:
        resp = _client.table("workout_sessions").delete().eq("date", date).execute()
        return bool(resp.data)
    except Exception as e:
        logger.error("delete_workout_session error: %s", e)
        # fallback to KV during migration
        sessions = get_json("sessions", {})
        if date in sessions:
            del sessions[date]
            set_json("sessions", sessions)
            return True
        return False


# ---------------------------------------------------------------------------
# Exercise logs
# ---------------------------------------------------------------------------

def get_exercise_history(exercise_name: str, limit: int = 50) -> List[dict]:
    """Return [{date, weight, reps, session_id}] newest first."""
    if _client is None or MODE == "OFFLINE":
        weights = get_json("weights", {})
        return weights.get(exercise_name, {}).get("history", [])[:limit]
    try:
        ex_id = get_exercise_id(exercise_name)
        if not ex_id:
            weights = get_json("weights", {})
            return weights.get(exercise_name, {}).get("history", [])[:limit]
        resp = (
            _client.table("exercise_logs")
            .select("weight, reps, session_id, workout_sessions(date)")
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
                "session_id": r["session_id"],
            }
            for r in rows
            if r.get("workout_sessions")
        ]
    except Exception as e:
        logger.error("get_exercise_history(%s) error: %s", exercise_name, e)
        weights = get_json("weights", {})
        return weights.get(exercise_name, {}).get("history", [])[:limit]


def get_all_exercise_history() -> dict:
    """Return {exercise_name: [{date, weight, reps}]} for all exercises in one query.

    Used by load_weights() to avoid N+1 per-exercise queries.
    Falls back to KV get_json('weights') on error.
    """
    if _client is None or MODE == "OFFLINE":
        weights = get_json("weights", {})
        return {
            name: data.get("history", [])
            for name, data in weights.items()
        }
    try:
        resp = (
            _client.table("exercise_logs")
            .select("weight, reps, exercises(name), workout_sessions(date)")
            .execute()
        )
        rows = resp.data or []
        result: dict = {}
        for r in rows:
            name = (r.get("exercises") or {}).get("name")
            date = (r.get("workout_sessions") or {}).get("date")
            if not name or not date:
                continue
            entry = {"date": date, "weight": r.get("weight"), "reps": r.get("reps")}
            result.setdefault(name, []).append(entry)
        # Sort each exercise history newest-first
        for name in result:
            result[name].sort(key=lambda x: x.get("date", ""), reverse=True)
        return result
    except Exception as e:
        logger.error("get_all_exercise_history error: %s", e)
        weights = get_json("weights", {})
        return {name: data.get("history", []) for name, data in weights.items()}


def get_session_exercise_logs(session_date: str) -> List[dict]:
    """Return [{exercise_name, weight, reps}] for a given session date."""
    # fallback to KV during migration
    if _client is None or MODE == "OFFLINE":
        weights = get_json("weights", {})
        result = []
        for name, data in weights.items():
            history = data.get("history", [])
            if history and history[0].get("date") == session_date:
                result.append({
                    "exercise_name": name,
                    "weight": history[0].get("weight"),
                    "reps": history[0].get("reps"),
                })
        return result
    try:
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
    except Exception as e:
        logger.error("get_session_exercise_logs(%s) error: %s", session_date, e)
        # fallback to KV during migration
        weights = get_json("weights", {})
        result = []
        for name, data in weights.items():
            history = data.get("history", [])
            if history and history[0].get("date") == session_date:
                result.append({
                    "exercise_name": name,
                    "weight": history[0].get("weight"),
                    "reps": history[0].get("reps"),
                })
        return result


def upsert_exercise_log(
    session_date: str, exercise_name: str, weight: float, reps: str
) -> bool:
    """Insert or update an exercise log entry. Resolves IDs internally. Returns True on success."""
    # fallback to KV during migration
    if _client is None or MODE == "OFFLINE":
        weights = get_json("weights", {})
        entry = {"date": session_date, "weight": weight, "reps": reps}
        ex_data = weights.setdefault(exercise_name, {"history": []})
        history = ex_data.get("history", [])
        # Replace today's entry if it exists
        if history and history[0].get("date") == session_date:
            history[0] = entry
        else:
            history.insert(0, entry)
        ex_data["history"] = history
        weights[exercise_name] = ex_data
        set_json("weights", weights)
        return True
    try:
        exercise_id = get_exercise_id(exercise_name)
        if not exercise_id:
            logger.warning("upsert_exercise_log: exercise '%s' not found", exercise_name)
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
        resp = (
            _client.table("exercise_logs")
            .upsert(payload, on_conflict="session_id,exercise_id")
            .execute()
        )
        return bool(resp.data)
    except Exception as e:
        logger.error("upsert_exercise_log error: %s", e)
        # fallback to KV during migration
        weights = get_json("weights", {})
        entry = {"date": session_date, "weight": weight, "reps": reps}
        ex_data = weights.setdefault(exercise_name, {"history": []})
        history = ex_data.get("history", [])
        if history and history[0].get("date") == session_date:
            history[0] = entry
        else:
            history.insert(0, entry)
        ex_data["history"] = history
        weights[exercise_name] = ex_data
        set_json("weights", weights)
        return True


def delete_exercise_log_entry(session_date: str, exercise_name: str) -> bool:
    """Delete a single exercise_log entry by date + exercise name."""
    if _client is None or MODE == "OFFLINE":
        return False
    try:
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
    except Exception as e:
        logger.error("delete_exercise_log_entry error: %s", e)
        return False


def delete_session_exercise_logs(session_date: str) -> bool:
    """Delete all exercise_logs for a given session date. Returns True on success."""
    # fallback to KV during migration
    if _client is None or MODE == "OFFLINE":
        # Cannot cleanly remove individual day logs from KV without full reload
        logger.warning("delete_session_exercise_logs: KV fallback does not support deletion by date")
        return False
    try:
        session = get_workout_session(session_date)
        if not session:
            return False
        session_id = session["id"]
        resp = _client.table("exercise_logs").delete().eq("session_id", session_id).execute()
        return True
    except Exception as e:
        logger.error("delete_session_exercise_logs error: %s", e)
        return False  # fallback to KV during migration not feasible here


# ---------------------------------------------------------------------------
# Body weight
# ---------------------------------------------------------------------------

def get_body_weight_logs(limit: int = 100) -> List[dict]:
    """Return body weight log entries, newest first."""
    # fallback to KV during migration
    if _client is None or MODE == "OFFLINE":
        data = get_json("body_weight", [])
        return data[:limit]
    try:
        resp = (
            _client.table("body_weight_logs")
            .select("*")
            .order("date", desc=True)
            .limit(limit)
            .execute()
        )
        return resp.data or []
    except Exception as e:
        logger.error("get_body_weight_logs error: %s", e)
        data = get_json("body_weight", [])  # fallback to KV during migration
        return data[:limit]


def upsert_body_weight(
    date: str,
    weight: float,
    note: str = "",
    body_fat: Optional[float] = None,
    waist_cm: Optional[float] = None,
    arms_cm: Optional[float] = None,
    chest_cm: Optional[float] = None,
    thighs_cm: Optional[float] = None,
    hips_cm: Optional[float] = None,
) -> bool:
    """Insert or update a body weight log entry for the given date."""
    kv_entry: dict = {"date": date, "poids": weight, "note": note}
    for field, val in [("body_fat", body_fat), ("waist_cm", waist_cm),
                       ("arms_cm", arms_cm), ("chest_cm", chest_cm),
                       ("thighs_cm", thighs_cm), ("hips_cm", hips_cm)]:
        if val is not None:
            kv_entry[field] = val

    # fallback to KV during migration
    if _client is None or MODE == "OFFLINE":
        data = get_json("body_weight", [])
        existing = next((i for i, e in enumerate(data) if e.get("date") == date), None)
        if existing is not None:
            data[existing] = kv_entry
        else:
            data.insert(0, kv_entry)
        set_json("body_weight", data)
        return True
    try:
        payload: dict = {"date": date, "weight": weight, "note": note}
        for field, val in [("body_fat", body_fat), ("waist_cm", waist_cm),
                           ("arms_cm", arms_cm), ("chest_cm", chest_cm),
                           ("thighs_cm", thighs_cm), ("hips_cm", hips_cm)]:
            if val is not None:
                payload[field] = val
        resp = (
            _client.table("body_weight_logs")
            .upsert(payload, on_conflict="date")
            .execute()
        )
        return bool(resp.data)
    except Exception as e:
        logger.error("upsert_body_weight error: %s", e)
        # fallback to KV during migration
        data = get_json("body_weight", [])
        entry = kv_entry
        existing = next((i for i, e in enumerate(data) if e.get("date") == date), None)
        if existing is not None:
            data[existing] = entry
        else:
            data.insert(0, entry)
        set_json("body_weight", data)
        return True


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
    # fallback to KV during migration
    if _client is None or MODE == "OFFLINE":
        data = get_json("body_weight", [])
        before = len(data)
        data = [e for e in data if e.get("date") != date]
        set_json("body_weight", data)
        return len(data) < before
    try:
        resp = _client.table("body_weight_logs").delete().eq("date", date).execute()
        return bool(resp.data)
    except Exception as e:
        logger.error("delete_body_weight error: %s", e)
        # fallback to KV during migration
        data = get_json("body_weight", [])
        before = len(data)
        data = [e for e in data if e.get("date") != date]
        set_json("body_weight", data)
        return len(data) < before


# ---------------------------------------------------------------------------
# HIIT logs
# ---------------------------------------------------------------------------

def get_hiit_logs(limit: int = 100) -> List[dict]:
    """Return HIIT log entries, newest first."""
    # fallback to KV during migration
    if _client is None or MODE == "OFFLINE":
        data = get_json("hiit_log", [])
        return data[:limit]
    try:
        resp = (
            _client.table("hiit_logs")
            .select("*")
            .order("date", desc=True)
            .order("logged_at", desc=True)
            .limit(limit)
            .execute()
        )
        return resp.data or []
    except Exception as e:
        logger.error("get_hiit_logs error: %s", e)
        data = get_json("hiit_log", [])  # fallback to KV during migration
        return data[:limit]


def insert_hiit_log(data: dict) -> dict:
    """Insert a new HIIT log entry. Returns the inserted record."""
    # fallback to KV during migration
    if _client is None or MODE == "OFFLINE":
        log = get_json("hiit_log", [])
        log.insert(0, data)
        set_json("hiit_log", log)
        return data
    try:
        resp = _client.table("hiit_logs").insert(data).execute()
        return resp.data[0] if resp.data else data
    except Exception as e:
        logger.error("insert_hiit_log error: %s", e)
        # fallback to KV during migration
        log = get_json("hiit_log", [])
        log.insert(0, data)
        set_json("hiit_log", log)
        return data


def update_hiit_log(hiit_id: str, patch: dict) -> bool:
    """Update a HIIT log entry by its UUID. Returns True on success."""
    # fallback to KV during migration
    if _client is None or MODE == "OFFLINE":
        logger.warning("update_hiit_log: UUID-based update not supported in KV fallback")
        return False
    try:
        resp = _client.table("hiit_logs").update(patch).eq("id", hiit_id).execute()
        return bool(resp.data)
    except Exception as e:
        logger.error("update_hiit_log error: %s", e)
        return False  # fallback to KV during migration not feasible by UUID


def delete_hiit_log_by_id(hiit_id: str) -> bool:
    """Delete a HIIT log entry by its UUID. Returns True on success."""
    # fallback to KV during migration
    if _client is None or MODE == "OFFLINE":
        logger.warning("delete_hiit_log_by_id: UUID-based deletion not supported in KV fallback")
        return False
    try:
        resp = _client.table("hiit_logs").delete().eq("id", hiit_id).execute()
        return bool(resp.data)
    except Exception as e:
        logger.error("delete_hiit_log_by_id error: %s", e)
        return False  # fallback to KV during migration not feasible by UUID


# ---------------------------------------------------------------------------
# Recovery logs
# ---------------------------------------------------------------------------

def get_recovery_logs(limit: int = 100) -> List[dict]:
    """Return recovery log entries, newest first."""
    # fallback to KV during migration
    if _client is None or MODE == "OFFLINE":
        data = get_json("recovery_log", [])
        return data[:limit]
    try:
        resp = (
            _client.table("recovery_logs")
            .select("*")
            .order("date", desc=True)
            .limit(limit)
            .execute()
        )
        return resp.data or []
    except Exception as e:
        logger.error("get_recovery_logs error: %s", e)
        data = get_json("recovery_log", [])  # fallback to KV during migration
        return data[:limit]


def upsert_recovery_log(data: dict) -> bool:
    """Insert or update a recovery log by date. data must include 'date'."""
    # fallback to KV during migration
    if _client is None or MODE == "OFFLINE":
        log = get_json("recovery_log", [])
        date_val = data.get("date", "")
        existing = next((i for i, e in enumerate(log) if e.get("date") == date_val), None)
        if existing is not None:
            log[existing].update(data)
        else:
            log.insert(0, data)
        set_json("recovery_log", log)
        return True
    try:
        resp = (
            _client.table("recovery_logs")
            .upsert(data, on_conflict="date")
            .execute()
        )
        return bool(resp.data)
    except Exception as e:
        logger.error("upsert_recovery_log error: %s", e)
        # fallback to KV during migration
        log = get_json("recovery_log", [])
        date_val = data.get("date", "")
        existing = next((i for i, e in enumerate(log) if e.get("date") == date_val), None)
        if existing is not None:
            log[existing].update(data)
        else:
            log.insert(0, data)
        set_json("recovery_log", log)
        return True


def merge_recovery_wearable(target_date: str, wearable: dict) -> bool:
    """Merge HealthKit/Apple Watch data into recovery_logs for target_date.

    Only fills in fields that are not already set (manual entries take priority).
    Never overwrites: sleep_quality, soreness, notes.
    """
    WEARABLE_KEYS = ("steps", "sleep_hours", "resting_hr", "hrv", "active_energy")

    existing_list = get_recovery_logs(limit=365)
    existing      = next((e for e in existing_list if e.get("date") == target_date), {})

    merged          = dict(existing)
    merged["date"]  = target_date
    # Keep source=manual if the entry was manually created, otherwise mark healthkit
    if not existing:
        merged["source"] = "healthkit"

    for key in WEARABLE_KEYS:
        if key in wearable and merged.get(key) is None:
            merged[key] = wearable[key]

    return upsert_recovery_log(merged)


def delete_recovery_log(date: str) -> bool:
    """Delete a recovery log entry by date. Returns True on success."""
    # fallback to KV during migration
    if _client is None or MODE == "OFFLINE":
        log = get_json("recovery_log", [])
        before = len(log)
        log = [e for e in log if e.get("date") != date]
        set_json("recovery_log", log)
        return len(log) < before
    try:
        resp = _client.table("recovery_logs").delete().eq("date", date).execute()
        return bool(resp.data)
    except Exception as e:
        logger.error("delete_recovery_log error: %s", e)
        # fallback to KV during migration
        log = get_json("recovery_log", [])
        before = len(log)
        log = [e for e in log if e.get("date") != date]
        set_json("recovery_log", log)
        return len(log) < before


# ---------------------------------------------------------------------------
# Goals
# ---------------------------------------------------------------------------

def get_goals() -> Dict[str, dict]:
    """Return {exercise_name: {target_weight, target_date, id}}.

    'achieved' is NOT stored — derive it by comparing target_weight
    against get_exercise_history(name, limit=1)[0]['weight'].
    """
    # fallback to KV during migration
    if _client is None or MODE == "OFFLINE":
        return get_json("goals", {})
    try:
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
    except Exception as e:
        logger.error("get_goals error: %s", e)
        return get_json("goals", {})  # fallback to KV during migration


def set_goal(
    exercise_name: str,
    target_weight: float,
    target_date: Optional[str] = None,
) -> bool:
    """Create or update a goal for an exercise. Returns True on success."""
    # fallback to KV during migration
    if _client is None or MODE == "OFFLINE":
        goals = get_json("goals", {})
        goals[exercise_name] = {
            "goal_weight": target_weight,
            "deadline": target_date,
            "achieved": False,
        }
        set_json("goals", goals)
        return True
    try:
        exercise_id = get_exercise_id(exercise_name)
        if not exercise_id:
            logger.warning("set_goal: exercise '%s' not found", exercise_name)
            # fallback to KV during migration
            goals = get_json("goals", {})
            goals[exercise_name] = {
                "goal_weight": target_weight,
                "deadline": target_date,
                "achieved": False,
            }
            set_json("goals", goals)
            return True
        payload: dict = {"exercise_id": exercise_id, "target_weight": target_weight}
        if target_date:
            payload["target_date"] = target_date
        resp = (
            _client.table("goals")
            .upsert(payload, on_conflict="exercise_id")
            .execute()
        )
        return bool(resp.data)
    except Exception as e:
        logger.error("set_goal error: %s", e)
        # fallback to KV during migration
        goals = get_json("goals", {})
        goals[exercise_name] = {
            "goal_weight": target_weight,
            "deadline": target_date,
            "achieved": False,
        }
        set_json("goals", goals)
        return True


# ---------------------------------------------------------------------------
# Cardio logs
# ---------------------------------------------------------------------------

def get_cardio_logs(limit: int = 100) -> List[dict]:
    """Return cardio log entries, newest first."""
    # fallback to KV during migration
    if _client is None or MODE == "OFFLINE":
        return get_json("cardio_log", [])[:limit]
    try:
        resp = (
            _client.table("cardio_logs")
            .select("*")
            .order("date", desc=True)
            .limit(limit)
            .execute()
        )
        return resp.data or []
    except Exception as e:
        logger.error("get_cardio_logs error: %s", e)
        return get_json("cardio_log", [])[:limit]  # fallback to KV during migration


def insert_cardio_log(data: dict) -> bool:
    """Insert a new cardio log entry. Returns True on success."""
    # fallback to KV during migration
    if _client is None or MODE == "OFFLINE":
        log = get_json("cardio_log", [])
        log.insert(0, data)
        set_json("cardio_log", log)
        return True
    try:
        resp = _client.table("cardio_logs").insert(data).execute()
        return bool(resp.data)
    except Exception as e:
        logger.error("insert_cardio_log error: %s", e)
        # fallback to KV during migration
        log = get_json("cardio_log", [])
        log.insert(0, data)
        set_json("cardio_log", log)
        return True


def delete_cardio_log(date: str, type_: str) -> bool:
    """Delete a cardio log entry by date and type. Returns True on success."""
    # fallback to KV during migration
    if _client is None or MODE == "OFFLINE":
        log = get_json("cardio_log", [])
        before = len(log)
        log = [e for e in log if not (e.get("date") == date and e.get("type") == type_)]
        set_json("cardio_log", log)
        return len(log) < before
    try:
        resp = (
            _client.table("cardio_logs")
            .delete()
            .eq("date", date)
            .eq("type", type_)
            .execute()
        )
        return bool(resp.data)
    except Exception as e:
        logger.error("delete_cardio_log error: %s", e)
        # fallback to KV during migration
        log = get_json("cardio_log", [])
        before = len(log)
        log = [e for e in log if not (e.get("date") == date and e.get("type") == type_)]
        set_json("cardio_log", log)
        return len(log) < before


# ---------------------------------------------------------------------------
# User profile
# ---------------------------------------------------------------------------

def get_profile() -> dict:
    """Return the single user_profile row as a dict."""
    if _client is None or MODE == "OFFLINE":
        return get_json("user_profile", {})
    try:
        resp = (
            _client.table("user_profile")
            .select("*")
            .eq("id", 1)
            .limit(1)
            .execute()
        )
        return (resp.data[0] if resp and resp.data else None) or get_json("user_profile", {})
    except Exception as e:
        logger.warning("get_profile error: %s", e)
        return get_json("user_profile", {})


def update_profile(patch: dict) -> bool:
    """Update the user profile. Creates the row if it does not yet exist."""
    # fallback to KV during migration
    if _client is None or MODE == "OFFLINE":
        profile = get_json("user_profile", {})
        profile.update(patch)
        set_json("user_profile", profile)
        return True
    try:
        payload = {**patch, "id": 1, "updated_at": _now_iso()}
        resp = (
            _client.table("user_profile")
            .upsert(payload, on_conflict="id")
            .execute()
        )
        return bool(resp.data)
    except Exception as e:
        logger.error("update_profile error: %s", e)
        # fallback to KV during migration
        profile = get_json("user_profile", {})
        profile.update(patch)
        set_json("user_profile", profile)
        return True


# ---------------------------------------------------------------------------
# Nutrition
# ---------------------------------------------------------------------------

def get_nutrition_settings() -> dict:
    """Return nutrition settings (single row)."""
    _default = {"calorie_limit": 2000, "protein_target": 150}
    if _client is None or MODE == "OFFLINE":
        return get_json("nutrition_settings", _default)
    try:
        resp = (
            _client.table("nutrition_settings")
            .select("*")
            .eq("id", 1)
            .limit(1)
            .execute()
        )
        return (resp.data[0] if resp and resp.data else None) or get_json("nutrition_settings", _default)
    except Exception as e:
        logger.warning("get_nutrition_settings error: %s", e)
        return get_json("nutrition_settings", _default)


def update_nutrition_settings(patch: dict) -> bool:
    """Update nutrition settings row."""
    # fallback to KV during migration
    if _client is None or MODE == "OFFLINE":
        settings = get_json("nutrition_settings", {})
        settings.update(patch)
        set_json("nutrition_settings", settings)
        return True
    try:
        payload = {**patch, "id": 1, "updated_at": _now_iso()}
        resp = (
            _client.table("nutrition_settings")
            .upsert(payload, on_conflict="id")
            .execute()
        )
        return bool(resp.data)
    except Exception as e:
        logger.error("update_nutrition_settings error: %s", e)
        # fallback to KV during migration
        settings = get_json("nutrition_settings", {})
        settings.update(patch)
        set_json("nutrition_settings", settings)
        return True


# ---------------------------------------------------------------------------
# Nutrition entries
# ---------------------------------------------------------------------------

def get_nutrition_entries(date: str) -> List[dict]:
    """Return nutrition entries for a specific date, ordered by insertion time."""
    if _client is None or MODE == "OFFLINE":
        log = get_json("nutrition_log", {})
        return (log.get(date) or {}).get("entries", [])
    try:
        resp = (
            _client.table("nutrition_entries")
            .select("*")
            .eq("date", date)
            .order("heure")
            .execute()
        )
        return resp.data or []
    except Exception as e:
        logger.error("get_nutrition_entries error: %s", e)
        log = get_json("nutrition_log", {})
        return (log.get(date) or {}).get("entries", [])


def get_nutrition_entries_recent(n: int = 7) -> List[dict]:
    """Return one summary row per day for the last n distinct days.

    Returns [{"date": ..., "calories": ..., "nb": ...}, ...] newest first.
    """
    if _client is None or MODE == "OFFLINE":
        log = get_json("nutrition_log", {})
        days = sorted(log.keys(), reverse=True)[:n]
        result = []
        for day in days:
            entries = (log.get(day) or {}).get("entries", [])
            result.append({
                "date":     day,
                "calories": round(sum(e.get("calories", 0) for e in entries)),
                "nb":       len(entries),
            })
        return result
    try:
        from datetime import date as _date, timedelta
        cutoff = (_date.today() - timedelta(days=n * 2)).isoformat()
        resp = (
            _client.table("nutrition_entries")
            .select("date, calories")
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
                seen[d] = {"date": d, "calories": 0, "nb": 0}
            seen[d]["calories"] += row.get("calories", 0)
            seen[d]["nb"] += 1
        sorted_days = sorted(seen.values(), key=lambda x: x["date"], reverse=True)[:n]
        for day in sorted_days:
            day["calories"] = round(day["calories"])
        return sorted_days
    except Exception as e:
        logger.error("get_nutrition_entries_recent error: %s", e)
        log = get_json("nutrition_log", {})
        days = sorted(log.keys(), reverse=True)[:n]
        return [
            {
                "date":     d,
                "calories": round(sum(e.get("calories", 0) for e in (log.get(d) or {}).get("entries", []))),
                "nb":       len((log.get(d) or {}).get("entries", [])),
            }
            for d in days
        ]


def insert_nutrition_entry(data: dict) -> dict:
    """Insert a nutrition entry. Returns the saved entry (with id)."""
    if _client is None or MODE == "OFFLINE":
        log = get_json("nutrition_log", {})
        date = data.get("date", "")
        if date not in log:
            log[date] = {"entries": []}
        log[date]["entries"].append(data)
        set_json("nutrition_log", log)
        return data
    try:
        resp = _client.table("nutrition_entries").insert(data).execute()
        return resp.data[0] if resp.data else data
    except Exception as e:
        logger.error("insert_nutrition_entry error: %s", e)
        log = get_json("nutrition_log", {})
        date = data.get("date", "")
        if date not in log:
            log[date] = {"entries": []}
        log[date]["entries"].append(data)
        set_json("nutrition_log", log)
        return data


def delete_nutrition_entry(entry_id: str) -> bool:
    """Delete a nutrition entry by id. Returns True on success."""
    if _client is None or MODE == "OFFLINE":
        log = get_json("nutrition_log", {})
        for date, day_data in log.items():
            entries = day_data.get("entries", [])
            before = len(entries)
            day_data["entries"] = [e for e in entries if e.get("id") != entry_id]
            if len(day_data["entries"]) < before:
                set_json("nutrition_log", log)
                return True
        return False
    try:
        resp = _client.table("nutrition_entries").delete().eq("id", entry_id).execute()
        return bool(resp.data)
    except Exception as e:
        logger.error("delete_nutrition_entry error: %s", e)
        return False


# ---------------------------------------------------------------------------
# Deload state
# ---------------------------------------------------------------------------

def get_deload_state() -> dict:
    """Return the current deload state (single row)."""
    # fallback to KV during migration
    if _client is None or MODE == "OFFLINE":
        return get_json("deload_state", {"active": False, "started_at": None, "reason": None})
    try:
        resp = (
            _client.table("deload_state")
            .select("*")
            .eq("id", 1)
            .single()
            .execute()
        )
        return resp.data or {"active": False, "started_at": None, "reason": None}
    except Exception as e:
        logger.error("get_deload_state error: %s", e)
        return get_json("deload_state", {"active": False})  # fallback to KV during migration


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

    # fallback to KV during migration
    if _client is None or MODE == "OFFLINE":
        existing = get_json("deload_state", {})
        existing.update(payload)
        set_json("deload_state", existing)
        return True
    try:
        resp = (
            _client.table("deload_state")
            .upsert(payload, on_conflict="id")
            .execute()
        )
        return bool(resp.data)
    except Exception as e:
        logger.error("set_deload_state error: %s", e)
        # fallback to KV during migration
        existing = get_json("deload_state", {})
        existing.update(payload)
        set_json("deload_state", existing)
        return True


# ---------------------------------------------------------------------------
# Program relational tables
# (program_sessions, program_blocks, program_block_exercises, weekly_schedule)
# ---------------------------------------------------------------------------

def get_full_program() -> dict | None:
    """Return {session_name: {"blocks": [{"type", "order", "exercises": {name: scheme}}]}}.

    Compatible with the block format used by planner.py / blocks.py.
    Returns {} if relational tables are genuinely empty (no sessions).
    Returns None if the relational layer is unavailable or a network/query error occurs —
    callers must treat None as "unknown state, do NOT overwrite existing data".
    """
    if _client is None or MODE == "OFFLINE":
        return None
    try:
        # Load all sessions
        sessions_resp = _client.table("program_sessions").select("id, name, order_index").order("order_index").execute()
        sessions = sessions_resp.data or []
        if not sessions:
            return {}  # Genuinely empty — safe to seed defaults

        program: dict = {}
        for session in sessions:
            sid = session["id"]
            sname = session["name"]

            # Load blocks for this session
            blocks_resp = (
                _client.table("program_blocks")
                .select("id, type, order_index, hiit_config")
                .eq("session_id", sid)
                .order("order_index")
                .execute()
            )
            blocks_data = blocks_resp.data or []

            built_blocks = []
            for block in blocks_data:
                bid = block["id"]
                btype = block.get("type", "strength")
                border = block.get("order_index", 0)

                if btype == "strength":
                    # Load exercises for this block
                    ex_resp = (
                        _client.table("program_block_exercises")
                        .select("scheme, order_index, exercises(name)")
                        .eq("block_id", bid)
                        .order("order_index")
                        .execute()
                    )
                    ex_rows = ex_resp.data or []
                    exercises: dict = {}
                    for row in ex_rows:
                        ex_name = (row.get("exercises") or {}).get("name")
                        if ex_name:
                            exercises[ex_name] = row.get("scheme", "3x8-12")
                    built_blocks.append({"type": "strength", "order": border, "exercises": exercises})
                else:
                    cfg = block.get("hiit_config") or {}
                    built_blocks.append({"type": btype, "order": border, "hiit_config": cfg})

            program[sname] = {"blocks": built_blocks}

        return program
    except Exception as e:
        logger.warning("get_full_program error: %s — retrying once", e)
        # Retry once on transient connection errors (e.g. "Server disconnected")
        try:
            sessions_resp = _client.table("program_sessions").select("id, name, order_index").order("order_index").execute()
            sessions = sessions_resp.data or []
            if not sessions:
                return {}
            program2: dict = {}
            for session in sessions:
                sid, sname = session["id"], session["name"]
                blocks_resp = _client.table("program_blocks").select("id, type, order_index, hiit_config").eq("session_id", sid).order("order_index").execute()
                built_blocks = []
                for block in (blocks_resp.data or []):
                    bid, btype, border = block["id"], block.get("type", "strength"), block.get("order_index", 0)
                    if btype == "strength":
                        ex_resp = _client.table("program_block_exercises").select("scheme, order_index, exercises(name)").eq("block_id", bid).order("order_index").execute()
                        exercises = {(r.get("exercises") or {}).get("name"): r.get("scheme", "3x8-12") for r in (ex_resp.data or []) if (r.get("exercises") or {}).get("name")}
                        built_blocks.append({"type": "strength", "order": border, "exercises": exercises})
                    else:
                        built_blocks.append({"type": btype, "order": border, "hiit_config": block.get("hiit_config") or {}})
                program2[sname] = {"blocks": built_blocks}
            return program2
        except Exception as e2:
            logger.error("get_full_program retry failed: %s", e2)
            return None


def save_full_program(program: dict) -> bool:
    """Persist {session_name: {"blocks": [...]}} to relational tables.

    For each session: upsert program_sessions, upsert program_blocks,
    delete + reinsert program_block_exercises.
    Returns True on full success, False on any error.
    """
    if _client is None or MODE == "OFFLINE":
        return False
    try:
        for order_idx, (session_name, session_def) in enumerate(program.items()):
            # Upsert session
            sess_resp = (
                _client.table("program_sessions")
                .upsert({"name": session_name, "order_index": order_idx}, on_conflict="name")
                .execute()
            )
            # Fetch session id
            sess_row = (
                _client.table("program_sessions")
                .select("id")
                .eq("name", session_name)
                .single()
                .execute()
            )
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
    except Exception as e:
        logger.error("save_full_program error: %s", e)
        return False


def delete_program_session(name: str) -> bool:
    """Delete a programme session and all its data (blocks, exercises, schedule refs)."""
    if _client is None or MODE == "OFFLINE":
        return False
    try:
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
    except Exception as e:
        logger.error("delete_program_session error: %s", e)
        return False


def get_relational_week_schedule() -> dict:
    """Return {"Lun": "Push A", "Mar": "Pull A", ...} from weekly_schedule JOIN program_sessions.

    Days with no session assigned are omitted.
    Returns {} if relational layer is unavailable.
    """
    if _client is None or MODE == "OFFLINE":
        return {}
    try:
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
        return result
    except Exception as e:
        logger.error("get_relational_week_schedule error: %s", e)
        return {}


def set_relational_week_schedule(schedule: dict) -> bool:
    """Upsert weekly_schedule. schedule = {"Lun": "Push A", "Mar": None, ...}.

    None / missing session_name clears the day (session_id = NULL).
    Returns True on success.
    """
    if _client is None or MODE == "OFFLINE":
        return False
    try:
        for day_name, session_name in schedule.items():
            session_id = None
            if session_name:
                sess_resp = (
                    _client.table("program_sessions")
                    .select("id")
                    .eq("name", session_name)
                    .execute()
                )
                if sess_resp.data:
                    session_id = sess_resp.data[0]["id"]
            _client.table("weekly_schedule").upsert(
                {"day_name": day_name, "session_id": session_id, "slot": "morning"},
                on_conflict="day_name,slot",
            ).execute()
        return True
    except Exception as e:
        logger.error("set_relational_week_schedule error: %s", e)
        return False


def get_evening_week_schedule() -> dict:
    """Return {"Lun": "Core", ...} for slot='evening' from weekly_schedule."""
    if _client is None or MODE == "OFFLINE":
        return {}
    try:
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
    except Exception as e:
        logger.error("get_evening_week_schedule error: %s", e)
        return {}


def set_evening_week_schedule(schedule: dict) -> bool:
    """Upsert weekly_schedule for slot='evening'. None clears the day."""
    if _client is None or MODE == "OFFLINE":
        return False
    try:
        for day_name, session_name in schedule.items():
            session_id = None
            if session_name:
                sess_resp = (
                    _client.table("program_sessions")
                    .select("id")
                    .eq("name", session_name)
                    .execute()
                )
                if sess_resp.data:
                    session_id = sess_resp.data[0]["id"]
            _client.table("weekly_schedule").upsert(
                {"day_name": day_name, "session_id": session_id, "slot": "evening"},
                on_conflict="day_name,slot",
            ).execute()
        return True
    except Exception as e:
        logger.error("set_evening_week_schedule error: %s", e)
        return False
