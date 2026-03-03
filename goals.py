# goals.py
import json
from pathlib import Path
from datetime import datetime

BASE_DIR    = Path(__file__).parent
GOALS_FILE  = BASE_DIR / "data" / "goals.json"


# ─────────────────────────────────────────────────────────────
# LOAD / SAVE
# ─────────────────────────────────────────────────────────────

def load_goals() -> dict:
    if not GOALS_FILE.exists():
        GOALS_FILE.parent.mkdir(parents=True, exist_ok=True)
        return {}
    try:
        with open(GOALS_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except:
        return {}


def save_goals(goals: dict):
    with open(GOALS_FILE, "w", encoding="utf-8") as f:
        json.dump(goals, f, indent=2, ensure_ascii=False)


# ─────────────────────────────────────────────────────────────
# LOGIQUE
# ─────────────────────────────────────────────────────────────

def set_goal(exercise: str, goal_weight: float, deadline: str = None, note: str = ""):
    goals = load_goals()
    goals[exercise] = {
        "goal_weight":  goal_weight,
        "deadline":     deadline,
        "note":         note,
        "created":      datetime.now().strftime("%Y-%m-%d"),
        "achieved":     False,
        "achieved_on":  None
    }
    save_goals(goals)
    print(f"✅ Objectif défini : {exercise} → {goal_weight} lbs")


def check_goals_achieved(weights: dict) -> list[str]:
    """
    Vérifie si des objectifs ont été atteints.
    Retourne la liste des exercices nouvellement atteints.
    """
    goals    = load_goals()
    achieved = []

    for exercise, goal in goals.items():
        if goal.get("achieved"):
            continue

        data           = weights.get(exercise, {})
        current_weight = data.get("current_weight", data.get("weight", 0))

        if current_weight and current_weight >= goal["goal_weight"]:
            goals[exercise]["achieved"]    = True
            goals[exercise]["achieved_on"] = datetime.now().strftime("%Y-%m-%d")
            achieved.append(exercise)

    if achieved:
        save_goals(goals)

    return achieved


def get_progress_bar(current: float, goal: float, width: int = 20) -> str:
    """Retourne une barre de progression ASCII."""
    if goal <= 0:
        return "─" * width
    pct    = min(current / goal, 1.0)
    filled = int(pct * width)
    bar    = "█" * filled + "░" * (width - filled)
    return f"[{bar}] {pct*100:.0f}%"


# ─────────────────────────────────────────────────────────────
# AFFICHAGE
# ─────────────────────────────────────────────────────────────

def afficher_objectifs(weights: dict):
    goals = load_goals()

    if not goals:
        print("\nAucun objectif défini pour l'instant.")
        print("Ajoute-en un via l'option 'Gérer mes objectifs' ! 🎯")
        return

    print(f"\n{'═' * 65}")
    print(f"   🎯 OBJECTIFS PERSONNELS")
    print(f"{'═' * 65}\n")

    actifs   = {k: v for k, v in goals.items() if not v.get("achieved")}
    atteints = {k: v for k, v in goals.items() if v.get("achieved")}

    # Objectifs en cours
    if actifs:
        print("  EN COURS :\n")
        for exercise, goal in actifs.items():
            data           = weights.get(exercise, {})
            current_weight = data.get("current_weight", data.get("weight", 0)) or 0
            goal_weight    = goal["goal_weight"]
            bar            = get_progress_bar(current_weight, goal_weight)
            remaining      = goal_weight - current_weight

            print(f"  🎯 {exercise}")
            print(f"     Objectif  : {goal_weight} lbs")
            print(f"     Actuel    : {current_weight} lbs")
            print(f"     Progrès   : {bar}")
            print(f"     Restant   : {remaining:.1f} lbs")

            if goal.get("deadline"):
                print(f"     Deadline  : {goal['deadline']}")
            if goal.get("note"):
                print(f"     Note      : {goal['note']}")
            print()

    # Objectifs atteints
    if atteints:
        print("  ✅ ATTEINTS :\n")
        for exercise, goal in atteints.items():
            print(f"  🏆 {exercise:<25} {goal['goal_weight']} lbs  "
                  f"(atteint le {goal['achieved_on']})")
        print()

    print(f"{'═' * 65}")


# ─────────────────────────────────────────────────────────────
# GESTION VIA MENU
# ─────────────────────────────────────────────────────────────

def gerer_objectifs(weights: dict):
    from menu_select import selectionner, selectionner_exercice_inventaire
    from inventory import load_inventory

    while True:
        goals = load_goals()

        action = selectionner(
            "Gérer mes objectifs :",
            [
                "🎯 Voir mes objectifs",
                "➕ Ajouter un objectif",
                "✏️  Modifier un objectif",
                "🗑️  Supprimer un objectif",
                "✅ Marquer comme atteint manuellement"
            ]
        )

        if not action or action == "↩ Annuler":
            break

        # ── VOIR ─────────────────────────────────────────
        if action.startswith("🎯"):
            afficher_objectifs(weights)
            input("\nEntrée pour continuer...")

        # ── AJOUTER ──────────────────────────────────────
        elif action.startswith("➕"):
            inv      = load_inventory()
            exercise = selectionner_exercice_inventaire(
                "Pour quel exercice ?", inv
            )
            if not exercise or exercise == "↩ Annuler":
                continue

            # Affiche le poids actuel
            data           = weights.get(exercise, {})
            current_weight = data.get("current_weight", data.get("weight", 0)) or 0
            if current_weight:
                print(f"\n   Poids actuel : {current_weight} lbs")

            goal_str = input("   Objectif (lbs) → ").strip()
            if not goal_str:
                continue
            try:
                goal_weight = float(goal_str.replace(",", "."))
            except ValueError:
                print("❌ Valeur invalide.")
                continue

            deadline = input("   Deadline (ex: 2026-06-01, Entrée=aucune) → ").strip() or None
            note     = input("   Note (Entrée=rien) → ").strip()

            set_goal(exercise, goal_weight, deadline, note)

        # ── MODIFIER ─────────────────────────────────────
        elif action.startswith("✏️"):
            if not goals:
                print("Aucun objectif à modifier.")
                continue

            exercise = selectionner(
                "Quel objectif modifier ?",
                list(goals.keys())
            )
            if not exercise or exercise == "↩ Annuler":
                continue

            goal        = goals[exercise]
            goal_str    = input(f"   Nouvel objectif [{goal['goal_weight']} lbs] → ").strip()
            goal_weight = float(goal_str.replace(",", ".")) if goal_str else goal["goal_weight"]

            deadline = input(f"   Deadline [{goal.get('deadline') or 'aucune'}] → ").strip()
            deadline = deadline or goal.get("deadline")

            note = input(f"   Note [{goal.get('note') or '—'}] → ").strip()
            note = note or goal.get("note", "")

            set_goal(exercise, goal_weight, deadline, note)

        # ── SUPPRIMER ─────────────────────────────────────
        elif action.startswith("🗑️"):
            if not goals:
                print("Aucun objectif à supprimer.")
                continue

            exercise = selectionner(
                "Quel objectif supprimer ?",
                list(goals.keys())
            )
            if not exercise or exercise == "↩ Annuler":
                continue

            confirmer = selectionner(
                f"Supprimer l'objectif '{exercise}' ?",
                ["Oui, supprimer", "Non, annuler"]
            )
            if confirmer == "Oui, supprimer":
                del goals[exercise]
                save_goals(goals)
                print(f"✅ Objectif '{exercise}' supprimé.")

        # ── MARQUER ATTEINT ───────────────────────────────
        elif action.startswith("✅"):
            actifs = {k: v for k, v in goals.items() if not v.get("achieved")}
            if not actifs:
                print("Aucun objectif actif.")
                continue

            exercise = selectionner(
                "Quel objectif marquer comme atteint ?",
                list(actifs.keys())
            )
            if not exercise or exercise == "↩ Annuler":
                continue

            goals[exercise]["achieved"]    = True
            goals[exercise]["achieved_on"] = datetime.now().strftime("%Y-%m-%d")
            save_goals(goals)
            print(f"🏆 Félicitations ! '{exercise}' marqué comme atteint !")