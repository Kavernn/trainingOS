from __future__ import annotations
import os, json, sqlite3, threading
from typing import Any, Dict, Optional, Tuple
from datetime import datetime, timezone

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
        print(f"DEBUG GET ERROR: {e}") # Apparaîtra dans les logs Vercel
        return None, None


def _set_online(key: str, value: Any) -> Tuple[bool, Optional[str]]:
    if not _client:
        print("DEBUG: Client Supabase non initialisé")
        return False, None
    try:
        # On tente l'upsert
        payload = {"key": key, "value": value}
        print(f"DEBUG: Tentative upsert pour la clé: {key}")

        # Utilisation de .execute() pour obtenir la réponse
        resp = _client.table(_TABLE).upsert(payload).execute()

        # Vérification si des données ont été retournées
        if hasattr(resp, 'data') and len(resp.data) > 0:
            updated_at = resp.data[0].get("updated_at")
            print(f"DEBUG: Succès Supabase pour {key}")
            return True, updated_at

        # Si succès mais pas de data en retour (dépend de la version du SDK)
        print(f"DEBUG: Upsert envoyé pour {key} (vérifier manuellement)")
        return True, _now_iso()

    except Exception as e:
        # C'est ici que l'erreur cruciale va apparaître dans tes logs Vercel
        print(f"DEBUG ERROR Supabase détaillée: {type(e).__name__} - {str(e)}")
        return False, None
# ---------------------------------------------------------------------------
# API publique utilisée par tes modules
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
        if verbose: print("[sync] Ignoré: environnement Vercel (ONLINE uniquement).")
        return actions
    if not _client:
        if verbose: print("[sync] Pas de client Supabase disponible.")
        return actions

    dirty_map = _sqlite_all_dirty()
    if verbose: print(f"[sync] Dirty keys: {list(dirty_map.keys())}")

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
            print(f"[sync] {k}: {a}")
    return actions