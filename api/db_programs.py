from __future__ import annotations
import logging
from typing import Optional
import db_core
from db_profile import get_profile, update_profile
from utils import _today_mtl


# Blocs qui portent des program_block_exercises avec scheme reps.
# hiit/cardio EXCLUS : ils utilisent hiit_config (colonne dédiée).
REPS_BLOCKS = frozenset({
    "strength", "force", "isolation", "core",
    "mobility", "explosive", "finisher",
})


def get_all_programs() -> list:
    """Return [{id, name, created_at}, ...] ordered by created_at ASC."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> list:
        resp = db_core._client.table("programs").select("id, name, created_at").order("created_at").execute()
        return resp.data or []

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_all_programs retry error: %s", e2)
                return []
        db_core.logger.error("get_all_programs error: %s", e)
        return []


def get_active_program_id() -> str | None:
    """Return the active program_id.

    Priority:
    1. user_profile.active_program_id (explicit user choice)
    2. weekly_schedule morning slot (legacy schedule-based detection)
    3. Oldest program (default fallback)
    """
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return get_default_program_id()

    # 1. Explicit choice stored in user_profile
    try:
        profile = get_profile()
        pid = profile.get("active_program_id")
        if pid:
            return str(pid)
    except Exception:
        pass

    # 2. Schedule-based detection — only conclusive when all morning slots agree
    def _do() -> str | None:
        resp = (
            db_core._client.table("weekly_schedule")
            .select("program_sessions(program_id)")
            .eq("slot", "morning")
            .not_.is_("session_id", "null")
            .execute()
        )
        pids = {
            str(row["program_sessions"]["program_id"])
            for row in (resp.data or [])
            if row.get("program_sessions") and row["program_sessions"].get("program_id")
        }
        return pids.pop() if len(pids) == 1 else None

    try:
        result = _do()
        if result is not None:
            return result
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                result = _do()
                if result is not None:
                    return result
            except Exception as e2:
                db_core.logger.error("get_active_program_id retry error: %s", e2)
        else:
            db_core.logger.error("get_active_program_id error: %s", e)
    return get_default_program_id()


def set_active_program_id(program_id: str) -> bool:
    """Persist the user's active programme choice in user_profile."""
    return update_profile({"active_program_id": program_id})


def get_session_override() -> dict | None:
    """Return today's session override if it exists and matches today's date.

    Returns {"date": "2026-05-15", "session": "Push B"} or None.
    """
    import json as _json
    from datetime import date
    profile = get_profile()
    raw = profile.get("session_override")
    if not raw:
        return None
    try:
        override = _json.loads(raw) if isinstance(raw, str) else raw
        if isinstance(override, dict) and override.get("date") == _today_mtl():
            return override
    except Exception:
        pass
    return None


def set_session_override(session: str | None) -> bool:
    """Store (or clear) a session override for today.

    Pass session=None to clear the override.
    """
    import json as _json
    from datetime import date
    if session is None:
        return update_profile({"session_override": None})
    payload = {"date": _today_mtl(), "session": session}
    return update_profile({"session_override": _json.dumps(payload)})


def get_default_program_id() -> str | None:
    """Return the UUID of the first (oldest) program, or None if none exist."""
    programs = get_all_programs()
    return programs[0]["id"] if programs else None


def create_program(name: str) -> str | None:
    """Insert a new program. Returns its UUID or None on error."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do() -> str | None:
        resp = db_core._client.table("programs").insert({"name": name}).execute()
        return resp.data[0]["id"] if resp.data else None

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("create_program retry error: %s", e2)
                return None
        db_core.logger.error("create_program error: %s", e)
        return None


def rename_program(program_id: str, new_name: str) -> bool:
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        db_core._client.table("programs").update({"name": new_name}).eq("id", program_id).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("rename_program retry error: %s", e2)
                return False
        db_core.logger.error("rename_program error: %s", e)
        return False


def delete_program(program_id: str) -> bool:
    """Delete a program — sessions cascade via FK."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        db_core._client.table("programs").delete().eq("id", program_id).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("delete_program retry error: %s", e2)
                return False
        db_core.logger.error("delete_program error: %s", e)
        return False


def get_cycle_start_date() -> str | None:
    """Return cycle_start_date (YYYY-MM-DD) of the default program, or None."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do() -> str | None:
        program_id = get_default_program_id()
        if not program_id:
            return None
        resp = (db_core._client.table("programs")
                .select("cycle_start_date")
                .eq("id", program_id)
                .single()
                .execute())
        val = (resp.data or {}).get("cycle_start_date")
        return str(val)[:10] if val else None

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_cycle_start_date retry error: %s", e2)
                return None
        db_core.logger.error("get_cycle_start_date error: %s", e)
        return None


def set_cycle_start_date(date_str: str) -> bool:
    """Set cycle_start_date on the default program. date_str = 'YYYY-MM-DD'."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        program_id = get_default_program_id()
        if not program_id:
            return False
        db_core._client.table("programs").update({"cycle_start_date": date_str}).eq("id", program_id).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("set_cycle_start_date retry error: %s", e2)
                return False
        db_core.logger.error("set_cycle_start_date error: %s", e)
        return False


def get_all_session_names() -> list[str]:
    """Return all session names across all programs (for schedule pickers)."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> list[str]:
        resp = db_core._client.table("program_sessions").select("name").order("name").execute()
        return [r["name"] for r in (resp.data or [])]

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_all_session_names retry error: %s", e2)
                return []
        db_core.logger.error("get_all_session_names error: %s", e)
        return []


def get_full_program(program_id: str | None = None) -> dict | None:
    """Return {session_name: {"blocks": [{"type", "order", "exercises": {name: scheme}}]}}.

    If program_id is None, uses the first/oldest program.
    Compatible with the block format used by planner.py / blocks.py.
    Returns {} if relational tables are genuinely empty (no sessions).
    Returns None if the relational layer is unavailable or a network/query error occurs —
    callers must treat None as "unknown state, do NOT overwrite existing data".
    """
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return None

    def _do() -> dict | None:
        # Étape 3b — le join exercises(id, name) porte l'id DEPUIS LA MÊME ROW
        # qui produit le name. Le map exercise_ids capturé ci-dessous a donc les
        # mêmes strings-clés que exercises {name: scheme}, invariant garanti par
        # construction. Aucune query séparée qui pourrait diverger.
        q = db_core._client.table("program_sessions").select(
            "id, name, order_index, "
            "program_blocks(id, type, order_index, hiit_config, "
            "program_block_exercises(scheme, order_index, exercises(id, name)))"
        ).order("order_index")
        if program_id:
            q = q.eq("program_id", program_id)
        sessions = q.execute().data or []
        if not sessions:
            return {}
        program: dict = {}
        for session in sorted(sessions, key=lambda s: s.get("order_index", 0)):
            sname = session["name"]
            built_blocks = []
            blocks_data = sorted(
                session.get("program_blocks") or [],
                key=lambda b: b.get("order_index", 0),
            )
            for block in blocks_data:
                btype  = block.get("type", "strength")
                border = block.get("order_index", 0)
                if btype in REPS_BLOCKS:
                    ex_rows = sorted(
                        block.get("program_block_exercises") or [],
                        key=lambda e: e.get("order_index", 0),
                    )
                    exercises = {}
                    exercise_ids = {}
                    for r in ex_rows:
                        ex_join = r.get("exercises") or {}
                        name = ex_join.get("name")
                        ex_id = ex_join.get("id")
                        if not name:
                            continue
                        exercises[name] = r.get("scheme", "3x8-12")
                        if ex_id:
                            exercise_ids[name] = ex_id
                    built_blocks.append({
                        "type": btype, "order": border,
                        "exercises": exercises,
                        "exercise_ids": exercise_ids,
                    })
                else:
                    built_blocks.append({"type": btype, "order": border,
                                         "hiit_config": block.get("hiit_config") or {}})
            program[sname] = {"blocks": built_blocks}
        return program

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_full_program retry error: %s", e2)
                return None
        db_core.logger.error("get_full_program error: %s", e)
        return None


def get_session_supersets(program_id: str | None = None) -> dict:
    """Return superset structure for all sessions of a program.

    Shape: {session_name: {"SS1": {"A": ex_name, "B": ex_name, "rest": int}, ...}}
    Only exercises with superset_group set are included.
    Returns {} on error or if no superset data exists.
    """
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return {}

    def _do() -> dict:
        q = db_core._client.table("program_sessions").select("id, name")
        if program_id:
            q = q.eq("program_id", program_id)
        sessions = (q.order("order_index").execute().data) or []
        result: dict = {}
        for session in sessions:
            sid, sname = session["id"], session["name"]
            blocks = (db_core._client.table("program_blocks")
                      .select("id").eq("session_id", sid).in_("type", list(REPS_BLOCKS))
                      .execute().data) or []
            ss_map: dict = {}
            for block in blocks:
                bid = block["id"]
                rows = (db_core._client.table("program_block_exercises")
                        .select("superset_group, superset_position, rest_after_superset, exercises(name)")
                        .eq("block_id", bid)
                        .not_.is_("superset_group", "null")
                        .order("order_index")
                        .execute().data) or []
                for row in rows:
                    grp     = row.get("superset_group")
                    pos     = row.get("superset_position")
                    ex_name = (row.get("exercises") or {}).get("name")
                    if not grp or not ex_name:
                        continue
                    if grp not in ss_map:
                        ss_map[grp] = {}
                    if pos == 1:
                        ss_map[grp]["A"] = ex_name
                    elif pos == 2:
                        ss_map[grp]["B"] = ex_name
                        ss_map[grp]["rest"] = 120
            if ss_map:
                result[sname] = ss_map
        return result

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_session_supersets retry error: %s", e2)
                return {}
        db_core.logger.error("get_session_supersets error: %s", e)
        return {}


def reorder_program_sessions(session_names: list, program_id: str) -> bool:
    """Update order_index for each session by its position in session_names."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        for idx, name in enumerate(session_names):
            (db_core._client.table("program_sessions")
             .update({"order_index": idx})
             .eq("program_id", program_id)
             .eq("name", name)
             .execute())
        return True

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("reorder_program_sessions retry error: %s", e2)
                return False
        db_core.logger.error("reorder_program_sessions error: %s", e)
        return False


def save_full_program(program: dict, program_id: str | None = None) -> bool:
    """Persist {session_name: {"blocks": [...]}} to relational tables.

    If program_id is None, uses the first/oldest program.
    For each session: upsert program_sessions, upsert program_blocks,
    delete + reinsert program_block_exercises.
    Returns True on full success, False on any error.
    """
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False
    if program_id is None:
        program_id = get_default_program_id()

    def _do() -> bool:
        for order_idx, (session_name, session_def) in enumerate(program.items()):
            # Upsert session (conflict on program_id + name after migration)
            upsert_data: dict = {"name": session_name, "order_index": order_idx}
            if program_id:
                upsert_data["program_id"] = program_id
            sess_resp = (
                db_core._client.table("program_sessions")
                .upsert(upsert_data, on_conflict="program_id,name")
                .execute()
            )
            # Fetch session id
            q = db_core._client.table("program_sessions").select("id").eq("name", session_name)
            if program_id:
                q = q.eq("program_id", program_id)
            sess_row = q.single().execute()
            if not sess_row.data:
                db_core.logger.error("save_full_program: session %s not found after upsert", session_name)
                continue
            session_id = sess_row.data["id"]

            blocks = session_def.get("blocks", [])
            for block in sorted(blocks, key=lambda b: b.get("order", 0)):
                btype = block.get("type", "strength")
                border = block.get("order", 0)
                hiit_cfg = block.get("hiit_config", {})

                # Upsert block (match by session_id + type + order_index)
                existing_block = (
                    db_core._client.table("program_blocks")
                    .select("id")
                    .eq("session_id", session_id)
                    .eq("type", btype)
                    .eq("order_index", border)
                    .execute()
                )
                if existing_block.data:
                    block_id = existing_block.data[0]["id"]
                    db_core._client.table("program_blocks").update({"hiit_config": hiit_cfg}).eq("id", block_id).execute()
                else:
                    block_resp = (
                        db_core._client.table("program_blocks")
                        .insert({"session_id": session_id, "type": btype, "order_index": border, "hiit_config": hiit_cfg})
                        .execute()
                    )
                    block_id = block_resp.data[0]["id"] if block_resp.data else None

                if not block_id or btype not in REPS_BLOCKS:
                    continue

                exercises = block.get("exercises", {})

                # Safety guard: never wipe a block that has exercises when saving 0
                # (would silently delete all exercises from program_block_exercises)
                if not exercises:
                    existing_count_resp = (
                        db_core._client.table("program_block_exercises")
                        .select("id", count="exact")
                        .eq("block_id", block_id)
                        .execute()
                    )
                    existing_count = existing_count_resp.count  # None on query error
                    if existing_count is None or existing_count > 0:
                        db_core.logger.warning(
                            "save_full_program: refusing to save 0 exercises over %d existing for block %s — skipping",
                            existing_count, block_id,
                        )
                        continue

                # Clear existing exercises for this block then reinsert
                db_core._client.table("program_block_exercises").delete().eq("block_id", block_id).execute()

                for ex_order, (ex_name, scheme) in enumerate(exercises.items()):
                    ex_id_resp = (
                        db_core._client.table("exercises")
                        .select("id")
                        .eq("name", ex_name)
                        .execute()
                    )
                    if not ex_id_resp.data:
                        # Auto-create exercise in inventory with defaults so nothing is lost
                        ins = db_core._client.table("exercises").insert({
                            "name": ex_name,
                            "type": "machine",
                            "category": "strength",
                            "increment": 5.0,
                            "default_scheme": scheme,
                        }).execute()
                        if not ins.data:
                            db_core.logger.warning("save_full_program: could not create exercise '%s', skipping", ex_name)
                            continue
                        ex_id = ins.data[0]["id"]
                    else:
                        ex_id = ex_id_resp.data[0]["id"]
                    db_core._client.table("program_block_exercises").insert({
                        "block_id": block_id,
                        "exercise_id": ex_id,
                        "scheme": scheme,
                        "order_index": ex_order,
                    }).execute()

        return True

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("save_full_program retry error: %s", e2)
                return False
        db_core.logger.error("save_full_program error: %s", e)
        return False


def delete_program_session(name: str) -> bool:
    """Delete a programme session and all its data (blocks, exercises, schedule refs)."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        resp = db_core._client.table("program_sessions").select("id").eq("name", name).limit(1).execute()
        if not resp.data:
            return True  # already gone
        session_id = resp.data[0]["id"]
        # Clear schedule references first (FK)
        db_core._client.table("weekly_schedule").delete().eq("session_id", session_id).execute()
        # Fetch and delete block exercises, then blocks
        blocks_resp = db_core._client.table("program_blocks").select("id").eq("session_id", session_id).execute()
        for block in (blocks_resp.data or []):
            db_core._client.table("program_block_exercises").delete().eq("block_id", block["id"]).execute()
        db_core._client.table("program_blocks").delete().eq("session_id", session_id).execute()
        db_core._client.table("program_sessions").delete().eq("id", session_id).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("delete_program_session retry error: %s", e2)
                return False
        db_core.logger.error("delete_program_session error: %s", e)
        return False


def get_relational_week_schedule() -> dict:
    """Return {"Lun": "Push A", "Mar": "Pull A", ...} from weekly_schedule JOIN program_sessions.

    Days with no session assigned are omitted.
    Returns {} if relational layer is unavailable.
    """
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return {}

    def _do() -> dict:
        resp = (
            db_core._client.table("weekly_schedule")
            .select("day_name, program_sessions(name)")
            .eq("slot", "morning")
            .execute()
        )
        result: dict = {}
        for row in (resp.data or []):
            session = row.get("program_sessions")
            if session and session.get("name"):
                result[row["day_name"]] = session["name"]
            else:
                # Explicit Repos — must be included so callers don't fall back to hardcoded SCHEDULE
                result[row["day_name"]] = "Repos"
        return result

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_relational_week_schedule retry error: %s", e2)
                return {}
        db_core.logger.error("get_relational_week_schedule error: %s", e)
        return {}


def set_relational_week_schedule(schedule: dict) -> bool:
    """Upsert weekly_schedule. schedule = {"Lun": "Push A", "Mar": None, ...}.

    None / missing session_name clears the day (session_id = NULL).
    Returns True on success.
    """
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        active_pid = get_active_program_id()
        for day_name, session_name in schedule.items():
            session_id = None
            if session_name:
                q = (
                    db_core._client.table("program_sessions")
                    .select("id")
                    .eq("name", session_name)
                )
                if active_pid:
                    q = q.eq("program_id", active_pid)
                sess_resp = q.execute()
                if sess_resp.data:
                    session_id = sess_resp.data[0]["id"]
                else:
                    db_core.logger.warning(
                        "set_relational_week_schedule: session '%s' not found "
                        "(program_id=%s) — day '%s' will be cleared",
                        session_name, active_pid, day_name,
                    )
            db_core._client.table("weekly_schedule").upsert(
                {"day_name": day_name, "session_id": session_id, "slot": "morning"},
                on_conflict="day_name,slot",
            ).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("set_relational_week_schedule retry error: %s", e2)
                return False
        db_core.logger.error("set_relational_week_schedule error: %s", e)
        return False


def get_evening_week_schedule() -> dict:
    """Return {"Lun": "Core", ...} for slot='evening' from weekly_schedule."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return {}

    def _do() -> dict:
        resp = (
            db_core._client.table("weekly_schedule")
            .select("day_name, program_sessions(name)")
            .eq("slot", "evening")
            .execute()
        )
        result: dict = {}
        for row in (resp.data or []):
            session = row.get("program_sessions")
            if session and session.get("name"):
                result[row["day_name"]] = session["name"]
        return result

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_evening_week_schedule retry error: %s", e2)
                return {}
        db_core.logger.error("get_evening_week_schedule error: %s", e)
        return {}


def set_evening_week_schedule(schedule: dict) -> bool:
    """Upsert weekly_schedule for slot='evening'. None clears the day."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return False

    def _do() -> bool:
        active_pid = get_active_program_id()
        for day_name, session_name in schedule.items():
            session_id = None
            if session_name:
                q = (
                    db_core._client.table("program_sessions")
                    .select("id")
                    .eq("name", session_name)
                )
                if active_pid:
                    q = q.eq("program_id", active_pid)
                sess_resp = q.execute()
                if sess_resp.data:
                    session_id = sess_resp.data[0]["id"]
            db_core._client.table("weekly_schedule").upsert(
                {"day_name": day_name, "session_id": session_id, "slot": "evening"},
                on_conflict="day_name,slot",
            ).execute()
        return True

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("set_evening_week_schedule retry error: %s", e2)
                return False
        db_core.logger.error("set_evening_week_schedule error: %s", e)
        return False
