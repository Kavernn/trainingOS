"""
graveyard_engine.py — Compute all tombstones from raw user data.

Types implemented (v1):
  pr_killed      — old 1RM surpassed by a new one
  streak_slain   — consecutive-day streak record beaten
  stress_floor   — PSS all-time low broken
  bodycomp_shed  — body weight milestone crossed + confirmed (3-day avg)

Detection is idempotent and deterministic — same data → same tombstones.
"""
from __future__ import annotations
import db
import logging
import hashlib
from datetime import datetime, timezone, timedelta, date
from utils import _today_mtl as _today_iso

logger = logging.getLogger("trainingos.graveyard")


def _fr_date(iso: str) -> str:
    months = ["janvier", "février", "mars", "avril", "mai", "juin",
              "juillet", "août", "septembre", "octobre", "novembre", "décembre"]
    try:
        d = date.fromisoformat(iso)
        return f"{d.day} {months[d.month - 1]} {d.year}"
    except Exception:
        return iso


def _days_since(death_date: str) -> int:
    try:
        delta = date.fromisoformat(_today_iso()) - date.fromisoformat(death_date)
        return max(0, delta.days)
    except Exception:
        return 999


def _uid(*parts) -> str:
    raw = "_".join(str(p) for p in parts)
    return hashlib.md5(raw.encode()).hexdigest()[:16]


def _epley_1rm(weight: float, reps: int) -> float:
    """Estimation 1RM : Epley ≤10 reps, Brzycki 11-20 reps, 0.0 si >20 reps."""
    if weight <= 0 or reps <= 0:
        return 0.0
    if reps == 1:
        return weight
    if reps > 20:
        return 0.0
    if reps > 10:
        return round(weight * (36 / (37 - reps)), 1)
    return round(weight * (1 + reps / 30.0), 1)


def _best_1rm_from_entry(entry: dict) -> float:
    sets = entry.get("sets")
    if sets and isinstance(sets, list):
        candidates = [
            _epley_1rm(float(s.get("weight") or 0), int(s.get("reps") or 0))
            for s in sets
            if s.get("weight") and s.get("reps")
        ]
        if candidates:
            return max(candidates)
    w = float(entry.get("weight") or 0)
    r = int(str(entry.get("reps") or "0").split(",")[0].strip() or "0")
    return _epley_1rm(w, r)


# ── PR_KILLED ─────────────────────────────────────────────────────────────────

def _pr_killed_tombstones() -> list[dict]:
    history = db.get_all_exercise_history() or {}
    results = []

    for exercise_name, ex_data in history.items():
        entries = sorted(ex_data if isinstance(ex_data, list) else (ex_data.get("history") or []), key=lambda e: e.get("date", ""))
        running_best = 0.0
        running_best_date = None

        for entry in entries:
            entry_date = entry.get("date", "")
            one_rm = _best_1rm_from_entry(entry)
            if one_rm <= 0:
                continue

            if one_rm > running_best * 1.02:
                if running_best > 0 and running_best_date:
                    results.append({
                        "id": _uid("pr_killed", exercise_name, running_best, entry_date),
                        "type": "pr_killed",
                        "title": f"{exercise_name} — {running_best:.0f} lbs",
                        "epitaph": (
                            f"R.I.P. {_fr_date(running_best_date)}. "
                            f"Tué par {one_rm:.0f} lbs le {_fr_date(entry_date)}."
                        ),
                        "death_date": entry_date,
                        "born_date": running_best_date,
                        "old_value": running_best,
                        "new_value": one_rm,
                        "exercise_name": exercise_name,
                        "days_since_death": _days_since(entry_date),
                    })
                running_best = one_rm
                running_best_date = entry_date

    return results


# ── STREAK_SLAIN ─────────────────────────────────────────────────────────────

def _compute_streaks(sessions: list[dict]) -> list[dict]:
    completed_dates = sorted(set(
        s.get("date") for s in sessions
        if s.get("completed") and s.get("date")
    ))
    if not completed_dates:
        return []

    streaks = []
    streak_start = completed_dates[0]
    streak_len = 1
    prev = date.fromisoformat(completed_dates[0])

    for ds in completed_dates[1:]:
        d = date.fromisoformat(ds)
        if (d - prev).days == 1:
            streak_len += 1
        else:
            streaks.append({"start": streak_start, "end": prev.isoformat(), "length": streak_len})
            streak_start = ds
            streak_len = 1
        prev = d

    streaks.append({"start": streak_start, "end": prev.isoformat(), "length": streak_len})
    return streaks


def _streak_slain_tombstones() -> list[dict]:
    sessions = db.get_workout_sessions(limit=1000) or []
    streaks = _compute_streaks(sessions)
    results = []
    all_time_best = 0

    for streak in streaks:
        length = streak["length"]
        if length > all_time_best and all_time_best > 0:
            # Day the new streak surpassed the old record
            kill_date = (
                date.fromisoformat(streak["start"]) + timedelta(days=all_time_best)
            ).isoformat()
            results.append({
                "id": _uid("streak_slain", all_time_best, kill_date),
                "type": "streak_slain",
                "title": f"Ancien record : {all_time_best} jours consécutifs",
                "epitaph": (
                    f"Tué le {_fr_date(kill_date)} "
                    f"par un streak de {length} jours."
                ),
                "death_date": kill_date,
                "born_date": streak["start"],
                "old_value": float(all_time_best),
                "new_value": float(length),
                "exercise_name": None,
                "days_since_death": _days_since(kill_date),
            })
        if length > all_time_best:
            all_time_best = length

    return results


# ── STRESS_FLOOR ─────────────────────────────────────────────────────────────

def _stress_floor_tombstones() -> list[dict]:
    records = db.get_pss_records(limit=500) or []
    sorted_records = sorted(records, key=lambda r: r.get("date", ""))
    results = []
    all_time_low = None

    for rec in sorted_records:
        score_raw = rec.get("pss_score") or rec.get("score")
        if score_raw is None:
            continue
        score = float(score_raw)
        rec_date = rec.get("date", "")

        if all_time_low is not None and score < all_time_low:
            results.append({
                "id": _uid("stress_floor", all_time_low, rec_date),
                "type": "stress_floor",
                "title": f"Plancher de stress : {all_time_low:.0f} — enterré",
                "epitaph": (
                    f"Ton stress n'avait jamais été sous {all_time_low:.0f}. "
                    f"Première fois à {score:.0f} le {_fr_date(rec_date)}."
                ),
                "death_date": rec_date,
                "born_date": None,
                "old_value": all_time_low,
                "new_value": score,
                "exercise_name": None,
                "days_since_death": _days_since(rec_date),
            })

        if all_time_low is None or score < all_time_low:
            all_time_low = score

    return results


# ── BODYCOMP_SHED ─────────────────────────────────────────────────────────────

def _bodycomp_shed_tombstones() -> list[dict]:
    logs = db.get_body_weight_logs(limit=365) or []
    if not logs:
        return []

    # Reverse to chronological order (db returns newest first)
    logs = sorted(logs, key=lambda l: l.get("date", ""))

    weights = [(l.get("date", ""), float(l.get("weight") or 0)) for l in logs if l.get("weight")]
    if len(weights) < 4:
        return []

    starting_weight = weights[0][1]
    milestone_step = 5.0  # lbs
    # All milestones the user could cross downward from starting weight
    first_milestone = (starting_weight // milestone_step) * milestone_step
    milestones = [
        first_milestone - i * milestone_step
        for i in range(100)
        if first_milestone - i * milestone_step > 0
    ]

    results = []
    for milestone in milestones:
        # Find first date where 3-day rolling average ≤ milestone
        for i in range(2, len(weights)):
            avg = sum(w for _, w in weights[i - 2:i + 1]) / 3
            if avg <= milestone:
                crossed_date = weights[i][0]
                if weights[0][1] <= milestone:
                    break  # user always was below this milestone
                results.append({
                    "id": _uid("bodycomp_shed", milestone, crossed_date),
                    "type": "bodycomp_shed",
                    "title": f"{milestone:.0f} lbs — enterré",
                    "epitaph": (
                        f"Tu pesais {starting_weight:.0f} lbs. "
                        f"Le palier des {milestone:.0f} lbs franchi le {_fr_date(crossed_date)}. "
                        f"Tu ne reviendras pas."
                    ),
                    "death_date": crossed_date,
                    "born_date": weights[0][0],
                    "old_value": starting_weight,
                    "new_value": milestone,
                    "exercise_name": None,
                    "days_since_death": _days_since(crossed_date),
                })
                break

    return results


# ── Inception date ────────────────────────────────────────────────────────────

def _inception_date() -> str | None:
    sessions = db.get_workout_sessions(limit=1000) or []
    dates = [s.get("date") for s in sessions if s.get("date") and s.get("completed")]
    if not dates:
        return None
    return min(dates)


# ── Main entry ────────────────────────────────────────────────────────────────

def compute() -> dict:
    try:
        pr_tombstones      = _pr_killed_tombstones()
    except Exception as e:
        logger.error("pr_killed error: %s", e)
        pr_tombstones = []

    try:
        streak_tombstones  = _streak_slain_tombstones()
    except Exception as e:
        logger.error("streak_slain error: %s", e)
        streak_tombstones = []

    try:
        stress_tombstones  = _stress_floor_tombstones()
    except Exception as e:
        logger.error("stress_floor error: %s", e)
        stress_tombstones = []

    try:
        bodycomp_tombstones = _bodycomp_shed_tombstones()
    except Exception as e:
        logger.error("bodycomp_shed error: %s", e)
        bodycomp_tombstones = []

    all_tombstones = pr_tombstones + streak_tombstones + stress_tombstones + bodycomp_tombstones
    # Sort newest death first
    all_tombstones.sort(key=lambda t: t.get("death_date", ""), reverse=True)

    return {
        "tombstones": all_tombstones,
        "total_count": len(all_tombstones),
        "inception_date": _inception_date(),
    }
