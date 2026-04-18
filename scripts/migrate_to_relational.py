#!/usr/bin/env python3
"""
One-time migration: Supabase KV table → relational tables.
Run with: python migrate_to_relational.py
Requires: SUPABASE_URL and SUPABASE_ANON_KEY env vars.
Safe to run multiple times (uses ON CONFLICT DO NOTHING / DO UPDATE).
"""

from __future__ import annotations
import os
import sys
import json
import uuid
import logging
from datetime import datetime
from typing import Any, Optional

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)
logger = logging.getLogger("migrate")

SUPABASE_URL = os.environ["SUPABASE_URL"]
SUPABASE_KEY = os.environ["SUPABASE_ANON_KEY"]

try:
    from supabase import create_client, Client
except ImportError:
    logger.error("supabase-py not installed. Run: pip install supabase")
    sys.exit(1)

client: Client = create_client(SUPABASE_URL, SUPABASE_KEY)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def fetch_kv(key: str) -> Any:
    """Fetch a value from the kv table by key. Returns None if missing."""
    try:
        resp = client.table("kv").select("value").eq("key", key).single().execute()
        return resp.data["value"] if resp.data else None
    except Exception as e:
        logger.warning("fetch_kv(%s) error: %s", key, e)
        return None


def safe_int(val: Any) -> Optional[int]:
    try:
        return int(val) if val is not None else None
    except (ValueError, TypeError):
        return None


def safe_float(val: Any) -> Optional[float]:
    try:
        return float(val) if val is not None else None
    except (ValueError, TypeError):
        return None


def safe_str(val: Any) -> Optional[str]:
    return str(val) if val not in (None, "", "None") else None


def now_iso() -> str:
    return datetime.utcnow().isoformat() + "Z"


def get_or_create_exercise_id(name: str) -> Optional[str]:
    """Return the UUID of an exercise by name, creating a minimal row if absent."""
    try:
        resp = client.table("exercises").select("id").eq("name", name).single().execute()
        if resp.data:
            return resp.data["id"]
    except Exception:
        pass
    # Not found — insert minimal row
    try:
        resp = client.table("exercises").insert({"name": name}).execute()
        if resp.data:
            logger.info("  Created exercise: %s", name)
            return resp.data[0]["id"]
    except Exception as e:
        logger.warning("  Could not create exercise '%s': %s", name, e)
    return None


def get_or_create_session_id(date: str, is_second: bool = False) -> Optional[str]:
    """Return the UUID of a workout_session by date, creating a minimal row if absent."""
    try:
        resp = (
            client.table("workout_sessions")
            .select("id")
            .eq("date", date)
            .eq("is_second", is_second)
            .single()
            .execute()
        )
        if resp.data:
            return resp.data["id"]
    except Exception:
        pass
    try:
        resp = client.table("workout_sessions").insert({
            "date": date,
            "is_second": is_second,
            "logged_at": now_iso(),
        }).execute()
        if resp.data:
            return resp.data[0]["id"]
    except Exception as e:
        logger.warning("  Could not create workout_session for %s: %s", date, e)
    return None


def upsert_rows(table: str, rows: list[dict], on_conflict: str = "") -> int:
    """Bulk upsert rows into a table. Returns count of rows processed."""
    if not rows:
        return 0
    try:
        kwargs: dict = {}
        if on_conflict:
            kwargs["on_conflict"] = on_conflict
        resp = client.table(table).upsert(rows, **kwargs).execute()
        count = len(resp.data) if resp.data else len(rows)
        logger.info("  Upserted %d rows into %s", count, table)
        return count
    except Exception as e:
        logger.error("  upsert_rows(%s) error: %s", table, e)
        return 0


# ---------------------------------------------------------------------------
# 1. Exercises  (inventory KV → exercises table)
# ---------------------------------------------------------------------------

def migrate_exercises() -> None:
    logger.info("=== Migrating exercises (inventory) ===")
    inventory: dict = fetch_kv("inventory") or {}
    if not inventory:
        logger.info("  No inventory found, skipping.")
        return

    rows = []
    for name, info in inventory.items():
        if not isinstance(info, dict):
            info = {}
        row: dict = {"name": name}
        for field in ("type", "category", "pattern", "level", "tips",
                      "default_scheme"):
            val = info.get(field) or info.get(field.replace("_", ""))
            if val is not None:
                row[field] = str(val)
        if "muscles" in info and isinstance(info["muscles"], list):
            row["muscles"] = info["muscles"]
        if "increment" in info:
            row["increment"] = safe_float(info["increment"])
        if "bar_weight" in info or "barWeight" in info:
            row["bar_weight"] = safe_float(info.get("bar_weight") or info.get("barWeight", 0))
        rows.append(row)

    # Insert one by one to handle conflicts gracefully
    created = 0
    for row in rows:
        try:
            client.table("exercises").upsert(row, on_conflict="name").execute()
            created += 1
        except Exception as e:
            logger.warning("  Could not upsert exercise '%s': %s", row.get("name"), e)
    logger.info("  Processed %d exercises.", created)


# ---------------------------------------------------------------------------
# 2. Program  (program KV → program_sessions + program_blocks + program_block_exercises)
# ---------------------------------------------------------------------------

def migrate_program() -> None:
    logger.info("=== Migrating program ===")
    program: dict = fetch_kv("program") or {}
    if not program:
        logger.info("  No program found, skipping.")
        return

    for order_idx, (session_name, session_def) in enumerate(program.items()):
        if not isinstance(session_def, dict):
            continue

        # Upsert session
        try:
            resp = (
                client.table("program_sessions")
                .upsert({"name": session_name, "order_index": order_idx}, on_conflict="name")
                .execute()
            )
            session_id = resp.data[0]["id"] if resp.data else None
            if not session_id:
                resp2 = client.table("program_sessions").select("id").eq("name", session_name).single().execute()
                session_id = resp2.data["id"] if resp2.data else None
        except Exception as e:
            logger.warning("  Could not upsert session '%s': %s", session_name, e)
            continue

        if not session_id:
            logger.warning("  Skipping session '%s' (no ID)", session_name)
            continue

        # Determine blocks
        if "blocks" in session_def and isinstance(session_def["blocks"], list):
            blocks_raw = session_def["blocks"]
        else:
            # Legacy flat format: treat entire dict as a strength block
            blocks_raw = [{"type": "strength", "order": 0, "exercises": session_def}]

        for block_raw in blocks_raw:
            if not isinstance(block_raw, dict):
                continue
            block_type = block_raw.get("type", "strength")
            block_order = safe_int(block_raw.get("order", 0)) or 0
            hiit_cfg = block_raw.get("hiit_config", {})
            if block_type == "cardio":
                hiit_cfg = block_raw.get("cardio_config", {})

            try:
                resp = (
                    client.table("program_blocks")
                    .insert({
                        "session_id": session_id,
                        "type": block_type,
                        "order_index": block_order,
                        "hiit_config": hiit_cfg or {},
                    })
                    .execute()
                )
                block_id = resp.data[0]["id"] if resp.data else None
            except Exception as e:
                logger.warning("  Could not insert block for session '%s': %s", session_name, e)
                continue

            if not block_id or block_type != "strength":
                continue

            # Insert exercises for strength block
            exercises_dict = block_raw.get("exercises", {})
            if not isinstance(exercises_dict, dict):
                continue

            for ex_order, (ex_name, scheme) in enumerate(exercises_dict.items()):
                exercise_id = get_or_create_exercise_id(ex_name)
                if not exercise_id:
                    continue
                try:
                    client.table("program_block_exercises").upsert(
                        {
                            "block_id": block_id,
                            "exercise_id": exercise_id,
                            "scheme": safe_str(scheme),
                            "order_index": ex_order,
                        },
                        on_conflict="block_id,exercise_id",
                    ).execute()
                except Exception as e:
                    logger.warning("  Could not upsert program exercise '%s': %s", ex_name, e)

    logger.info("  Program migration complete.")


# ---------------------------------------------------------------------------
# 3. Workout sessions + exercise logs  (sessions KV + weights KV)
# ---------------------------------------------------------------------------

def migrate_workout_sessions() -> None:
    logger.info("=== Migrating workout sessions + exercise logs ===")
    sessions: dict = fetch_kv("sessions") or {}
    weights: dict = fetch_kv("weights") or {}

    if not sessions and not weights:
        logger.info("  No sessions or weights found, skipping.")
        return

    # Build {date: session_id} mapping after upserting each session
    date_to_session_id: dict[str, str] = {}

    for date_str, entry in sessions.items():
        if not isinstance(entry, dict):
            continue
        row: dict = {
            "date": date_str,
            "is_second": False,
            "logged_at": entry.get("logged_at") or now_iso(),
        }
        if entry.get("rpe") is not None:
            row["rpe"] = safe_int(entry["rpe"])
        if entry.get("comment"):
            row["comment"] = safe_str(entry["comment"])
        if entry.get("duration_min") is not None:
            row["duration_min"] = safe_int(entry["duration_min"])
        if entry.get("energy_pre") is not None:
            row["energy_pre"] = safe_int(entry["energy_pre"])

        try:
            resp = (
                client.table("workout_sessions")
                .upsert(row, on_conflict="date,is_second")
                .execute()
            )
            session_id = resp.data[0]["id"] if resp.data else None
            if not session_id:
                resp2 = (
                    client.table("workout_sessions")
                    .select("id")
                    .eq("date", date_str)
                    .eq("is_second", False)
                    .single()
                    .execute()
                )
                session_id = resp2.data["id"] if resp2.data else None
            if session_id:
                date_to_session_id[date_str] = session_id
        except Exception as e:
            logger.warning("  Could not upsert workout_session %s: %s", date_str, e)

    logger.info("  Upserted %d workout sessions.", len(date_to_session_id))

    # Migrate exercise logs from weights KV
    log_count = 0
    for exercise_name, ex_data in weights.items():
        if not isinstance(ex_data, dict):
            continue
        history = ex_data.get("history", [])
        if not isinstance(history, list):
            continue

        exercise_id = get_or_create_exercise_id(exercise_name)
        if not exercise_id:
            continue

        for entry in history:
            if not isinstance(entry, dict):
                continue
            date_str = entry.get("date")
            if not date_str:
                continue

            session_id = date_to_session_id.get(date_str)
            if not session_id:
                # Session not in KV sessions — create minimal session row
                session_id = get_or_create_session_id(date_str, is_second=False)
                if session_id:
                    date_to_session_id[date_str] = session_id

            if not session_id:
                continue

            weight_val = safe_float(entry.get("weight"))
            reps_val = safe_str(entry.get("reps"))

            # Do NOT store 1rm or volume — those are derived fields
            try:
                client.table("exercise_logs").upsert(
                    {
                        "session_id": session_id,
                        "exercise_id": exercise_id,
                        "weight": weight_val,
                        "reps": reps_val,
                    },
                    on_conflict="session_id,exercise_id",
                ).execute()
                log_count += 1
            except Exception as e:
                logger.warning(
                    "  Could not upsert exercise_log (%s / %s): %s",
                    exercise_name, date_str, e,
                )

    logger.info("  Upserted %d exercise log entries.", log_count)


# ---------------------------------------------------------------------------
# 4. HIIT logs  (hiit_log KV → hiit_logs table)
# ---------------------------------------------------------------------------

def migrate_hiit_logs() -> None:
    logger.info("=== Migrating HIIT logs ===")
    hiit_log: list = fetch_kv("hiit_log") or []
    if not hiit_log:
        logger.info("  No HIIT logs found, skipping.")
        return

    rows = []
    for entry in hiit_log:
        if not isinstance(entry, dict):
            continue
        row: dict = {
            "date": entry.get("date") or entry.get("timestamp", "")[:10],
            "session_type": safe_str(entry.get("session_type") or entry.get("type") or "HIIT") or "HIIT",
            "logged_at": entry.get("logged_at") or now_iso(),
        }
        if not row["date"]:
            continue
        for field, converter in [
            ("rounds_planned",    safe_int),
            ("rounds_completed",  safe_int),
            ("rpe",               safe_int),
            ("week",              safe_int),
            ("speed_max",         safe_float),
            ("speed_cruise",      safe_float),
        ]:
            # Try both English and French field names from the KV store
            if entry.get(field) is None:
                fr_aliases = {
                    "rounds_planned":   "rounds_planifies",
                    "rounds_completed": "rounds_completes",
                    "speed_max":        "vitesse_max",
                    "speed_cruise":     "vitesse_croisiere",
                }
                if field in fr_aliases:
                    entry = {**entry, field: entry.get(fr_aliases[field])}
            val = entry.get(field)
            if val is not None:
                row[field] = converter(val)
        for field in ("feeling", "comment"):
            val = safe_str(entry.get(field))
            if val:
                row[field] = val
        is_second = bool(entry.get("is_second", False))
        row["is_second"] = is_second
        rows.append(row)

    if rows:
        try:
            client.table("hiit_logs").insert(rows).execute()
            logger.info("  Inserted %d HIIT log entries.", len(rows))
        except Exception as e:
            logger.error("  HIIT log bulk insert error: %s — trying one by one.", e)
            count = 0
            for row in rows:
                try:
                    client.table("hiit_logs").insert(row).execute()
                    count += 1
                except Exception as e2:
                    logger.warning("  Skipped HIIT entry: %s", e2)
            logger.info("  Inserted %d HIIT log entries (individual).", count)


# ---------------------------------------------------------------------------
# 5. Body weight  (body_weight KV → body_weight_logs table)
# ---------------------------------------------------------------------------

def migrate_body_weight() -> None:
    logger.info("=== Migrating body weight logs ===")
    body_weight: list = fetch_kv("body_weight") or []
    if not body_weight:
        logger.info("  No body weight data found, skipping.")
        return

    rows = []
    seen_dates: set[str] = set()
    for entry in body_weight:
        if not isinstance(entry, dict):
            continue
        date_str = entry.get("date")
        weight_val = safe_float(entry.get("poids") or entry.get("weight"))
        if not date_str or weight_val is None:
            continue
        if date_str in seen_dates:
            continue  # keep first occurrence (newest due to insert(0, ...) pattern)
        seen_dates.add(date_str)
        rows.append({
            "date": date_str,
            "weight": weight_val,
            "note": entry.get("note") or "",
        })

    upsert_rows("body_weight_logs", rows, on_conflict="date")


# ---------------------------------------------------------------------------
# 6. Recovery logs  (recovery_log KV → recovery_logs table)
# ---------------------------------------------------------------------------

def migrate_recovery() -> None:
    logger.info("=== Migrating recovery logs ===")
    recovery_log: list = fetch_kv("recovery_log") or []
    if not recovery_log:
        logger.info("  No recovery logs found, skipping.")
        return

    rows = []
    seen_dates: set[str] = set()
    for entry in recovery_log:
        if not isinstance(entry, dict):
            continue
        date_str = entry.get("date")
        if not date_str or date_str in seen_dates:
            continue
        seen_dates.add(date_str)
        row: dict = {"date": date_str}
        for field, converter in [
            ("sleep_hours", safe_float),
            ("sleep_quality", safe_int),
            ("soreness", safe_int),
            ("resting_hr", safe_int),
            ("hrv", safe_float),
            ("steps", safe_int),
        ]:
            val = entry.get(field)
            if val is not None:
                row[field] = converter(val)
        notes = safe_str(entry.get("notes"))
        if notes:
            row["notes"] = notes
        rows.append(row)

    upsert_rows("recovery_logs", rows, on_conflict="date")


# ---------------------------------------------------------------------------
# 7. Goals  (goals KV → goals table)
# ---------------------------------------------------------------------------

def migrate_goals() -> None:
    logger.info("=== Migrating goals ===")
    goals: dict = fetch_kv("goals") or {}
    if not goals:
        logger.info("  No goals found, skipping.")
        return

    count = 0
    for exercise_name, goal_data in goals.items():
        if not isinstance(goal_data, dict):
            continue
        target_weight = safe_float(
            goal_data.get("goal_weight") or goal_data.get("target_weight")
        )
        if target_weight is None:
            continue
        exercise_id = get_or_create_exercise_id(exercise_name)
        if not exercise_id:
            continue
        row: dict = {
            "exercise_id": exercise_id,
            "target_weight": target_weight,
        }
        deadline = safe_str(goal_data.get("deadline") or goal_data.get("target_date"))
        if deadline:
            row["target_date"] = deadline
        try:
            client.table("goals").upsert(row, on_conflict="exercise_id").execute()
            count += 1
        except Exception as e:
            logger.warning("  Could not upsert goal for '%s': %s", exercise_name, e)

    logger.info("  Migrated %d goals.", count)


# ---------------------------------------------------------------------------
# 8. Cardio logs  (cardio_log KV → cardio_logs table)
# ---------------------------------------------------------------------------

def migrate_cardio() -> None:
    logger.info("=== Migrating cardio logs ===")
    cardio_log: list = fetch_kv("cardio_log") or []
    if not cardio_log:
        logger.info("  No cardio logs found, skipping.")
        return

    rows = []
    for entry in cardio_log:
        if not isinstance(entry, dict):
            continue
        date_str = entry.get("date")
        type_str = safe_str(entry.get("type") or entry.get("cardio_type"))
        if not date_str or not type_str:
            continue
        row: dict = {
            "date": date_str,
            "type": type_str,
            "logged_at": entry.get("logged_at") or now_iso(),
        }
        for field, converter in [
            ("duration_min", safe_int),
            ("rpe", safe_int),
            ("distance_km", safe_float),
        ]:
            val = entry.get(field)
            if val is not None:
                row[field] = converter(val)
        rows.append(row)

    if rows:
        try:
            client.table("cardio_logs").insert(rows).execute()
            logger.info("  Inserted %d cardio log entries.", len(rows))
        except Exception as e:
            logger.error("  Cardio log bulk insert error: %s — trying one by one.", e)
            count = 0
            for row in rows:
                try:
                    client.table("cardio_logs").insert(row).execute()
                    count += 1
                except Exception as e2:
                    logger.warning("  Skipped cardio entry: %s", e2)
            logger.info("  Inserted %d cardio entries (individual).", count)


# ---------------------------------------------------------------------------
# 9. User profile  (user_profile KV → user_profile table)
# ---------------------------------------------------------------------------

def migrate_user_profile() -> None:
    logger.info("=== Migrating user profile ===")
    profile: dict = fetch_kv("user_profile") or {}
    if not profile:
        logger.info("  No user profile found, skipping.")
        return

    row: dict = {"id": 1, "updated_at": now_iso()}
    field_map = {
        "name": ("name", safe_str),
        "age": ("age", safe_int),
        "sex": ("sex", safe_str),
        "weight": ("weight", safe_float),
        "height": ("height", safe_int),
        "level": ("level", safe_str),
        "goal": ("goal", safe_str),
        "units": ("units", safe_str),
        # Intentionally omit photo_b64 to avoid large payload issues during migration
    }
    for kv_key, (col, converter) in field_map.items():
        val = profile.get(kv_key)
        if val is not None:
            converted = converter(val)
            if converted is not None:
                row[col] = converted

    try:
        client.table("user_profile").upsert(row, on_conflict="id").execute()
        logger.info("  User profile migrated (photo_b64 skipped).")
    except Exception as e:
        logger.error("  Could not upsert user profile: %s", e)


# ---------------------------------------------------------------------------
# 10. Nutrition  (nutrition_settings + nutrition_log KV → tables)
# ---------------------------------------------------------------------------

def migrate_nutrition() -> None:
    logger.info("=== Migrating nutrition ===")

    # Settings
    settings: dict = fetch_kv("nutrition_settings") or {}
    if settings:
        row: dict = {"id": 1, "updated_at": now_iso()}
        if settings.get("calorie_limit") is not None:
            row["calorie_limit"] = safe_int(settings["calorie_limit"])
        if settings.get("protein_target") is not None:
            row["protein_target"] = safe_int(settings["protein_target"])
        try:
            client.table("nutrition_settings").upsert(row, on_conflict="id").execute()
            logger.info("  Nutrition settings migrated.")
        except Exception as e:
            logger.error("  Could not upsert nutrition_settings: %s", e)

    # Logs
    nutrition_log: list = fetch_kv("nutrition_log") or []
    if not nutrition_log:
        logger.info("  No nutrition log found, skipping.")
        return

    rows = []
    for entry in nutrition_log:
        if not isinstance(entry, dict):
            continue
        date_str = entry.get("date")
        food_str = safe_str(entry.get("food") or entry.get("name"))
        if not date_str or not food_str:
            continue
        row_log: dict = {
            "date": date_str,
            "food": food_str,
            "logged_at": entry.get("logged_at") or now_iso(),
        }
        for field in ("meal",):
            val = safe_str(entry.get(field))
            if val:
                row_log[field] = val
        for field, converter in [
            ("calories", safe_int),
            ("protein", safe_float),
            ("carbs", safe_float),
            ("fat", safe_float),
        ]:
            val = entry.get(field)
            if val is not None:
                row_log[field] = converter(val)
        rows.append(row_log)

    if rows:
        try:
            client.table("nutrition_logs").insert(rows).execute()
            logger.info("  Inserted %d nutrition log entries.", len(rows))
        except Exception as e:
            logger.error("  Nutrition log bulk insert error: %s — trying one by one.", e)
            count = 0
            for row in rows:
                try:
                    client.table("nutrition_logs").insert(row).execute()
                    count += 1
                except Exception as e2:
                    logger.warning("  Skipped nutrition entry: %s", e2)
            logger.info("  Inserted %d nutrition entries (individual).", count)


# ---------------------------------------------------------------------------
# 11. Mental health  (mood_log, pss_records, self_care_habits, self_care_log,
#                    journal_entries, breathwork_sessions, sleep_records,
#                    life_stress_scores KV → tables)
# ---------------------------------------------------------------------------

def migrate_mood_pss_mental() -> None:
    logger.info("=== Migrating mental health data ===")

    # mood_log
    mood_log: list = fetch_kv("mood_log") or []
    mood_rows = []
    for entry in mood_log:
        if not isinstance(entry, dict):
            continue
        date_str = entry.get("date")
        if not date_str:
            continue
        row: dict = {"date": date_str}
        score = safe_int(entry.get("score") or entry.get("mood_score"))
        if score is not None:
            row["score"] = score
        for arr_field in ("emotions", "triggers"):
            val = entry.get(arr_field)
            if isinstance(val, list):
                row[arr_field] = val
            elif isinstance(val, str) and val:
                row[arr_field] = [val]
        notes = safe_str(entry.get("notes"))
        if notes:
            row["notes"] = notes
        pss = safe_int(entry.get("pss_score_linked"))
        if pss is not None:
            row["pss_score_linked"] = pss
        mood_rows.append(row)
    if mood_rows:
        try:
            client.table("mood_logs").insert(mood_rows).execute()
            logger.info("  Inserted %d mood log entries.", len(mood_rows))
        except Exception as e:
            logger.error("  mood_logs insert error: %s", e)

    # pss_records
    pss_records_raw: list = fetch_kv("pss_records") or []
    pss_rows = []
    for entry in pss_records_raw:
        if not isinstance(entry, dict):
            continue
        date_str = entry.get("date")
        if not date_str:
            continue
        row_pss: dict = {
            "date": date_str,
            "recorded_at": entry.get("recorded_at") or now_iso(),
        }
        for field, converter in [
            ("type", safe_str),
            ("score", safe_int),
            ("max_score", safe_int),
            ("category", safe_str),
            ("category_label", safe_str),
            ("streak", safe_int),
            ("notes", safe_str),
        ]:
            val = entry.get(field)
            if val is not None:
                converted = converter(val)
                if converted is not None:
                    row_pss[field] = converted
        for arr_field in ("responses", "inverted_responses", "triggers", "insights"):
            val = entry.get(arr_field)
            if isinstance(val, list):
                row_pss[arr_field] = val
        for json_field in ("trigger_ratings",):
            val = entry.get(json_field)
            if isinstance(val, dict):
                row_pss[json_field] = val
        pss_rows.append(row_pss)
    if pss_rows:
        try:
            client.table("pss_records").insert(pss_rows).execute()
            logger.info("  Inserted %d PSS records.", len(pss_rows))
        except Exception as e:
            logger.error("  pss_records insert error: %s", e)

    # self_care_habits
    habits_raw: dict = fetch_kv("self_care_habits") or {}
    if isinstance(habits_raw, list):
        habits_raw = {h.get("id", str(i)): h for i, h in enumerate(habits_raw) if isinstance(h, dict)}
    habit_rows = []
    for habit_id, habit_data in habits_raw.items():
        if not isinstance(habit_data, dict):
            continue
        row_h: dict = {
            "id": str(habit_id),
            "name": safe_str(habit_data.get("name") or habit_id) or habit_id,
        }
        for field in ("icon", "category"):
            val = safe_str(habit_data.get(field))
            if val:
                row_h[field] = val
        row_h["is_default"] = bool(habit_data.get("is_default", False))
        row_h["order_index"] = safe_int(habit_data.get("order_index") or habit_data.get("order", 0)) or 0
        habit_rows.append(row_h)
    if habit_rows:
        try:
            client.table("self_care_habits").upsert(habit_rows).execute()
            logger.info("  Upserted %d self_care_habits.", len(habit_rows))
        except Exception as e:
            logger.error("  self_care_habits upsert error: %s", e)

    # self_care_log — stored as {"2026-03-09": ["water", "walk", ...]} in KV
    self_care_log_raw = fetch_kv("self_care_log") or {}
    sc_rows = []
    if isinstance(self_care_log_raw, dict):
        for date_str, habit_ids in self_care_log_raw.items():
            if not isinstance(habit_ids, list):
                continue
            for habit_id in habit_ids:
                if habit_id:
                    sc_rows.append({"date": date_str, "habit_id": str(habit_id)})
    else:
        # Tolerate old list-of-dicts format
        for entry in self_care_log_raw:
            if not isinstance(entry, dict):
                continue
            date_str = entry.get("date")
            habit_id = safe_str(entry.get("habit_id") or entry.get("id"))
            if date_str and habit_id:
                sc_rows.append({"date": date_str, "habit_id": habit_id})
    if sc_rows:
        try:
            client.table("self_care_logs").upsert(sc_rows, on_conflict="date,habit_id").execute()
            logger.info("  Upserted %d self_care_log entries.", len(sc_rows))
        except Exception as e:
            logger.error("  self_care_logs upsert error: %s", e)

    # journal_entries
    journal_raw: list = fetch_kv("journal_entries") or []
    journal_rows = []
    for entry in journal_raw:
        if not isinstance(entry, dict):
            continue
        date_str = entry.get("date")
        content = safe_str(entry.get("content"))
        if not date_str or not content:
            continue
        row_j: dict = {
            "date": date_str,
            "content": content,
            "created_at": entry.get("created_at") or now_iso(),
        }
        mood = safe_int(entry.get("mood_score") or entry.get("mood"))
        if mood is not None:
            row_j["mood_score"] = mood
        tags = entry.get("tags")
        if isinstance(tags, list):
            row_j["tags"] = tags
        journal_rows.append(row_j)
    if journal_rows:
        try:
            client.table("journal_entries").insert(journal_rows).execute()
            logger.info("  Inserted %d journal entries.", len(journal_rows))
        except Exception as e:
            logger.error("  journal_entries insert error: %s", e)

    # breathwork_sessions
    breathwork_raw: list = fetch_kv("breathwork_sessions") or []
    bw_rows = []
    for entry in breathwork_raw:
        if not isinstance(entry, dict):
            continue
        date_str = entry.get("date")
        if not date_str:
            continue
        row_bw: dict = {
            "date": date_str,
            "logged_at": entry.get("logged_at") or now_iso(),
        }
        for field in ("technique",):
            val = safe_str(entry.get(field))
            if val:
                row_bw[field] = val
        dur = safe_int(entry.get("duration_min") or entry.get("duration"))
        if dur is not None:
            row_bw["duration_min"] = dur
        notes = safe_str(entry.get("notes"))
        if notes:
            row_bw["notes"] = notes
        bw_rows.append(row_bw)
    if bw_rows:
        try:
            client.table("breathwork_sessions").insert(bw_rows).execute()
            logger.info("  Inserted %d breathwork sessions.", len(bw_rows))
        except Exception as e:
            logger.error("  breathwork_sessions insert error: %s", e)

    # sleep_records
    sleep_raw: list = fetch_kv("sleep_records") or []
    sleep_rows = []
    for entry in sleep_raw:
        if not isinstance(entry, dict):
            continue
        date_str = entry.get("date")
        if not date_str:
            continue
        row_sl: dict = {
            "date": date_str,
            "logged_at": entry.get("logged_at") or now_iso(),
        }
        dur = safe_float(entry.get("duration_hours") or entry.get("duration"))
        if dur is not None:
            row_sl["duration_hours"] = dur
        quality = safe_int(entry.get("quality") or entry.get("sleep_quality"))
        if quality is not None:
            row_sl["quality"] = quality
        notes = safe_str(entry.get("notes"))
        if notes:
            row_sl["notes"] = notes
        sleep_rows.append(row_sl)
    if sleep_rows:
        try:
            client.table("sleep_records").insert(sleep_rows).execute()
            logger.info("  Inserted %d sleep records.", len(sleep_rows))
        except Exception as e:
            logger.error("  sleep_records insert error: %s", e)

    # life_stress_scores — stored as {date: {...}} dict in KV, not a list
    stress_raw = fetch_kv("life_stress_scores") or {}
    if isinstance(stress_raw, list):
        # Tolerate accidental list format
        stress_raw = {e["date"]: e for e in stress_raw if isinstance(e, dict) and "date" in e}
    stress_rows = []
    seen_stress_dates: set[str] = set()
    for date_str, entry in stress_raw.items():
        if not isinstance(entry, dict):
            continue
        if date_str in seen_stress_dates:
            continue
        seen_stress_dates.add(date_str)
        entry = {**entry, "date": date_str}
        row_st: dict = {"date": date_str}
        score = safe_float(entry.get("score"))
        if score is not None:
            row_st["score"] = score
        cov = safe_float(entry.get("data_coverage"))
        if cov is not None:
            row_st["data_coverage"] = cov
        for json_field in ("flags", "components"):
            val = entry.get(json_field)
            if isinstance(val, dict):
                row_st[json_field] = val
        recs = entry.get("recommendations")
        if isinstance(recs, list):
            row_st["recommendations"] = recs
        stress_rows.append(row_st)
    if stress_rows:
        try:
            client.table("life_stress_scores").upsert(stress_rows, on_conflict="date").execute()
            logger.info("  Upserted %d life_stress_scores.", len(stress_rows))
        except Exception as e:
            logger.error("  life_stress_scores upsert error: %s", e)


# ---------------------------------------------------------------------------
# 12. Coach history  (coach_history KV → coach_history table)
# ---------------------------------------------------------------------------

def migrate_coach_history() -> None:
    logger.info("=== Migrating coach history ===")
    coach_raw: list = fetch_kv("coach_history") or []
    if not coach_raw:
        logger.info("  No coach history found, skipping.")
        return

    rows = []
    for entry in coach_raw:
        if not isinstance(entry, dict):
            continue
        row: dict = {
            "created_at": entry.get("created_at") or entry.get("timestamp") or now_iso(),
        }
        mode = safe_str(entry.get("mode") or entry.get("role"))
        if mode:
            row["mode"] = mode
        user_msg = safe_str(entry.get("user_message") or entry.get("user") or entry.get("question"))
        if user_msg:
            row["user_message"] = user_msg
        asst_resp = safe_str(
            entry.get("assistant_response")
            or entry.get("assistant")
            or entry.get("response")
            or entry.get("answer")
        )
        if asst_resp:
            row["assistant_response"] = asst_resp
        if not row.get("user_message") and not row.get("assistant_response"):
            continue
        rows.append(row)

    if rows:
        # Insert in batches of 50 to stay within payload limits
        batch_size = 50
        total = 0
        for i in range(0, len(rows), batch_size):
            batch = rows[i:i + batch_size]
            try:
                client.table("coach_history").insert(batch).execute()
                total += len(batch)
            except Exception as e:
                logger.error("  coach_history batch insert error: %s", e)
        logger.info("  Inserted %d coach history entries.", total)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

if __name__ == "__main__":
    logger.info("Starting TrainingOS KV → relational migration...")
    migrate_exercises()
    migrate_program()
    migrate_workout_sessions()
    migrate_hiit_logs()
    migrate_body_weight()
    migrate_recovery()
    migrate_goals()
    migrate_cardio()
    migrate_user_profile()
    migrate_nutrition()
    migrate_mood_pss_mental()
    migrate_coach_history()
    logger.info("Migration complete.")
