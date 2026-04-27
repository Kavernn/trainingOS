"""Pure volume computation — no storage, no database calls.

All volume metrics are derived on-demand from raw weight + reps values.
Nothing is persisted; callers receive enriched copies for API responses only.

Formulas
--------
Epley 1RM : weight * (1 + max_set_reps / 30)
set_volume : set_weight * set_reps              (real per-set load; 0 when weight is None or 0)
exercise_volume : SUM(set_volume for each set)  when sets_json available
                  weight * total_reps_count     fallback when sets_json is absent
session_volume  : sum of exercise_volumes across all exercises in the session
"""
from __future__ import annotations


# ---------------------------------------------------------------------------
# Reps parsing
# ---------------------------------------------------------------------------

def parse_reps(reps) -> list[int]:
    """Parse a reps value into a list of per-set rep counts.

    Accepts:
      - int / float  → treated as a single set: [int(reps)]
      - str          → comma-separated counts: "7,6,6,5" → [7, 6, 6, 5]
                       handles extra whitespace and semicolons

    Returns an empty list when the input is None, empty, or unparseable.
    """
    if reps is None:
        return []
    if isinstance(reps, (int, float)):
        val = int(reps)
        return [val] if val > 0 else []
    s = str(reps).strip()
    if not s:
        return []
    # Accept both comma and semicolon as separators
    s = s.replace(";", ",")
    result = []
    for part in s.split(","):
        part = part.strip()
        if part.isdigit():
            result.append(int(part))
    return result


def max_reps(reps) -> int:
    """Return the highest single-set rep count from a reps value.

    Returns 0 if the reps value is empty or unparseable.
    """
    parsed = parse_reps(reps)
    return max(parsed) if parsed else 0


def total_reps_count(reps) -> int:
    """Return the sum of all per-set reps.

    Returns 0 if the reps value is empty or unparseable.
    """
    return sum(parse_reps(reps))


# ---------------------------------------------------------------------------
# 1RM  (Epley formula)
# ---------------------------------------------------------------------------

def calc_1rm(weight: float, reps) -> float:
    """Estimate 1-rep-max using the Epley formula.

    Formula: weight * (1 + max_set_reps / 30)

    Rules:
      - Returns 0.0 when weight is None, zero, or negative.
      - Uses the highest set's reps as the representative value (best-set 1RM).
      - Rounded to 1 decimal place.
    """
    if weight is None:
        return 0.0
    w = float(weight)
    if w <= 0:
        return 0.0
    r = max_reps(reps)
    if r <= 0:
        return 0.0
    return round(w * (1 + r / 30), 1)


# ---------------------------------------------------------------------------
# Volume
# ---------------------------------------------------------------------------

def calc_exercise_volume(weight: float, reps, sets_json: list | None = None) -> float:
    """Compute exercise volume using per-set real loads when sets_json is available.

    When sets_json is provided, sums each set's individual load (set_volume or
    set_weight × set_reps) so that sets with different weights are computed
    correctly instead of using the average top-level weight.

    Falls back to weight × total_reps_count when sets_json is absent.
    Returns 0.0 for bodyweight exercises. Rounded to 2 decimal places.
    """
    if sets_json:
        total = 0.0
        for s in sets_json:
            sv = s.get("set_volume")
            if sv is not None:
                total += float(sv)
            else:
                sw = float(s.get("weight") or 0)
                sr = sum(parse_reps(s.get("reps", 0)))
                total += sw * sr
        return round(total, 2)
    if weight is None:
        return 0.0
    w = float(weight)
    if w <= 0:
        return 0.0
    return round(w * total_reps_count(reps), 2)


def calc_session_volume(exercise_logs: list[dict]) -> dict:
    """Compute aggregated volume metrics for a list of exercise log entries.

    Parameters
    ----------
    exercise_logs : list of dicts, each containing at minimum:
        {
            "weight": float | None,   # None or 0 = bodyweight
            "reps":   str | int | float,
        }

    Returns
    -------
    {
        "volume":     float,   # total lifted load (weight × reps), kg·reps
        "total_reps": int,     # sum of all reps across all exercises
        "total_sets": int,     # number of individual sets across all exercises
    }
    """
    volume = 0.0
    total_reps = 0
    total_sets = 0

    for entry in exercise_logs:
        if not isinstance(entry, dict):
            continue
        sets = entry.get("sets_json") or entry.get("sets")
        if sets:
            for s in sets:
                sr = sum(parse_reps(s.get("reps", 0)))
                total_sets += 1
                total_reps += sr
                sv = s.get("set_volume")
                if sv is not None:
                    volume += float(sv)
                else:
                    sw = float(s.get("weight") or 0)
                    if sw > 0:
                        volume += sw * sr
        else:
            weight = entry.get("weight")
            reps = entry.get("reps")
            parsed = parse_reps(reps)
            total_sets += len(parsed)
            rep_count = sum(parsed)
            total_reps += rep_count
            if weight is not None:
                w = float(weight)
                if w > 0:
                    volume += w * rep_count

    return {
        "volume":     round(volume, 2),
        "total_reps": total_reps,
        "total_sets": total_sets,
    }


# ---------------------------------------------------------------------------
# Annotation helper
# ---------------------------------------------------------------------------

def annotate_history_entry(entry: dict) -> dict:
    """Return a copy of an exercise log entry enriched with computed fields.

    Adds:
      "1rm"    : float  — Epley 1RM estimate
      "volume" : float  — weight × total_reps_count

    The original dict is NOT mutated. Computed fields are for API responses only
    and must never be persisted back to the database.
    """
    weight = entry.get("weight")
    reps = entry.get("reps")
    sets_json = entry.get("sets_json") or entry.get("sets")
    return {
        **entry,
        "1rm":    calc_1rm(weight, reps),
        "volume": calc_exercise_volume(weight, reps, sets_json=sets_json),
    }


# ---------------------------------------------------------------------------
# Backward-compatible shims
# (kept so existing callers in index.py continue to work without changes)
# ---------------------------------------------------------------------------

def calc_set_volume(total_weight: float, reps) -> float:
    """Backward-compatible alias for calc_exercise_volume."""
    return calc_exercise_volume(total_weight, reps)


def _calc_session_volume_legacy(exercise_names: list, weights: dict, today_date: str) -> dict:
    """Old 3-arg signature used by index.py before migration."""
    logs = []
    for name in exercise_names:
        history = weights.get(name, {}).get("history", [])
        if history and history[0].get("date") == today_date:
            logs.append({"weight": history[0].get("weight"), "reps": history[0].get("reps")})
    result = calc_session_volume(logs)
    return {"session_volume": result["volume"], "total_reps": result["total_reps"], "total_sets": result["total_sets"]}
