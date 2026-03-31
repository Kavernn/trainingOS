"""Smart progression engine.

Compares the current session against the previous session of the same type
and generates per-exercise progression suggestions.

Rules by load_profile:
  compound_heavy       → +weight if ≥90% working sets hit top of scheme
  compound_hypertrophy → +weight if ≥90% working sets hit top of scheme
  isolation            → +weight if 100% working sets hit top of scheme
  NULL (core/mobility) → no suggestion

Wave loading: when sets have different weights, only the sets at the maximum
weight (working sets) are evaluated for hit rate. The suggested_weight is
based on the max weight of the current session.

Weight increments (in lbs):
  push / pull (upper) → +5 lbs
  legs                → +10 lbs

Plateau detection: ≥3 consecutive sessions at same max_weight
  → suggest add 1 set (even plateau count) OR deload -10% (odd)

Anti-regression: if current max_weight < previous max_weight → flag regression

Global fatigue: ≥50% of exercises show regression → fatigue_warning on all
"""
from __future__ import annotations

import json
import logging
from typing import Optional

import db

logger = logging.getLogger("trainingos.progression")

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _parse_scheme(scheme: str) -> tuple[int, int]:
    """Parse '3x8-12' → (num_sets=3, top_reps=12). Returns (0,0) on failure."""
    try:
        parts = scheme.strip().split("x")
        rep_part = parts[1] if len(parts) > 1 else parts[0]
        top = int(rep_part.split("-")[1]) if "-" in rep_part else int(rep_part)
        return int(parts[0]), top
    except Exception:
        return 0, 0


def _to_int(v) -> int:
    try:
        return int(v)
    except (TypeError, ValueError):
        return 0


def _sets_from_log(log: dict) -> list[dict]:
    """Return parsed sets_json; fall back to synthetic single-set from weight/reps."""
    sets = log.get("sets_json") or []
    if isinstance(sets, str):
        try:
            sets = json.loads(sets)
        except Exception:
            sets = []
    if not sets and log.get("weight") is not None:
        sets = [{"weight": log["weight"], "reps": _to_int(log.get("reps", "0"))}]
    return sets


def _working_sets(sets: list[dict]) -> list[dict]:
    """
    For wave-loading sessions (sets have varying weights), return only
    the sets performed at the maximum weight (the true working sets).
    For flat-load sessions (all same weight), return all sets.
    """
    if not sets:
        return []
    weights = [s.get("weight") or 0 for s in sets]
    max_w = max(weights)
    if len(set(weights)) > 1:
        return [s for s in sets if (s.get("weight") or 0) == max_w]
    return sets


def _max_weight(sets: list[dict]) -> Optional[float]:
    """Return the maximum weight across all sets."""
    if not sets:
        return None
    vals = [s.get("weight") or 0 for s in sets]
    return max(vals) if vals else None


def _hit_rate(sets: list[dict], top_reps: int) -> float:
    """Fraction of sets where reps >= top_reps."""
    if not sets:
        return 0.0
    return sum(1 for s in sets if _to_int(s.get("reps")) >= top_reps) / len(sets)


def _increment_for_category(category: str) -> float:
    """Weight increment in lbs."""
    return 10.0 if category == "legs" else 5.0


def _plateau_count(history: list[dict], max_weight: float) -> int:
    """Count consecutive recent sessions at same max_weight (newest first)."""
    count = 0
    for entry in history:
        entry_sets = _sets_from_log(entry) if "sets_json" in entry else []
        entry_w = _max_weight(entry_sets) or entry.get("weight")
        if entry_w == max_weight:
            count += 1
        else:
            break
    return count


# ---------------------------------------------------------------------------
# Core
# ---------------------------------------------------------------------------

def generate_suggestions(session_date: str, session_type: str, session_name: str = "") -> list[dict]:
    """
    Return suggestion dicts for each exercise in the current session.

    Matches against the previous session with the same session_name (e.g. "Push A").
    Falls back to session_type matching if session_name is not available.

    Dict shape:
      {
        "exercise_name":  str,
        "load_profile":   str | None,
        "suggestion_type": "increase_weight" | "increase_sets" | "deload"
                          | "maintain" | "regression",
        "current_weight":  float | None,   # max weight this session
        "suggested_weight": float | None,
        "current_scheme":  str | None,
        "suggested_scheme": str | None,
        "reason":          str,
        "fatigue_warning": bool,
      }
    """
    if session_type not in ("morning", "evening"):
        return []

    current_session = db.get_workout_session_by_type(session_date, session_type)
    if not current_session:
        return []

    # Match by session_name (e.g. "Push A") for accurate same-type comparison.
    # Fall back to session_type if session_name not stored (older sessions).
    if session_name:
        prev_session = db.get_previous_session_by_name(session_date, session_name)
    else:
        prev_session = db.get_previous_session_of_type(session_date, session_type)

    if not prev_session:
        return []

    current_logs = db.get_exercise_logs_for_session_with_names(current_session["id"])
    prev_logs_raw = db.get_exercise_logs_for_session_with_names(prev_session["id"])

    if not current_logs:
        return []

    prev_by_name: dict[str, dict] = {l["exercise_name"]: l for l in prev_logs_raw}

    suggestions: list[dict] = []
    regression_count = 0

    for log in current_logs:
        name = log["exercise_name"]
        info = db.get_exercise_info(name)
        load_profile   = info.get("load_profile") if info else None
        category       = (info.get("category") or "").lower() if info else ""
        default_scheme = (info.get("default_scheme") or "") if info else ""

        if not load_profile:
            continue

        prev_log = prev_by_name.get(name)
        if not prev_log:
            continue

        all_sets     = _sets_from_log(log)
        working      = _working_sets(all_sets)
        cur_max_w    = _max_weight(all_sets)

        prev_all_sets = _sets_from_log(prev_log)
        prev_max_w    = _max_weight(prev_all_sets)

        # Anti-regression (compare max weights)
        if cur_max_w is not None and prev_max_w is not None and cur_max_w < prev_max_w:
            regression_count += 1
            suggestions.append({
                "exercise_name":  name,
                "load_profile":   load_profile,
                "suggestion_type": "regression",
                "current_weight": cur_max_w,
                "suggested_weight": prev_max_w,
                "current_scheme": default_scheme,
                "suggested_scheme": None,
                "reason": f"↓ vs dernière session ({int(prev_max_w) if prev_max_w == int(prev_max_w) else prev_max_w} lbs). Récupère avant d'augmenter.",
                "fatigue_warning": False,
            })
            continue

        target_sets, top_reps = _parse_scheme(default_scheme)
        if top_reps == 0:
            continue

        threshold = 1.0 if load_profile == "isolation" else 0.9
        hit = _hit_rate(working, top_reps)

        # Plateau detection on max weight
        history = db.get_exercise_history(name, limit=5)
        plateau = _plateau_count(history, cur_max_w) if cur_max_w else 0

        if hit >= threshold and cur_max_w is not None:
            if plateau >= 3:
                # Cycle: sessions 3-4 → add set, 5-6 → deload, 7-8 → add set, …
                # Never exceed 4 sets. If already at 4, go straight to deload.
                can_add_set = target_sets < 4
                cycle_pos = (plateau - 3) % 4
                if cycle_pos < 2 and can_add_set:
                    new_scheme = (
                        f"{target_sets + 1}x{default_scheme.split('x')[1]}"
                        if "x" in default_scheme else default_scheme
                    )
                    suggestions.append({
                        "exercise_name":  name,
                        "load_profile":   load_profile,
                        "suggestion_type": "increase_sets",
                        "current_weight": cur_max_w,
                        "suggested_weight": cur_max_w,
                        "current_scheme": default_scheme,
                        "suggested_scheme": new_scheme,
                        "reason": f"Bloqué {plateau}× — essaie {target_sets + 1} séries",
                        "fatigue_warning": False,
                    })
                else:
                    # Already at 4 sets or in deload cycle
                    deload_w = round(cur_max_w * 0.9 / 2.5) * 2.5
                    reason = (
                        f"Bloqué {plateau}× à 4 séries — décharge -10%"
                        if not can_add_set else
                        f"Bloqué {plateau}× — décharge -10%"
                    )
                    suggestions.append({
                        "exercise_name":  name,
                        "load_profile":   load_profile,
                        "suggestion_type": "deload",
                        "current_weight": cur_max_w,
                        "suggested_weight": deload_w,
                        "current_scheme": default_scheme,
                        "suggested_scheme": default_scheme,
                        "reason": reason,
                        "fatigue_warning": False,
                    })
            else:
                increment = _increment_for_category(category)
                new_w = cur_max_w + increment
                suggestions.append({
                    "exercise_name":  name,
                    "load_profile":   load_profile,
                    "suggestion_type": "increase_weight",
                    "current_weight": cur_max_w,
                    "suggested_weight": new_w,
                    "current_scheme": default_scheme,
                    "suggested_scheme": default_scheme,
                    "reason": f"{target_sets}×{top_reps} accompli → +{int(increment)} lbs. Objectif : {default_scheme}",
                    "fatigue_warning": False,
                })
        else:
            suggestions.append({
                "exercise_name":  name,
                "load_profile":   load_profile,
                "suggestion_type": "maintain",
                "current_weight": cur_max_w,
                "suggested_weight": cur_max_w,
                "current_scheme": default_scheme,
                "suggested_scheme": default_scheme,
                "reason": f"Objectif : {default_scheme}. Continue à ce poids.",
                "fatigue_warning": False,
            })

    # Global fatigue flag
    if current_logs and regression_count / len(current_logs) >= 0.5:
        for s in suggestions:
            s["fatigue_warning"] = True

    return suggestions


def apply_suggestion(exercise_name: str, suggested_weight: float, suggested_scheme: Optional[str]) -> bool:
    """
    Persist an approved suggestion:
      1. Update exercises.default_scheme in Supabase (if scheme changed)
      2. Update weights KV current_weight (used by SeanceView pre-fill)
    """
    ok = True

    if suggested_scheme:
        ok = db.update_exercise_default_scheme(exercise_name, suggested_scheme) and ok

    weights = db.get_json("weights", {})
    ex_data = weights.get(exercise_name, {})
    ex_data["current_weight"] = suggested_weight
    weights[exercise_name] = ex_data
    db.set_json("weights", weights)

    return ok
