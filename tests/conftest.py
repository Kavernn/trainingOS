"""
Shared fixtures for TrainingOS route tests.
Provides make_store() and a BaseRouteTest class reused by all test modules.

Spec-guarded db mock (2026-07 hardening) : le db_mock retourné par make_store
lève AttributeError sur setattr d'un attribut absent du vrai module db. Attrape
les bugs mesocycle-style où un test injecte dynamiquement une méthode fantôme
(ex: `db_mod.get_active_program = MagicMock(...)` alors que la vraie API est
`get_active_program_id`) — MagicMock permissif masquait ces typos pendant des
semaines, laissant le code prod throw AttributeError capturé silencieusement.
"""
import copy
import json
import os
import sys
from unittest.mock import patch, MagicMock

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

# Capture les noms exposés par le vrai module db (243 fonctions/constantes en
# 2026-07). Utilisé par _SpecGuardedMock pour filtrer les setattr des tests.
# Fallback laissez-faire si import échoue (env incomplet) — le guard est
# désactivé mais les tests continuent à tourner.
try:
    import db as _real_db_for_spec
    _DB_SPEC_NAMES = frozenset(n for n in dir(_real_db_for_spec) if not n.startswith("__"))
except Exception:
    _DB_SPEC_NAMES = None


class _SpecGuardedMock:
    """Wrapper autour d'un MagicMock qui refuse setattr d'un attribut hors spec.

    Zéro impact sur la lecture (délègue à inner). Filtre uniquement les
    injections dynamiques `db_mod.foo = MagicMock(...)` des tests. Un attribut
    déjà configuré à l'instanciation reste accessible.
    """

    def __init__(self, inner, allowed_names):
        object.__setattr__(self, "_inner", inner)
        object.__setattr__(self, "_allowed", allowed_names)

    def __getattr__(self, name):
        return getattr(self._inner, name)

    def __setattr__(self, name, value):
        if name.startswith("_"):
            object.__setattr__(self, name, value)
            return
        if self._allowed is not None and name not in self._allowed:
            raise AttributeError(
                f"'{name}' n'est pas dans le spec du module db — typo? "
                f"(pattern mesocycle : test injecte un attribut fantôme, "
                f"MagicMock accepterait silencieusement. Vérifie le vrai nom "
                f"dans api/db_programs.py ou équivalent.)"
            )
        setattr(self._inner, name, value)

    def __delattr__(self, name):
        # Requis pour patch.object(_db, "foo") qui fait delattr au teardown
        # quand l'attribut n'était pas set en amont sur l'instance wrapper.
        delattr(self._inner, name)

    def __repr__(self):
        return f"<_SpecGuardedMock db, {len(self._allowed or [])} allowed names>"

# ── Common fixture data ───────────────────────────────────────────────────────

PROGRAM = {
    "Upper A": {
        "blocks": [{
            "type": "strength", "order": 0,
            "exercises": {
                "Bench Press":    "4x5-7",
                "Barbell Row":    "4x6-8",
                "Overhead Press": "3x6-8",
            },
        }]
    },
    "Lower": {
        "blocks": [{
            "type": "strength", "order": 0,
            "exercises": {
                "Back Squat":        "4x5-7",
                "Romanian Deadlift": "3x8-10",
                "Bench Press":       "3x8-10",
            },
        }]
    },
}

WEIGHTS = {
    "Bench Press": {
        "current_weight": 185.0,
        "last_reps": "6,6,5,5",
        "history": [
            # sets présents : régression bug 2026-07-20 (supplément historique_data
            # doit propager sets_json quand il ajoute un exo depuis weights.history).
            {"date": "2026-03-10", "weight": 185.0, "reps": "6,6,5,5", "1rm": 210.0,
             "sets": [
                 {"weight": 185, "reps": "6", "rir": 3, "rpe": 7.0},
                 {"weight": 185, "reps": "6", "rir": 3, "rpe": 7.5},
                 {"weight": 185, "reps": "5", "rir": 2, "rpe": 8.0},
                 {"weight": 185, "reps": "5", "rir": 2, "rpe": 8.5},
             ]},
            {"date": "2026-03-03", "weight": 180.0, "reps": "7,6,5,5"},
        ],
    },
    "Back Squat": {
        "current_weight": 225.0,
        "last_reps": "5,5,5,5",
        "history": [
            {"date": "2026-03-07", "weight": 225.0, "reps": "5,5,5,5"},
        ],
    },
}

SESSIONS = {
    "2026-03-10": {"rpe": 7, "comment": "good session"},
    "2026-03-07": {"rpe": 8, "comment": ""},
}

INVENTORY = {
    "Bench Press":    {"type": "barbell", "default_scheme": "4x5-7", "increment": 5, "bar_weight": 45},
    "Back Squat":     {"type": "barbell", "default_scheme": "4x5-7", "increment": 5, "bar_weight": 45},
    "Barbell Row":    {"type": "barbell", "default_scheme": "4x6-8", "increment": 5, "bar_weight": 45},
    "Overhead Press": {"type": "barbell", "default_scheme": "3x6-8", "increment": 5, "bar_weight": 45},
    "Romanian Deadlift": {"type": "barbell", "default_scheme": "3x8-10", "increment": 5, "bar_weight": 45},
    "Cable Fly":      {"type": "cable",   "default_scheme": "3x12-15", "increment": 5},
}

PROFILE = {
    "name": "Test User", "weight": 180.0, "height": 175,
    "age": 30, "level": "intermediate",
}

HIIT_LOG = [
    # Noms de champs = schema.sql relational (rounds_planned/rounds_completed).
    # Les anciens noms KV legacy (rounds_planifies/rounds_completes) étaient
    # traduits par scripts/migrate_to_relational.py:415-416 lors de la bascule.
    {"date": "2026-03-11", "session_type": "Tabata", "rounds_planned": 8,
     "rounds_completed": 8, "rpe": 8, "feeling": "good", "comment": ""},
]


def make_store():
    store = {
        "program":             copy.deepcopy(PROGRAM),
        "weights":             copy.deepcopy(WEIGHTS),
        "sessions":            copy.deepcopy(SESSIONS),
        "inventory":           copy.deepcopy(INVENTORY),
        "user_profile":        copy.deepcopy(PROFILE),
        "hiit_log":            copy.deepcopy(HIIT_LOG),
        "body_weight":         [],
        "goals":               {},
        "deload_state":        {"active": False},
        "nutrition_settings":  {"limite_calories": 2200, "objectif_proteines": 160},
        "nutrition_log":       {},
        "cardio_log":          [],
        "recovery_log":        [],
        "sleep_records":       [],
        "mood_log":            [],
        "journal_entries":     [],
        "breathwork_sessions": [],
        "self_care_habits":    [],
        "self_care_log":       {},
        "pss_records":         [],
        "coach_history":       [],
    }

    def get_json(key, default=None):
        return copy.deepcopy(store.get(key, default))

    def set_json(key, value):
        store[key] = copy.deepcopy(value)
        return True

    def update_json(key, patch_dict):
        current = copy.deepcopy(store.get(key, {}))
        current.update(patch_dict)
        store[key] = current
        return True

    def append_json_list(key, entry, max_items=None):
        lst = copy.deepcopy(store.get(key, []))
        lst.insert(0, entry)
        if max_items:
            lst = lst[:max_items]
        store[key] = lst
        return True

    # ── Domain methods ────────────────────────────────────────────────────────

    def get_exercises():
        return copy.deepcopy(store.get("inventory", {}))

    def get_exercise_by_name(name):
        inv = store.get("inventory", {})
        info = inv.get(name)
        return {"name": name, **info} if info else None

    def get_exercise_id(name):
        return name  # use name as ID in tests

    def upsert_exercise(data):
        name = data.get("name")
        if not name:
            return None
        inv = store.get("inventory", {})
        inv[name] = {k: v for k, v in data.items() if k != "name"}
        store["inventory"] = inv
        return data

    def rename_exercise_table(old_name, new_name):
        inv = store.get("inventory", {})
        if old_name in inv:
            if new_name not in inv:
                inv[new_name] = inv.pop(old_name)
            else:
                del inv[old_name]   # new_name already exists — just remove old
            store["inventory"] = inv
            return True
        return False

    def delete_exercise_by_name(name):
        inv = store.get("inventory", {})
        if name not in inv:
            return False
        del inv[name]
        store["inventory"] = inv
        # Simulate CASCADE: remove exercise from all program strength blocks
        program = store.get("program", {})
        for sdef in program.values():
            for block in sdef.get("blocks", []):
                if block.get("type") == "strength":
                    block.get("exercises", {}).pop(name, None)
        store["program"] = program
        return True

    def get_full_program(program_id=None):
        return copy.deepcopy(store.get("program", {}))

    def save_full_program(program, program_id=None):
        current = store.get("program", {})
        current.update(copy.deepcopy(program))
        store["program"] = current
        return True

    def get_workout_sessions(limit=100, offset=0, since=None):
        # Signature miroir db_sessions.py:9 — offset (pagination), since (filtre
        # date iso). Le fake ignore since/offset au filtre mais accepte les kwargs.
        # id = date (convention fake), permet aux endpoints qui font
        # get_exercise_history_grouped_by_session(session_ids=...) de matcher.
        sessions = store.get("sessions", {})
        dates = sorted(sessions.keys(), reverse=True)
        if since:
            dates = [d for d in dates if d >= since]
        dates = dates[offset:offset + limit]
        result = []
        for date in dates:
            entry = copy.deepcopy(sessions[date])
            entry["date"] = date
            entry.setdefault("id", date)
            result.append(entry)
        return result

    def get_workout_session(date):
        sessions = store.get("sessions", {})
        if date in sessions:
            entry = copy.deepcopy(sessions[date])
            entry["date"] = date
            return entry
        return None

    def create_workout_session(
        date,
        rpe=None,
        comment=None,
        duration_min=None,
        energy_pre=None,
        is_second=False,
        session_type="morning",
        session_name=None,
    ):
        sessions = store.get("sessions", {})
        key = date if not is_second else f"{date}_2"
        entry = {"rpe": rpe, "comment": comment or "", "exos": []}
        if session_type is not None:
            entry["session_type"] = session_type
        if session_name is not None:
            entry["session_name"] = session_name
        if duration_min is not None:
            entry["duration_min"] = duration_min
        sessions[key] = entry
        store["sessions"] = sessions
        return {**entry, "date": date, "id": key}

    def update_workout_session(date, patch):
        sessions = store.get("sessions", {})
        if date in sessions:
            sessions[date].update(patch)
            store["sessions"] = sessions
            return True
        return False

    def delete_workout_session(date):
        sessions = store.get("sessions", {})
        if date in sessions:
            del sessions[date]
            store["sessions"] = sessions
            return True
        return False

    def get_all_exercise_history(cutoff_days=180):
        # Signature miroir db (cutoff_days ajouté après refonte weights).
        # Le fake ignore le filtre — les tests n'ont pas assez de fixtures pour
        # que le cutoff impacte, retourne tout.
        # Propage "sets" si présent dans le fixture : miroir de db_sessions.py:906-907
        # (le vrai db ajoute entry["sets"] uniquement pour les listes non-vides).
        weights = store.get("weights", {})
        result = {}
        for name, ex_data in weights.items():
            history = ex_data.get("history", [])
            if not history:
                continue
            entries = []
            for e in history:
                entry = {"date": e.get("date"), "weight": e.get("weight"), "reps": e.get("reps")}
                if e.get("sets"):
                    entry["sets"] = e["sets"]
                entries.append(entry)
            result[name] = entries
        return result

    def bulk_apply_session_exercise_patches(date, session_type, patches):
        # Contrat db_sessions : applique un lot de patches (add/update/delete)
        # sur les exercise_logs d'une session. Retourne (updated_count, error_list).
        # Fake fonctionnel : mute store["weights"][ex_name]["history"] pour que
        # les tests qui vérifient les mutations post-update passent.
        weights = store.get("weights", {})
        applied = 0
        for p in (patches or []):
            action = p.get("action") or "update"
            ex_name = p.get("exercise") or p.get("exercise_name")
            if not ex_name:
                continue
            ex_data = weights.setdefault(ex_name, {"history": []})
            history = ex_data.setdefault("history", [])
            if action == "delete":
                ex_data["history"] = [e for e in history if e.get("date") != date]
                applied += 1
            elif action == "add":
                history.insert(0, {
                    "date":   date,
                    "weight": p.get("weight"),
                    "reps":   p.get("reps"),
                })
                applied += 1
            else:  # update
                for e in history:
                    if e.get("date") == date:
                        if p.get("weight") is not None:
                            e["weight"] = p.get("weight")
                        if p.get("reps") is not None:
                            e["reps"] = p.get("reps")
                        applied += 1
                        break
                else:
                    # Pas de row date → treat as add
                    history.insert(0, {
                        "date":   date,
                        "weight": p.get("weight"),
                        "reps":   p.get("reps"),
                    })
                    applied += 1
        store["weights"] = weights
        return applied, []

    def get_exercise_history_bulk(exercise_names, limit_per=20):
        # Signature miroir db (bulk fetch pour load_weights). Alias filtré.
        result = {}
        weights = store.get("weights", {})
        for name in exercise_names:
            history = weights.get(name, {}).get("history", [])
            if history:
                result[name] = [
                    {"date": e.get("date"), "weight": e.get("weight"), "reps": e.get("reps")}
                    for e in history[:limit_per]
                ]
        return result

    def get_or_create_workout_session(date):
        sessions = store.get("sessions", {})
        if date in sessions:
            entry = copy.deepcopy(sessions[date])
            entry["date"] = date
            entry.setdefault("id", date)
            return entry
        entry = {"rpe": None, "comment": "", "exos": [], "id": date}
        sessions[date] = entry
        store["sessions"] = sessions
        return {**entry, "date": date}

    def get_exercise_history(exercise_name, limit=50):
        weights = store.get("weights", {})
        history = weights.get(exercise_name, {}).get("history", [])
        result = []
        for entry in history[:limit]:
            result.append({
                "date":       entry.get("date"),
                "weight":     entry.get("weight"),
                "reps":       entry.get("reps"),
                "session_id": entry.get("date"),
            })
        return result

    def get_session_exercise_logs(session_date):
        weights = store.get("weights", {})
        result = []
        for name, ex_data in weights.items():
            history = ex_data.get("history", [])
            for entry in history:
                if entry.get("date") == session_date:
                    result.append({"exercise_name": name, "weight": entry.get("weight"), "reps": entry.get("reps")})
        return result

    def upsert_exercise_log(session_date, exercise_name, weight, reps):
        weights = store.get("weights", {})
        if exercise_name not in weights:
            weights[exercise_name] = {"current_weight": weight or 0, "last_reps": reps or "", "history": []}
        history = weights[exercise_name].get("history", [])
        for entry in history:
            if entry.get("date") == session_date:
                entry["weight"] = weight
                entry["reps"] = reps
                store["weights"] = weights
                return True
        history.insert(0, {"date": session_date, "weight": weight, "reps": reps})
        weights[exercise_name]["history"] = history
        if weight:
            weights[exercise_name]["current_weight"] = weight
        if reps:
            weights[exercise_name]["last_reps"] = reps
        store["weights"] = weights
        return True

    def upsert_exercise_log_by_type(session_date, session_type, exercise_name, weight, reps, sets_json=None):
        return upsert_exercise_log(session_date, exercise_name, weight, reps)

    def delete_exercise_log_entry(session_date, exercise_name):
        weights = store.get("weights", {})
        if exercise_name not in weights:
            return False
        before = len(weights[exercise_name].get("history", []))
        weights[exercise_name]["history"] = [
            e for e in weights[exercise_name].get("history", [])
            if e.get("date") != session_date
        ]
        store["weights"] = weights
        return len(weights[exercise_name]["history"]) < before

    def delete_exercise_log_entry_by_type(session_date, session_type, exercise_name):
        return delete_exercise_log_entry(session_date, exercise_name)

    def delete_session_exercise_logs(session_date):
        weights = store.get("weights", {})
        for ex_data in weights.values():
            ex_data["history"] = [e for e in ex_data.get("history", []) if e.get("date") != session_date]
            # Recalculate denormalized fields to reflect the new most-recent entry
            remaining = ex_data["history"]
            if remaining:
                most_recent = max(remaining, key=lambda e: e.get("date", ""))
                ex_data["current_weight"] = most_recent.get("weight", ex_data.get("current_weight", 0))
                ex_data["last_reps"] = most_recent.get("reps", ex_data.get("last_reps", ""))
        store["weights"] = weights
        return True

    def get_body_weight_logs(limit=100):
        return copy.deepcopy(store.get("body_weight", []))[:limit]

    def upsert_body_weight(date, weight, note="", body_fat=None, waist_cm=None,
                           neck_cm=None, arms_cm=None, chest_cm=None,
                           thighs_cm=None, hips_cm=None):
        # Signature miroir db_body.py:40 — neck_cm ajouté après refonte mesures
        # corporelles. Le fake stockait déjà les autres cm mais neck manquait.
        bw = store.get("body_weight", [])
        entry_data = {"date": date, "poids": weight, "note": note}
        for field, val in [("body_fat", body_fat), ("waist_cm", waist_cm),
                           ("neck_cm", neck_cm), ("arms_cm", arms_cm),
                           ("chest_cm", chest_cm), ("thighs_cm", thighs_cm),
                           ("hips_cm", hips_cm)]:
            if val is not None:
                entry_data[field] = val
        for entry in bw:
            if entry.get("date") == date:
                entry.update(entry_data)
                store["body_weight"] = bw
                return True
        bw.insert(0, entry_data)
        store["body_weight"] = bw
        return True

    def get_nutrition_entries(date):
        log = store.get("nutrition_log", {})
        return copy.deepcopy((log.get(date) or {}).get("entries", []))

    def get_nutrition_entries_recent(n=7):
        log = store.get("nutrition_log", {})
        days = sorted(log.keys(), reverse=True)[:n]
        return [
            {
                "date":     d,
                "calories": round(sum(e.get("calories", 0) for e in (log.get(d) or {}).get("entries", []))),
                "nb":       len((log.get(d) or {}).get("entries", [])),
            }
            for d in days
        ]

    def insert_nutrition_entry(data):
        log = store.get("nutrition_log", {})
        d = data.get("date", "")
        if d not in log:
            log[d] = {"entries": []}
        log[d]["entries"].append(copy.deepcopy(data))
        store["nutrition_log"] = log
        return copy.deepcopy(data)

    def delete_nutrition_entry(entry_id):
        log = store.get("nutrition_log", {})
        for day_data in log.values():
            before = len(day_data.get("entries", []))
            day_data["entries"] = [e for e in day_data.get("entries", []) if e.get("id") != entry_id]
            if len(day_data["entries"]) < before:
                store["nutrition_log"] = log
                return True
        return False

    def delete_body_weight(date):
        bw = store.get("body_weight", [])
        store["body_weight"] = [e for e in bw if e.get("date") != date]
        return True

    def get_hiit_logs(limit=100):
        import uuid as _uuid
        logs = store.get("hiit_log", [])
        # Assign stable IDs to entries that don't have one yet
        for entry in logs:
            if "id" not in entry:
                entry["id"] = str(_uuid.uuid4())
        return copy.deepcopy(logs[:limit])

    def insert_hiit_log(data):
        import uuid
        logs = store.get("hiit_log", [])
        entry = copy.deepcopy(data)
        if "id" not in entry:
            entry["id"] = str(uuid.uuid4())
        logs.insert(0, entry)
        store["hiit_log"] = logs
        return entry

    def update_hiit_log(hiit_id, patch):
        logs = store.get("hiit_log", [])
        for entry in logs:
            if entry.get("id") == str(hiit_id) or logs.index(entry) == hiit_id:
                entry.update(patch)
                store["hiit_log"] = logs
                return True
        return False

    def delete_hiit_log_by_id(hiit_id):
        logs = store.get("hiit_log", [])
        before = len(logs)
        store["hiit_log"] = [e for e in logs if e.get("id") != str(hiit_id)]
        return len(store["hiit_log"]) < before

    def get_recovery_logs(limit=100):
        return copy.deepcopy(store.get("recovery_log", []))[:limit]

    def upsert_recovery_log(data):
        logs = store.get("recovery_log", [])
        date = data.get("date")
        for i, entry in enumerate(logs):
            if entry.get("date") == date:
                logs[i] = copy.deepcopy(data)
                store["recovery_log"] = logs
                return True
        logs.insert(0, copy.deepcopy(data))
        store["recovery_log"] = logs
        return True

    def delete_recovery_log(date):
        logs = store.get("recovery_log", [])
        store["recovery_log"] = [e for e in logs if e.get("date") != date]
        return True

    def get_goals():
        return copy.deepcopy(store.get("goals", {}))

    def set_goal(exercise_name, target_weight, target_date=None):
        goals = store.get("goals", {})
        goals[exercise_name] = {"goal_weight": target_weight}
        if target_date:
            goals[exercise_name]["target_date"] = target_date
        store["goals"] = goals
        return True

    def get_cardio_logs(limit=100):
        return copy.deepcopy(store.get("cardio_log", []))[:limit]

    def insert_cardio_log(data):
        logs = store.get("cardio_log", [])
        logs.insert(0, copy.deepcopy(data))
        store["cardio_log"] = logs
        return True

    def delete_cardio_log(date, type_):
        logs = store.get("cardio_log", [])
        store["cardio_log"] = [e for e in logs if not (e.get("date") == date and e.get("type") == type_)]
        return True

    def get_profile():
        return copy.deepcopy(store.get("user_profile", {}))

    def update_profile(patch):
        profile = store.get("user_profile", {})
        profile.update(patch)
        store["user_profile"] = profile
        return True

    def get_nutrition_settings():
        return copy.deepcopy(store.get("nutrition_settings", {}))

    def update_nutrition_settings(patch):
        settings = store.get("nutrition_settings", {})
        settings.update(patch)
        store["nutrition_settings"] = settings
        return True

    def get_deload_state():
        return copy.deepcopy(store.get("deload_state", {"active": False}))

    def set_deload_state(active, started_at=None, reason=None):
        state = {"active": active}
        if started_at:
            state["started_at"] = started_at
        if reason:
            state["reason"] = reason
        store["deload_state"] = state
        return True

    def get_all_programs():
        return []

    def get_default_program_id():
        return None

    def get_all_session_names():
        program = store.get("program", {})
        return sorted(program.keys())

    def complete_workout_session(date, patch=None):
        # Signature miroir db_sessions.py:380 — patch (dict) permet de merger
        # des champs (rpe, comment, duration_min, energy_pre, etc.) au moment
        # de la complétion. Le fake applique le patch au dict de la session.
        sessions = store.get("sessions", {})
        if date in sessions:
            sessions[date]["completed"] = True
            if patch:
                sessions[date].update(patch)
            store["sessions"] = sessions
            return True
        return False

    def complete_workout_session_bonus(date, patch=None):
        return True

    def get_workout_session_bonus(date):
        return None

    def delete_workout_session_by_type(date, session_type="morning"):
        sessions = store.get("sessions", {})
        if date in sessions:
            del sessions[date]
            store["sessions"] = sessions
            return True
        return False

    def update_workout_session_by_type(date, session_type, patch):
        sessions = store.get("sessions", {})
        if date in sessions:
            sessions[date].update(patch)
            store["sessions"] = sessions
            return True
        return False

    def delete_exercise_logs_for_session(session_id):
        return True

    def get_relational_week_schedule():
        return copy.deepcopy(store.get("morning_schedule", {}))

    def set_relational_week_schedule(schedule):
        store["morning_schedule"] = copy.deepcopy(schedule)
        return True

    def get_evening_week_schedule():
        return copy.deepcopy(store.get("evening_schedule", {}))

    def set_evening_week_schedule(schedule):
        store["evening_schedule"] = copy.deepcopy(schedule)
        return True

    # ── Fakes ajoutés commit sync 2026-07 (fields exposés par endpoints récents
    # qui renvoyaient MagicMock non-JSON — cycle_start_date, current_program_id,
    # macros_by_day_type, session_supersets).

    def get_active_program_id():
        # Retour str stable pour que les endpoints qui piggyback ce champ dans
        # leur JSON ne pètent pas. Le fake n'a pas de vraie table programs — la
        # majorité des tests n'a pas besoin d'un ID particulier.
        return store.get("active_program_id", "test-program-id")

    def set_active_program_id(program_id):
        store["active_program_id"] = program_id
        return True

    def get_cycle_start_date():
        # None par défaut (cycle non démarré) — les tests qui veulent une valeur
        # override via db_mod.get_cycle_start_date = MagicMock(return_value=...).
        return store.get("cycle_start_date")

    def set_cycle_start_date(date_str):
        store["cycle_start_date"] = date_str
        return True

    def get_macros_by_day_type(days=60, nutr_days=None, sessions_raw=None):
        # Retour dict plausible vide — les tests stats ne vérifient pas le contenu
        # de ce champ, juste sa présence dans le payload sans exception JSON.
        return {"session_days": {}, "rest_days": {}}

    def get_session_supersets(program_id=None):
        # Retour dict vide — pas de supersets configurés dans les fixtures.
        return {}

    def get_session_override():
        # None par défaut — pas d'override. Sans ce fake, planner.get_today()
        # tombe sur MagicMock permissif qui pollue tout le pipeline session.
        return store.get("session_override")

    def set_session_override(payload):
        store["session_override"] = payload
        return True

    def get_workout_session_by_type(date, session_type="morning"):
        # Contrat db_sessions : dict session ou None. Utilisé par nutrition
        # _get_day_intensity pour distinguer session actual vs schedulée.
        sessions = store.get("sessions", {})
        if date in sessions:
            entry = copy.deepcopy(sessions[date])
            entry["date"] = date
            entry["session_type"] = session_type
            return entry
        return None

    def get_workout_session_second(date):
        # Séance soir. None par défaut (pas de soir loggée).
        return None

    def get_today_sessions_all(date):
        # Toutes les slots (matin+soir+bonus) du jour. Retourne [] si aucun.
        sessions = store.get("sessions", {})
        if date in sessions:
            entry = copy.deepcopy(sessions[date])
            entry["id"] = date
            return [entry]
        return []

    def get_exercises_info_bulk(exercise_names):
        # Retour dict par nom d'exercice avec les infos inventaire. Utilisé
        # par smart_progression pour bulk-lookup.
        inv = store.get("inventory", {})
        return {n: copy.deepcopy(inv.get(n, {})) for n in exercise_names}

    def get_exercise_log_sets_json(date, session_type, exercise):
        # Retourne les sets structurés d'un exo loggé (workout_logging garde
        # anti-fantôme). None si pas loggé.
        return None

    def get_nutrition_daily_full(days=180):
        # Contrat db_stats : liste [{"date": "YYYY-MM-DD", "calories": ..., ...}]
        # sur les N derniers jours. Vide par défaut — les tests stats ne vérifient
        # pas le contenu, juste que le champ est JSON-serializable.
        return []

    def get_current_1rm_estimates():
        # Contrat db_stats : liste [{"name": ..., "estimated_1rm": ...}].
        # Vide par défaut. Utilisé par /api/programme_data L246.
        return []

    def get_full_program_by_id(program_id):
        # Multi-programmes : lookup par ID. Fallback sur le programme unique
        # du fake — la majorité des tests n'a qu'un programme.
        return copy.deepcopy(store.get("program", {}))

    def get_exercises_bulk(exercise_names):
        # Alias de get_exercises_info_bulk (nom historique). Certains chemins
        # backend l'appellent sous ce nom.
        inv = store.get("inventory", {})
        return [{"name": n, **copy.deepcopy(inv.get(n, {}))} for n in exercise_names]

    # ── Stats/analytics fakes (retours JSON-safe vides) — les tests stats
    # vérifient présence des clés dans le payload, pas leur contenu.
    def _empty_list(*a, **kw): return []
    def _empty_dict(*a, **kw): return {}
    get_weekly_tonnage = _empty_list
    get_pattern_volume = _empty_dict
    get_programme_compliance = _empty_dict
    get_one_rm_trend = _empty_dict
    get_protein_weight_ratio = _empty_dict
    get_mood_trend = _empty_list
    get_pss_records = _empty_list
    get_self_care_streaks_computed = _empty_dict
    get_self_care_compliance = _empty_dict
    get_soreness_volume_scatter = _empty_list
    get_sleep_volume_scatter = _empty_list
    get_rpe_progression = _empty_list
    get_rir_by_exercise = _empty_dict
    get_food_catalog = _empty_list
    get_meal_templates = _empty_list

    def get_exercise_history_grouped_by_session(session_ids=None):
        # Groupe les exos loggés par session_id. Contrat db_sessions.py:651-656 : dict
        # {session_id: [{"exercise", "weight", "reps", "sets"}]} — sets vient de
        # sets_json de la row exercise_logs. Le fake dérive depuis
        # store["weights"][name]["history"] → maps par date (session_id = date
        # dans nos fakes) au niveau exercice.
        result = {}
        weights = store.get("weights", {})
        for name, data in weights.items():
            for entry in data.get("history", []):
                d = entry.get("date")
                if not d:
                    continue
                if session_ids is not None and d not in session_ids:
                    continue
                result.setdefault(d, []).append({
                    "exercise": name,
                    "weight":   entry.get("weight"),
                    "reps":     entry.get("reps"),
                    "sets":     entry.get("sets") or [],
                })
        return result

    def delete_program_session(seance):
        program = store.get("program", {})
        if seance in program:
            del program[seance]
            store["program"] = program
            return True
        return False

    db_mock = MagicMock(
        get_json=get_json,
        set_json=set_json,
        update_json=update_json,
        append_json_list=append_json_list,
        _ON_VERCEL=False,
        # Domain methods
        get_exercises=get_exercises,
        get_exercise_by_name=get_exercise_by_name,
        get_exercise_id=get_exercise_id,
        upsert_exercise=upsert_exercise,
        rename_exercise_table=rename_exercise_table,
        delete_exercise_by_name=delete_exercise_by_name,
        get_full_program=get_full_program,
        save_full_program=save_full_program,
        get_workout_sessions=get_workout_sessions,
        get_workout_session=get_workout_session,
        get_or_create_workout_session=get_or_create_workout_session,
        create_workout_session=create_workout_session,
        update_workout_session=update_workout_session,
        delete_workout_session=delete_workout_session,
        get_all_exercise_history=get_all_exercise_history,
        get_exercise_history=get_exercise_history,
        get_session_exercise_logs=get_session_exercise_logs,
        upsert_exercise_log=upsert_exercise_log,
        upsert_exercise_log_by_type=upsert_exercise_log_by_type,
        delete_exercise_log_entry=delete_exercise_log_entry,
        delete_exercise_log_entry_by_type=delete_exercise_log_entry_by_type,
        delete_session_exercise_logs=delete_session_exercise_logs,
        get_body_weight_logs=get_body_weight_logs,
        upsert_body_weight=upsert_body_weight,
        delete_body_weight=delete_body_weight,
        get_nutrition_entries=get_nutrition_entries,
        get_nutrition_entries_recent=get_nutrition_entries_recent,
        insert_nutrition_entry=insert_nutrition_entry,
        delete_nutrition_entry=delete_nutrition_entry,
        get_hiit_logs=get_hiit_logs,
        insert_hiit_log=insert_hiit_log,
        update_hiit_log=update_hiit_log,
        delete_hiit_log_by_id=delete_hiit_log_by_id,
        get_recovery_logs=get_recovery_logs,
        upsert_recovery_log=upsert_recovery_log,
        delete_recovery_log=delete_recovery_log,
        get_goals=get_goals,
        set_goal=set_goal,
        get_cardio_logs=get_cardio_logs,
        insert_cardio_log=insert_cardio_log,
        delete_cardio_log=delete_cardio_log,
        get_profile=get_profile,
        update_profile=update_profile,
        get_nutrition_settings=get_nutrition_settings,
        update_nutrition_settings=update_nutrition_settings,
        get_deload_state=get_deload_state,
        set_deload_state=set_deload_state,
        get_all_programs=get_all_programs,
        get_default_program_id=get_default_program_id,
        get_all_session_names=get_all_session_names,
        complete_workout_session=complete_workout_session,
        complete_workout_session_bonus=complete_workout_session_bonus,
        get_workout_session_bonus=get_workout_session_bonus,
        delete_workout_session_by_type=delete_workout_session_by_type,
        update_workout_session_by_type=update_workout_session_by_type,
        delete_exercise_logs_for_session=delete_exercise_logs_for_session,
        get_relational_week_schedule=get_relational_week_schedule,
        set_relational_week_schedule=set_relational_week_schedule,
        get_evening_week_schedule=get_evening_week_schedule,
        set_evening_week_schedule=set_evening_week_schedule,
        # Ajouts commit sync : méthodes exposées par endpoints récents (mésocycle,
        # multi-programmes, macros stats) qui retournaient MagicMock non-JSON.
        get_active_program_id=get_active_program_id,
        set_active_program_id=set_active_program_id,
        get_cycle_start_date=get_cycle_start_date,
        set_cycle_start_date=set_cycle_start_date,
        get_macros_by_day_type=get_macros_by_day_type,
        get_session_supersets=get_session_supersets,
        get_session_override=get_session_override,
        set_session_override=set_session_override,
        get_workout_session_by_type=get_workout_session_by_type,
        get_workout_session_second=get_workout_session_second,
        get_today_sessions_all=get_today_sessions_all,
        get_exercises_info_bulk=get_exercises_info_bulk,
        get_exercise_log_sets_json=get_exercise_log_sets_json,
        get_nutrition_daily_full=get_nutrition_daily_full,
        get_current_1rm_estimates=get_current_1rm_estimates,
        get_full_program_by_id=get_full_program_by_id,
        get_exercises_bulk=get_exercises_bulk,
        # Stats fakes — retours JSON-safe vides
        get_weekly_tonnage=get_weekly_tonnage,
        get_pattern_volume=get_pattern_volume,
        get_programme_compliance=get_programme_compliance,
        get_one_rm_trend=get_one_rm_trend,
        get_protein_weight_ratio=get_protein_weight_ratio,
        get_mood_trend=get_mood_trend,
        get_pss_records=get_pss_records,
        get_self_care_streaks_computed=get_self_care_streaks_computed,
        get_self_care_compliance=get_self_care_compliance,
        get_soreness_volume_scatter=get_soreness_volume_scatter,
        get_sleep_volume_scatter=get_sleep_volume_scatter,
        get_rpe_progression=get_rpe_progression,
        get_rir_by_exercise=get_rir_by_exercise,
        get_food_catalog=get_food_catalog,
        get_meal_templates=get_meal_templates,
        get_exercise_history_grouped_by_session=get_exercise_history_grouped_by_session,
        delete_program_session=delete_program_session,
        get_exercise_history_bulk=get_exercise_history_bulk,
        bulk_apply_session_exercise_patches=bulk_apply_session_exercise_patches,
    )
    # Wrap dans le spec-guard : setattr d'un attribut hors spec du vrai module
    # db lève AttributeError. Attrape les typos type mesocycle (get_active_program
    # vs get_active_program_id) que MagicMock nu masquait silencieusement.
    return store, _SpecGuardedMock(db_mock, _DB_SPEC_NAMES)


import unittest

_MODULES_TO_EVICT = (
    "index", "planner", "log_workout", "sessions", "inventory",
    "progression", "deload", "goals", "body_weight", "user_profile",
    "hiit", "blocks", "nutrition", "volume", "health_data",
    "life_stress_engine", "mental_health_dashboard", "mood", "journal",
    "breathwork", "self_care", "sleep", "pss", "cardio", "weights",
)

TODAY = "2026-03-14"


class BaseRouteTest(unittest.TestCase):
    """Flask test client with in-memory store and mocked db layer."""

    def setUp(self):
        self.store, db_mock = make_store()

        self.db_patch = patch.dict("sys.modules", {"db": db_mock})
        self.db_patch.start()

        for mod in list(sys.modules.keys()):
            if mod in _MODULES_TO_EVICT or any(mod.startswith(m) for m in _MODULES_TO_EVICT):
                del sys.modules[mod]

        self._today_patch = patch("planner.get_today_date", return_value=TODAY)
        self._today_patch.start()

        import index as idx
        self.idx = idx
        self.app = idx.app
        self.app.config["TESTING"] = True
        self.client = self.app.test_client()

    def tearDown(self):
        self.db_patch.stop()
        try:
            self._today_patch.stop()
        except RuntimeError:
            pass

    def get(self, url):
        return self.client.get(url)

    def post(self, url, payload):
        return self.client.post(url, json=payload,
                                content_type="application/json")

    def json(self, resp):
        return json.loads(resp.data)
