import os
import sys
import requests

# ── Ajoute /api au path pour accéder à db.py ────────────────
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "api"))
import db as _db

HEADERS = {
    "X-RapidAPI-Key": os.getenv("X_RAPIDAPI_KEY", "35105723d4msh22056a747ded06ap1784e0jsnda9b2359112f"),
    "X-RapidAPI-Host": "exercisedb.p.rapidapi.com"
}

# ── Mapping équipement ExerciseDB → tes types ───────────────
EQUIPMENT_MAP = {
    "barbell":        "barbell",
    "dumbbell":       "dumbbell",
    "cable":          "cable",
    "machine":        "machine",
    "body weight":    "bodyweight",
    "assisted":       "bodyweight",
    "resistance band":"cable",
    "kettlebell":     "dumbbell",
    "ez barbell":     "barbell",
    "trap bar":       "barbell",
    "other":          "machine",
    "leverage machine":"machine",
    "smith machine":  "machine",
    "olympic barbell":"barbell",
    "weighted":       "barbell",
    "roller":         "bodyweight",
    "skierg machine": "machine",
    "sled machine":   "machine",
    "upper body ergometer": "machine",
    "wheel roller":   "bodyweight",
    "rope":           "cable",
    "stability ball": "bodyweight",
    "bosu ball":      "bodyweight",
}

# ── Mapping bodyPart → category ──────────────────────────────
CATEGORY_MAP = {
    "chest":       "push",
    "shoulders":   "push",
    "triceps":     "push",
    "back":        "pull",
    "upper legs":  "legs",
    "lower legs":  "legs",
    "upper arms":  "pull",   # biceps dominants
    "forearms":    "pull",
    "waist":       "core",
    "cardio":      "mobility",
    "neck":        "mobility",
}

# ── Mapping target muscle → pattern ─────────────────────────
PATTERN_MAP = {
    "pectorals":          "horizontal_push",
    "serratus anterior":  "horizontal_push",
    "deltoid lateral":    "vertical_push",
    "deltoid":            "vertical_push",
    "triceps":            "horizontal_push",
    "lats":               "vertical_pull",
    "traps":              "horizontal_pull",
    "upper back":         "horizontal_pull",
    "spine":              "hinge",
    "fessiers":             "hinge",
    "hamstrings":         "hinge",
    "quads":              "squat",
    "quadriceps":         "squat",
    "calves":             "squat",
    "biceps":             "vertical_pull",
    "abs":                "core",
    "obliques":           "core",
    "cardiovascular system": "mobility",
    "forearms":           "isolation",
}

# ── Mapping level selon bodyPart + equipment ─────────────────
def guess_level(body_part: str, equipment: str) -> str:
    if equipment in ["body weight", "assisted"]:
        return "beginner"
    if body_part in ["waist", "cardio", "neck"]:
        return "beginner"
    if equipment in ["barbell", "trap bar", "olympic barbell"]:
        return "intermediate"
    return "beginner"


LEVEL_MAP = {"beginner": "beginner", "intermediate": "intermediate", "advanced": "advanced"}
BATCH_SIZE = 10  # Plan gratuit RapidAPI = 10 résultats max par appel


def fetch_batch(offset: int) -> list:
    """Fetch un batch de 10 exercices depuis ExerciseDB."""
    try:
        response = requests.get(
            "https://exercisedb.p.rapidapi.com/exercises",
            headers=HEADERS,
            params={"limit": "10", "offset": str(offset)},
            timeout=15
        )
        response.raise_for_status()
        data = response.json()
        return data if isinstance(data, list) else []
    except Exception as e:
        print(f"❌ Erreur batch offset={offset} : {e}")
        return []


def parse_exercise(item: dict, existing: dict) -> tuple[str, dict]:
    """Parse un exercice ExerciseDB → format TrainingOS."""
    raw_name     = item.get("name", "Unknown")
    name         = raw_name.title()
    body_part    = item.get("bodyPart", "").lower()
    equipment    = item.get("equipment", "other").lower()
    target       = item.get("target", "").lower()
    secondary    = item.get("secondaryMuscles", [])
    instructions = item.get("instructions", [])
    difficulty   = item.get("difficulty", "").lower()

    ex_type    = EQUIPMENT_MAP.get(equipment, "machine")
    category   = CATEGORY_MAP.get(body_part, "push")
    pattern    = PATTERN_MAP.get(target, "isolation")
    bar_weight = 45.0 if ex_type == "barbell" else 0.0
    level      = LEVEL_MAP.get(difficulty) or guess_level(body_part, equipment)

    muscles = [target] if target else []
    muscles += [m.lower() for m in secondary if m.lower() not in muscles]
    tips = ". ".join(instructions[:2]) if instructions else ""

    entry = {
        "type":           ex_type,
        "category":       category,
        "pattern":        pattern,
        "level":          level,
        "increment":      existing.get(name, {}).get("increment", 5.0),
        "bar_weight":     existing.get(name, {}).get("bar_weight", bar_weight),
        "default_scheme": existing.get(name, {}).get("default_scheme", "3x8-12"),
        "muscles":        muscles,
        "tips":           tips,
    }
    return name, entry


def import_exercises(total: int = 1300, merge: bool = True):
    """
    Importe les exercices depuis ExerciseDB avec pagination automatique (10 par appel).

    Args:
        total: Nombre total d'exercices à importer.
        merge: Si True, fusionne avec l'inventaire existant. Si False, repart de zéro.
    """
    import time

    print(f"📥 Import ExerciseDB — total={total}, merge={merge}, batch={BATCH_SIZE}")
    print(f"⏱  ~{(total // BATCH_SIZE)} appels API nécessaires\n")

    existing  = _db.get_exercises() or {} if merge else {}
    new_count = 0
    upd_count = 0
    offset    = 0
    empty_batches = 0

    while offset < total:
        batch = fetch_batch(offset)

        if not batch:
            empty_batches += 1
            if empty_batches >= 3:
                print(f"\n⚠️  3 batches vides consécutifs — fin de la DB à offset={offset}")
                break
            offset += BATCH_SIZE
            continue

        empty_batches = 0

        for item in batch:
            name, entry = parse_exercise(item, existing)
            is_new = name not in existing
            existing[name] = entry
            _db.upsert_exercise(entry)
            if is_new:
                new_count += 1
            else:
                upd_count += 1
            print(f"{'✅' if is_new else '🔄'} [{offset:4d}] {name} [{entry['type']} · {entry['category']} · {entry['level']}]")

        offset += BATCH_SIZE

        if offset % 100 == 0:
            print(f"\n─── {offset} traités · {len(existing)} total ───\n")

        time.sleep(0.3)  # Évite le rate limit RapidAPI

    print(f"\n🚀 Import terminé — {new_count} ajoutés · {upd_count} mis à jour · {len(existing)} total")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Import ExerciseDB → TrainingOS inventory")
    parser.add_argument("--total",   type=int, default=1300, help="Nb total d'exercices (défaut: 1300)")
    parser.add_argument("--replace", action="store_true",    help="Remplace tout l'inventaire (défaut: merge)")
    args = parser.parse_args()

    import_exercises(total=args.total, merge=not args.replace)