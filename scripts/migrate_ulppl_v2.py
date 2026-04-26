"""
migrate_ulppl_v2.py
───────────────────
Migration UL/PPL v2 — met à jour les sessions Upper A, Lower A, Push, Pull, Legs B
avec les exercices et supersets du nouveau programme.

Nouveaux exercices créés si absents :
  - Lying Leg Curl, Standing Calf Raise, Seated Calf Raise
  - Cable Pull-Through, Sissy Squat, Seated Leg Curl
  - Goblet Squat, Hack Squat (si absents)

Run:
    cd /Users/vincentpinard/TrainingOS
    python3 scripts/migrate_ulppl_v2.py
"""
from __future__ import annotations
import os, sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

for env_filename in (".env.local", ".env"):
    env_path = os.path.join(os.path.dirname(__file__), "..", env_filename)
    if os.path.exists(env_path):
        with open(env_path) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    k = k.strip(); v = v.strip().strip('"').strip("'")
                    os.environ.setdefault(k, v)
                    if k == "SUPABASE_KEY":
                        os.environ.setdefault("SUPABASE_ANON_KEY", v)

import db
from supabase import create_client

db._client = create_client(
    os.environ["SUPABASE_URL"],
    os.environ["SUPABASE_ANON_KEY"],
)
print("✅ Supabase connecté\n")


# ── 1. Exercices v2 ──────────────────────────────────────────────────────────
# Upsert tous les exercices mentionnés dans le PDF v2 avec métadonnées complètes.
# Les exercices existants sont mis à jour ; les nouveaux sont créés.

EXERCISES_V2 = {
    # ── Upper A ────────────────────────────────────────────────────────────────
    "Bench Press": {
        "type": "barbell", "category": "strength", "pattern": "horizontal_push",
        "level": "intermediate", "muscles": ["pectorals", "triceps", "anterior deltoid"],
        "increment": 5.0, "bar_weight": 45.0, "default_scheme": "4x6-8",
        "tips": "Descente contrôlée · prise standard · coudes à 75°",
    },
    "Barbell Row": {
        "type": "barbell", "category": "strength", "pattern": "horizontal_pull",
        "level": "intermediate", "muscles": ["lats", "rhomboids", "traps", "biceps"],
        "increment": 5.0, "bar_weight": 45.0, "default_scheme": "4x6-8",
        "tips": "Penché avant · pronation · coudes serrés",
    },
    "Overhead Press": {
        "type": "barbell", "category": "strength", "pattern": "vertical_push",
        "level": "intermediate", "muscles": ["anterior deltoid", "triceps", "traps"],
        "increment": 5.0, "bar_weight": 45.0, "default_scheme": "3x8-10",
        "tips": "Debout · barre · core engagé · poignets neutres",
    },
    "Lat Pulldown": {
        "type": "cable", "category": "strength", "pattern": "vertical_pull",
        "level": "beginner", "muscles": ["lats", "biceps", "rhomboids"],
        "increment": 5.0, "bar_weight": 0.0, "default_scheme": "3x8-10",
        "tips": "Prise large · coudes vers les hanches · squeeze dorsaux",
    },
    "Incline DB Press": {
        "type": "dumbbell", "category": "strength", "pattern": "horizontal_push",
        "level": "intermediate", "muscles": ["upper pectorals", "anterior deltoid", "triceps"],
        "increment": 5.0, "bar_weight": 0.0, "default_scheme": "3x10-12",
        "tips": "30–45° · ROM complet · contrôle excentrique",
    },
    "Seated Cable Row": {
        "type": "cable", "category": "strength", "pattern": "horizontal_pull",
        "level": "beginner", "muscles": ["rhomboids", "traps", "lats", "biceps"],
        "increment": 5.0, "bar_weight": 0.0, "default_scheme": "3x10-12",
        "tips": "Câble bas · poignée neutre · squeeze omoplate",
    },
    "Lateral Raise": {
        "type": "dumbbell", "category": "strength", "pattern": "isolation",
        "level": "beginner", "muscles": ["lateral deltoid"],
        "increment": 2.5, "bar_weight": 0.0, "default_scheme": "3x12-15",
        "tips": "Coudes légèrement fléchis · pas de balancier · pic en haut",
    },
    "Face Pull": {
        "type": "cable", "category": "strength", "pattern": "horizontal_pull",
        "level": "beginner", "muscles": ["rear deltoid", "rhomboids", "external rotators"],
        "increment": 2.5, "bar_weight": 0.0, "default_scheme": "3x12-15",
        "tips": "Câble · corde · hauteur yeux · rotation externe",
    },

    # ── Lower A ────────────────────────────────────────────────────────────────
    "Back Squat": {
        "type": "barbell", "category": "strength", "pattern": "squat",
        "level": "intermediate", "muscles": ["quadriceps", "fessiers", "hamstrings"],
        "increment": 5.0, "bar_weight": 45.0, "default_scheme": "4x6-8",
        "tips": "Profondeur complète · genoux sur orteils · chest up",
    },
    "Romanian Deadlift": {
        "type": "barbell", "category": "strength", "pattern": "hinge",
        "level": "intermediate", "muscles": ["hamstrings", "fessiers", "lower back"],
        "increment": 5.0, "bar_weight": 45.0, "default_scheme": "4x8-10",
        "tips": "Haltères ou barre · charnière hanche · dos neutre",
    },
    "Leg Press": {
        "type": "machine", "category": "strength", "pattern": "squat",
        "level": "beginner", "muscles": ["quadriceps", "fessiers", "hamstrings"],
        "increment": 5.0, "bar_weight": 0.0, "default_scheme": "3x10-12",
        "tips": "Pieds mi-hauteur · amplitude sans verrouiller",
    },
    "Lying Leg Curl": {
        "type": "machine", "category": "strength", "pattern": "hinge",
        "level": "beginner", "muscles": ["hamstrings", "calves"],
        "increment": 5.0, "bar_weight": 0.0, "default_scheme": "3x10-12",
        "tips": "Machine · tempo 2-0-1 · hanche à plat · pas de rebond",
    },
    "Bulgarian Split Squat": {
        "type": "dumbbell", "category": "strength", "pattern": "squat",
        "level": "intermediate", "muscles": ["quadriceps", "fessiers", "hamstrings"],
        "increment": 2.5, "bar_weight": 0.0, "default_scheme": "3x10",
        "tips": "Pied arrière surélevé · 10 reps/jambe · tronc droit",
    },
    "Nordic Curl": {
        "type": "bodyweight", "category": "strength", "pattern": "hinge",
        "level": "advanced", "muscles": ["hamstrings"],
        "increment": 0.0, "bar_weight": 0.0, "default_scheme": "3x6-8",
        "tips": "Genoux fixés · descente lente · remontée aidée",
    },
    "Leg Extension": {
        "type": "machine", "category": "strength", "pattern": "isolation",
        "level": "beginner", "muscles": ["quadriceps"],
        "increment": 5.0, "bar_weight": 0.0, "default_scheme": "3x15",
        "tips": "Machine · pic de contraction 1s en haut",
    },
    "Standing Calf Raise": {
        "type": "machine", "category": "strength", "pattern": "isolation",
        "level": "beginner", "muscles": ["calves", "soleus"],
        "increment": 5.0, "bar_weight": 0.0, "default_scheme": "3x15-20",
        "tips": "Amplitude maximale · descente lente · pause en bas",
    },

    # ── Push ───────────────────────────────────────────────────────────────────
    "Incline Barbell Press": {
        "type": "barbell", "category": "strength", "pattern": "horizontal_push",
        "level": "intermediate", "muscles": ["upper pectorals", "anterior deltoid", "triceps"],
        "increment": 5.0, "bar_weight": 45.0, "default_scheme": "4x8-10",
        "tips": "30–45° · prise légèrement plus large que les épaules",
    },
    "Cable Lateral Raise": {
        "type": "cable", "category": "strength", "pattern": "isolation",
        "level": "beginner", "muscles": ["lateral deltoid"],
        "increment": 2.5, "bar_weight": 0.0, "default_scheme": "4x12-15",
        "tips": "Câble bas · coude légèrement fléchi · résistance max en haut",
    },
    "Flat DB Press": {
        "type": "dumbbell", "category": "strength", "pattern": "horizontal_push",
        "level": "beginner", "muscles": ["pectorals", "anterior deltoid", "triceps"],
        "increment": 5.0, "bar_weight": 0.0, "default_scheme": "3x10-12",
        "tips": "ROM complet · pas de rebond · coudes à 75°",
    },
    "Tricep Pushdown": {
        "type": "cable", "category": "strength", "pattern": "isolation",
        "level": "beginner", "muscles": ["triceps"],
        "increment": 2.5, "bar_weight": 0.0, "default_scheme": "3x12-15",
        "tips": "Câble · corde · coudes fixes aux côtés",
    },
    "Seated DB Press": {
        "type": "dumbbell", "category": "strength", "pattern": "vertical_push",
        "level": "beginner", "muscles": ["anterior deltoid", "lateral deltoid", "triceps"],
        "increment": 5.0, "bar_weight": 0.0, "default_scheme": "3x10-12",
        "tips": "Haltères · amplitude complète · pas de momentum",
    },
    "Cable Fly / Pec Dec": {
        "type": "cable", "category": "strength", "pattern": "isolation",
        "level": "beginner", "muscles": ["pectorals"],
        "increment": 2.5, "bar_weight": 0.0, "default_scheme": "3x12-15",
        "tips": "Câble croisé · stretch en bas · squeeze en haut",
    },
    "Rear Delt Fly": {
        "type": "dumbbell", "category": "strength", "pattern": "isolation",
        "level": "beginner", "muscles": ["rear deltoid", "rhomboids"],
        "increment": 2.5, "bar_weight": 0.0, "default_scheme": "3x15",
        "tips": "Penché avant · coudes légèrement fléchis · ouverture lente",
    },
    "Overhead Tricep Ext.": {
        "type": "cable", "category": "strength", "pattern": "isolation",
        "level": "beginner", "muscles": ["triceps"],
        "increment": 2.5, "bar_weight": 0.0, "default_scheme": "3x12-15",
        "tips": "Câble · corde · tête fixe · étirement max",
    },

    # ── Pull ───────────────────────────────────────────────────────────────────
    "Pull-up / Weighted": {
        "type": "bodyweight", "category": "strength", "pattern": "vertical_pull",
        "level": "intermediate", "muscles": ["lats", "biceps", "rhomboids"],
        "increment": 2.5, "bar_weight": 0.0, "default_scheme": "4x6-8",
        "tips": "Lest si 3×8 acquis · prise légèrement large",
    },
    "Hammer Curl": {
        "type": "dumbbell", "category": "strength", "pattern": "isolation",
        "level": "beginner", "muscles": ["brachialis", "brachioradialis", "biceps"],
        "increment": 2.5, "bar_weight": 0.0, "default_scheme": "4x10-12",
        "tips": "Prise neutre · pas de balancier · tempo 2-0-1",
    },
    "Chest-Supported DB Row": {
        "type": "dumbbell", "category": "strength", "pattern": "horizontal_pull",
        "level": "beginner", "muscles": ["lats", "rhomboids", "traps", "rear deltoid"],
        "increment": 2.5, "bar_weight": 0.0, "default_scheme": "3x10-12",
        "tips": "Banc incliné 45° · coudes au ciel · squeeze omoplate",
    },
    "Incline DB Curl": {
        "type": "dumbbell", "category": "strength", "pattern": "isolation",
        "level": "beginner", "muscles": ["biceps"],
        "increment": 2.5, "bar_weight": 0.0, "default_scheme": "3x10-12",
        "tips": "45° · étirement biceps maximal en bas · supination",
    },
    "Single-Arm DB Row": {
        "type": "dumbbell", "category": "strength", "pattern": "horizontal_pull",
        "level": "beginner", "muscles": ["lats", "rhomboids", "traps", "biceps"],
        "increment": 2.5, "bar_weight": 0.0, "default_scheme": "3x10",
        "tips": "Genou sur banc · coude au ciel · 10/côté",
    },
    "EZ Bar Curl": {
        "type": "barbell", "category": "strength", "pattern": "isolation",
        "level": "beginner", "muscles": ["biceps", "brachialis"],
        "increment": 2.5, "bar_weight": 25.0, "default_scheme": "3x10-12",
        "tips": "Tempo 2-0-1 · coudes fixes · no cheat",
    },
    "Rear Delt Cable Fly": {
        "type": "cable", "category": "strength", "pattern": "isolation",
        "level": "beginner", "muscles": ["rear deltoid", "rhomboids"],
        "increment": 2.5, "bar_weight": 0.0, "default_scheme": "3x15",
        "tips": "Câbles croisés · hauteur épaules · coudes semi-fléchis · ouverture lente",
    },
    "Cable Curl": {
        "type": "cable", "category": "strength", "pattern": "isolation",
        "level": "beginner", "muscles": ["biceps"],
        "increment": 2.5, "bar_weight": 0.0, "default_scheme": "3x15",
        "tips": "Câble bas · squeeze au sommet · lent",
    },

    # ── Legs B ─────────────────────────────────────────────────────────────────
    "Cable Pull-Through": {
        "type": "cable", "category": "strength", "pattern": "hinge",
        "level": "beginner", "muscles": ["fessiers", "hamstrings"],
        "increment": 5.0, "bar_weight": 0.0, "default_scheme": "4x12-15",
        "tips": "Câble bas · entre les jambes · extension hanche complète · fessiers serrés",
    },
    "Goblet Squat": {
        "type": "dumbbell", "category": "strength", "pattern": "squat",
        "level": "beginner", "muscles": ["quadriceps", "fessiers"],
        "increment": 5.0, "bar_weight": 0.0, "default_scheme": "4x12",
        "tips": "Kettlebell · talons surélevés · genoux ouverts",
    },
    "Hip Thrust": {
        "type": "barbell", "category": "strength", "pattern": "hinge",
        "level": "intermediate", "muscles": ["fessiers", "hamstrings"],
        "increment": 5.0, "bar_weight": 45.0, "default_scheme": "3x10-12",
        "tips": "Barre + pad · ROM complet · squeeze 1s en haut",
    },
    "Seated Leg Curl": {
        "type": "machine", "category": "strength", "pattern": "hinge",
        "level": "beginner", "muscles": ["hamstrings"],
        "increment": 5.0, "bar_weight": 0.0, "default_scheme": "3x12-15",
        "tips": "Machine · hanche fléchie = plus de stretch ischio · descente lente",
    },
    "Walking Lunges": {
        "type": "dumbbell", "category": "strength", "pattern": "squat",
        "level": "beginner", "muscles": ["quadriceps", "fessiers", "hamstrings"],
        "increment": 2.5, "bar_weight": 0.0, "default_scheme": "3x12",
        "tips": "12 pas/jambe · tronc droit · genou avant sur orteil",
    },
    "Hack Squat": {
        "type": "machine", "category": "strength", "pattern": "squat",
        "level": "intermediate", "muscles": ["quadriceps"],
        "increment": 5.0, "bar_weight": 0.0, "default_scheme": "3x12",
        "tips": "Machine · pieds bas serrés · focus quad",
    },
    "Sissy Squat": {
        "type": "bodyweight", "category": "strength", "pattern": "isolation",
        "level": "intermediate", "muscles": ["quadriceps"],
        "increment": 0.0, "bar_weight": 0.0, "default_scheme": "3x12-15",
        "tips": "Talons surélevés · genoux vers l'avant · 3s excentrique",
    },
    "Seated Calf Raise": {
        "type": "machine", "category": "strength", "pattern": "isolation",
        "level": "beginner", "muscles": ["soleus", "calves"],
        "increment": 5.0, "bar_weight": 0.0, "default_scheme": "3x20",
        "tips": "Amplitude lente · étirement complet en bas",
    },
}

print("── Étape 1 : Upsert exercices v2 ───────────────────────────────────────")
for name, info in EXERCISES_V2.items():
    db.upsert_exercise({**info, "name": name})
    print(f"  ✅ {name}  [{info['type']} · {info['pattern']}]")
print()


# ── 2. Programme v2 ──────────────────────────────────────────────────────────
# Chaque session = 4 supersets × 2 exercices = 8 exercices.
# L'ordre dict reflète l'ordre d'affichage : A1, B1, A2, B2, A3, B3, A4, B4.

PROGRAM_V2 = {
    "Upper A": {
        "blocks": [{"type": "strength", "order": 0, "exercises": {
            "Bench Press":       "4x6-8",
            "Barbell Row":       "4x6-8",
            "Overhead Press":    "3x8-10",
            "Lat Pulldown":      "3x8-10",
            "Incline DB Press":  "3x10-12",
            "Seated Cable Row":  "3x10-12",
            "Lateral Raise":     "3x12-15",
            "Face Pull":         "3x12-15",
        }}]
    },
    "Lower A": {
        "blocks": [{"type": "strength", "order": 0, "exercises": {
            "Back Squat":          "4x6-8",
            "Romanian Deadlift":   "4x8-10",
            "Leg Press":           "3x10-12",
            "Lying Leg Curl":      "3x10-12",
            "Bulgarian Split Squat": "3x10",
            "Nordic Curl":         "3x6-8",
            "Leg Extension":       "3x15",
            "Standing Calf Raise": "3x15-20",
        }}]
    },
    "Push": {
        "blocks": [{"type": "strength", "order": 0, "exercises": {
            "Incline Barbell Press": "4x8-10",
            "Cable Lateral Raise":   "4x12-15",
            "Flat DB Press":         "3x10-12",
            "Tricep Pushdown":       "3x12-15",
            "Seated DB Press":       "3x10-12",
            "Cable Fly / Pec Dec":   "3x12-15",
            "Rear Delt Fly":         "3x15",
            "Overhead Tricep Ext.":  "3x12-15",
        }}]
    },
    "Pull": {
        "blocks": [{"type": "strength", "order": 0, "exercises": {
            "Pull-up / Weighted":     "4x6-8",
            "Hammer Curl":            "4x10-12",
            "Chest-Supported DB Row": "3x10-12",
            "Incline DB Curl":        "3x10-12",
            "Single-Arm DB Row":      "3x10",
            "EZ Bar Curl":            "3x10-12",
            "Rear Delt Cable Fly":    "3x15",
            "Cable Curl":             "3x15",
        }}]
    },
    "Legs B": {
        "blocks": [{"type": "strength", "order": 0, "exercises": {
            "Cable Pull-Through": "4x12-15",
            "Goblet Squat":       "4x12",
            "Hip Thrust":         "3x10-12",
            "Seated Leg Curl":    "3x12-15",
            "Walking Lunges":     "3x12",
            "Hack Squat":         "3x12",
            "Sissy Squat":        "3x12-15",
            "Seated Calf Raise":  "3x20",
        }}]
    },
}

print("── Étape 2 : save_full_program v2 ──────────────────────────────────────")
ok = db.save_full_program(PROGRAM_V2)
if ok:
    for sname, sdef in PROGRAM_V2.items():
        exos = list(sdef["blocks"][0]["exercises"].keys())
        print(f"  ✅ {sname}  ({len(exos)} exercices)")
else:
    print("  ❌ save_full_program a échoué")
    sys.exit(1)
print()


# ── 3. Supersets v2 ──────────────────────────────────────────────────────────
# Pour chaque session, met à jour superset_group / superset_position / rest_after_superset
# dans program_block_exercises.

SUPERSETS_V2 = {
    "Upper A": {
        "SS1": {"A": "Bench Press",      "B": "Barbell Row",      "rest": 90},
        "SS2": {"A": "Overhead Press",   "B": "Lat Pulldown",     "rest": 75},
        "SS3": {"A": "Incline DB Press", "B": "Seated Cable Row", "rest": 75},
        "SS4": {"A": "Lateral Raise",    "B": "Face Pull",        "rest": 60},
    },
    "Lower A": {
        "SS1": {"A": "Back Squat",            "B": "Romanian Deadlift",   "rest": 90},
        "SS2": {"A": "Leg Press",             "B": "Lying Leg Curl",      "rest": 75},
        "SS3": {"A": "Bulgarian Split Squat", "B": "Nordic Curl",         "rest": 75},
        "SS4": {"A": "Leg Extension",         "B": "Standing Calf Raise", "rest": 60},
    },
    "Push": {
        "SS1": {"A": "Incline Barbell Press", "B": "Cable Lateral Raise",  "rest": 75},
        "SS2": {"A": "Flat DB Press",         "B": "Tricep Pushdown",      "rest": 75},
        "SS3": {"A": "Seated DB Press",       "B": "Cable Fly / Pec Dec",  "rest": 60},
        "SS4": {"A": "Rear Delt Fly",         "B": "Overhead Tricep Ext.", "rest": 60},
    },
    "Pull": {
        "SS1": {"A": "Pull-up / Weighted",     "B": "Hammer Curl",         "rest": 90},
        "SS2": {"A": "Chest-Supported DB Row", "B": "Incline DB Curl",     "rest": 75},
        "SS3": {"A": "Single-Arm DB Row",      "B": "EZ Bar Curl",         "rest": 75},
        "SS4": {"A": "Rear Delt Cable Fly",    "B": "Cable Curl",          "rest": 60},
    },
    "Legs B": {
        "SS1": {"A": "Cable Pull-Through", "B": "Goblet Squat",      "rest": 90},
        "SS2": {"A": "Hip Thrust",         "B": "Seated Leg Curl",   "rest": 75},
        "SS3": {"A": "Walking Lunges",     "B": "Hack Squat",        "rest": 75},
        "SS4": {"A": "Sissy Squat",        "B": "Seated Calf Raise", "rest": 60},
    },
}

print("── Étape 3 : Mise à jour supersets v2 ──────────────────────────────────")
client = db._client
program_id = db.get_default_program_id()

for session_name, groups in SUPERSETS_V2.items():
    # Fetch session id
    q = client.table("program_sessions").select("id").eq("name", session_name)
    if program_id:
        q = q.eq("program_id", program_id)
    sess = q.single().execute()
    if not sess.data:
        print(f"  ❌ Session introuvable: {session_name}")
        continue
    session_id = sess.data["id"]

    # Fetch block id
    block_resp = (
        client.table("program_blocks")
        .select("id")
        .eq("session_id", session_id)
        .eq("type", "strength")
        .eq("order_index", 0)
        .execute()
    )
    if not block_resp.data:
        print(f"  ❌ Block introuvable pour: {session_name}")
        continue
    block_id = block_resp.data[0]["id"]

    # Fetch all pbe rows for this block
    pbe_resp = (
        client.table("program_block_exercises")
        .select("id, exercises(name)")
        .eq("block_id", block_id)
        .execute()
    )
    ex_name_to_pbe_id = {
        row["exercises"]["name"]: row["id"]
        for row in (pbe_resp.data or [])
        if row.get("exercises") and row["exercises"].get("name")
    }

    session_ok = True
    for group_label, group in groups.items():
        ex_a = group["A"]
        ex_b = group["B"]
        rest = group["rest"]

        pbe_a = ex_name_to_pbe_id.get(ex_a)
        pbe_b = ex_name_to_pbe_id.get(ex_b)

        if not pbe_a:
            print(f"  ❌ Exercice A introuvable dans PBE: {ex_a} ({session_name}/{group_label})")
            session_ok = False
            continue
        if not pbe_b:
            print(f"  ❌ Exercice B introuvable dans PBE: {ex_b} ({session_name}/{group_label})")
            session_ok = False
            continue

        client.table("program_block_exercises").update({
            "superset_group": group_label,
            "superset_position": 1,
            "rest_after_superset": None,
        }).eq("id", pbe_a).execute()

        client.table("program_block_exercises").update({
            "superset_group": group_label,
            "superset_position": 2,
            "rest_after_superset": rest,
        }).eq("id", pbe_b).execute()

    if session_ok:
        print(f"  ✅ {session_name}  ({len(groups)} supersets)")
    else:
        print(f"  ⚠️  {session_name}  (voir erreurs ci-dessus)")

print()


# ── 4. Vérification ───────────────────────────────────────────────────────────
print("── Vérification ────────────────────────────────────────────────────────")
ss_data = db.get_session_supersets(program_id)
for sess_name, groups in ss_data.items():
    if sess_name in SUPERSETS_V2:
        print(f"  {sess_name}:")
        for grp, data in sorted(groups.items()):
            print(f"    {grp}: {data.get('A')} ↔ {data.get('B')}  [{data.get('rest')}s]")

print("\n🚀 Migration UL/PPL v2 terminée.")
