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


def _make_supabase_client(url: str, key: str):
    # HTTP/2 multiplexes over a single persistent connection; in serverless pools that
    # connection goes stale between invocations and raises RemoteProtocolError on the
    # next request.  Patching create_session on the class forces HTTP/1.1 for all
    # connections — including after _reconnect() — without touching ClientOptions.
    try:
        import httpx
        from postgrest._sync.client import SyncPostgrestClient

        def _session_http1(self, base_url, headers, timeout, verify=True, proxy=None):
            return httpx.Client(
                base_url=base_url,
                headers=headers,
                timeout=timeout,
                verify=verify,
                proxy=proxy,
                follow_redirects=True,
                http2=False,
            )

        SyncPostgrestClient.create_session = _session_http1
    except Exception:
        pass  # postgrest unavailable; proceed without patch

    from supabase import create_client
    return create_client(url, key)


# Client Supabase (si accessible)
_client = None
if MODE != "OFFLINE":
    try:
        from supabase import Client
        if _SUPABASE_URL and _SUPABASE_KEY:
            _client: Client = _make_supabase_client(_SUPABASE_URL, _SUPABASE_KEY)
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
        _client = _make_supabase_client(_SUPABASE_URL, _SUPABASE_KEY)
        logger.info("Supabase reconnected")
        return True
    except Exception as e:
        logger.error("Supabase reconnect failed: %s", e)
        return False


def _is_disconnect(e: Exception) -> bool:
    msg = str(e).lower()
    return (
        "disconnected" in msg
        or "server disconnected" in msg
        or "send_end_stream" in msg          # h11 stream state machine error
        or "connection reset" in msg
        or "connection refused" in msg
        or "broken pipe" in msg
        or (isinstance(e, OSError) and e.errno in (11, 104, 110, 111))  # EAGAIN/ECONNRESET/ETIMEDOUT/ECONNREFUSED
    )

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


def _sqlite_all_dirty() -> Dict[str, Any]:
    """Return {key: value} for all rows with dirty=1 in the local SQLite cache."""
    if _ON_VERCEL:
        return {}
    _ensure_sqlite()
    with _SQL_LOCK:
        cur = _CONN.execute("select key, value from kv_local where dirty=1")
        result: Dict[str, Any] = {}
        for row in cur.fetchall():
            try:
                result[row[0]] = json.loads(row[1])
            except Exception:
                result[row[0]] = None
        return result


def client():
    """Retourne le client Supabase si disponible (sinon None)"""
    return _client


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
