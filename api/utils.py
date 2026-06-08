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

def _today_mtl_date() -> date:
    """Return today's date as a date object in Montreal timezone."""
    return date.fromisoformat(_today_mtl())

def _hour_mtl() -> int:
    return _now_mtl().hour


def get_nutrition_time_context(target_date: str | None = None) -> dict:
    """Temporal context for nutrition scoring.

    progress: 0.0 (wake) → 1.0 (nutrition end time, default 21:00)
    is_too_early:  progress < 0.20 — skip today's data to avoid false deficits
    is_end_of_day: progress > 0.80 — day is reliable enough to score fully
    """
    today = _today_mtl()
    if target_date and target_date < today:
        return {"progress": 1.0, "is_too_early": False, "is_end_of_day": True,
                "wake_time": "07:00", "end_time": "21:00", "current_hour": 23}

    now = _now_mtl()
    current_minutes = now.hour * 60 + now.minute

    wake_time_str = "07:00"
    try:
        import db as _db
        recs = _db.get_sleep_records(limit=1) or []
        if recs and recs[0].get("wake_time"):
            wake_time_str = str(recs[0]["wake_time"])[:5]
    except Exception:
        pass

    end_time_str = "21:00"
    try:
        import db as _db
        settings = _db.get_nutrition_settings() or {}
        if settings.get("nutrition_end_time"):
            end_time_str = str(settings["nutrition_end_time"])[:5]
    except Exception:
        pass

    def _hhmm_to_min(s: str) -> int:
        try:
            h, m = s.split(":")
            return int(h) * 60 + int(m)
        except Exception:
            return 0

    wake_min = _hhmm_to_min(wake_time_str)
    end_min  = _hhmm_to_min(end_time_str)
    window   = max(1, end_min - wake_min)
    elapsed  = current_minutes - wake_min
    progress = max(0.0, min(1.0, elapsed / window))

    return {
        "progress":      round(progress, 3),
        "is_too_early":  progress < 0.20,
        "is_end_of_day": progress > 0.80,
        "wake_time":     wake_time_str,
        "end_time":      end_time_str,
        "current_hour":  now.hour,
    }


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
    delta = date.fromisoformat(_today_mtl()) - start
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

    week = max(1, ((date.fromisoformat(_today_mtl()) - start).days // 7) + 1)

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


# ── Périodisation par phase (opt-in) ────────────────────────────────────────
# Seuils de hit rate et volume max ajustés selon la phase du mésocycle.
# Utilisés par smart_progression.py quand phase != None.
# Défaut (phase=None) → comportement actuel inchangé (compound 90%, isolation 100%).
#
# Source : Israetel et al. (RP Hypertrophy), NSCA Essentials of Strength Training.

_PHASE_PARAMS: dict[str, dict] = {
    "Mise en place": {
        "hit_rate_compound":  0.85,   # Tolérant — apprentissage des patterns moteurs
        "hit_rate_isolation": 0.90,
        "max_sets":           3,
        "rpe_deload_trigger": 9.0,    # Moins sensible en début de cycle
    },
    "Accumulation": {
        "hit_rate_compound":  0.90,   # Standard
        "hit_rate_isolation": 1.00,
        "max_sets":           5,      # Volume maximal du mésocycle
        "rpe_deload_trigger": 8.5,
    },
    "Surcharge": {
        "hit_rate_compound":  0.95,   # Strict — charges lourdes, chaque rep compte
        "hit_rate_isolation": 1.00,
        "max_sets":           3,      # Volume réduit, intensité haute
        "rpe_deload_trigger": 8.0,    # Sensible — on approche du max
    },
    "Deload": {
        "hit_rate_compound":  0.80,
        "hit_rate_isolation": 0.80,
        "max_sets":           2,
        "rpe_deload_trigger": 10.0,   # Jamais de trigger pendant un deload actif
    },
    "Nouveau cycle": {
        "hit_rate_compound":  0.90,
        "hit_rate_isolation": 1.00,
        "max_sets":           4,
        "rpe_deload_trigger": 8.5,
    },
}

_PHASE_PARAMS_DEFAULT: dict = {
    "hit_rate_compound":  0.90,
    "hit_rate_isolation": 1.00,
    "max_sets":           4,
    "rpe_deload_trigger": 8.5,
}


def get_phase_params(phase: str | None = None) -> dict:
    """Retourne les paramètres de progression pour la phase courante.

    Appelé par smart_progression quand la périodisation est activée.
    phase=None → paramètres par défaut (comportement actuel).
    """
    if not phase:
        return _PHASE_PARAMS_DEFAULT
    return _PHASE_PARAMS.get(phase, _PHASE_PARAMS_DEFAULT)


# ── Warm-up guidance (recommandations textuelles) ────────────────────────────
# Guidance préventive basée sur les patterns d'exercice de la séance.
# C'est une recommandation textuelle — pas de tracking, pas de blocage.

_WARMUP_GUIDANCE: dict[str, str] = {
    "squat":            "Barre vide × 10 → 50% × 5 → 70% × 3, puis working sets",
    "hinge":            "Barre vide × 10 → 50% × 5 → 70% × 3, puis working sets",
    "horizontal_push":  "Band pull-aparts × 15, barre vide × 10 → 50% × 5, puis working sets",
    "vertical_push":    "Rotations d'épaules × 15, 50% × 8 → 70% × 5, puis working sets",
    "horizontal_pull":  "Band pull-aparts × 15, 50% × 8 → 70% × 5, puis working sets",
    "vertical_pull":    "Mobilité épaules × 10, 50% × 8 → 70% × 5, puis working sets",
    "carry":            "Mobilité hanches × 10, 50% × 5, puis working sets",
    "core":             "Activation : dead bug × 10, planche 20s, puis working sets",
}

_WARMUP_DEFAULT = "2 sets progressifs : 50% × 8 puis 70% × 5 avant les working sets"


def get_warmup_guidance(patterns: list[str]) -> str:
    """Retourne une recommandation d'échauffement selon les patterns dominants de la séance.

    patterns : liste des patterns d'exercice (ex. ['horizontal_push', 'vertical_pull'])
    Retourne le guidage du premier pattern reconnu, sinon le défaut.
    """
    for p in patterns:
        if p in _WARMUP_GUIDANCE:
            return _WARMUP_GUIDANCE[p]
    return _WARMUP_DEFAULT


def allowed_file(filename):
    ALLOWED_EXTENSIONS = {'png', 'jpg', 'jpeg', 'gif'}
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS


def load_hiit_log() -> list:
    import db as _db
    return _db.get_hiit_logs(limit=200) or []


# Alias rétrocompatibilité — à supprimer quand tous les call sites sont migrés
load_hiit_log_local = load_hiit_log


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
    "delts":              "deltoids",
    "delt":               "deltoids",
    "shoulders":          "deltoids",
    "shoulder":           "deltoids",
    "anterior deltoid":   "deltoids",
    "lateral deltoid":    "deltoids",
    # rear delt — canonical key matches MUSCLE_LANDMARKS
    "rear deltoid":       "rear delt",
    "rear delts":         "rear delt",
    "posterior deltoid":  "rear delt",
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
    cutoff = (date.fromisoformat(_today_mtl()) - timedelta(days=7)).isoformat()
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


# French muscle_group → normalized English key (same keys as MUSCLE_LANDMARKS)
_MUSCLE_GROUP_FR_TO_EN: dict[str, str] = {
    "pectoraux":         "chest",
    "dos":               "lats",
    "épaules":           "deltoids",
    "épaules post.":     "rear delt",
    "biceps":            "biceps",
    "triceps":           "triceps",
    "quadriceps":        "quadriceps",
    "ischio-jambiers":   "hamstrings",
    "fessiers":          "fessiers",
    "mollets":           "calves",
    "abdominaux":        "core",
    "avant-bras":        "forearms",
    "trapèzes":          "trapezius",
}


def _calc_weekly_specific_breakdown(weights: dict, inventory: dict) -> dict[str, dict[str, int]]:
    """Return {muscle_key: {specific_name: sets}} for exercises with muscle_specific set, last 7 days.

    Used to show 'Épaules → Deltoïde postérieur: X sets' in the volume landmarks card.
    Only populated for exercises where muscle_specific is explicitly set (new taxonomy).
    """
    from datetime import date, timedelta
    from progression import parse_reps
    cutoff = (date.fromisoformat(_today_mtl()) - timedelta(days=7)).isoformat()
    result: dict[str, dict[str, int]] = {}
    for ex_name, ex_data in weights.items():
        inv = inventory.get(ex_name) or {}
        muscle_group_fr  = (inv.get("muscle_group")  or "").strip()
        muscle_specific  = (inv.get("muscle_specific") or "").strip()
        if not muscle_group_fr or not muscle_specific:
            continue
        muscle_key = _MUSCLE_GROUP_FR_TO_EN.get(muscle_group_fr.lower())
        if not muscle_key:
            continue
        for entry in ex_data.get("history", []):
            d = entry.get("date") or ""
            if d < cutoff:
                break
            if entry.get("sets"):
                n_sets = len(entry["sets"])
            else:
                try:
                    n_sets = len(parse_reps(entry.get("reps") or ""))
                except Exception:
                    n_sets = 1
            by_key = result.setdefault(muscle_key, {})
            by_key[muscle_specific] = by_key.get(muscle_specific, 0) + n_sets
    return result


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
