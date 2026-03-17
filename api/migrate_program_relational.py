"""
migrate_program_relational.py
─────────────────────────────
One-shot migration script:
  1. Corrige les données exercises (type, pattern, muscles, increment, bar_weight)
  2. Peuple program_sessions + program_blocks + program_block_exercises
  3. Peuple weekly_schedule

Run:
    cd /Users/vincentpinard/PycharmProjects/trainingOS
    python3 api/migrate_program_relational.py
"""
from __future__ import annotations
import os, sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__)))

# ── Load env ─────────────────────────────────────────────────────────────────
_env_path = os.path.join(os.path.dirname(__file__), "..", ".env")
with open(_env_path) as f:
    for line in f:
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            k = k.strip(); v = v.strip().strip('"').strip("'")
            os.environ[k] = v
            if k == "SUPABASE_KEY":
                os.environ["SUPABASE_ANON_KEY"] = v

import db
from supabase import create_client

db._client = create_client(
    os.environ["SUPABASE_URL"],
    os.environ["SUPABASE_ANON_KEY"],
)
print("✅ Supabase connecté\n")


# ── 1. Exercise definitions ───────────────────────────────────────────────────

EXERCISES = {
    # Push A
    "Bench Press": {
        "type": "barbell", "category": "strength", "pattern": "horizontal_push",
        "level": "intermediate", "muscles": ["pectorals", "triceps", "anterior deltoid"],
        "increment": 5.0, "bar_weight": 45.0, "default_scheme": "4x5-7",
    },
    "Overhead Press": {
        "type": "barbell", "category": "strength", "pattern": "vertical_push",
        "level": "intermediate", "muscles": ["anterior deltoid", "triceps", "traps"],
        "increment": 5.0, "bar_weight": 45.0, "default_scheme": "3x6-8",
    },
    "Incline DB Press": {
        "type": "dumbbell", "category": "strength", "pattern": "horizontal_push",
        "level": "intermediate", "muscles": ["upper pectorals", "anterior deltoid", "triceps"],
        "increment": 5.0, "bar_weight": 0.0, "default_scheme": "3x8-10",
    },
    "Lateral Raises": {
        "type": "dumbbell", "category": "strength", "pattern": "isolation",
        "level": "beginner", "muscles": ["lateral deltoid"],
        "increment": 2.5, "bar_weight": 0.0, "default_scheme": "3x12-15",
    },
    "Triceps Extension": {
        "type": "cable", "category": "strength", "pattern": "isolation",
        "level": "beginner", "muscles": ["triceps"],
        "increment": 5.0, "bar_weight": 0.0, "default_scheme": "3x10-12",
    },
    # Pull A
    "Barbell Row": {
        "type": "barbell", "category": "strength", "pattern": "horizontal_pull",
        "level": "intermediate", "muscles": ["lats", "rhomboids", "traps", "biceps"],
        "increment": 5.0, "bar_weight": 45.0, "default_scheme": "4x6-8",
    },
    "Lat Pulldown": {
        "type": "cable", "category": "strength", "pattern": "vertical_pull",
        "level": "beginner", "muscles": ["lats", "biceps", "rhomboids"],
        "increment": 5.0, "bar_weight": 0.0, "default_scheme": "3x8-10",
    },
    "Seated Row": {
        "type": "cable", "category": "strength", "pattern": "horizontal_pull",
        "level": "beginner", "muscles": ["rhomboids", "traps", "lats", "biceps"],
        "increment": 5.0, "bar_weight": 0.0, "default_scheme": "3x10-12",
    },
    "Face Pull": {
        "type": "cable", "category": "strength", "pattern": "horizontal_pull",
        "level": "beginner", "muscles": ["rear deltoid", "rhomboids", "external rotators"],
        "increment": 2.5, "bar_weight": 0.0, "default_scheme": "3x15",
    },
    "Hammer Curl": {
        "type": "dumbbell", "category": "strength", "pattern": "isolation",
        "level": "beginner", "muscles": ["brachialis", "brachioradialis", "biceps"],
        "increment": 2.5, "bar_weight": 0.0, "default_scheme": "3x10-12",
    },
    # Legs
    "Back Squat": {
        "type": "barbell", "category": "strength", "pattern": "squat",
        "level": "intermediate", "muscles": ["quadriceps", "glutes", "hamstrings", "calves"],
        "increment": 5.0, "bar_weight": 45.0, "default_scheme": "4x5-7",
    },
    "Leg Press": {
        "type": "machine", "category": "strength", "pattern": "squat",
        "level": "beginner", "muscles": ["quadriceps", "glutes", "hamstrings"],
        "increment": 5.0, "bar_weight": 0.0, "default_scheme": "3x10-12",
    },
    "Leg Curl": {
        "type": "machine", "category": "strength", "pattern": "hinge",
        "level": "beginner", "muscles": ["hamstrings", "calves"],
        "increment": 5.0, "bar_weight": 0.0, "default_scheme": "3x10-12",
    },
    "Romanian Deadlift": {
        "type": "barbell", "category": "strength", "pattern": "hinge",
        "level": "intermediate", "muscles": ["hamstrings", "glutes", "lower back"],
        "increment": 5.0, "bar_weight": 45.0, "default_scheme": "3x8-10",
    },
    "Calf Raise": {
        "type": "machine", "category": "strength", "pattern": "isolation",
        "level": "beginner", "muscles": ["calves", "soleus"],
        "increment": 5.0, "bar_weight": 0.0, "default_scheme": "3x12-15",
    },
    "Abs": {
        "type": "bodyweight", "category": "strength", "pattern": "core",
        "level": "beginner", "muscles": ["rectus abdominis", "obliques"],
        "increment": 0.0, "bar_weight": 0.0, "default_scheme": "3x12-15",
    },
    # Push B
    "DB Bench Press": {
        "type": "dumbbell", "category": "strength", "pattern": "horizontal_push",
        "level": "beginner", "muscles": ["pectorals", "anterior deltoid", "triceps"],
        "increment": 5.0, "bar_weight": 0.0, "default_scheme": "3x10-12",
    },
    # Pull B + Full Body
    "Deadlift": {
        "type": "barbell", "category": "strength", "pattern": "hinge",
        "level": "intermediate", "muscles": ["glutes", "hamstrings", "lower back", "traps"],
        "increment": 5.0, "bar_weight": 45.0, "default_scheme": "3x5",
    },
    "T-Bar Row": {
        "type": "barbell", "category": "strength", "pattern": "horizontal_pull",
        "level": "intermediate", "muscles": ["lats", "rhomboids", "traps", "biceps"],
        "increment": 5.0, "bar_weight": 45.0, "default_scheme": "4x8-10",
    },
}

print("── Étape 1 : Correction exercises ──────────────────────────────────────")
for name, info in EXERCISES.items():
    db.upsert_exercise({**info, "name": name})
    print(f"  ✅ {name}  [{info['type']} · {info['pattern']}]")

print()


# ── 2. Program sessions ───────────────────────────────────────────────────────

PROGRAM = {
    "Push A": {
        "blocks": [{
            "type": "strength", "order": 0,
            "exercises": {
                "Bench Press":       "4x5-7",
                "Overhead Press":    "3x6-8",
                "Incline DB Press":  "3x8-10",
                "Lateral Raises":    "3x12-15",
                "Triceps Extension": "3x10-12",
            },
        }]
    },
    "Pull A": {
        "blocks": [{
            "type": "strength", "order": 0,
            "exercises": {
                "Barbell Row":  "4x6-8",
                "Lat Pulldown": "3x8-10",
                "Seated Row":   "3x10-12",
                "Face Pull":    "3x15",
                "Hammer Curl":  "3x10-12",
            },
        }]
    },
    "Legs": {
        "blocks": [{
            "type": "strength", "order": 0,
            "exercises": {
                "Back Squat":        "4x5-7",
                "Leg Press":         "3x10-12",
                "Leg Curl":          "3x10-12",
                "Romanian Deadlift": "3x8-10",
                "Calf Raise":        "3x12-15",
                "Abs":               "3x12-15",
            },
        }]
    },
    "Push B": {
        "blocks": [{
            "type": "strength", "order": 0,
            "exercises": {
                "Incline DB Press":  "4x8-10",
                "DB Bench Press":    "3x10-12",
                "Overhead Press":    "3x8-10",
                "Lateral Raises":    "4x12-15",
                "Triceps Extension": "3x12-15",
            },
        }]
    },
    "Pull B + Full Body": {
        "blocks": [{
            "type": "strength", "order": 0,
            "exercises": {
                "Deadlift":     "3x5",
                "T-Bar Row":    "4x8-10",
                "Lat Pulldown": "3x10-12",
                "Face Pull":    "3x15",
                "Hammer Curl":  "3x12-15",
            },
        }]
    },
}

print("── Étape 2 : Peupler program_sessions + blocks + exercises ─────────────")
ok = db.save_full_program(PROGRAM)
if ok:
    for sname, sdef in PROGRAM.items():
        exos = sdef["blocks"][0]["exercises"]
        print(f"  ✅ {sname}  ({len(exos)} exercices)")
else:
    print("  ❌ save_full_program a échoué")

print()


# ── 3. Weekly schedule ────────────────────────────────────────────────────────

SCHEDULE = {
    "Lun": "Push A",
    "Mar": "Pull A",
    "Mer": "Legs",
    "Jeu": "Push B",
    "Ven": "Pull B + Full Body",
    "Sam": None,
    "Dim": None,
}

print("── Étape 3 : Peupler weekly_schedule ───────────────────────────────────")
ok = db.set_relational_week_schedule(SCHEDULE)
if ok:
    for day, sess in SCHEDULE.items():
        print(f"  ✅ {day} → {sess or '(repos)'}")
else:
    print("  ❌ set_relational_week_schedule a échoué")

print()


# ── 4. Vérification ───────────────────────────────────────────────────────────

print("── Vérification ────────────────────────────────────────────────────────")
loaded = db.get_full_program()
for sname, sdef in loaded.items():
    from blocks import get_strength_exercises
    exos = get_strength_exercises(sdef)
    print(f"  {sname}: {list(exos.keys())}")

print()
sched = db.get_relational_week_schedule()
print(f"  Schedule: {sched}")
print("\n🚀 Migration terminée.")
