"""Smart progression engine.

Compares the current session against the previous session of the same type
and generates per-exercise progression suggestions.

Rules by load_profile:
  compound_heavy       → +weight if ≥90% sets hit top of scheme
  compound_hypertrophy → +weight if ≥90% sets hit top of scheme
  isolation            → +weight if 100% sets hit top of scheme
  NULL (core/mobility) → no suggestion

Weight increment caps by body-part (exercises.category):
  push / pull (upper)  → +2.5 kg
  legs                 → +5 kg
  default              → +2.5 kg

Plateau detection: ≥3 consecutive sessions at same weight/reps
  → suggest add 1 set  OR  deload -10% (alternating)

Anti-regression: if current weight < previous weight → flag regression

Global fatigue: ≥50% of exercises show regression → append fatigue warning
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
    """Parse '3x8-12' → (3, 12). Returns (0, 0) on failure."""
    try:
        parts = scheme.strip().split("x")
        sets = int(parts[0])
        rep_part = parts[1] if len(parts) > 1 else parts[0]
        if "-" in rep_part:
            top = int(rep_part.split("-")[1])
        else:
            top = int(rep_part)
        return sets, top
    except Exception:
        return 0, 0


def _sets_from_log(log: dict) -> list[dict]:
    """Return sets_json list; fall back to a single synthetic set from weight/reps."""
    sets = log.get("sets_json") or []
    if isinstance(sets, str):
        try:
            sets = json.loads(sets)
        except Exception:
            sets = []
    if not sets:
        weight = log.get("weight")
        reps_str = log.get("reps", "")
        if weight is not None:
            try:
                reps = int(reps_str)
            except (ValueError, TypeError):
                reps = 0
            sets = [{"weight": weight, "reps": reps}]
    return sets


def _increment_for_category(category: str) -> float:
    """Weight increment in kg based on body-part category."""
    if category in ("push", "pull"):
        return 2.5
    if category == "legs":
        return 5.0
    return 2.5


def _hit_rate(sets: list[dict], top_reps: int) -> float:
    """Fraction of sets where reps >= top_reps."""
    if not sets:
        return 0.0
    hits = sum(1 for s in sets if (s.get("reps") or 0) >= top_reps)
    return hits / len(sets)


def _plateau_count(history: list[dict], current_weight: float, current_reps: str) -> int:
    """Count consecutive recent sessions with same weight + reps (including current)."""
    count = 0
    for entry in history:
        if entry.get("weight") == current_weight and entry.get("reps") == current_reps:
            count += 1
        else:
            break
    return count


# ---------------------------------------------------------------------------
# Core
# ---------------------------------------------------------------------------

def generate_suggestions(session_date: str, session_type: str) -> list[dict]:
    """
    Return a list of suggestion dicts for exercises in the current session.

    Each dict:
      {
        "exercise_name": str,
        "load_profile": str | None,
        "suggestion_type": "increase_weight" | "increase_sets" | "deload" | "maintain" | "regression",
        "current_weight": float | None,
        "suggested_weight": float | None,
        "current_scheme": str | None,
        "suggested_scheme": str | None,
        "reason": str,
        "fatigue_warning": bool,
      }
    """
    # Skip bonus sessions
    if session_type not in ("morning", "evening"):
        return []

    current_session = db.get_workout_session_by_type(session_date, session_type)
    if not current_session:
        return []

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
        load_profile = info.get("load_profile") if info else None
        category = (info.get("category") or "").lower() if info else ""
        default_scheme = (info.get("default_scheme") or "") if info else ""

        current_sets = _sets_from_log(log)
        current_weight = log.get("weight")
        current_reps = log.get("reps", "")

        # No suggestion for unclassified exercises
        if not load_profile:
            continue

        prev_log = prev_by_name.get(name)
        if not prev_log:
            # First time this exercise appears with this session type
            continue

        prev_weight = prev_log.get("weight")
        prev_reps = prev_log.get("reps", "")

        # Anti-regression check
        if (
            current_weight is not None
            and prev_weight is not None
            and current_weight < prev_weight
        ):
            regression_count += 1
            suggestions.append({
                "exercise_name": name,
                "load_profile": load_profile,
                "suggestion_type": "regression",
                "current_weight": current_weight,
                "suggested_weight": prev_weight,
                "current_scheme": default_scheme,
                "suggested_scheme": None,
                "reason": f"Régression détectée: {current_weight} kg vs {prev_weight} kg la session précédente",
                "fatigue_warning": False,
            })
            continue

        # Scheme parsing
        target_sets, top_reps = _parse_scheme(default_scheme)

        # Threshold by load_profile
        threshold = 1.0 if load_profile == "isolation" else 0.9

        hit = _hit_rate(current_sets, top_reps) if top_reps > 0 else 0.0

        # Plateau detection (last 3 sessions including current)
        history = db.get_exercise_history(name, limit=5)
        plateau = _plateau_count(history, current_weight, current_reps)

        if hit >= threshold and current_weight is not None:
            # Check plateau first
            if plateau >= 3:
                # Alternate: if last suggestion was add_set → deload; else add_set
                # Simple heuristic: plateau % 2 == 0 → add set, else deload
                if plateau % 2 == 0:
                    # Add set
                    if target_sets > 0:
                        new_scheme = f"{target_sets + 1}x{default_scheme.split('x')[1]}" if 'x' in default_scheme else default_scheme
                    else:
                        new_scheme = default_scheme
                    suggestions.append({
                        "exercise_name": name,
                        "load_profile": load_profile,
                        "suggestion_type": "increase_sets",
                        "current_weight": current_weight,
                        "suggested_weight": current_weight,
                        "current_scheme": default_scheme,
                        "suggested_scheme": new_scheme,
                        "reason": f"Plateau {plateau} sessions — ajouter 1 série",
                        "fatigue_warning": False,
                    })
                else:
                    # Deload
                    deload_weight = round(current_weight * 0.9 / 2.5) * 2.5
                    suggestions.append({
                        "exercise_name": name,
                        "load_profile": load_profile,
                        "suggestion_type": "deload",
                        "current_weight": current_weight,
                        "suggested_weight": deload_weight,
                        "current_scheme": default_scheme,
                        "suggested_scheme": default_scheme,
                        "reason": f"Plateau {plateau} sessions — décharge -10%",
                        "fatigue_warning": False,
                    })
            else:
                # Standard progression: increase weight
                increment = _increment_for_category(category)
                new_weight = current_weight + increment
                suggestions.append({
                    "exercise_name": name,
                    "load_profile": load_profile,
                    "suggestion_type": "increase_weight",
                    "current_weight": current_weight,
                    "suggested_weight": new_weight,
                    "current_scheme": default_scheme,
                    "suggested_scheme": default_scheme,
                    "reason": f"{int(hit * 100)}% des séries au plafond — progression +{increment} kg",
                    "fatigue_warning": False,
                })
        else:
            suggestions.append({
                "exercise_name": name,
                "load_profile": load_profile,
                "suggestion_type": "maintain",
                "current_weight": current_weight,
                "suggested_weight": current_weight,
                "current_scheme": default_scheme,
                "suggested_scheme": default_scheme,
                "reason": f"{int(hit * 100)}% des séries au plafond — maintenir",
                "fatigue_warning": False,
            })

    # Global fatigue flag
    total = len([s for s in suggestions if s["suggestion_type"] != "maintain"])
    if total > 0 and regression_count / len(current_logs) >= 0.5:
        for s in suggestions:
            s["fatigue_warning"] = True

    return suggestions


def apply_suggestion(exercise_name: str, suggested_weight: float, suggested_scheme: Optional[str]) -> bool:
    """
    Persist approved progression:
      1. Update exercises.default_scheme (if changed)
      2. Update weights KV current_weight
    Returns True on success.
    """
    ok = True

    if suggested_scheme:
        ok = db.update_exercise_default_scheme(exercise_name, suggested_scheme) and ok

    # Update KV weights
    weights = db.get_json("weights", {})
    ex_data = weights.get(exercise_name, {})
    ex_data["current_weight"] = suggested_weight
    weights[exercise_name] = ex_data
    db.set_json("weights", weights)

    return ok
