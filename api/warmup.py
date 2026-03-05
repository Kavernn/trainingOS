# warmup.py
from pathlib import Path


# ─────────────────────────────────────────────────────────────
# CALCUL DES SÉRIES D'ÉCHAUFFEMENT
# ─────────────────────────────────────────────────────────────

# Exercices qui nécessitent un échauffement complet
NEEDS_WARMUP = [
    "Bench Press", "Back Squat", "Romanian Deadlift",
    "Overhead Press", "Barbell Row", "Deadlift"
]

# Exercices qui n'ont pas besoin d'échauffement dédié
NO_WARMUP = [
    "Lateral Raises", "Face Pull", "Hammer Curl",
    "Triceps Extension", "Calf Raise", "Abs"
]

# Protocole d'échauffement standard
# (pourcentage du poids de travail, reps, repos en secondes)
WARMUP_PROTOCOL = [
    {"pct": 0.0,  "reps": 10, "label": "Barre seule",  "repos": 60},
    {"pct": 0.40, "reps": 8,  "label": "40%",          "repos": 60},
    {"pct": 0.60, "reps": 5,  "label": "60%",          "repos": 90},
    {"pct": 0.75, "reps": 3,  "label": "75%",          "repos": 90},
    {"pct": 0.90, "reps": 1,  "label": "90%",          "repos": 120},
]


def calculer_warmup(exercise: str, working_weight: float, ex_type: str = "barbell", bar_weight: float = 45.0) -> list[dict]:
    """
    Calcule les séries d'échauffement pour un exercice.
    Retourne une liste de séries avec poids et reps.
    """
    if exercise in NO_WARMUP:
        return []

    # Pas d'échauffement si poids trop léger
    if working_weight < 50:
        return []

    series = []

    for step in WARMUP_PROTOCOL:
        pct = step["pct"]

        if pct == 0.0:
            # Barre seule
            if ex_type == "barbell":
                poids = bar_weight
            else:
                continue  # Pas de barre seule pour dumbbell/machine
        else:
            poids = working_weight * pct

        # Arrondi au 2.5 le plus proche
        poids = round(poids / 2.5) * 2.5

        # Pas de doublon avec le poids de travail
        if poids >= working_weight * 0.95:
            continue

        if ex_type == "barbell":
            plaques = (poids - bar_weight) / 2
            if plaques < 0:
                plaques = 0
            display = f"{poids:.1f} lbs ({plaques:.1f} par côté)"
        elif ex_type == "dumbbell":
            par_halter = poids / 2
            display = f"{poids:.1f} lbs ({par_halter:.1f} par haltère)"
        else:
            display = f"{poids:.1f} lbs"

        series.append({
            "label":  step["label"],
            "poids":  poids,
            "reps":   step["reps"],
            "repos":  step["repos"],
            "display": display
        })

    return series


def afficher_warmup(exercise: str, working_weight: float, ex_type: str = "barbell", bar_weight: float = 45.0):
    """Affiche les séries d'échauffement dans le terminal."""
    series = calculer_warmup(exercise, working_weight, ex_type, bar_weight)

    if not series:
        return

    print(f"\n{'─' * 60}")
    print(f"  🔥 ÉCHAUFFEMENT — {exercise}")
    print(f"{'─' * 60}")
    print(f"  {'Série':<10} {'Poids':<25} {'Reps':<8} Repos")
    print(f"  {'─' * 55}")

    for i, s in enumerate(series, 1):
        repos = f"{s['repos']}s"
        print(f"  {i}. {s['label']:<8}  {s['display']:<25} {s['reps']} reps   {repos}")

    print(f"  {'─' * 55}")
    print(f"  → Poids de travail : {working_weight:.1f} lbs\n")


def proposer_warmup(exercise: str, weights: dict, inv: dict, program: dict, today: str) -> bool:
    """
    Propose l'échauffement avant de logger un exercice.
    Retourne True si l'échauffement a été fait.
    """
    from menu_select import selectionner
    from timer import countdown

    # Récupère les infos de l'exercice
    ex_info       = inv.get(exercise, {})
    ex_type       = ex_info.get("type", "machine")
    bar_weight    = ex_info.get("bar_weight", 45.0)

    # Récupère le poids de travail prévu
    data           = weights.get(exercise, {})
    working_weight = data.get("current_weight", data.get("weight", 0))

    if not working_weight or working_weight < 50:
        return False

    # Vérifie si l'exercice mérite un échauffement
    series = calculer_warmup(exercise, working_weight, ex_type, bar_weight)
    if not series:
        return False

    afficher_warmup(exercise, working_weight, ex_type, bar_weight)

    choix = selectionner(
        "Faire l'échauffement ?",
        ["Oui, je suis le protocole 🔥", "Non, je skip"]
    )

    if choix != "Oui, je suis le protocole 🔥":
        return False

    # Guide série par série
    print()
    for i, s in enumerate(series, 1):
        print(f"\n  Série {i}/{len(series)} — {s['label']} : {s['display']} × {s['reps']} reps")
        input("  Appuie sur Entrée quand tu es prêt...")
        input(f"  Fais tes {s['reps']} reps... Appuie sur Entrée quand c'est fait ✅")

        if i < len(series):
            from timer import countdown
            countdown(s["repos"], f"Repos avant série {i + 1}")

    print(f"\n  ✅ Échauffement terminé – c'est parti pour le travail ! 💪")
    return True