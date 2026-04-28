# api/utils.py — shared helpers used by blueprints and index.py
from __future__ import annotations
import os, re as _re
from datetime import datetime, date, timedelta


# ── Timezone Montréal (gère l'heure d'été) ───────────────────
def _now_mtl() -> datetime:
    # 1. zoneinfo + tzdata
    try:
        from zoneinfo import ZoneInfo
        return datetime.now(ZoneInfo("America/Montreal"))
    except Exception:
        pass
    # 2. pytz
    try:
        import pytz
        return datetime.now(pytz.timezone("America/Montreal"))
    except Exception:
        pass
    # 3. Calcul DST manuel (aucune dépendance)
    from datetime import timezone, timedelta as td
    utc = datetime.now(timezone.utc)
    def nth_sunday(y, m, n):
        first = datetime(y, m, 1)
        return first + td(days=(6 - first.weekday()) % 7 + 7 * (n - 1))
    y = utc.year
    dst_start = nth_sunday(y, 3,  2).replace(hour=7, tzinfo=timezone.utc)
    dst_end   = nth_sunday(y, 11, 1).replace(hour=6, tzinfo=timezone.utc)
    offset = -4 if dst_start <= utc < dst_end else -5
    return utc.astimezone(timezone(td(hours=offset)))

def _today_mtl() -> str:
    return _now_mtl().strftime("%Y-%m-%d")


def cap_scheme_sets(scheme: str, max_sets: int = 3) -> str:
    """Cap the set count in a scheme string. '4x8' → '3x8', '3x8-12' unchanged."""
    m = _re.match(r'^(\d+)(x.+)$', scheme or "", _re.IGNORECASE)
    return f"{max_sets}{m.group(2)}" if m and int(m.group(1)) > max_sets else (scheme or "")


# ── Rate limiting for Anthropic AI routes ─────────────────────────────────────
# Stored in Supabase so the limit is shared across all Vercel workers.
# Table: ai_rate_limit (hour_key TEXT PRIMARY KEY, count INTEGER DEFAULT 0)
# Schema: CREATE TABLE IF NOT EXISTS ai_rate_limit (hour_key TEXT PRIMARY KEY, count INTEGER NOT NULL DEFAULT 0);
_AI_MAX_TOKENS = 10  # calls per hour

def _ai_rate_check() -> bool:
    """Return True if the request is allowed, False if rate limited.
    Uses Supabase for cross-worker consistency on Vercel."""
    from datetime import timezone
    hour_key = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H")
    try:
        import db as _db
        client = _db._client
        if client is None:
            return True  # offline mode — allow
        # Read current count for this hour
        resp = client.table("ai_rate_limit").select("count").eq("hour_key", hour_key).limit(1).execute()
        current = resp.data[0]["count"] if resp.data else 0
        if current >= _AI_MAX_TOKENS:
            return False
        # Increment (slight race window acceptable at this scale)
        client.table("ai_rate_limit").upsert(
            {"hour_key": hour_key, "count": current + 1},
            on_conflict="hour_key",
        ).execute()
        return True
    except Exception:
        return True  # fail open — better to allow than block on infra error


# ── Input validation ─────────────────────────────────────────

def require_fields(data: dict, *fields: str):
    """Return (data, None) when all fields are present and non-None/empty.
    Return (None, (response, status)) when any field is missing — caller should
    immediately return the error tuple:
        data, err = require_fields(body, "exercise", "reps")
        if err: return err
    """
    from flask import jsonify
    missing = [f for f in fields if not data.get(f) and data.get(f) != 0]
    if missing:
        return None, (jsonify({"error": f"Champs requis manquants : {', '.join(missing)}"}), 400)
    return data, None


# ── Helpers ─────────────────────────────────────────────────

def get_current_week() -> int:
    """Week number since user creation. Reads created_at from user_profile; falls back to 2026-03-03."""
    try:
        import db as _db
        profile     = _db.get_profile()
        created_str = (profile.get("created_at") or "2026-03-03T00:00:00")[:10]
        start       = date.fromisoformat(created_str)
    except Exception:
        start = date(2026, 3, 3)
    delta = date.today() - start
    return max(1, (delta.days // 7) + 1)


def get_mesocycle_info() -> dict:
    """Return mesocycle week + phase derived from programs.cycle_start_date.

    Falls back to 2026-04-25 (UL/PPL v1 start) if unset.
    """
    try:
        import db as _db
        start_str = _db.get_cycle_start_date() or "2026-04-25"
        start = date.fromisoformat(start_str[:10])
    except Exception:
        start = date(2026, 4, 25)

    week = max(1, ((date.today() - start).days // 7) + 1)

    if week <= 2:
        phase, phase_label, rpe_target = "Mise en place", "S1–S2", "7"
        note = "Apprends les mouvements. Tempo contrôlé. Ne cherche pas l'échec."
    elif week <= 4:
        phase, phase_label, rpe_target = "Accumulation", "S3–S4", "8"
        note = "Pousse les reps vers le haut de la fourchette. Charge stable."
    elif week <= 6:
        phase, phase_label, rpe_target = "Surcharge", "S5–S6", "8–9"
        note = "Plafond atteint sur TOUTES les séries → +2.5 kg composés / +1.25 kg isolation."
    elif week == 7:
        phase, phase_label, rpe_target = "Deload", "S7", "5–6"
        note = "−1 série par superset. 70% de la charge S6. Obligatoire."
    else:
        phase, phase_label, rpe_target = "Nouveau cycle", "S8+", "7"
        note = "Charges de S5 + 5%. Nouvelle base, nouveau plafond."

    return {
        "week": week,
        "phase": phase,
        "phase_label": phase_label,
        "rpe_target": rpe_target,
        "note": note,
    }


def allowed_file(filename):
    ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'gif'}
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS


def load_hiit_log_local() -> list:
    import db as _db
    return _db.get_hiit_logs() or []


# ── Scheme / Muscle helpers ───────────────────────────────────

def _parse_scheme(scheme: str) -> tuple[int, int, int]:
    """Parse '3x8-10' or '4×6' → (sets, rep_min, rep_max). Defaults: (3, 8, 12)."""
    m = _re.match(r'(\d+)\s*[xX×]\s*(\d+)(?:\s*[-–]\s*(\d+))?', scheme or "")
    if m:
        sets = max(1, min(int(m.group(1)), 8))
        rmin = int(m.group(2))
        rmax = int(m.group(3)) if m.group(3) else rmin
        return sets, rmin, rmax
    return 3, 8, 12


_MUSCLE_ALIASES: dict = {
    # Quads
    "quads":           "quadriceps",
    "quad":            "quadriceps",
    # Delts
    "delts":           "deltoids",
    "delt":            "deltoids",
    "shoulders":       "deltoids",
    "shoulder":        "deltoids",
    "anterior deltoid":"deltoids",
    "lateral deltoid": "deltoids",
    "rear deltoid":    "deltoids",
    # Chest
    "pectorals":       "chest",
    "pectoral":        "chest",
    "upper chest":     "chest",
    "lower chest":     "chest",
    "pecs":            "chest",
    # Traps
    "traps":           "trapezius",
    "trap":            "trapezius",
    # Back
    "upper back":      "lats",
    "rhomboids":       "lats",
    # Calves
    "calf":            "calves",
    # Arms
    "brachialis":      "biceps",
    "brachioradialis": "biceps",
    "avant bras":      "forearms",
    # External rotators → rear deltoid canonical
    "external rotators": "rear delt",
    # Core
    "abdominaux":          "core",
    "abdominaux obliques": "core",
    "gainage":             "core",
    "abs":                 "core",
}

def _normalize_muscle(name: str) -> str:
    return _MUSCLE_ALIASES.get(name.lower().strip(), name.lower().strip())


# Weekly set landmarks per muscle (MEV/MAV/MRV — Israetel et al.)
# Keys match _normalize_muscle() output
MUSCLE_LANDMARKS: dict[str, dict] = {
    "chest":      {"mev": 8,  "mav": 16, "mrv": 22},
    "lats":       {"mev": 10, "mav": 18, "mrv": 25},
    "deltoids":   {"mev": 8,  "mav": 16, "mrv": 22},
    "rear delt":  {"mev": 6,  "mav": 14, "mrv": 20},
    "trapezius":  {"mev": 4,  "mav": 12, "mrv": 18},
    "biceps":     {"mev": 6,  "mav": 14, "mrv": 20},
    "triceps":    {"mev": 6,  "mav": 14, "mrv": 18},
    "quadriceps": {"mev": 8,  "mav": 16, "mrv": 22},
    "hamstrings": {"mev": 6,  "mav": 12, "mrv": 16},
    "fessiers":     {"mev": 4,  "mav": 12, "mrv": 16},
    "calves":     {"mev": 8,  "mav": 16, "mrv": 20},
    "abs":        {"mev": 4,  "mav": 16, "mrv": 25},
    "forearms":   {"mev": 4,  "mav": 10, "mrv": 14},
}


def _calc_weekly_sets_per_muscle(weights: dict, inventory: dict) -> dict[str, int]:
    """Count direct hard sets per muscle group logged in the last 7 days."""
    from datetime import date, timedelta
    from progression import parse_reps
    cutoff = (date.today() - timedelta(days=7)).isoformat()
    weekly: dict[str, int] = {}
    for ex_name, ex_data in weights.items():
        raw_muscles = (inventory.get(ex_name) or {}).get("muscles") or []
        muscles = [_normalize_muscle(m) for m in raw_muscles]
        if not muscles:
            continue
        for entry in ex_data.get("history", []):
            d = entry.get("date") or ""
            if d < cutoff:
                break  # history is newest-first
            if entry.get("sets"):
                n_sets = len(entry["sets"])
            else:
                try:
                    n_sets = len(parse_reps(entry.get("reps") or ""))
                except Exception:
                    n_sets = 1
            for muscle in muscles:
                weekly[muscle] = weekly.get(muscle, 0) + n_sets
    return weekly


def _calc_muscle_stats(sessions: dict, weights: dict, inventory: dict) -> dict:
    """Compute per-muscle volume from weights history × inventory muscles.

    sessions.exos is unreliable (often empty in relational layer), so we
    derive exercise dates directly from weights history entries.

    Muscle names are normalized via _MUSCLE_ALIASES to merge duplicates
    (e.g. 'quads' + 'quadriceps' → 'quadriceps').

    Returns {muscle: {volume, sessions, last_date}}.
    """
    from progression import parse_reps
    muscle_data: dict = {}
    # Track which muscles were hit per date to avoid double-counting sessions
    date_muscles_seen: dict = {}

    for ex_name, ex_data in weights.items():
        raw_muscles = (inventory.get(ex_name) or {}).get("muscles") or []
        muscles = [_normalize_muscle(m) for m in raw_muscles]
        if not muscles:
            continue
        history = ex_data.get("history") or []
        for entry in history:
            date      = entry.get("date", "")
            if not date:
                continue
            w         = float(entry.get("weight") or 0)
            reps_list = parse_reps(entry.get("reps") or "")
            vol       = round(w * sum(reps_list), 2) if w > 0 and reps_list else 0.0

            for muscle in muscles:
                if muscle not in muscle_data:
                    muscle_data[muscle] = {"volume": 0.0, "sessions": 0, "last_date": ""}
                muscle_data[muscle]["volume"] = round(muscle_data[muscle]["volume"] + vol, 2)
                # Count one session per (muscle, date) pair
                key = (muscle, date)
                if key not in date_muscles_seen:
                    date_muscles_seen[key] = True
                    muscle_data[muscle]["sessions"] += 1
                if date > muscle_data[muscle]["last_date"]:
                    muscle_data[muscle]["last_date"] = date
    return muscle_data
