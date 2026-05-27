from __future__ import annotations
import logging
from typing import Dict, List, Optional, Tuple
import db_core
from db_exercises import get_exercise_id, get_or_create_exercise_id


def get_workout_sessions(limit: int = 100, offset: int = 0) -> List[dict]:
    """Return list of workout sessions ordered by date DESC.

    Uses DB-level LIMIT/OFFSET so callers never fetch more rows than needed.
    """
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        resp = (
            db_core._client.table("workout_sessions")
            .select("*")
            .order("date", desc=True)
            .range(offset, offset + limit - 1)
            .execute()
        )
        return resp.data or []

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_workout_sessions retry error: %s", e2)
                return []
        db_core.logger.error("get_workout_sessions error: %s", e)
        return []


def get_total_session_count() -> int:
    """Count all completed sessions (all-time) — lightweight, no payload."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return 0
    try:
        resp = (
            db_core._client.table("workout_sessions")
            .select("id", count="exact")
            .or_("completed.eq.true,rpe.not.is.null")
            .execute()
        )
        return resp.count or 0
    except Exception as e:
        db_core.logger.error("get_total_session_count error: %s", e)
        return 0


def get_all_time_volume_lbs() -> float:
    """Sum all session volume from v_session_volume view."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return 0.0
    try:
        resp = (
            db_core._client.table("v_session_volume")
            .select("total_volume")
            .execute()
        )
        return round(sum(float(r.get("total_volume") or 0) for r in (resp.data or [])), 0)
    except Exception as e:
        db_core.logger.error("get_all_time_volume_lbs error: %s", e)
        return 0.0


def get_session_streaks() -> dict:
    """Return current and all-time longest workout streak."""
    from datetime import date as _date, timedelta
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return {"current": 0, "longest": 0}
    try:
        resp = (
            db_core._client.table("workout_sessions")
            .select("date")
            .or_("completed.eq.true,rpe.not.is.null")
            .order("date")
            .execute()
        )
        dates = sorted(set(r["date"] for r in (resp.data or []) if r.get("date")))
    except Exception as e:
        db_core.logger.error("get_session_streaks error: %s", e)
        return {"current": 0, "longest": 0}

    if not dates:
        return {"current": 0, "longest": 0}

    all_set = set(dates)
    current = 0
    d = _date.today()
    if d.isoformat() not in all_set:
        d -= timedelta(days=1)
    while current < 365:
        if d.isoformat() in all_set:
            current += 1
            d -= timedelta(days=1)
        else:
            break

    longest = run = 0
    prev = None
    for d_str in dates:
        d_obj = _date.fromisoformat(d_str)
        run = run + 1 if (prev and (d_obj - prev).days == 1) else 1
        longest = max(longest, run)
        prev = d_obj

    return {"current": current, "longest": longest}


def get_workout_session(date: str) -> Optional[dict]:
    """Return a single workout session by date (is_second=False), or None."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do() -> Optional[dict]:
        resp = (
            db_core._client.table("workout_sessions")
            .select("*")
            .eq("date", date)
            .eq("session_type", "morning")
            .limit(1)
            .execute()
        )
        return resp.data[0] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.debug("get_workout_session(%s) retry error: %s", date, e2)
                return None
        db_core.logger.debug("get_workout_session(%s) error: %s", date, e)
        return None


def get_or_create_workout_session(date: str) -> dict:
    """Return the workout session for *date*, creating a minimal stub if none exists."""
    existing = get_workout_session(date)
    if existing:
        return existing
    return create_workout_session(date)


def get_workout_session_second(date: str) -> Optional[dict]:
    """Return the second (is_second=True) workout session for a date, or None."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do() -> Optional[dict]:
        resp = (
            db_core._client.table("workout_sessions")
            .select("*")
            .eq("date", date)
            .eq("is_second", True)
            .single()
            .execute()
        )
        return resp.data

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.debug("get_workout_session_second(%s) retry error: %s", date, e2)
                return None
        db_core.logger.debug("get_workout_session_second(%s) error: %s", date, e)
        return None


def get_or_create_workout_session_second(date: str) -> dict:
    """Return the second session for *date*, creating a stub if none exists."""
    existing = get_workout_session_second(date)
    if existing:
        return existing
    return create_workout_session(date, is_second=True, session_type="evening")


def get_workout_session_bonus(date: str) -> Optional[dict]:
    """Return the bonus (session_type='bonus') workout session for a date, or None."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do() -> Optional[dict]:
        resp = (
            db_core._client.table("workout_sessions")
            .select("*")
            .eq("date", date)
            .eq("session_type", "bonus")
            .limit(1)
            .execute()
        )
        return resp.data[0] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.debug("get_workout_session_bonus(%s) retry error: %s", date, e2)
                return None
        db_core.logger.debug("get_workout_session_bonus(%s) error: %s", date, e)
        return None


def get_or_create_workout_session_bonus(date: str) -> dict:
    """Return the bonus session for *date*, creating a stub if none exists."""
    existing = get_workout_session_bonus(date)
    if existing:
        return existing
    return create_workout_session(date, session_type="bonus")


def create_workout_session(
    date: str,
    rpe=None,
    comment=None,
    duration_min=None,
    energy_pre=None,
    is_second: bool = False,
    session_type: str = "morning",
    session_name: str | None = None,
) -> dict:
    """Insert a new workout session row. Returns the created record."""
    payload: dict = {"date": date, "is_second": is_second, "session_type": session_type}
    if rpe is not None:
        payload["rpe"] = int(round(float(rpe)))
    if duration_min is not None:
        payload["duration_min"] = int(float(duration_min))
    if energy_pre is not None:
         payload["energy_pre"] = int(float(energy_pre))

    if comment is not None:
        payload["comment"] = comment
    if session_name is not None:
        payload["session_name"] = session_name

    if db_core._client is None or db_core.MODE == "OFFLINE":
        return {}

    def _do() -> dict:
        resp = db_core._client.table("workout_sessions").insert(payload).execute()
        return resp.data[0] if resp.data else payload

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("create_workout_session retry error: %s", e2)
                return {}
        db_core.logger.error("create_workout_session error: %s", e)
        return {}


def complete_workout_session(date: str, patch: Optional[dict] = None) -> bool:
    """Mark a workout session as completed and persist session metadata."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        # Warn when completing a session that has no exercise logs — likely a
        # crash-during-write scenario where exercise data was lost.
        try:
            session_row = (
                db_core._client.table("workout_sessions")
                .select("id")
                .eq("date", date)
                .eq("session_type", "morning")
                .single()
                .execute()
            )
            if session_row.data:
                log_check = (
                    db_core._client.table("exercise_logs")
                    .select("id", count="exact")
                    .eq("session_id", session_row.data["id"])
                    .limit(1)
                    .execute()
                )
                if (log_check.count or 0) == 0:
                    db_core.logger.warning(
                        "complete_workout_session: completing session %s on %s with zero exercise_logs",
                        session_row.data["id"], date,
                    )
        except Exception:
            pass  # guard should never block completion

        data = {"completed": True}
        if patch:
            for k, v in patch.items():
                if k not in ("rpe", "comment", "duration_min", "energy_pre", "session_name"):
                    continue
                if v is None:
                    continue
                if k == "rpe":
                    data[k] = int(round(float(v)))
                elif k in ("duration_min", "energy_pre"):
                    data[k] = int(float(v))
                else:
                    data[k] = v
        resp = (
            db_core._client.table("workout_sessions")
            .update(data)
            .eq("date", date)
            .eq("session_type", "morning")
            .execute()
        )
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("complete_workout_session retry error: %s", e2)
                return False
        db_core.logger.error("complete_workout_session error: %s", e)
        return False


def complete_workout_session_bonus(date: str, patch: Optional[dict] = None) -> bool:
    """Mark a bonus session as completed and persist session metadata."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        data = {"completed": True}
        if patch:
            for k, v in patch.items():
                if k not in ("rpe", "comment", "duration_min", "energy_pre", "session_name"):
                    continue
                if v is None:
                    continue
                if k == "rpe":
                    data[k] = int(round(float(v)))
                elif k in ("duration_min", "energy_pre"):
                    data[k] = int(float(v))
                else:
                    data[k] = v
        resp = (
            db_core._client.table("workout_sessions")
            .update(data)
            .eq("date", date)
            .eq("session_type", "bonus")
            .execute()
        )
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("complete_workout_session_bonus retry error: %s", e2)
                return False
        db_core.logger.error("complete_workout_session_bonus error: %s", e)
        return False


def update_workout_session_bonus(date: str, patch: dict) -> bool:
    """Update fields on a bonus session. Returns True on success."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        resp = (
            db_core._client.table("workout_sessions")
            .update(patch)
            .eq("date", date)
            .eq("session_type", "bonus")
            .execute()
        )
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("update_workout_session_bonus retry error: %s", e2)
                return False
        db_core.logger.error("update_workout_session_bonus error: %s", e)
        return False


def delete_workout_session_by_type(date: str, session_type: str = "morning") -> bool:
    """Delete a single session row by date + session_type."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        resp = (
            db_core._client.table("workout_sessions")
            .delete()
            .eq("date", date)
            .eq("session_type", session_type)
            .execute()
        )
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("delete_workout_session_by_type retry error: %s", e2)
                return False
        db_core.logger.error("delete_workout_session_by_type error: %s", e)
        return False


def delete_exercise_logs_for_session(session_id: str) -> bool:
    """Delete all exercise_logs for a given session_id."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        db_core._client.table("exercise_logs").delete().eq("session_id", session_id).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("delete_exercise_logs_for_session retry error: %s", e2)
                return False
        db_core.logger.error("delete_exercise_logs_for_session error: %s", e)
        return False


def upsert_exercise_log_direct(
    session_id: str,
    exercise_name: str,
    weight: float,
    reps: str,
    sets_json: list | None = None,
    rpe: float | None = None,
    pain_zone: str | None = None,
) -> bool:
    """Insert/update an exercise_log row using session_id directly (bypasses date lookup)."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        exercise_id = get_or_create_exercise_id(exercise_name)
        if not exercise_id:
            db_core.logger.warning("upsert_exercise_log_direct: exercise '%s' unavailable", exercise_name)
            return False
        payload = {
            "session_id": session_id,
            "exercise_id": exercise_id,
            "weight": weight,
            "reps": reps,
        }
        if sets_json is not None:
            payload["sets_json"] = sets_json
        if rpe is not None:
            payload["rpe"] = round(float(rpe), 1)
        if pain_zone:
            payload["pain_zone"] = pain_zone
        resp = (
            db_core._client.table("exercise_logs")
            .upsert(payload, on_conflict="session_id,exercise_id")
            .execute()
        )
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("upsert_exercise_log_direct retry error: %s", e2)
                return False
        db_core.logger.error("upsert_exercise_log_direct error: %s", e)
        return False


def get_exercise_history_grouped_by_session(session_ids: list | None = None) -> dict:
    """Return exercise history keyed by workout_sessions.id (UUID string).

    Paginates through exercise_logs to bypass Supabase's 1000-row default cap.
    Returns: {session_id: [{"exercise": name, "weight": w, "reps": r}, ...]}
    """
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return {}
    result: dict = {}
    page_size = 1000
    offset = 0

    def _do() -> dict:
        nonlocal result, offset
        result = {}
        offset = 0
        while True:
            q = (
                db_core._client.table("exercise_logs")
                .select("weight, reps, session_id, exercises(name)")
                .range(offset, offset + page_size - 1)
            )
            if session_ids:
                q = q.in_("session_id", session_ids)
            resp = q.execute()
            rows = resp.data or []
            for r in rows:
                sid = r.get("session_id")
                name = (r.get("exercises") or {}).get("name")
                if not sid or not name:
                    continue
                result.setdefault(sid, []).append({
                    "exercise": name,
                    "weight":   r.get("weight", 0),
                    "reps":     r.get("reps", ""),
                })
            if len(rows) < page_size:
                break
            offset += page_size
        return result

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_exercise_history_grouped_by_session retry error: %s", e2)
                return result  # return partial data rather than empty
        db_core.logger.error("get_exercise_history_grouped_by_session error: %s", e)
        return result  # return partial data rather than empty


def update_workout_session_by_type(date: str, session_type: str, patch: dict) -> bool:
    """Update fields on a workout session identified by date + session_type."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        resp = (
            db_core._client.table("workout_sessions")
            .update(patch)
            .eq("date", date)
            .eq("session_type", session_type)
            .execute()
        )
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("update_workout_session_by_type(%s,%s) retry error: %s", date, session_type, e2)
                return False
        db_core.logger.error("update_workout_session_by_type(%s,%s) error: %s", date, session_type, e)
        return False


INT_FIELDS = {"duration_min", "energy_pre", "rpe"}  # rpe is SMALLINT in DB
DECIMAL_FIELDS: set = set()

def update_workout_session(date: str, patch: dict) -> bool:
    """Update fields on a workout session by date. Returns True on success."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        cleaned = {}

        for k, v in patch.items():
            if v is None:
                cleaned[k] = None
            elif k in INT_FIELDS:
                cleaned[k] = int(float(v))
            elif k in DECIMAL_FIELDS:
                cleaned[k] = round(float(v), 1)
            else:
                cleaned[k] = v

        resp = (
            db_core._client.table("workout_sessions")
            .update(cleaned)
            .eq("date", date)
            .eq("session_type", "morning")
            .execute()
        )

        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("update_workout_session retry error: %s", e2)
                return False
        db_core.logger.error("update_workout_session error: %s", e)
        return False


def delete_workout_session(date: str) -> bool:
    """Delete a workout session and its exercise_logs (cascade). Returns True on success."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        resp = db_core._client.table("workout_sessions").delete().eq("date", date).execute()
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("delete_workout_session retry error: %s", e2)
                return False
        db_core.logger.error("delete_workout_session error: %s", e)
        return False


# ---------------------------------------------------------------------------
# Exercise logs
# ---------------------------------------------------------------------------

def get_exercise_history(exercise_name: str, limit: int = 50) -> List[dict]:
    """Return [{date, weight, reps, session_id}] newest first."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        ex_id = get_exercise_id(exercise_name)
        if not ex_id:
            return []
        resp = (
            db_core._client.table("exercise_logs")
            .select("weight, reps, sets_json, session_id, workout_sessions(date)")
            .eq("exercise_id", ex_id)
            .order("workout_sessions(date)", desc=True)
            .limit(limit)
            .execute()
        )
        rows = resp.data or []
        return [
            {
                "date":       r["workout_sessions"]["date"],
                "weight":     r["weight"],
                "reps":       r["reps"],
                "sets_json":  r.get("sets_json"),
                "session_id": r["session_id"],
            }
            for r in rows
            if r.get("workout_sessions")
        ]

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_exercise_history(%s) retry error: %s", exercise_name, e2)
                return []
        db_core.logger.error("get_exercise_history(%s) error: %s", exercise_name, e)
        return []


def get_all_exercise_history() -> dict:
    """Return {exercise_name: [{date, weight, reps}]} for all exercises in one query.

    Used by load_weights() to avoid N+1 per-exercise queries.
    Paginates to bypass Supabase's 1000-row default cap.
    """
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return {}
    page_size = 1000

    def _do() -> dict:
        result: dict = {}
        offset = 0
        while True:
            resp = (
                db_core._client.table("exercise_logs")
                .select("weight, reps, sets_json, exercises(name), workout_sessions(date)")
                .range(offset, offset + page_size - 1)
                .execute()
            )
            rows = resp.data or []
            for r in rows:
                name = (r.get("exercises") or {}).get("name")
                date = (r.get("workout_sessions") or {}).get("date")
                if not name or not date:
                    continue
                entry = {"date": date, "weight": r.get("weight"), "reps": r.get("reps")}
                sets_json = r.get("sets_json")
                if sets_json:
                    entry["sets"] = sets_json
                result.setdefault(name, []).append(entry)
            if len(rows) < page_size:
                break
            offset += page_size
        # Sort each exercise history newest-first
        for name in result:
            result[name].sort(key=lambda x: x.get("date", ""), reverse=True)
        return result

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_all_exercise_history retry error: %s", e2)
                return {}
        db_core.logger.error("get_all_exercise_history error: %s", e)
        return {}


def get_exercise_history_bulk(exercise_names: list[str], limit_per: int = 20) -> dict:
    """Return {exercise_name: [{date, weight, reps, sets_json}]} for a subset of exercises.

    This is a performance-critical helper for /api/seance_data: we only need
    today's exercises, not the full training history for every exercise.
    """
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return {}
    names = [n for n in exercise_names if isinstance(n, str) and n.strip()]
    if not names:
        return {}

    def _do() -> dict:
        ex_rows = (
            db_core._client.table("exercises")
            .select("id,name")
            .in_("name", names)
            .is_("deleted_at", "null")
            .execute()
        ).data or []
        id_to_name = {r["id"]: r["name"] for r in ex_rows if r.get("id") and r.get("name")}
        ex_ids = list(id_to_name.keys())
        if not ex_ids:
            return {}

        resp = (
            db_core._client.table("exercise_logs")
            .select("exercise_id, weight, reps, sets_json, workout_sessions(date)")
            .in_("exercise_id", ex_ids)
            .order("workout_sessions(date)", desc=True)
            .execute()
        )
        rows = resp.data or []
        result: dict[str, list[dict]] = {id_to_name[i]: [] for i in ex_ids if i in id_to_name}
        for r in rows:
            ex_id = r.get("exercise_id")
            name = id_to_name.get(ex_id)
            if not name:
                continue
            d = (r.get("workout_sessions") or {}).get("date")
            if not d:
                continue
            lst = result.setdefault(name, [])
            if len(lst) >= limit_per:
                continue
            entry = {"date": d, "weight": r.get("weight"), "reps": r.get("reps")}
            if r.get("sets_json"):
                entry["sets"] = r.get("sets_json")
            lst.append(entry)
        return result

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_exercise_history_bulk retry error: %s", e2)
                return {}
        db_core.logger.error("get_exercise_history_bulk error: %s", e)
        return {}


def get_session_exercise_logs(session_date: str) -> List[dict]:
    """Return [{exercise_name, weight, reps}] for a given session date."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        session = get_workout_session(session_date)
        if not session:
            return []
        session_id = session["id"]
        resp = (
            db_core._client.table("exercise_logs")
            .select("weight, reps, exercises(name)")
            .eq("session_id", session_id)
            .execute()
        )
        rows = resp.data or []
        return [
            {
                "exercise_name": r["exercises"]["name"],
                "weight": r["weight"],
                "reps": r["reps"],
            }
            for r in rows
            if r.get("exercises")
        ]

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_session_exercise_logs(%s) retry error: %s", session_date, e2)
                return []
        db_core.logger.error("get_session_exercise_logs(%s) error: %s", session_date, e)
        return []


def get_previous_session_by_name(current_date: str, session_name: str) -> Optional[dict]:
    """Return the most recent workout_session with session_name strictly before current_date."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do() -> Optional[dict]:
        resp = (
            db_core._client.table("workout_sessions")
            .select("*")
            .eq("session_name", session_name)
            .lt("date", current_date)
            .order("date", desc=True)
            .limit(1)
            .execute()
        )
        return resp.data[0] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_previous_session_by_name(%s,%s) retry error: %s", current_date, session_name, e2)
                return None
        db_core.logger.error("get_previous_session_by_name(%s,%s) error: %s", current_date, session_name, e)
        return None


def get_workout_session_by_type(date: str, session_type: str) -> Optional[dict]:
    """Return workout session for date + session_type, or None."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do() -> Optional[dict]:
        resp = (
            db_core._client.table("workout_sessions")
            .select("*")
            .eq("date", date)
            .eq("session_type", session_type)
            .limit(1)
            .execute()
        )
        return resp.data[0] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_workout_session_by_type(%s,%s) retry error: %s", date, session_type, e2)
                return None
        db_core.logger.error("get_workout_session_by_type(%s,%s) error: %s", date, session_type, e)
        return None


def get_exercise_logs_for_session_with_names(session_id: str) -> List[dict]:
    """Return [{exercise_name, weight, reps, sets_json}] for a session_id."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        resp = (
            db_core._client.table("exercise_logs")
            .select("weight, reps, sets_json, exercises(name)")
            .eq("session_id", session_id)
            .execute()
        )
        rows = resp.data or []
        return [
            {
                "exercise_name": r["exercises"]["name"],
                "weight": r["weight"],
                "reps": r["reps"],
                "sets_json": r.get("sets_json") or [],
            }
            for r in rows
            if r.get("exercises")
        ]

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_exercise_logs_for_session_with_names(%s) retry error: %s", session_id, e2)
                return []
        db_core.logger.error("get_exercise_logs_for_session_with_names(%s) error: %s", session_id, e)
        return []


def get_exercise_logs_since(cutoff_date: str) -> List[dict]:
    """Return exercise logs since cutoff_date (inclusive) with muscles info.

    Returns [{exercise_name, muscles, sets_json, rpe, date}] sorted date desc.
    Used by muscle_volume.compute_weekly_hard_sets().
    """
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> List[dict]:
        resp = (
            db_core._client.table("exercise_logs")
            .select("sets_json, exercises(name, muscles), workout_sessions(date, rpe)")
            .gte("workout_sessions.date", cutoff_date)
            .execute()
        )
        rows = resp.data or []
        result = []
        for r in rows:
            ex  = r.get("exercises") or {}
            ses = r.get("workout_sessions") or {}
            if not ex.get("name") or not ses.get("date"):
                continue
            result.append({
                "exercise_name": ex["name"],
                "muscles":       ex.get("muscles") or [],
                "sets_json":     r.get("sets_json") or [],
                "rpe":           ses.get("rpe"),
                "date":          ses["date"],
            })
        return result

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_exercise_logs_since(%s) retry error: %s", cutoff_date, e2)
                return []
        db_core.logger.error("get_exercise_logs_since(%s) error: %s", cutoff_date, e)
        return []


def get_previous_session_by_exercises(ref_date: str, session_type: str, exercise_names: list) -> Optional[dict]:
    """
    Find the most recent session before ref_date whose exercise_logs contain
    the most overlap with exercise_names.  Used as fallback when session_name
    is NULL (sessions logged before migration 010).

    Three queries: exercise IDs → session IDs with overlap count → session rows.
    Returns the most recent session with ≥40% exercise overlap, or the most
    recent session among the candidates if none reaches the threshold.
    """
    if not exercise_names or db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do() -> Optional[dict]:
        # 1. Resolve exercise names → IDs
        ex_resp = (
            db_core._client.table("exercises")
            .select("id")
            .in_("name", exercise_names)
            .is_("deleted_at", "null")
            .execute()
        )
        ex_ids = [e["id"] for e in (ex_resp.data or [])]
        if not ex_ids:
            return None

        # 2. Find session IDs that have any of those exercises
        logs_resp = (
            db_core._client.table("exercise_logs")
            .select("session_id, exercise_id")
            .in_("exercise_id", ex_ids)
            .limit(1000)
            .execute()
        )
        session_counts: dict = {}
        for log in (logs_resp.data or []):
            sid = log["session_id"]
            session_counts[sid] = session_counts.get(sid, 0) + 1
        if not session_counts:
            return None

        # 3. Filter to sessions of the right type before ref_date
        sessions_resp = (
            db_core._client.table("workout_sessions")
            .select("id, date, session_type, session_name")
            .in_("id", list(session_counts.keys()))
            .eq("session_type", session_type)
            .lt("date", ref_date)
            .order("date", desc=True)
            .limit(10)
            .execute()
        )
        candidates = sessions_resp.data or []
        if not candidates:
            return None

        threshold = max(1, len(exercise_names) * 0.4)
        for s in candidates:
            if session_counts.get(s["id"], 0) >= threshold:
                return s
        return candidates[0]

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_previous_session_by_exercises(%s) retry error: %s", ref_date, e2)
                return None
        db_core.logger.error("get_previous_session_by_exercises(%s) error: %s", ref_date, e)
        return None


def get_previous_session_of_type(current_date: str, session_type: str) -> Optional[dict]:
    """Return the most recent workout_session of session_type strictly before current_date."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do() -> Optional[dict]:
        resp = (
            db_core._client.table("workout_sessions")
            .select("*")
            .eq("session_type", session_type)
            .lt("date", current_date)
            .order("date", desc=True)
            .limit(1)
            .execute()
        )
        return resp.data[0] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_previous_session_of_type(%s,%s) retry error: %s", current_date, session_type, e2)
                return None
        db_core.logger.error("get_previous_session_of_type(%s,%s) error: %s", current_date, session_type, e)
        return None


def get_exercise_info(exercise_name: str) -> Optional[dict]:
    """Return exercise row (category, load_profile, default_scheme) from exercises table."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do() -> Optional[dict]:
        resp = (
            db_core._client.table("exercises")
            .select("name, category, load_profile, default_scheme")
            .eq("name", exercise_name)
            .is_("deleted_at", "null")
            .limit(1)
            .execute()
        )
        return resp.data[0] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_exercise_info(%s) retry error: %s", exercise_name, e2)
                return None
        db_core.logger.error("get_exercise_info(%s) error: %s", exercise_name, e)
        return None


def get_exercises_info_bulk(exercise_names: list[str]) -> dict[str, dict]:
    """Batch fetch exercise info (category, load_profile, default_scheme) for multiple exercises.

    Returns: {exercise_name: {category, load_profile, default_scheme}}
    """
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return {}
    names = [n for n in exercise_names if isinstance(n, str) and n.strip()]
    if not names:
        return {}

    def _do() -> dict[str, dict]:
        resp = (
            db_core._client.table("exercises")
            .select("name, category, load_profile, default_scheme")
            .in_("name", names)
            .is_("deleted_at", "null")
            .execute()
        )
        return {row["name"]: row for row in (resp.data or []) if row.get("name")}

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_exercises_info_bulk retry error: %s", e2)
                return {}
        db_core.logger.error("get_exercises_info_bulk error: %s", e)
        return {}


def update_exercise_default_scheme(exercise_name: str, default_scheme: str) -> bool:
    """Update exercises.default_scheme for an exercise."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        db_core._client.table("exercises").update({"default_scheme": default_scheme}).eq("name", exercise_name).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("update_exercise_default_scheme(%s) retry error: %s", exercise_name, e2)
                return False
        db_core.logger.error("update_exercise_default_scheme(%s) error: %s", exercise_name, e)
        return False


def normalize_schemes_max_sets(max_sets: int = 3) -> int:
    """Cap set count to max_sets for every exercise whose default_scheme has more.
    e.g. '4x5' → '3x5', '5x3' → '3x3'. Returns number of exercises updated."""
    import re
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return 0

    def _do() -> int:
        rows = (db_core._client.table("exercises").select("name,default_scheme").is_("deleted_at", "null").execute().data or [])
        updated = 0
        for row in rows:
            scheme = (row.get("default_scheme") or "").strip()
            m = re.match(r'^(\d+)(x.+)$', scheme, re.IGNORECASE)
            if m and int(m.group(1)) > max_sets:
                new_scheme = f"{max_sets}{m.group(2)}"
                db_core._client.table("exercises").update({"default_scheme": new_scheme}).eq("name", row["name"]).execute()
                updated += 1
        return updated

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("normalize_schemes_max_sets retry error: %s", e2)
                return 0
        db_core.logger.error("normalize_schemes_max_sets error: %s", e)
        return 0


def bulk_set_rest_seconds(seconds: int) -> bool:
    """Set rest_seconds = seconds for every exercise in the inventory."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        db_core._client.table("exercises").update({"rest_seconds": seconds}).neq("name", "").is_("deleted_at", "null").execute()
        return True

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("bulk_set_rest_seconds retry error: %s", e2)
                return False
        db_core.logger.error("bulk_set_rest_seconds error: %s", e)
        return False


def upsert_exercise_log(
    session_date: str, exercise_name: str, weight: float, reps: str, sets_json: list | None = None
) -> bool:
    """Insert or update an exercise log entry. Resolves IDs internally. Returns True on success."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        exercise_id = get_or_create_exercise_id(exercise_name)
        if not exercise_id:
            db_core.logger.warning("upsert_exercise_log: exercise '%s' unavailable", exercise_name)
            return False
        session = get_workout_session(session_date)
        if not session:
            db_core.logger.warning("upsert_exercise_log: no session for date %s", session_date)
            return False
        session_id = session["id"]
        payload = {
            "session_id": session_id,
            "exercise_id": exercise_id,
            "weight": weight,
            "reps": reps,
        }
        if sets_json is not None:
            payload["sets_json"] = sets_json
        resp = (
            db_core._client.table("exercise_logs")
            .upsert(payload, on_conflict="session_id,exercise_id")
            .execute()
        )
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("upsert_exercise_log retry error: %s", e2)
                return False
        db_core.logger.error("upsert_exercise_log error: %s", e)
        return False


def upsert_exercise_log_by_type(
    session_date: str,
    session_type: str,
    exercise_name: str,
    weight: float,
    reps: str,
    sets_json: list | None = None,
) -> bool:
    """Insert/update an exercise log entry by date + session_type."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        exercise_id = get_or_create_exercise_id(exercise_name)
        if not exercise_id:
            db_core.logger.warning("upsert_exercise_log_by_type: exercise '%s' unavailable", exercise_name)
            return False
        session = get_workout_session_by_type(session_date, session_type)
        if not session:
            db_core.logger.warning("upsert_exercise_log_by_type: no session for date=%s type=%s", session_date, session_type)
            return False
        payload = {
            "session_id": session["id"],
            "exercise_id": exercise_id,
            "weight": weight,
            "reps": reps,
        }
        if sets_json is not None:
            payload["sets_json"] = sets_json
        resp = (
            db_core._client.table("exercise_logs")
            .upsert(payload, on_conflict="session_id,exercise_id")
            .execute()
        )
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("upsert_exercise_log_by_type retry error: %s", e2)
                return False
        db_core.logger.error("upsert_exercise_log_by_type error: %s", e)
        return False


def delete_exercise_log_entry(session_date: str, exercise_name: str) -> bool:
    """Delete a single exercise_log entry by date + exercise name."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        session = get_workout_session(session_date)
        if not session:
            return False
        exercise_id = get_exercise_id(exercise_name)
        if not exercise_id:
            return False
        db_core._client.table("exercise_logs") \
            .delete() \
            .eq("session_id", session["id"]) \
            .eq("exercise_id", exercise_id) \
            .execute()
        return True

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("delete_exercise_log_entry retry error: %s", e2)
                return False
        db_core.logger.error("delete_exercise_log_entry error: %s", e)
        return False


def delete_exercise_log_entry_by_type(session_date: str, session_type: str, exercise_name: str) -> bool:
    """Delete one exercise_log entry by date + session_type + exercise name."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        session = get_workout_session_by_type(session_date, session_type)
        if not session:
            return False
        exercise_id = get_exercise_id(exercise_name)
        if not exercise_id:
            return False
        db_core._client.table("exercise_logs") \
            .delete() \
            .eq("session_id", session["id"]) \
            .eq("exercise_id", exercise_id) \
            .execute()
        return True

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("delete_exercise_log_entry_by_type retry error: %s", e2)
                return False
        db_core.logger.error("delete_exercise_log_entry_by_type error: %s", e)
        return False


def bulk_upsert_exercise_logs(entries: list[dict]) -> bool:
    """Batch upsert exercise_logs. Each entry: {date, exercise_name, weight, reps, sets_json?}.

    Reduces the per-exercise N+1 to 3 queries total (session lookup, exercise lookup, upsert).
    Atomic: the single upsert call either fully succeeds or fully fails.
    """
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False
    if not entries:
        return True

    def _do() -> bool:
        dates = list({e["date"] for e in entries})
        names = list({e["exercise_name"] for e in entries})

        sessions_resp = (
            db_core._client.table("workout_sessions")
            .select("id, date")
            .in_("date", dates)
            .execute()
        )
        session_by_date = {s["date"]: s["id"] for s in (sessions_resp.data or [])}

        ex_resp = (
            db_core._client.table("exercises")
            .select("id, name")
            .in_("name", names)
            .is_("deleted_at", "null")
            .execute()
        )
        id_by_name = {e["name"]: e["id"] for e in (ex_resp.data or [])}

        payloads = []
        for entry in entries:
            session_id = session_by_date.get(entry["date"])
            exercise_id = id_by_name.get(entry["exercise_name"])
            if not session_id or not exercise_id:
                db_core.logger.warning(
                    "bulk_upsert_exercise_logs: skipping %s on %s — session_id=%s exercise_id=%s",
                    entry["exercise_name"], entry["date"], session_id, exercise_id,
                )
                continue
            row = {
                "session_id": session_id,
                "exercise_id": exercise_id,
                "weight": entry.get("weight"),
                "reps": entry.get("reps"),
            }
            if entry.get("sets_json") is not None:
                row["sets_json"] = entry["sets_json"]
            payloads.append(row)

        if not payloads:
            return True

        resp = (
            db_core._client.table("exercise_logs")
            .upsert(payloads, on_conflict="session_id,exercise_id")
            .execute()
        )
        return bool(resp.data)

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("bulk_upsert_exercise_logs retry error: %s", e2)
                return False
        db_core.logger.error("bulk_upsert_exercise_logs error: %s", e)
        return False


def bulk_apply_session_exercise_patches(
    session_date: str,
    session_type: str,
    patches: list[dict],
) -> tuple[bool, list[str]]:
    """Apply a list of exercise patches (upsert/delete) to a session in batch.

    Each patch: {exercise_name, action ('update'|'add'|'delete'), weight?, reps?, sets_json?}
    Returns (overall_ok, list_of_error_strings).

    Reduces the per-patch N+1 to 4 queries total:
      1 session lookup, 1 exercise batch lookup, 1 batch delete, 1 batch upsert.
    """
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False, ["offline"]
    if not patches:
        return True, []

    def _do() -> tuple[bool, list[str]]:
        session = get_workout_session_by_type(session_date, session_type)
        if not session:
            return False, [f"no session for date={session_date} type={session_type}"]
        session_id = session["id"]

        names = list({p["exercise_name"] for p in patches})
        ex_resp = (
            db_core._client.table("exercises")
            .select("id, name")
            .in_("name", names)
            .is_("deleted_at", "null")
            .execute()
        )
        id_by_name = {e["name"]: e["id"] for e in (ex_resp.data or [])}

        errors: list[str] = []
        delete_ids: list[str] = []
        upsert_rows: list[dict] = []

        for patch in patches:
            ex_name = patch["exercise_name"]
            exercise_id = id_by_name.get(ex_name)
            if not exercise_id:
                errors.append(f"{ex_name}: exercise not found")
                continue
            action = (patch.get("action") or "update").lower()
            if action == "delete":
                delete_ids.append(exercise_id)
            else:
                row = {
                    "session_id": session_id,
                    "exercise_id": exercise_id,
                    "weight": float(patch.get("weight") or 0),
                    "reps": str(patch.get("reps") or ""),
                }
                if patch.get("sets_json") is not None:
                    row["sets_json"] = patch["sets_json"]
                upsert_rows.append(row)

        if delete_ids:
            db_core._client.table("exercise_logs") \
                .delete() \
                .eq("session_id", session_id) \
                .in_("exercise_id", delete_ids) \
                .execute()

        if upsert_rows:
            resp = (
                db_core._client.table("exercise_logs")
                .upsert(upsert_rows, on_conflict="session_id,exercise_id")
                .execute()
            )
            if not resp.data:
                errors.append("batch upsert returned no data")

        return len(errors) == 0, errors

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("bulk_apply_session_exercise_patches retry error: %s", e2)
                return False, [str(e2)]
        db_core.logger.error("bulk_apply_session_exercise_patches error: %s", e)
        return False, [str(e)]


def delete_session_exercise_logs(session_date: str) -> bool:
    """Delete all exercise_logs for a given session date. Returns True on success."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        session = get_workout_session(session_date)
        if not session:
            return False
        session_id = session["id"]
        db_core._client.table("exercise_logs").delete().eq("session_id", session_id).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("delete_session_exercise_logs retry error: %s", e2)
                return False
        db_core.logger.error("delete_session_exercise_logs error: %s", e)
        return False
