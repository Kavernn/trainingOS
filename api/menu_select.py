# menu_select.py
import questionary
from questionary import Style

STYLE = Style([
    ("selected",        "fg:#f97316 bold"),
    ("pointer",         "fg:#f97316 bold"),
    ("highlighted",     "fg:#f97316"),
    ("answer",          "fg:#22c55e bold"),
    ("question",        "fg:#e0e0e0 bold"),
    ("instruction",     "fg:#666666"),
])

def selectionner(message: str, choix: list[str]) -> str | None:
    """Menu flèches simple – retourne le choix ou None si annulé."""
    if not choix:
        print("Aucun choix disponible.")
        return None
    return questionary.select(
        message,
        choices=choix + ["↩ Annuler"],
        style=STYLE
    ).ask()


def selectionner_exercice_inventaire(message: str, inventaire: dict) -> str | None:
    """Sélectionne un exercice depuis l'inventaire avec infos affichées."""
    if not inventaire:
        print("Inventaire vide.")
        return None

    choix_affiches = []
    map_affiche_vers_nom = {}

    for nom, info in sorted(inventaire.items()):
        muscles = ", ".join(info.get("muscles", [])) or "—"
        label = f"{nom:<25} [{info['type']:<9}] {info.get('default_scheme','—'):<10} {muscles}"
        choix_affiches.append(label)
        map_affiche_vers_nom[label] = nom

    choix_affiches.append("↩ Annuler")

    resultat = questionary.select(
        message,
        choices=choix_affiches,
        style=STYLE
    ).ask()

    if not resultat or resultat == "↩ Annuler":
        return None

    return map_affiche_vers_nom.get(resultat)


def selectionner_exercice_programme(message: str, programme_jour: dict) -> str | None:
    """Sélectionne un exercice déjà dans le programme d'un jour."""
    if not programme_jour:
        print("Aucun exercice dans ce programme.")
        return None

    choix_affiches = []
    map_affiche_vers_nom = {}

    for nom, scheme in programme_jour.items():
        label = f"{nom:<25} {scheme}"
        choix_affiches.append(label)
        map_affiche_vers_nom[label] = nom

    choix_affiches.append("↩ Annuler")

    resultat = questionary.select(
        message,
        choices=choix_affiches,
        style=STYLE
    ).ask()

    if not resultat or resultat == "↩ Annuler":
        return None

    return map_affiche_vers_nom.get(resultat)

def menu_principal(message: str, choix: list[str]) -> str | None:
    """Menu principal avec flèches et Enter."""
    if not choix:
        return None
    return questionary.select(
        message,
        choices=choix,
        style=STYLE
    ).ask()