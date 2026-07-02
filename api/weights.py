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
import logging
from datetime import datetime, timezone, timedelta
from utils import _today_mtl as _today_local
from volume import calc_exercise_volume

_logger = logging.getLogger(__name__)

# --- OVERLOAD_DEBUG (temporaire — retiré dans le diff de fix) ---
# Nom EXACT stocké en DB pour l'exo test (Title Case confirmé par
# scripts/seed_load_profiles.py:57). Filtre sensible à la casse.
_OVERLOAD_DEBUG_NAME = "Seated Z Press"


def _calc_1rm(weight, reps_str):
    """1RM estimate: Epley ≤10 reps, Brzycki >10 reps, 0 if >20 reps (too imprecise).

    Delegates to progression.estimate_1rm — single source of truth.
    Returns 0 when the estimate is unreliable (>20 reps) so callers treat 0
    as "no estimate available" rather than storing a dangerously wrong value.
    """
    try:
        if not weight or not reps_str:
            return 0
        from progression import estimate_1rm
        result = estimate_1rm(float(weight), str(reps_str))
        return result if result is not None else 0
    except Exception:
        return 0


def load_weights(exercise_names: list[str] | None = None, limit_per: int = 20) -> dict:
    """
    Build the old weights dict from exercise_logs in a single bulk query.
    Returns {} if no history found (new user or empty DB).
    """
    try:
        if exercise_names:
            all_history = db.get_exercise_history_bulk(exercise_names, limit_per=limit_per)
        else:
            all_history = db.get_all_exercise_history(cutoff_days=180)
        if not isinstance(all_history, dict):
            return {}

        weights = {}
        for name, history_rows in all_history.items():
            if not isinstance(history_rows, list) or not history_rows:
                continue
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
                if row.get("sets"):
                    entry["sets"] = row["sets"]
                # Volume dérivé à la lecture : source unique côté client pour la
                # cible progressive-overload. Jamais persisté en DB (le schéma
                # exercise_logs n'a pas de colonne dédiée ; set_volume vit dans
                # sets_json). Fail loud si le calcul plante — l'entry sort sans
                # la clé, iOS traite l'absence comme "pas de cible".
                w_val = entry.get("weight")
                r_val = entry.get("reps")
                if w_val is not None and r_val is not None:
                    try:
                        entry["exercise_volume"] = calc_exercise_volume(
                            w_val, r_val, sets_json=row.get("sets")
                        )
                    except Exception as e:
                        _logger.warning(
                            "load_weights: exercise_volume calc failed for %s (date=%s): %s",
                            name, entry.get("date"), e
                        )
                history.append(entry)

            if not history:
                continue

            # --- OVERLOAD_DEBUG (temporaire — retiré dans le diff de fix) ---
            if name == _OVERLOAD_DEBUG_NAME:
                first_entry  = history[0]
                last_entry   = history[-1]
                sets_raw     = first_entry.get("sets")
                sets_type    = type(sets_raw).__name__
                sets_preview = repr(sets_raw)[:200] if sets_raw is not None else "None"
                vol          = first_entry.get("exercise_volume", "ABSENT")
                _logger.warning(
                    "OVERLOAD_DEBUG %s: n_history=%d w=%s r=%s sets_type=%s "
                    "sets_preview=%s vol=%s first_date=%s last_date=%s",
                    name, len(history),
                    first_entry.get("weight"), first_entry.get("reps"),
                    sets_type, sets_preview, vol,
                    first_entry.get("date"), last_entry.get("date"),
                )

            latest = history[0]
            weights[name] = {
                "current_weight": latest.get("weight") or 0,
                "last_reps":      latest.get("reps") or "",
                "history":        history,
            }

        return weights
    except Exception:
        return {}


def save_weights(weights: dict) -> bool:
    """
    Persist the most recent history entry per exercise to exercise_logs.
    Only writes history[0] — the entry that was just added or modified.
    """
    try:
        for exercise_name, ex_data in weights.items():
            if not isinstance(ex_data, dict):
                continue
            history = ex_data.get("history", [])
            if not history or not isinstance(history[0], dict):
                continue
            entry     = history[0]
            date      = entry.get("date")
            weight    = entry.get("weight")
            reps      = entry.get("reps")
            sets_json = entry.get("sets") or None
            if date and (weight is not None or reps is not None):
                db.upsert_exercise_log(date, exercise_name, weight, reps, sets_json=sets_json)
        return True
    except Exception:
        return False
