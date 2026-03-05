# api/db.py
from __future__ import annotations

import os
from typing import Any, Dict, List, Optional, Tuple, Union

from supabase import Client, create_client

_SUPABASE_URL = os.getenv("SUPABASE_URL")
_SUPABASE_KEY = os.getenv("SUPABASE_ANON_KEY")

if not _SUPABASE_URL or not _SUPABASE_KEY:
    raise RuntimeError(
        "SUPABASE_URL et/ou SUPABASE_ANON_KEY manquent dans les variables d'environnement."
    )

_client: Client = create_client(_SUPABASE_URL, _SUPABASE_KEY)
_TABLE = "kv"

def _single_or_none(resp) -> Optional[dict]:
    data = getattr(resp, "data", None)
    if isinstance(data, list):
        return data[0] if data else None
    return data

def get_json(key: str, default: Any = None) -> Any:
    """Lit la valeur JSON associée à `key` dans la table kv."""
    try:
        resp = _client.table(_TABLE).select("value").eq("key", key).single().execute()
        row = _single_or_none(resp)
        if row is None:
            return default
        return row.get("value", default)
    except Exception:
        return default

def set_json(key: str, value: Any) -> bool:
    """Écrit/remplace la valeur JSON pour `key` (upsert)."""
    try:
        _client.table(_TABLE).upsert({"key": key, "value": value}).execute()
        return True
    except Exception as e:
        print(f"[DB] set_json({key}) error: {e}")
        return False

def update_json(key: str, patch: Dict[str, Any]) -> Any:
    """Lit JSON, merge avec `patch`, réécrit, retourne la nouvelle valeur."""
    base = get_json(key, {}) or {}
    if not isinstance(base, dict):
        base = {}
    base.update(patch)
    ok = set_json(key, base)
    return base if ok else None

def append_json_list(key: str, entry: Any, max_items: Optional[int] = None) -> List[Any]:
    """Insère `entry` en tête d'une liste JSON stockée sous `key`."""
    arr = get_json(key, []) or []
    if not isinstance(arr, list):
        arr = []
    arr.insert(0, entry)
    if max_items:
        arr = arr[:max_items]
    set_json(key, arr)
    return arr

def client() -> Client:
    """Expose le client natif Supabase pour les cas avancés."""
    return _client