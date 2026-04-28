#!/usr/bin/env python3
"""
Populate exercises.gif_url (+ muscles if empty) from free-exercise-db.
Source: https://github.com/yuhonas/free-exercise-db

Run (all exercises, skip already-populated):
    python3 scripts/populate_exercise_media.py [--dry-run]

Run (force-overwrite specific exercises):
    python3 scripts/populate_exercise_media.py --force --exercises "Nordic Curl" "Burpee"

Run (force-overwrite ALL):
    python3 scripts/populate_exercise_media.py --force
"""

import json, os, sys, time, difflib, urllib.request, urllib.parse, argparse

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

IMAGES_BASE = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/"
DB_URL      = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json"

# ── Manual overrides ──────────────────────────────────────────────────────────
# Only ONE entry per key — duplicates silently overwrite in Python dicts.
MANUAL_MAP = {
    # Barbell compounds
    "Bench Press":                  "Barbell Bench Press - Medium Grip",
    "Back Squat":                   "Barbell Squat",
    "Deadlift":                     "Barbell Deadlift",
    "Shoulder Press":               "Barbell Shoulder Press",
    "Incline Bench Press":          "Barbell Incline Bench Press - Medium Grip",
    "Romanian Deadlift":            "Romanian Deadlift",
    "Skull Crusher":                "EZ-Bar Skullcrusher",
    "Hip Thrust":                   "Barbell Hip Thrust",

    # Upper body
    "Pull Up":                      "Pullups",
    "Pull-Up / Chin-Up":            "Pullups",
    "Pull-up / Weighted":           "Pullups",
    "Lat Pulldown":                 "Wide-Grip Lat Pulldown",
    "Dumbbell Fly":                 "Dumbbell Flyes",
    "Tricep Pushdown":              "Triceps Pushdown",
    "Cable Lateral Raise":          "Side Lateral Raise",
    "Dumbbell Row":                 "Bent Over Two-Dumbbell Row",
    "Chest-Supported DB Row":       "Bent Over Two-Dumbbell Row",
    "Dumbbell Shoulder Press":      "Dumbbell Shoulder Press",
    "Dumbbell Bicep Curl":          "Dumbbell Alternate Bicep Curl",
    "Face Pull":                    "Face Pull",
    "Dips":                         "Dips - Chest Version",
    "Seated Cable Row":             "Seated Cable Rows",
    "Cable Pull Over":              "Straight-Arm Pulldown",
    "Cable Fly / Pec Dec":          "Flat Bench Cable Flyes",
    "Lever Seated Fly":             "Lever Pec Deck Fly",

    # Lower body
    "Leg Curl":                     "Seated Leg Curl",
    "Leg Extension":                "Leg Extensions",
    # Nordic Curl: kneeling eccentric hamstring — closest match in free-exercise-db
    "Nordic Curl":                  "Nordic Hamstring Curl",

    # Bodyweight / cardio
    "Push Up":                      "Pushups",
    "Burpee":                       "Burpees",

    # Core
    "Abs":                          "Cable Crunch",
    "Plank":                        "Plank",
    "Russian Twist":                "Russian Twist",
}


def fetch_db() -> list[dict]:
    print("Fetching free-exercise-db…")
    req = urllib.request.Request(DB_URL, headers={"Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=20) as r:
        data = json.loads(r.read())
    print(f"  {len(data)} exercises loaded")
    return data


def build_index(db: list[dict]) -> dict[str, dict]:
    return {e["name"].lower(): e for e in db}


def best_match(name: str, index: dict[str, dict]) -> dict | None:
    # 1. Manual override
    override = MANUAL_MAP.get(name)
    if override:
        result = index.get(override.lower())
        if result is None:
            print(f"    [WARN] Manual override '{override}' not found in free-exercise-db for '{name}'")
        return result

    # 2. Exact (case-insensitive)
    if name.lower() in index:
        return index[name.lower()]

    # 3. DB name contains our name as a word sequence
    nl = name.lower()
    tokens = nl.split()
    candidates = [k for k in index if all(t in k for t in tokens)]
    if candidates:
        best = min(candidates, key=len)
        return index[best]

    # 4. Fuzzy fallback (cutoff 0.7)
    matches = difflib.get_close_matches(nl, list(index.keys()), n=1, cutoff=0.7)
    if matches:
        return index[matches[0]]

    return None


def image_url(relative: str) -> str:
    return IMAGES_BASE + urllib.parse.quote(relative, safe="/")


def run(dry_run: bool, force: bool, only_exercises: list[str] | None):
    supabase_url = os.getenv("SUPABASE_URL")
    supabase_key = os.getenv("SUPABASE_ANON_KEY")
    if not supabase_url or not supabase_key:
        env_path = os.path.join(os.path.dirname(__file__), "..", ".env")
        if os.path.exists(env_path):
            for line in open(env_path):
                line = line.strip()
                if "=" in line and not line.startswith("#"):
                    k, v = line.split("=", 1)
                    os.environ.setdefault(k.strip(), v.strip())
        supabase_url = os.getenv("SUPABASE_URL")
        supabase_key = os.getenv("SUPABASE_ANON_KEY")

    if not supabase_url or not supabase_key:
        print("ERROR: SUPABASE_URL / SUPABASE_ANON_KEY not set")
        sys.exit(1)

    os.environ["APP_DATA_MODE"] = "ONLINE"
    os.environ["SUPABASE_URL"]      = supabase_url
    os.environ["SUPABASE_ANON_KEY"] = supabase_key
    import db as dbmod
    from supabase import create_client
    client = create_client(supabase_url, supabase_key)

    free_db = fetch_db()
    index   = build_index(free_db)

    exercises = dbmod.get_exercises()
    if not exercises:
        print("ERROR: could not load exercises from Supabase")
        sys.exit(1)

    if only_exercises:
        exercises = {k: v for k, v in exercises.items() if k in only_exercises}
        print(f"\nTargeting {len(exercises)} exercise(s): {list(exercises.keys())}\n")
    else:
        print(f"\n{len(exercises)} exercises in Supabase\n")

    matched, skipped, unmatched = 0, 0, []

    for name, row in sorted(exercises.items()):
        m = best_match(name, index)
        if not m:
            unmatched.append(name)
            print(f"  NO MATCH  {name}")
            continue

        imgs    = m.get("images", [])
        img0    = image_url(imgs[0]) if len(imgs) > 0 else None
        img1    = image_url(imgs[1]) if len(imgs) > 1 else None
        muscles = m.get("primaryMuscles", []) + m.get("secondaryMuscles", [])

        update: dict = {}

        # gif_url: update if empty OR if --force
        if img0 and (not row.get("gif_url") or force):
            update["gif_url"] = img0
        if img1 and (not row.get("tips") or force):
            update["tips"] = img1

        # muscles: only fill if empty
        if not (row.get("muscles") or []) and muscles:
            update["muscles"] = muscles

        if not update:
            skipped += 1
            print(f"  SKIP  {name} (already populated)")
            continue

        print(f"  {'DRY ' if dry_run else ''}UPDATE  {name}")
        print(f"          → matched : {m['name']}")
        if "gif_url" in update:
            print(f"          → gif     : {update['gif_url']}")

        if not dry_run:
            try:
                client.table("exercises").update(update).eq("name", name).execute()
                matched += 1
                time.sleep(0.05)
            except Exception as e:
                print(f"          ERROR: {e}")

    print(f"\n{'[DRY RUN] ' if dry_run else ''}Results:")
    print(f"  Updated  : {matched}")
    print(f"  Skipped  : {skipped}")
    print(f"  Unmatched: {len(unmatched)} → {unmatched}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true", help="Preview without writing to DB")
    parser.add_argument("--force",   action="store_true", help="Overwrite gif_url even if already set")
    parser.add_argument("--exercises", nargs="+", metavar="NAME",
                        help="Only process these exercise names (exact match)")
    args = parser.parse_args()
    run(dry_run=args.dry_run, force=args.force, only_exercises=args.exercises)
