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
    if _client is None or MODE == "OFFLINE":
        return []
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
        return []


def get_workout_session(date: str) -> Optional[dict]:
    """Return a single workout session by date (is_second=False), or None."""
    if _client is None or MODE == "OFFLINE":
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
        payload["rpe"] = int(round(float(rpe)))
    if comment is not None:
        payload["comment"] = comment
    if duration_min is not None:
        payload["duration_min"] = int(duration_min)
    if energy_pre is not None:
        payload["energy_pre"] = int(energy_pre)

    if _client is None or MODE == "OFFLINE":
        return {}
    try:
        resp = _client.table("workout_sessions").insert(payload).execute()
        return resp.data[0] if resp.data else payload
    except Exception as e:
        logger.error("create_workout_session error: %s", e)
        return {}


def complete_workout_session(date: str) -> bool:
    """Mark a workout session as completed (user tapped Terminer)."""
    if _client is None or MODE == "OFFLINE":
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
    except Exception as e:
        logger.error("upsert_exercise_log_direct error: %s", e)
        return False


def update_exercise_current_weight(exercise_name: str, weight: float) -> bool:
    """Update exercises.current_weight for the given exercise name."""
    if _client is None or MODE == "OFFLINE":
        return False
    try:
        _client.table("exercises").update({"current_weight": round(weight, 1)}).eq("name", exercise_name).execute()
        return True
    except Exception as e:
        logger.error("update_exercise_current_weight error: %s", e)
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


def update_workout_session_by_type(date: str, session_type: str, patch: dict) -> bool:
    """Update fields on a workout session identified by date + session_type."""
    if _client is None or MODE == "OFFLINE":
        return False
    try:
        resp = (
            _client.table("workout_sessions")
            .update(patch)
            .eq("date", date)
            .eq("session_type", session_type)
            .execute()
        )
        return bool(resp.data)
    except Exception as e:
        logger.error("update_workout_session_by_type(%s,%s) error: %s", date, session_type, e)
        return False


def update_workout_session(date: str, patch: dict) -> bool:
    """Update fields on a workout session by date. Returns True on success."""
    if _client is None or MODE == "OFFLINE":
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
        return False


def delete_workout_session(date: str) -> bool:
    """Delete a workout session and its exercise_logs (cascade). Returns True on success."""
    if _client is None or MODE == "OFFLINE":
        return False
    try:
        resp = _client.table("workout_sessions").delete().eq("date", date).execute()
        return bool(resp.data)
    except Exception as e:
        logger.error("delete_workout_session error: %s", e)
        return False


# ---------------------------------------------------------------------------
# Exercise logs
# ---------------------------------------------------------------------------

def get_exercise_history(exercise_name: str, limit: int = 50) -> List[dict]:
    """Return [{date, weight, reps, session_id}] newest first."""
    if _client is None or MODE == "OFFLINE":
        return []
    try:
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
    except Exception as e:
        logger.error("get_exercise_history(%s) error: %s", exercise_name, e)
        return []


def get_all_exercise_history() -> dict:
    """Return {exercise_name: [{date, weight, reps}]} for all exercises in one query.

    Used by load_weights() to avoid N+1 per-exercise queries.
    """
    if _client is None or MODE == "OFFLINE":
        return {}
    try:
        resp = (
            _client.table("exercise_logs")
            .select("weight, reps, sets_json, exercises(name), workout_sessions(date)")
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
            sets_json = r.get("sets_json")
            if sets_json:
                entry["sets"] = sets_json
            result.setdefault(name, []).append(entry)
        # Sort each exercise history newest-first
        for name in result:
            result[name].sort(key=lambda x: x.get("date", ""), reverse=True)
        return result
    except Exception as e:
        logger.error("get_all_exercise_history error: %s", e)
        return {}


def get_session_exercise_logs(session_date: str) -> List[dict]:
    """Return [{exercise_name, weight, reps}] for a given session date."""
    if _client is None or MODE == "OFFLINE":
        return []
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
        return []


def get_previous_session_by_name(current_date: str, session_name: str) -> Optional[dict]:
    """Return the most recent workout_session with session_name strictly before current_date."""
    if _client is None or MODE == "OFFLINE":
        return None
    try:
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
    except Exception as e:
        logger.error("get_previous_session_by_name(%s,%s) error: %s", current_date, session_name, e)
        return None


def get_workout_session_by_type(date: str, session_type: str) -> Optional[dict]:
    """Return workout session for date + session_type, or None."""
    if _client is None or MODE == "OFFLINE":
        return None
    try:
        resp = (
            _client.table("workout_sessions")
            .select("*")
            .eq("date", date)
            .eq("session_type", session_type)
            .limit(1)
            .execute()
        )
        return resp.data[0] if resp.data else None
    except Exception as e:
        logger.error("get_workout_session_by_type(%s,%s) error: %s", date, session_type, e)
        return None


def get_exercise_logs_for_session_with_names(session_id: str) -> List[dict]:
    """Return [{exercise_name, weight, reps, sets_json}] for a session_id."""
    if _client is None or MODE == "OFFLINE":
        return []
    try:
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
    except Exception as e:
        logger.error("get_exercise_logs_for_session_with_names(%s) error: %s", session_id, e)
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
    try:
        # 1. Resolve exercise names → IDs
        ex_resp = (
            _client.table("exercises")
            .select("id")
            .in_("name", exercise_names)
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
    except Exception as e:
        logger.error("get_previous_session_by_exercises(%s) error: %s", ref_date, e)
        return None


def get_previous_session_of_type(current_date: str, session_type: str) -> Optional[dict]:
    """Return the most recent workout_session of session_type strictly before current_date."""
    if _client is None or MODE == "OFFLINE":
        return None
    try:
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
    except Exception as e:
        logger.error("get_previous_session_of_type(%s,%s) error: %s", current_date, session_type, e)
        return None


def get_exercise_info(exercise_name: str) -> Optional[dict]:
    """Return exercise row (category, load_profile, default_scheme) from exercises table."""
    if _client is None or MODE == "OFFLINE":
        return None
    try:
        resp = (
            _client.table("exercises")
            .select("name, category, load_profile, default_scheme")
            .eq("name", exercise_name)
            .limit(1)
            .execute()
        )
        return resp.data[0] if resp.data else None
    except Exception as e:
        logger.error("get_exercise_info(%s) error: %s", exercise_name, e)
        return None


def update_exercise_default_scheme(exercise_name: str, default_scheme: str) -> bool:
    """Update exercises.default_scheme for an exercise."""
    if _client is None or MODE == "OFFLINE":
        return False
    try:
        _client.table("exercises").update({"default_scheme": default_scheme}).eq("name", exercise_name).execute()
        return True
    except Exception as e:
        logger.error("update_exercise_default_scheme(%s) error: %s", exercise_name, e)
        return False


def upsert_exercise_log(
    session_date: str, exercise_name: str, weight: float, reps: str, sets_json: list | None = None
) -> bool:
    """Insert or update an exercise log entry. Resolves IDs internally. Returns True on success."""
    if _client is None or MODE == "OFFLINE":
        return False
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
        if sets_json is not None:
            payload["sets_json"] = sets_json
        resp = (
            _client.table("exercise_logs")
            .upsert(payload, on_conflict="session_id,exercise_id")
            .execute()
        )
        return bool(resp.data)
    except Exception as e:
        logger.error("upsert_exercise_log error: %s", e)
        return False


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
    if _client is None or MODE == "OFFLINE":
        return False
    try:
        session = get_workout_session(session_date)
        if not session:
            return False
        session_id = session["id"]
        _client.table("exercise_logs").delete().eq("session_id", session_id).execute()
        return True
    except Exception as e:
        logger.error("delete_session_exercise_logs error: %s", e)
        return False


# ---------------------------------------------------------------------------
# Body weight
# ---------------------------------------------------------------------------

def get_body_weight_logs(limit: int = 100) -> List[dict]:
    """Return body weight log entries, newest first."""
    if _client is None or MODE == "OFFLINE":
        return []
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
        return []


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
    if _client is None or MODE == "OFFLINE":
        return False
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
    try:
        _client.table("body_weight_logs").delete().eq("date", date).execute()
        return True
    except Exception as e:
        logger.error("delete_body_weight error: %s", e)
        return False


# ---------------------------------------------------------------------------
# HIIT logs
# ---------------------------------------------------------------------------

def get_hiit_logs(limit: int = 100) -> List[dict]:
    """Return HIIT log entries, newest first."""
    if _client is None or MODE == "OFFLINE":
        return []
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
        return []


def insert_hiit_log(data: dict) -> dict:
    """Insert a new HIIT log entry. Returns the inserted record."""
    if _client is None or MODE == "OFFLINE":
        return data
    try:
        resp = _client.table("hiit_logs").insert(data).execute()
        return resp.data[0] if resp.data else data
    except Exception as e:
        logger.error("insert_hiit_log error: %s", e)
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
    if _client is None or MODE == "OFFLINE":
        return []
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
        return []


def upsert_recovery_log(data: dict) -> bool:
    """Insert or update a recovery log by date. data must include 'date'."""
    if _client is None or MODE == "OFFLINE":
        return False
    try:
        resp = (
            _client.table("recovery_logs")
            .upsert(data, on_conflict="date")
            .execute()
        )
        return bool(resp.data)
    except Exception as e:
        logger.error("upsert_recovery_log error: %s", e)
        return False


def merge_recovery_wearable(target_date: str, wearable: dict) -> bool:
    """Merge HealthKit/Apple Watch data into recovery_logs for target_date.

    Only fills in fields that are not already set (manual entries take priority).
    Never overwrites: sleep_quality, soreness, notes.
    """
    WEARABLE_KEYS = ("steps", "sleep_hours", "resting_hr", "hrv", "active_energy")
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
    try:
        resp = _client.table("recovery_logs").delete().eq("date", date).execute()
        return bool(resp.data)
    except Exception as e:
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
        return {}


def set_goal(
    exercise_name: str,
    target_weight: float,
    target_date: Optional[str] = None,
) -> bool:
    """Create or update a goal for an exercise. Returns True on success."""
    if _client is None or MODE == "OFFLINE":
        return False
    try:
        exercise_id = get_exercise_id(exercise_name)
        if not exercise_id:
            logger.warning("set_goal: exercise '%s' not found", exercise_name)
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
    except Exception as e:
        logger.error("set_goal error: %s", e)
        return False


# ---------------------------------------------------------------------------
# Cardio logs
# ---------------------------------------------------------------------------

def get_cardio_logs(limit: int = 100) -> List[dict]:
    """Return cardio log entries, newest first."""
    if _client is None or MODE == "OFFLINE":
        return []
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
        return []


def insert_cardio_log(data: dict) -> bool:
    """Insert a new cardio log entry. Returns True on success."""
    if _client is None or MODE == "OFFLINE":
        return False
    try:
        resp = _client.table("cardio_logs").insert(data).execute()
        return bool(resp.data)
    except Exception as e:
        logger.error("insert_cardio_log error: %s", e)
        return False


def delete_cardio_log(date: str, type_: str) -> bool:
    """Delete a cardio log entry by date and type. Returns True on success."""
    if _client is None or MODE == "OFFLINE":
        return False
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
        return False


# ---------------------------------------------------------------------------
# User profile
# ---------------------------------------------------------------------------

def get_profile() -> dict:
    """Return the single user_profile row as a dict."""
    if _client is None or MODE == "OFFLINE":
        return {}
    try:
        resp = (
            _client.table("user_profile")
            .select("*")
            .eq("id", 1)
            .limit(1)
            .execute()
        )
        return (resp.data[0] if resp and resp.data else None) or {}
    except Exception as e:
        logger.warning("get_profile error: %s", e)
        return {}


def update_profile(patch: dict) -> bool:
    """Update the user profile. Creates the row if it does not yet exist."""
    if _client is None or MODE == "OFFLINE":
        return False
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
        return False


# ---------------------------------------------------------------------------
# Nutrition
# ---------------------------------------------------------------------------

def get_nutrition_settings() -> dict:
    """Return nutrition settings (single row, Supabase only)."""
    _default = {"calorie_limit": 2000, "protein_target": 150}
    if _client is None or MODE == "OFFLINE":
        return _default
    try:
        resp = (
            _client.table("nutrition_settings")
            .select("*")
            .eq("id", 1)
            .limit(1)
            .execute()
        )
        return (resp.data[0] if resp and resp.data else None) or _default
    except Exception as e:
        logger.warning("get_nutrition_settings error: %s", e)
        return _default


def update_nutrition_settings(patch: dict) -> bool:
    """Update nutrition settings row (Supabase only)."""
    if _client is None or MODE == "OFFLINE":
        raise RuntimeError("Supabase client not available")
    payload = {**patch, "id": 1, "updated_at": _now_iso()}
    resp = (
        _client.table("nutrition_settings")
        .upsert(payload, on_conflict="id")
        .execute()
    )
    return bool(resp.data)


# ---------------------------------------------------------------------------
# Nutrition entries
# ---------------------------------------------------------------------------

def get_nutrition_entries(date: str) -> List[dict]:
    """Return nutrition entries for a specific date, ordered by insertion time."""
    if _client is None or MODE == "OFFLINE":
        return []
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
        return []


def get_nutrition_entries_recent(n: int = 7) -> List[dict]:
    """Return one summary row per day for the last n distinct days.

    Returns [{"date": ..., "calories": ..., "proteines": ..., "nb": ...}, ...] newest first.
    """
    if _client is None or MODE == "OFFLINE":
        return []
    try:
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
    except Exception as e:
        logger.error("get_nutrition_entries_recent error: %s", e)
        return []


def insert_nutrition_entry(data: dict) -> dict:
    """Insert a nutrition entry. Returns the saved entry (with id)."""
    if _client is None or MODE == "OFFLINE":
        return data
    try:
        resp = _client.table("nutrition_entries").insert(data).execute()
        return resp.data[0] if resp.data else data
    except Exception as e:
        logger.error("insert_nutrition_entry error: %s", e)
        return data


def delete_nutrition_entry(entry_id: str) -> bool:
    """Delete a nutrition entry by id. Returns True on success."""
    if _client is None or MODE == "OFFLINE":
        return False
    try:
        resp = _client.table("nutrition_entries").delete().eq("id", entry_id).execute()
        return bool(resp.data)
    except Exception as e:
        logger.error("delete_nutrition_entry error: %s", e)
        return False


def update_nutrition_entry(entry_id: str, patch: dict) -> bool:
    """Update fields of a nutrition entry by id. Returns True on success."""
    if _client is None or MODE == "OFFLINE":
        return False
    try:
        resp = _client.table("nutrition_entries").update(patch).eq("id", entry_id).execute()
        return bool(resp.data)
    except Exception as e:
        logger.error("update_nutrition_entry error: %s", e)
        return False


# ---------------------------------------------------------------------------
# Food catalog
# ---------------------------------------------------------------------------

def get_food_catalog() -> list:
    """Return all food catalog items."""
    if _client is None or MODE == "OFFLINE":
        return []
    try:
        resp = _client.table("food_catalog").select("*").execute()
        return resp.data or []
    except Exception as e:
        logger.error("get_food_catalog error: %s", e)
        return []


def save_food_catalog(items: list) -> bool:
    """Replace entire food catalog (delete-all + reinsert)."""
    if _client is None or MODE == "OFFLINE":
        return False
    try:
        _client.table("food_catalog").delete().neq("id", "").execute()
        if items:
            _client.table("food_catalog").insert(items).execute()
        return True
    except Exception as e:
        logger.error("save_food_catalog error: %s", e)
        return False


# ---------------------------------------------------------------------------
# Deload state
# ---------------------------------------------------------------------------

def get_deload_state() -> dict:
    """Return the current deload state (single row)."""
    if _client is None or MODE == "OFFLINE":
        return {"active": False, "started_at": None, "reason": None}
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
    try:
        resp = (
            _client.table("deload_state")
            .upsert(payload, on_conflict="id")
            .execute()
        )
        return bool(resp.data)
    except Exception as e:
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
    try:
        _client.table("weekly_schedule").select("day_name, slot").limit(1).execute()
        _client.table("programs").select("id").limit(1).execute()
        _client.table("program_sessions").select("id, program_id").limit(1).execute()
        return True
    except Exception as e:
        logger.error(
            "⚠️  Schema migration required! Run docs/migrations/002_multi_programs.sql "
            "in your Supabase SQL Editor. Error: %s", e
        )
        return False


def get_all_programs() -> list:
    """Return [{id, name, created_at}, ...] ordered by created_at ASC."""
    if _client is None or MODE == "OFFLINE":
        return []
    try:
        resp = _client.table("programs").select("id, name, created_at").order("created_at").execute()
        return resp.data or []
    except Exception as e:
        logger.error("get_all_programs error: %s", e)
        return []


def get_default_program_id() -> str | None:
    """Return the UUID of the first (oldest) program, or None if none exist."""
    programs = get_all_programs()
    return programs[0]["id"] if programs else None


def create_program(name: str) -> str | None:
    """Insert a new program. Returns its UUID or None on error."""
    if _client is None or MODE == "OFFLINE":
        return None
    try:
        resp = _client.table("programs").insert({"name": name}).execute()
        return resp.data[0]["id"] if resp.data else None
    except Exception as e:
        logger.error("create_program error: %s", e)
        return None


def rename_program(program_id: str, new_name: str) -> bool:
    if _client is None or MODE == "OFFLINE":
        return False
    try:
        _client.table("programs").update({"name": new_name}).eq("id", program_id).execute()
        return True
    except Exception as e:
        logger.error("rename_program error: %s", e)
        return False


def delete_program(program_id: str) -> bool:
    """Delete a program — sessions cascade via FK."""
    if _client is None or MODE == "OFFLINE":
        return False
    try:
        _client.table("programs").delete().eq("id", program_id).execute()
        return True
    except Exception as e:
        logger.error("delete_program error: %s", e)
        return False


def get_all_session_names() -> list[str]:
    """Return all session names across all programs (for schedule pickers)."""
    if _client is None or MODE == "OFFLINE":
        return []
    try:
        resp = _client.table("program_sessions").select("name").order("name").execute()
        return [r["name"] for r in (resp.data or [])]
    except Exception as e:
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
    # Resolve program_id
    if program_id is None:
        program_id = get_default_program_id()
    try:
        # Load sessions filtered by program
        q = _client.table("program_sessions").select("id, name, order_index")
        if program_id:
            q = q.eq("program_id", program_id)
        sessions_resp = q.order("order_index").execute()
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
            q2 = _client.table("program_sessions").select("id, name, order_index")
            if program_id:
                q2 = q2.eq("program_id", program_id)
            sessions_resp = q2.order("order_index").execute()
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
    try:
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


# ---------------------------------------------------------------------------
# Mood logs
# ---------------------------------------------------------------------------

def get_mood_logs(days: int = 0, limit: int = 0) -> List[dict]:
    """Return mood log entries, newest first."""
    if _client is None or MODE == "OFFLINE":
        return []
    try:
        from datetime import date as _date, timedelta
        q = _client.table("mood_logs").select("*").order("date", desc=True)
        if days:
            cutoff = (_date.today() - timedelta(days=days)).isoformat()
            q = q.gte("date", cutoff)
        if limit:
            q = q.limit(limit)
        resp = q.execute()
        return resp.data or []
    except Exception as e:
        logger.error("get_mood_logs error: %s", e)
        return []


def insert_mood_log(entry: dict) -> Optional[dict]:
    """Insert a mood log entry. Returns saved record or None."""
    if _client is None or MODE == "OFFLINE":
        return None
    try:
        resp = _client.table("mood_logs").insert(entry).execute()
        return resp.data[0] if resp.data else None
    except Exception as e:
        logger.error("insert_mood_log error: %s", e)
        return None


# ---------------------------------------------------------------------------
# PSS records
# ---------------------------------------------------------------------------

def get_pss_records(pss_type: Optional[str] = None, limit: int = 0) -> List[dict]:
    """Return PSS records, newest first."""
    if _client is None or MODE == "OFFLINE":
        return []
    try:
        q = _client.table("pss_records").select("*").order("date", desc=True)
        if pss_type:
            q = q.eq("type", pss_type)
        if limit:
            q = q.limit(limit)
        resp = q.execute()
        return resp.data or []
    except Exception as e:
        logger.error("get_pss_records error: %s", e)
        return []


def insert_pss_record(entry: dict) -> Optional[dict]:
    """Insert a PSS record. Returns saved record or None."""
    if _client is None or MODE == "OFFLINE":
        return None
    try:
        resp = _client.table("pss_records").insert(entry).execute()
        return resp.data[0] if resp.data else None
    except Exception as e:
        logger.error("insert_pss_record error: %s", e)
        return None


# ---------------------------------------------------------------------------
# Sleep records
# ---------------------------------------------------------------------------

def get_sleep_records(limit: int = 0, offset: int = 0) -> List[dict]:
    """Return sleep records, newest first."""
    if _client is None or MODE == "OFFLINE":
        return []
    try:
        q = _client.table("sleep_records").select("*").order("date", desc=True)
        if limit:
            q = q.range(offset, offset + limit - 1)
        resp = q.execute()
        return resp.data or []
    except Exception as e:
        logger.error("get_sleep_records error: %s", e)
        return []


def upsert_sleep_record(entry: dict) -> Optional[dict]:
    """Insert or replace sleep record for a date (on_conflict=date)."""
    if _client is None or MODE == "OFFLINE":
        return None
    try:
        resp = _client.table("sleep_records").upsert(entry, on_conflict="date").execute()
        return resp.data[0] if resp.data else None
    except Exception as e:
        logger.error("upsert_sleep_record error: %s", e)
        return None


def delete_sleep_record(record_id: str) -> bool:
    """Delete a sleep record by id."""
    if _client is None or MODE == "OFFLINE":
        return False
    try:
        _client.table("sleep_records").delete().eq("id", record_id).execute()
        return True
    except Exception as e:
        logger.error("delete_sleep_record error: %s", e)
        return False


# ---------------------------------------------------------------------------
# Journal entries
# ---------------------------------------------------------------------------

def get_journal_entries_all(limit: int = 0, offset: int = 0) -> List[dict]:
    """Return journal entries, newest first."""
    if _client is None or MODE == "OFFLINE":
        return []
    try:
        q = _client.table("journal_entries").select("*").order("date", desc=True)
        if limit:
            q = q.range(offset, offset + limit - 1)
        resp = q.execute()
        return resp.data or []
    except Exception as e:
        logger.error("get_journal_entries_all error: %s", e)
        return []


def insert_journal_entry(entry: dict) -> Optional[dict]:
    """Insert a journal entry."""
    if _client is None or MODE == "OFFLINE":
        return None
    try:
        resp = _client.table("journal_entries").insert(entry).execute()
        return resp.data[0] if resp.data else None
    except Exception as e:
        logger.error("insert_journal_entry error: %s", e)
        return None


def search_journal_entries_db(query: str) -> List[dict]:
    """Search journal entries by content or prompt (case-insensitive)."""
    if _client is None or MODE == "OFFLINE":
        return []
    try:
        resp = (
            _client.table("journal_entries")
            .select("*")
            .or_(f"content.ilike.%{query}%,prompt.ilike.%{query}%")
            .order("date", desc=True)
            .execute()
        )
        return resp.data or []
    except Exception as e:
        logger.error("search_journal_entries_db error: %s", e)
        return []


def count_journal_entries_since(since_date: str) -> int:
    """Count journal entries on or after since_date."""
    if _client is None or MODE == "OFFLINE":
        return 0
    try:
        resp = (
            _client.table("journal_entries")
            .select("id", count="exact")
            .gte("date", since_date)
            .execute()
        )
        return resp.count or 0
    except Exception as e:
        logger.error("count_journal_entries_since error: %s", e)
        return 0


# ---------------------------------------------------------------------------
# Breathwork sessions
# ---------------------------------------------------------------------------

def get_breathwork_sessions(days: int = 30) -> List[dict]:
    """Return breathwork sessions within last N days, newest first."""
    if _client is None or MODE == "OFFLINE":
        return []
    try:
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
    except Exception as e:
        logger.error("get_breathwork_sessions error: %s", e)
        return []


def insert_breathwork_session(entry: dict) -> Optional[dict]:
    """Insert a breathwork session."""
    if _client is None or MODE == "OFFLINE":
        return None
    try:
        resp = _client.table("breathwork_sessions").insert(entry).execute()
        return resp.data[0] if resp.data else None
    except Exception as e:
        logger.error("insert_breathwork_session error: %s", e)
        return None


# ---------------------------------------------------------------------------
# Self-care habits + logs
# ---------------------------------------------------------------------------

def get_self_care_habits() -> List[dict]:
    """Return all self-care habits ordered by order_index."""
    if _client is None or MODE == "OFFLINE":
        return []
    try:
        resp = _client.table("self_care_habits").select("*").order("order_index").execute()
        return resp.data or []
    except Exception as e:
        logger.error("get_self_care_habits error: %s", e)
        return []


def upsert_self_care_habit(habit: dict) -> Optional[dict]:
    """Insert or update a self-care habit by id."""
    if _client is None or MODE == "OFFLINE":
        return None
    try:
        resp = _client.table("self_care_habits").upsert(habit, on_conflict="id").execute()
        return resp.data[0] if resp.data else None
    except Exception as e:
        logger.error("upsert_self_care_habit error: %s", e)
        return None


def delete_self_care_habit(habit_id: str) -> bool:
    """Delete a self-care habit and all its log entries."""
    if _client is None or MODE == "OFFLINE":
        return False
    try:
        _client.table("self_care_logs").delete().eq("habit_id", habit_id).execute()
        _client.table("self_care_habits").delete().eq("id", habit_id).execute()
        return True
    except Exception as e:
        logger.error("delete_self_care_habit error: %s", e)
        return False


def get_self_care_log(days: int = 90) -> Dict[str, List[str]]:
    """Return {date: [habit_id, ...]} for last N days."""
    if _client is None or MODE == "OFFLINE":
        return {}
    try:
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
    except Exception as e:
        logger.error("get_self_care_log error: %s", e)
        return {}


def set_self_care_log_for_date(date: str, habit_ids: List[str]) -> bool:
    """Replace self-care log for a specific date."""
    if _client is None or MODE == "OFFLINE":
        return False
    try:
        _client.table("self_care_logs").delete().eq("date", date).execute()
        if habit_ids:
            rows = [{"date": date, "habit_id": hid} for hid in habit_ids]
            _client.table("self_care_logs").insert(rows).execute()
        return True
    except Exception as e:
        logger.error("set_self_care_log_for_date error: %s", e)
        return False


# ---------------------------------------------------------------------------
# Life stress scores
# ---------------------------------------------------------------------------

def get_life_stress_score_db(date: str) -> Optional[dict]:
    """Return cached life stress score for a date, or None."""
    if _client is None or MODE == "OFFLINE":
        return None
    try:
        resp = _client.table("life_stress_scores").select("*").eq("date", date).single().execute()
        return resp.data
    except Exception:
        return None


def upsert_life_stress_score(entry: dict) -> bool:
    """Insert or update a life stress score entry."""
    if _client is None or MODE == "OFFLINE":
        return False
    try:
        _client.table("life_stress_scores").upsert(entry, on_conflict="date").execute()
        return True
    except Exception as e:
        logger.error("upsert_life_stress_score error: %s", e)
        return False


# ---------------------------------------------------------------------------
# Coach history
# ---------------------------------------------------------------------------

def get_coach_history(limit: int = 50) -> List[dict]:
    """Return coach history entries, newest first."""
    if _client is None or MODE == "OFFLINE":
        return []
    try:
        resp = (
            _client.table("coach_history")
            .select("*")
            .order("created_at", desc=True)
            .limit(limit)
            .execute()
        )
        return resp.data or []
    except Exception as e:
        logger.error("get_coach_history error: %s", e)
        return []


def insert_coach_message(entry: dict) -> Optional[dict]:
    """Insert a coach history message."""
    if _client is None or MODE == "OFFLINE":
        return None
    try:
        resp = _client.table("coach_history").insert(entry).execute()
        return resp.data[0] if resp.data else None
    except Exception as e:
        logger.error("insert_coach_message error: %s", e)
        return None


# ---------------------------------------------------------------------------
# Goals archived
# ---------------------------------------------------------------------------

def get_goals_archived() -> List[str]:
    """Return list of archived exercise names."""
    if _client is None or MODE == "OFFLINE":
        return []
    try:
        resp = _client.table("goals_archived").select("exercise_name").execute()
        return [r["exercise_name"] for r in (resp.data or [])]
    except Exception as e:
        logger.error("get_goals_archived error: %s", e)
        return []


def add_goal_archived(exercise_name: str) -> bool:
    """Archive a goal by exercise name."""
    if _client is None or MODE == "OFFLINE":
        return False
    try:
        _client.table("goals_archived").upsert(
            {"exercise_name": exercise_name}, on_conflict="exercise_name"
        ).execute()
        return True
    except Exception as e:
        logger.error("add_goal_archived error: %s", e)
        return False


def remove_goal_archived(exercise_name: str) -> bool:
    """Restore a goal (remove from archived)."""
    if _client is None or MODE == "OFFLINE":
        return False
    try:
        _client.table("goals_archived").delete().eq("exercise_name", exercise_name).execute()
        return True
    except Exception as e:
        logger.error("remove_goal_archived error: %s", e)
        return False


# ---------------------------------------------------------------------------
# Exercise current weight (smart progression pre-fill)
# ---------------------------------------------------------------------------

def update_exercise_current_weight(name: str, weight: float) -> bool:
    """Update current_weight for an exercise (used by SeanceView pre-fill)."""
    if _client is None or MODE == "OFFLINE":
        return False
    try:
        resp = _client.table("exercises").update({"current_weight": weight}).eq("name", name).execute()
        return bool(resp.data)
    except Exception as e:
        logger.error("update_exercise_current_weight error: %s", e)
        return False


# ---------------------------------------------------------------------------
# Sessions with volume (for correlations)
# ---------------------------------------------------------------------------

def get_sessions_for_correlations(days: int = 60) -> Dict[str, dict]:
    """Return {date: {rpe, session_volume}} for the last N days."""
    if _client is None or MODE == "OFFLINE":
        return {}
    from datetime import date as _date, timedelta
    cutoff = (_date.today() - timedelta(days=days)).isoformat()
    result: Dict[str, dict] = {}
    try:
        resp = (
            _client.table("workout_sessions")
            .select("date, rpe")
            .gte("date", cutoff)
            .execute()
        )
        for row in (resp.data or []):
            d = str(row.get("date", ""))[:10]
            if d:
                result[d] = {"rpe": row.get("rpe")}
    except Exception as e:
        logger.error("get_sessions_for_correlations (sessions) error: %s", e)

    try:
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
    except Exception as e:
        logger.error("get_sessions_for_correlations (volume) error: %s", e)

    return result


# ---------------------------------------------------------------------------
# Smart Goals
# ---------------------------------------------------------------------------

SMART_GOAL_META: dict = {
    "body_fat":           {"label": "% Masse grasse",        "unit": "%",       "lower_is_better": True},
    "lean_mass":          {"label": "Masse maigre",           "unit": "lbs",     "lower_is_better": False},
    "waist_cm":           {"label": "Tour de taille",         "unit": "cm",      "lower_is_better": True},
    "weekly_volume":      {"label": "Volume hebdo",           "unit": "lbs",     "lower_is_better": False},
    "training_frequency": {"label": "Séances / semaine",      "unit": "séances", "lower_is_better": False},
    "protein_daily":      {"label": "Protéines / jour",       "unit": "g",       "lower_is_better": False},
    "nutrition_streak":   {"label": "Streak nutrition",       "unit": "jours",   "lower_is_better": False},
}


def get_smart_goals() -> List[dict]:
    if _client is None or MODE == "OFFLINE":
        return []
    try:
        resp = _client.table("smart_goals").select("*").order("created_at").execute()
        return resp.data or []
    except Exception as e:
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
    try:
        payload: dict = {"type": goal_type, "target_value": target_value}
        if goal_id:
            payload["id"] = goal_id
        if initial_value is not None:
            payload["initial_value"] = round(initial_value, 2)
        if target_date:
            payload["target_date"] = target_date
        resp = _client.table("smart_goals").upsert(payload, on_conflict="id").execute()
        return resp.data[0] if resp.data else None
    except Exception as e:
        logger.error("upsert_smart_goal error: %s", e)
        return None


def delete_smart_goal(goal_id: str) -> bool:
    if _client is None or MODE == "OFFLINE":
        return False
    try:
        _client.table("smart_goals").delete().eq("id", goal_id).execute()
        return True
    except Exception as e:
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
