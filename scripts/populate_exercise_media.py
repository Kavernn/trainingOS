#!/usr/bin/env python3
"""
Populate exercises.gif_url (+ muscles if empty) from free-exercise-db.
Source: https://github.com/yuhonas/free-exercise-db

Run:
    cd /Users/vincentpinard/trainingos
    SUPABASE_URL=... SUPABASE_ANON_KEY=... APP_DATA_MODE=ONLINE \
        python3 scripts/populate_exercise_media.py [--dry-run]
"""

import json, os, sys, time, difflib, urllib.request, urllib.parse, argparse

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

IMAGES_BASE = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/exercises/"
DB_URL      = "https://raw.githubusercontent.com/yuhonas/free-exercise-db/main/dist/exercises.json"

# ── Manual overrides for exercises that don't fuzzy-match well ────────────────
MANUAL_MAP = {
    "Bench Press":                       "Barbell Bench Press - Medium Grip",
    "Back Squat":                        "Barbell Squat",
    "Deadlift":                          "Barbell Deadlift",
    "Pull Up":                           "Pullups",
    "Pull-Up / Chin-Up":                 "Pullups",
    "Shoulder Press":                    "Barbell Shoulder Press",
    "Lat Pulldown":                      "Wide-Grip Lat Pulldown",
    "Dumbbell Fly":                      "Dumbbell Flyes",
    "Tricep Pushdown":                   "Triceps Pushdown",
    "Seated Cable Row":                  "Seated Cable Rows",
    "Cable Lateral Raise":               "Side Lateral Raise",
    "Incline Bench Press":               "Barbell Incline Bench Press - Medium Grip",
    "Romanian Deadlift":                 "Romanian Deadlift",
    "Leg Curl":                          "Leg Curl",
    "Leg Extension":                     "Leg Extensions",
    "Hip Thrust":                        "Barbell Hip Thrust",
    "Dumbbell Row":                      "Bent Over Two-Dumbbell Row",
    "Dumbbell Shoulder Press":           "Dumbbell Shoulder Press",
    "Dumbbell Bicep Curl":               "Dumbbell Alternate Bicep Curl",
    "Skull Crusher":                     "Barbell Lying Triceps Extension Skull Crusher",
    "Barbell Lying Triceps Extension Skull Crusher": "Barbell Lying Triceps Extension Skull Crusher",
    "Face Pull":                         "Face Pull",
    "Dips":                              "Dips - Chest Version",
    "Push Up":                           "Pushups",
    "Abs":                               "Crunch",
    "Plank":                             "Plank",
    "Russian Twist":                     "Russian Twist",
    # Unmatched from dry-run
    "Barbell Lying Triceps Extension Skull Crusher": "Lying Triceps Extension",
    "Burpee":                            "Burpees",
    "Cable Fly / Pec Dec":              "Cable Fly",
    "Cable Pull Over":                   "Straight-Arm Pulldown",
    "Chest-Supported DB Row":            "Bent Over Two-Dumbbell Row",
    "Leg Curl":                          "Leg Curl",
    "Lever Seated Fly":                  "Lever Pec Deck Fly",
    "Nordic Curl":                       "Lying Leg Curls",
    "Pull-up / Weighted":                "Pullups",
    "Abs":                               "Cable Crunch",
    "Barbell Lying Triceps Extension Skull Crusher": "EZ-Bar Skullcrusher",
    "Burpee":                            "Close-Grip Front Lat Pulldown",
    "Cable Fly / Pec Dec":              "Flat Bench Cable Flyes",
    "Leg Curl":                          "Seated Leg Curl",
    "Lever Seated Fly":                  "Incline Cable Flye",
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
        return index.get(override.lower())

    # 2. Exact (case-insensitive)
    if name.lower() in index:
        return index[name.lower()]

    # 3. Our name is a substring of a DB name (e.g. "Barbell Curl" → "Barbell Curl")
    nl = name.lower()
    for key, val in index.items():
        if nl == key:
            return val

    # 4. DB name contains our name as a word sequence
    tokens = nl.split()
    candidates = [k for k in index if all(t in k for t in tokens)]
    if candidates:
        # prefer shorter (more specific)
        best = min(candidates, key=len)
        return index[best]

    # 5. Fuzzy fallback (cutoff 0.7 = strict)
    matches = difflib.get_close_matches(nl, list(index.keys()), n=1, cutoff=0.7)
    if matches:
        return index[matches[0]]

    return None


def image_url(relative: str) -> str:
    return IMAGES_BASE + urllib.parse.quote(relative, safe="/")


def run(dry_run: bool):
    # Load env
    supabase_url = os.getenv("SUPABASE_URL")
    supabase_key = os.getenv("SUPABASE_ANON_KEY")
    if not supabase_url or not supabase_key:
        # Try loading from .env
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
    # Must set env vars BEFORE importing db (client init happens at module level)
    os.environ["SUPABASE_URL"]      = supabase_url
    os.environ["SUPABASE_ANON_KEY"] = supabase_key
    import db as dbmod

    # Load source data
    free_db  = fetch_db()
    index    = build_index(free_db)

    # Load our exercises
    exercises = dbmod.get_exercises()
    if not exercises:
        print("ERROR: could not load exercises from Supabase")
        sys.exit(1)

    print(f"\n{len(exercises)} exercises in Supabase\n")

    matched = 0
    unmatched = []

    for name, row in sorted(exercises.items()):
        m = best_match(name, index)
        if not m:
            unmatched.append(name)
            continue

        imgs     = m.get("images", [])
        img0     = image_url(imgs[0]) if len(imgs) > 0 else None
        img1     = image_url(imgs[1]) if len(imgs) > 1 else None
        muscles  = m.get("primaryMuscles", []) + m.get("secondaryMuscles", [])
        category = m.get("category", "")
        mechanic = m.get("mechanic", "")

        update: dict = {}
        if img0 and not row.get("gif_url"):
            update["gif_url"] = img0
        # Store second image in tips if not already set (reuse field temporarily)
        if img1 and not row.get("tips"):
            update["tips"] = img1

        # Only update muscles if empty
        current_muscles = row.get("muscles") or []
        if not current_muscles and muscles:
            update["muscles"] = muscles

        if not update:
            print(f"  SKIP  {name} (already populated)")
            matched += 1
            continue

        print(f"  {'DRY ' if dry_run else ''}UPDATE  {name}")
        print(f"          → matched: {m['name']}")
        print(f"          → gif: {update.get('gif_url', '(keep)')}")
        print(f"          → muscles: {update.get('muscles', '(keep)')}")

        if not dry_run:
            try:
                from supabase import create_client
                client = create_client(supabase_url, supabase_key)
                client.table("exercises").update(update).eq("name", name).execute()
                matched += 1
                time.sleep(0.05)  # rate limit
            except Exception as e:
                print(f"          ERROR: {e}")

    print(f"\n{'DRY RUN — ' if dry_run else ''}Results:")
    print(f"  Matched & updated : {matched}/{len(exercises)}")
    print(f"  Unmatched ({len(unmatched)}): {unmatched}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true", help="Preview without writing to DB")
    args = parser.parse_args()
    run(dry_run=args.dry_run)
