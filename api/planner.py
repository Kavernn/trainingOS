from __future__ import annotations
import logging

from datetime import datetime
from typing import Dict, List
from blocks import make_strength_block, get_strength_exercises, sorted_blocks
from progression import suggest_next_weight

logger = logging.getLogger("trainingos.planner")


# ---------------------------------------------------------------------------
# Migration
# ---------------------------------------------------------------------------

def _migrate_session(data) -> dict:
    """Convert a legacy flat {exercise: scheme} session to the block format.

    Already-migrated sessions (containing "blocks") are returned unchanged.
    """
    if isinstance(data, dict) and "blocks" in data:
        return data
    if isinstance(data, dict):
        return {"blocks": [make_strength_block(data, order=0)]}
    return {"blocks": []}


# ---------------------------------------------------------------------------
# Persistence
# ---------------------------------------------------------------------------

def load_program() -> dict:
    """Load the program from relational tables (source of truth).

    Returns {} if Supabase is unavailable — never falls back to hardcoded data.
    """
    import db as _db
    program_id = _db.get_active_program_id()
    program = _db.get_full_program(program_id=program_id)

    if program is None:
        logger.error("load_program: Supabase unavailable — returning empty program")
        return {}

    return program


def save_program(program: dict):
    """Persist program to relational tables (source of truth)."""
    import db as _db
    _db.save_full_program(program)


# ---------------------------------------------------------------------------
# Timezone helpers (Montreal / Eastern)
# ---------------------------------------------------------------------------

def _eastern_offset_hours(utc_dt: datetime) -> int:
    """Return -4 (EDT) or -5 (EST) based on Canadian Eastern DST rules."""
    from datetime import timedelta as td

    def nth_sunday(year: int, month: int, n: int) -> datetime:
        first = datetime(year, month, 1)
        days_to_sunday = (6 - first.weekday()) % 7
        return first + td(days=days_to_sunday + 7 * (n - 1))

    y = utc_dt.year
    from datetime import timezone
    utc = timezone.utc
    dst_start = nth_sunday(y, 3,  2).replace(hour=7,  tzinfo=utc)
    dst_end   = nth_sunday(y, 11, 1).replace(hour=6,  tzinfo=utc)
    return -4 if dst_start <= utc_dt < dst_end else -5


def _montreal_now() -> datetime:
    try:
        from zoneinfo import ZoneInfo
        return datetime.now(ZoneInfo("America/Montreal"))
    except Exception:
        pass
    try:
        import pytz
        return datetime.now(pytz.timezone("America/Montreal"))
    except Exception:
        pass
    from datetime import timezone, timedelta
    utc_now = datetime.now(timezone.utc)
    offset  = _eastern_offset_hours(utc_now)
    return utc_now.astimezone(timezone(timedelta(hours=offset)))


def get_today() -> str:
    import db as _db
    # Explicit user override for today (e.g. rescheduled session)
    try:
        override = _db.get_session_override()
        if override and override.get("session"):
            return override["session"]
    except Exception:
        pass
    schedule = _db.get_relational_week_schedule()
    days = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]
    day_key = days[_montreal_now().weekday()]
    if schedule:
        return schedule.get(day_key, "Repos")
    logger.error("get_today: relational schedule unavailable — returning Repos")
    return "Repos"


def get_today_date() -> str:
    return _montreal_now().strftime("%Y-%m-%d")


def get_week_schedule() -> Dict[str, str]:
    import db as _db
    return _db.get_relational_week_schedule() or {}


def get_evening_schedule() -> Dict[str, str]:
    """Return the evening schedule dict {"Lun": "Core", ...} (empty if none configured)."""
    import db as _db
    return _db.get_evening_week_schedule() or {}


def get_today_evening() -> str | None:
    """Return the evening session name for today.

    Fallback héritage : si le planning soir est vide/Repos ce jour, retombe sur
    le nom de la séance matin ("Upper A" matin → "Upper A" hérité le soir,
    affiché « (suite) » côté UI, non peuplé par défaut). Retourne None seulement
    si matin ET soir sont Repos (vrai repos). Un override manuel du planning
    soir gagne toujours sur l'héritage.
    """
    days = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]
    day_key = days[_montreal_now().weekday()]
    evening = get_evening_schedule().get(day_key)
    if evening and evening != "Repos":
        return evening
    morning = get_today()
    return morning if morning and morning != "Repos" else None


# ---------------------------------------------------------------------------
# Weight suggestions
# ---------------------------------------------------------------------------

def get_suggested_weights_for_today(weights: dict, program: dict | None = None) -> List[dict]:
    from inventory import load_inventory
    today_session = get_today()
    if program is None:
        program = load_program()
    if today_session not in program:
        return []

    inventory = load_inventory() or {}
    exercises = get_strength_exercises(program[today_session])
    result: List[dict] = []
    for exercise in exercises:
        data      = weights.get(exercise, {})
        current   = data.get("current_weight", data.get("weight", 0.0))
        last_reps = data.get("last_reps", "")

        # Derive input_type from inventory (source of truth) with KV fallback
        inv_entry  = inventory.get(exercise, {})
        inv_type   = inv_entry.get("type", "")
        if inv_type == "barbell":
            input_type = "barbell"
        elif inv_type in ("dumbbell", "cable_double"):
            input_type = "dumbbell"
        else:
            input_type = data.get("input_type", "total")

        # Use last logged RPE from history for autoregulation
        last_history = data.get("history", [])
        last_rpe: float | None = None
        if last_history and isinstance(last_history[0], dict):
            rpe_val = last_history[0].get("rpe")
            if rpe_val is not None:
                try:
                    last_rpe = float(rpe_val)
                except (TypeError, ValueError):
                    pass

        suggested, _ = suggest_next_weight(exercise, current, last_reps, last_rpe, inventory=inventory)
        if input_type == "barbell":
            bar    = inv_entry.get("bar_weight") or 45.0
            side   = (suggested - bar) / 2 if suggested >= bar else 0
            display = f"{side:.1f} par cote (total {suggested:.1f} lbs)"
        elif input_type == "dumbbell":
            display = f"{suggested/2:.1f} par haltere"
        else:
            display = f"{suggested:.1f} lbs total"
        result.append({"exercise": exercise, "display": display})
    return result


# ---------------------------------------------------------------------------
# Day plan — étape 3 flow bonus (2026-07-26) — SOURCE UNIQUE
# ---------------------------------------------------------------------------

def get_day_plan(date: str, full_program: dict) -> dict:
    """Retourne {'morning': {...}, 'evening': {...}, 'bonus': {...}} pour la date
    donnée, avec session_plan_overrides appliqués.

    SOURCE UNIQUE consommée par api_seance_data, api_seance_soir_data,
    api_seance_bonus_data, api_dashboard, _get_day_intensity,
    api_progression_suggestions. Un consommateur qui contourne cette fonction
    recrée le trou d'incohérence (récap dit A, dashboard dit B) — cf. décision
    centralisation étape 3.

    Étape 4 : ajout clé 'bonus'. Bonus n'est JAMAIS au schedule — un exo y
    arrive uniquement via override to='bonus'. Le cas from='bonus' (bidir
    bonus→matin/soir) : l'exo n'est pas dans bonus_exos initial (schedule
    ignore bonus), fallback sur morning_exos/evening_exos qui contient l'origine
    schedule de l'exo.

    Ne mute JAMAIS full_program ni le programme template. Un override est
    strictement scopé à SA date (WHERE date = ...).
    """
    import db as _db
    from blocks import get_strength_exercises

    morning_name = get_today()
    evening_name = get_today_evening()

    morning_exos = dict(get_strength_exercises(full_program.get(morning_name, {}))) if morning_name else {}
    evening_exos = dict(get_strength_exercises(full_program.get(evening_name, {}))) if evening_name else {}
    bonus_exos: dict = {}

    overrides = _db.get_session_plan_overrides(date)
    pushed_to_evening: list[str] = []
    pushed_to_morning: list[str] = []
    pushed_to_bonus: list[str] = []

    if not overrides:
        return {
            "morning": morning_exos,
            "evening": evening_exos,
            "bonus": bonus_exos,
            "pushed_to_evening": [],
            "pushed_to_morning": [],
            "pushed_to_bonus": [],
        }

    # Résolution exercise_id → name : les overrides stockent l'id, le plan
    # est keyé par name. Batch lookup, une seule query. Le nom capturé ici
    # est la MÊME string que celle du plan (même table exercises, même colonne
    # name) — garantit qu'un lecteur iOS comparant par nom (Set<String>) matche.
    ex_ids = list({o.get("exercise_id") for o in overrides if o.get("exercise_id")})
    id_to_name: dict = {}
    if ex_ids:
        try:
            resp = _db._client.table("exercises").select("id,name").in_("id", ex_ids).execute()
            id_to_name = {r["id"]: r["name"] for r in (resp.data or []) if r.get("id") and r.get("name")}
        except Exception as e:
            logger.warning("get_day_plan: exercises lookup failed: %s", e)

    for o in overrides:
        name = id_to_name.get(o.get("exercise_id"))
        if not name:
            continue
        from_slot = o.get("from_session_type")
        to_slot = o.get("to_session_type")
        # Retire l'exo de sa source, préserve son scheme
        scheme = None
        if from_slot == "morning" and name in morning_exos:
            scheme = morning_exos.pop(name)
        elif from_slot == "evening" and name in evening_exos:
            scheme = evening_exos.pop(name)
        elif from_slot == "bonus":
            # Étape 4 — bonus n'est jamais au schedule ; fallback sur schedule matin/soir
            # pour retrouver l'origine de l'exo qui était passé en bonus.
            if name in morning_exos:
                scheme = morning_exos.pop(name)
            elif name in evening_exos:
                scheme = evening_exos.pop(name)
        if scheme is None:
            continue  # exo pas dans la source attendue — override obsolète, on l'ignore
        # Ajoute à la destination + capture pour les listes exposées
        if to_slot == "morning":
            morning_exos[name] = scheme
            pushed_to_morning.append(name)
        elif to_slot == "evening":
            evening_exos[name] = scheme
            pushed_to_evening.append(name)
        elif to_slot == "bonus":
            bonus_exos[name] = scheme
            pushed_to_bonus.append(name)

    return {
        "morning": morning_exos,
        "evening": evening_exos,
        "bonus": bonus_exos,
        "pushed_to_evening": sorted(set(pushed_to_evening)),
        "pushed_to_morning": sorted(set(pushed_to_morning)),
        "pushed_to_bonus": sorted(set(pushed_to_bonus)),
    }
