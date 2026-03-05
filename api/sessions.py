# sessions.py
import json
from pathlib import Path
from datetime import datetime

from pathlib import Path
BASE_DIR      = Path(__file__).parent
SESSIONS_FILE = BASE_DIR / "data" / "sessions.json"


def load_sessions() -> dict:
    if not SESSIONS_FILE.exists():
        SESSIONS_FILE.parent.mkdir(parents=True, exist_ok=True)
        return {}
    try:
        with open(SESSIONS_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except:
        return {}


def save_sessions(sessions: dict):
    try:
        with open(SESSIONS_FILE, "w", encoding="utf-8") as f:
            json.dump(sessions, f, indent=2, ensure_ascii=False)
    except Exception as e:
        print(f"Erreur sauvegarde sessions : {e}")


def log_session(date: str, rpe: int | None, comment: str, exos: list):
    sessions = load_sessions()
    sessions[date] = {
        "rpe":     rpe,
        "comment": comment,
        "exos":    exos,
        "logged_at": datetime.now().strftime("%Y-%m-%d %H:%M")
    }
    save_sessions(sessions)


def get_last_sessions(n: int = 10) -> list[dict]:
    sessions = load_sessions()
    result = []
    for date_key in sorted(sessions.keys(), reverse=True)[:n]:
        entry = sessions[date_key].copy()
        entry["date"] = date_key
        result.append(entry)
    return result


def migrate_sessions_from_weights(weights: dict) -> int:
    """Migre les sessions déjà dans weights.json vers sessions.json — à appeler une fois."""
    old_sessions = weights.get("sessions", {})
    if not old_sessions:
        return 0

    sessions = load_sessions()
    count = 0
    for date_key, data in old_sessions.items():
        if date_key not in sessions:
            sessions[date_key] = {
                "rpe":       data.get("rpe"),
                "comment":   data.get("comment", ""),
                "exos":      data.get("exos", []),
                "logged_at": data.get("logged_at", date_key)
            }
            count += 1

    save_sessions(sessions)
    return count