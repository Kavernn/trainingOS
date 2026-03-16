"""
Adapter: translates between old weights dict format and new exercise_logs table.

Old format (KV):
{
  "Bench Press": {
    "current_weight": 185.0,   # COMPUTED - derive from latest history entry
    "last_reps": "6,6,5,5",    # COMPUTED - derive from latest history entry
    "history": [
      {"date": "2026-03-10", "weight": 185.0, "reps": "6,6,5,5", "1rm": 210.0}
    ]
  }
}

New format (relational): exercise_logs table with exercise_id FK, no computed fields.
"""
import db


def _calc_1rm(weight, reps_str):
    """Simple 1RM estimate (Epley) from a reps string like '6,6,5,5'."""
    try:
        reps_list = [int(x) for x in str(reps_str).split(",") if x.strip().isdigit()]
        if not reps_list or not weight:
            return 0
        avg = sum(reps_list) / len(reps_list)
        return round(weight * (1 + avg / 30), 1)
    except Exception:
        return 0


def load_weights() -> dict:
    """
    Build the old weights dict from exercise_logs in a single bulk query.
    Falls back to KV get_json("weights") if domain methods unavailable.
    Supplemental fields (rpe, note, sets, exercise_volume) are merged from KV
    since the relational exercise_logs table only stores weight/reps.
    """
    try:
        all_history = db.get_all_exercise_history()
        if not isinstance(all_history, dict) or not all_history:
            raise ValueError("no history from relational layer")

        # Load KV for supplemental fields not stored in relational layer
        kv_weights = db.get_json("weights", {}) or {}

        weights = {}
        for name, history_rows in all_history.items():
            if not isinstance(history_rows, list) or not history_rows:
                continue
            kv_hist = (kv_weights.get(name) or {}).get("history", [])
            history = []
            for row in history_rows:
                if not isinstance(row, dict):
                    continue
                entry = {
                    "date":   row.get("date"),
                    "weight": row.get("weight"),
                    "reps":   row.get("reps"),
                }
                if entry["weight"] and entry["reps"]:
                    entry["1rm"] = _calc_1rm(entry["weight"], entry["reps"])
                # Merge supplemental fields from KV (rpe, note, sets, exercise_volume)
                kv_entry = next((e for e in kv_hist if e.get("date") == entry["date"]), None)
                if kv_entry:
                    for field in ("rpe", "note", "exercise_volume", "sets"):
                        if kv_entry.get(field) is not None:
                            entry[field] = kv_entry[field]
                history.append(entry)

            if not history:
                continue

            latest = history[0]
            weights[name] = {
                "current_weight": latest.get("weight", 0),
                "last_reps":      latest.get("reps", ""),
                "history":        history,
            }
        return weights
    except Exception:
        return db.get_json("weights", {}) or {}


def save_weights(weights: dict) -> bool:
    """
    Persist weights dict back to exercise_logs table AND to KV for consistency.
    Falls back to KV set_json only if domain methods fail.

    Before writing to KV, merge supplemental fields (rpe, note, sets, exercise_volume)
    from existing KV entries so they are not lost when weights was loaded from the
    relational layer (which only stores weight/reps).
    """
    # Merge supplemental fields from existing KV to avoid stripping rpe/note/sets
    try:
        existing_kv = db.get_json("weights", {}) or {}
        for name, ex_data in weights.items():
            kv_ex = existing_kv.get(name) or {}
            kv_hist = kv_ex.get("history", [])
            for entry in (ex_data.get("history") or []):
                date = entry.get("date")
                if not date:
                    continue
                kv_entry = next((e for e in kv_hist if e.get("date") == date), None)
                if kv_entry:
                    for field in ("rpe", "note", "exercise_volume", "sets"):
                        if field not in entry and kv_entry.get(field) is not None:
                            entry[field] = kv_entry[field]
    except Exception:
        pass

    # Always write to KV for backward compat and test consistency
    kv_ok = True
    try:
        db.set_json("weights", weights)
    except Exception:
        kv_ok = False

    # Also try to persist to relational layer
    try:
        for exercise_name, ex_data in weights.items():
            if not isinstance(ex_data, dict):
                continue
            history = ex_data.get("history", [])
            for entry in history:
                if not isinstance(entry, dict):
                    continue
                date   = entry.get("date")
                weight = entry.get("weight")
                reps   = entry.get("reps")
                if date and (weight is not None or reps is not None):
                    db.upsert_exercise_log(date, exercise_name, weight, reps)
    except Exception:
        pass

    return kv_ok
