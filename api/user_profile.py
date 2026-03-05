# user_profile.py

from pathlib import Path
import json
from datetime import datetime

from pathlib import Path
BASE_DIR  = Path(__file__).parent
USER_FILE = BASE_DIR / "data" / "user.json"

DEFAULT_USER = {
    "name": "Vince",
    "age": None,
    "weight_kg": None,
    "height_cm": None,
    "sex": None,  # "m" ou "f"
    "level": "intermédiaire",  # débutant / intermédiaire / avancé
    "goal": "force",  # force / hypertrophie / perte de poids / recomposition
    "units": "lbs",  # lbs ou kg
    "created": datetime.now().isoformat(),
    "last_updated": None
}


def load_user_profile() -> dict:
    if not USER_FILE.exists():
        USER_FILE.parent.mkdir(parents=True, exist_ok=True)
        with open(USER_FILE, "w", encoding="utf-8") as f:
            json.dump(DEFAULT_USER, f, indent=2, ensure_ascii=False)
        return DEFAULT_USER.copy()

    try:
        with open(USER_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data
    except:
        return DEFAULT_USER.copy()


def save_user_profile(profile: dict):
    profile["last_updated"] = datetime.now().isoformat()
    with open(USER_FILE, "w", encoding="utf-8") as f:
        json.dump(profile, f, indent=2, ensure_ascii=False)


def setup_user_profile():
    """Questionnaire rapide au premier lancement ou via menu"""
    profile = load_user_profile()

    print("\n" + "═" * 50)
    print("   CONFIGURATION PROFIL PERSONNEL")
    print("═" * 50)
    print("Pour te donner des conseils plus adaptés, remplis ces infos (tu peux skip avec Entrée)\n")
    from menu_select import selectionner
    profile["name"] = input(f"Prénom / surnom (actuel: {profile['name']}) → ").strip() or profile["name"]
    profile["age"] = input(f"Âge (actuel: {profile['age'] or '?'}) → ").strip() or profile["age"]
    profile["weight_kg"] = input(f"Poids actuel (kg) (actuel: {profile['weight_kg'] or '?'}) → ").strip() or profile["weight_kg"]
    profile["height_cm"] = input(f"Taille (cm) (actuel: {profile['height_cm'] or '?'}) → ").strip() or profile["height_cm"]
    sex = selectionner("Sexe :", ["m", "f"])
    profile["sex"] = sex or profile["sex"]

    level = selectionner("Niveau :", ["débutant", "intermédiaire", "avancé"])
    profile["level"] = level or profile["level"]
    goal = selectionner("Objectif principal :", ["force", "hypertrophie", "perte de poids", "recomposition"])
    profile["goal"] = goal or profile["goal"]
    units = selectionner("Unités préférées :", ["lbs", "kg"])
    profile["units"] = units or profile["units"]

    save_user_profile(profile)
    print("\nProfil sauvegardé ! Ton assistant est maintenant personnalisé 💪")