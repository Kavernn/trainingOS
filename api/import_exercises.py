import os
import sys
import requests

# ── Ajoute /api au path pour accéder à db.py ────────────────
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "api"))
from db import get_json, set_json

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
    "glutes":             "hinge",
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


def import_exercises(limit: int = 100, merge: bool = True, offset: int = 0):
    """
    Importe les exercices depuis ExerciseDB et les sauvegarde dans Supabase (kv → inventory).

    Args:
        limit:  Nombre d'exercices à importer (max 100 par appel).
        merge:  Si True, fusionne avec l'inventaire existant. Si False, remplace tout.
        offset: Décalage pour paginer (ex: 100 pour les exercices 100-199).
    """
    print(f"📥 Import ExerciseDB — limit={limit}, offset={offset}, merge={merge}")

    try:
        response = requests.get(
            "https://exercisedb.p.rapidapi.com/exercises",
            headers=HEADERS,
            params={"limit": str(limit), "offset": str(offset)},
            timeout=15
        )
        response.raise_for_status()
        exercises = response.json()
    except Exception as e:
        print(f"❌ Erreur API ExerciseDB : {e}")
        return

    # Charge l'inventaire existant si merge
    existing = get_json("inventory", {}) if merge else {}
    new_count = 0
    updated_count = 0

    for item in exercises:
        exo_id    = item.get("id", "")
        raw_name  = item.get("name", "Unknown")
        name      = raw_name.title()

        body_part = item.get("bodyPart", "").lower()
        equipment = item.get("equipment", "other").lower()
        target    = item.get("target", "").lower()
        secondary = item.get("secondaryMuscles", [])
        instructions = item.get("instructions", [])

        # GIF URL via CDN direct
        formatted_id = str(exo_id).zfill(4)
        gif_url = f"https://edb-4059a1.c.cdn77.org/exercises/{formatted_id}.gif"

        # Résolution des champs
        ex_type   = EQUIPMENT_MAP.get(equipment, "machine")
        category  = CATEGORY_MAP.get(body_part, "push")
        pattern   = PATTERN_MAP.get(target, "isolation")
        level     = guess_level(body_part, equipment)
        bar_weight = 45.0 if ex_type == "barbell" else 0.0

        # Muscles : target + secondaryMuscles
        muscles = [target] if target else []
        muscles += [m.lower() for m in secondary if m.lower() not in muscles]

        # Tips : 2 premières instructions
        tips = ". ".join(instructions[:2]) if instructions else ""

        is_new = name not in existing
        existing[name] = {
            "type":           ex_type,
            "category":       category,
            "pattern":        pattern,
            "level":          level,
            "increment":      existing.get(name, {}).get("increment", 5.0),   # préserve si existant
            "bar_weight":     existing.get(name, {}).get("bar_weight", bar_weight),
            "default_scheme": existing.get(name, {}).get("default_scheme", "3x8-12"),
            "muscles":        muscles,
            "tips":           tips,
            "gif_url":        gif_url,
        }

        status = "✅ NEW" if is_new else "🔄 MAJ"
        if is_new:
            new_count += 1
        else:
            updated_count += 1
        print(f"{status} {name} [{ex_type} · {category} · {level}]")

    # Sauvegarde dans Supabase via db.py
    ok = set_json("inventory", existing)
    total = len(existing)

    if ok:
        print(f"\n🚀 Inventaire sauvegardé dans Supabase !")
    else:
        print(f"\n⚠️  Sauvegarde échouée (Supabase indisponible, SQLite local utilisé)")

    print(f"📊 {new_count} ajoutés · {updated_count} mis à jour · {total} total dans l'inventaire")


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="Import ExerciseDB → TrainingOS inventory")
    parser.add_argument("--limit",  type=int, default=100, help="Nb d'exercices (défaut: 100)")
    parser.add_argument("--offset", type=int, default=0,   help="Offset pagination (défaut: 0)")
    parser.add_argument("--replace", action="store_true",  help="Remplace tout l'inventaire (défaut: merge)")
    args = parser.parse_args()

    import_exercises(limit=args.limit, merge=not args.replace, offset=args.offset)