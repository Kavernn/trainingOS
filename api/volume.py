"""Centralized volume calculation service.

set_volume      = total_weight * reps
exercise_volume = sum(set_volumes)
session_volume  = sum(exercise_volumes)

Bodyweight exercises have total_weight=0 → volume=0.
"""


def _parse_reps_count(reps) -> int:
    if isinstance(reps, (int, float)):
        return int(reps)
    parts = str(reps).split(",")
    return sum(int(r.strip()) for r in parts if r.strip().isdigit())


def calc_set_volume(total_weight: float, reps) -> float:
    return round(total_weight * _parse_reps_count(reps), 2)


def calc_exercise_volume(sets: list) -> float:
    total = 0.0
    for s in sets:
        w = float(s.get("weight", 0) or 0)
        r = s.get("reps", 0)
        total += calc_set_volume(w, r)
    return round(total, 2)


def calc_session_volume(exercise_names: list, weights: dict, today_date: str) -> dict:
    """Returns dict with session_volume, total_reps, total_sets."""
    vol, total_reps, total_sets = 0.0, 0, 0
    for name in exercise_names:
        history = weights.get(name, {}).get("history", [])
        if not history or history[0].get("date") != today_date:
            continue
        entry = history[0]
        if "exercise_volume" in entry:
            vol += float(entry["exercise_volume"])
            sets_arr = entry.get("sets", [])
            if sets_arr:
                total_sets += len(sets_arr)
                for s in sets_arr:
                    reps_str = str(s.get("reps", "") or "")
                    total_reps += sum(int(r) for r in reps_str.split(",") if r.strip().isdigit())
            else:
                reps_str = str(entry.get("reps", "") or "")
                total_reps += sum(int(r) for r in reps_str.split(",") if r.strip().isdigit())
        else:
            # Legacy fallback: no exercise_volume stored
            w = float(entry.get("weight", 0) or 0)
            reps_str = str(entry.get("reps", "") or "")
            reps_count = sum(int(r) for r in reps_str.split(",") if r.strip().isdigit())
            vol += w * reps_count
            total_reps += reps_count
            total_sets += len(reps_str.split(",")) if reps_str else 0
    return {"session_volume": round(vol, 2), "total_reps": total_reps, "total_sets": total_sets}
