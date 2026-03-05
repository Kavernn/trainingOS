# deload.py
import json
from pathlib import Path
from sessions import load_sessions

BASE_DIR      = Path(__file__).parent
DATA_FILE     = BASE_DIR / "data" / "weights.json"
DELOAD_FILE   = BASE_DIR / "data" / "deload.json"

STAGNATION_THRESHOLD = 3    # nb de séances au même poids = stagnation
RPE_FATIGUE_THRESHOLD = 8.5 # RPE moyen au dessus de ça = fatigue
DELOAD_FACTOR = 0.85        # -15% pendant le deload


# ─────────────────────────────────────────────────────────────
# DÉTECTION STAGNATION PAR EXERCICE
# ─────────────────────────────────────────────────────────────

def detect_stagnation(weights: dict) -> list[dict]:
    """Retourne la liste des exercices stagnants."""
    stagnants = []

    for ex, data in weights.items():
        if ex == "sessions":
            continue
        hist = data.get("history", [])
        if len(hist) < STAGNATION_THRESHOLD:
            continue

        last_n = hist[:STAGNATION_THRESHOLD]
        poids  = [e["weight"] for e in last_n]

        if len(set(poids)) == 1:
            stagnants.append({
                "exercise":  ex,
                "weight":    poids[0],
                "séances":   len(hist),
                "stagnation": STAGNATION_THRESHOLD
            })

    return stagnants


# ─────────────────────────────────────────────────────────────
# DÉTECTION FATIGUE VIA RPE
# ─────────────────────────────────────────────────────────────

def detect_fatigue_rpe() -> dict:
    """Analyse le RPE des 3 dernières séances."""
    sessions = load_sessions()
    if not sessions:
        return {"fatigue": False, "rpe_moyen": None, "nb_seances": 0}

    rpes = []
    for date_key in sorted(sessions.keys(), reverse=True)[:3]:
        rpe = sessions[date_key].get("rpe")
        if rpe:
            rpes.append(rpe)

    if not rpes:
        return {"fatigue": False, "rpe_moyen": None, "nb_seances": 0}

    rpe_moyen = sum(rpes) / len(rpes)
    return {
        "fatigue":    rpe_moyen >= RPE_FATIGUE_THRESHOLD,
        "rpe_moyen":  round(rpe_moyen, 1),
        "nb_seances": len(rpes)
    }


# ─────────────────────────────────────────────────────────────
# CALCUL DES POIDS DE DELOAD
# ─────────────────────────────────────────────────────────────

def calculer_poids_deload(weights: dict, exercices: list[str] = None) -> dict:
    """
    Calcule les poids de deload pour tous les exercices
    ou seulement ceux passés en paramètre.
    """
    result = {}
    cibles = exercices or [k for k in weights if k != "sessions"]

    for ex in cibles:
        data = weights.get(ex, {})
        poids_actuel = data.get("current_weight", data.get("weight", 0))
        if poids_actuel:
            result[ex] = {
                "poids_actuel": round(poids_actuel, 1),
                "poids_deload": round(poids_actuel * DELOAD_FACTOR, 1)
            }

    return result


# ─────────────────────────────────────────────────────────────
# SAUVEGARDE / CHARGEMENT ÉTAT DELOAD
# ─────────────────────────────────────────────────────────────

def load_deload_state() -> dict:
    if not DELOAD_FILE.exists():
        return {"active": False, "since": None, "reason": None}
    try:
        with open(DELOAD_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except:
        return {"active": False, "since": None, "reason": None}


def save_deload_state(state: dict):
    with open(DELOAD_FILE, "w", encoding="utf-8") as f:
        json.dump(state, f, indent=2, ensure_ascii=False)


def activer_deload(reason: str):
    from datetime import datetime
    state = {
        "active": True,
        "since":  datetime.now().strftime("%Y-%m-%d"),
        "reason": reason
    }
    save_deload_state(state)


def desactiver_deload():
    save_deload_state({"active": False, "since": None, "reason": None})


# ─────────────────────────────────────────────────────────────
# ANALYSE COMPLÈTE + RAPPORT
# ─────────────────────────────────────────────────────────────

def analyser_deload(weights: dict) -> dict:
    """
    Analyse complète — retourne un rapport avec :
    - stagnations détectées
    - fatigue RPE
    - recommandation deload oui/non
    - poids suggérés si deload
    """
    stagnants = detect_stagnation(weights)
    fatigue   = detect_fatigue_rpe()
    state     = load_deload_state()

    recommande = len(stagnants) >= 2 or fatigue["fatigue"]

    rapport = {
        "deload_actif":   state["active"],
        "deload_since":   state.get("since"),
        "deload_reason":  state.get("reason"),
        "stagnants":      stagnants,
        "fatigue_rpe":    fatigue,
        "recommande":     recommande,
        "poids_deload":   calculer_poids_deload(weights, [s["exercise"] for s in stagnants]) if recommande else {}
    }

    return rapport


# ─────────────────────────────────────────────────────────────
# AFFICHAGE TERMINAL
# ─────────────────────────────────────────────────────────────

def afficher_rapport_deload(weights: dict):
    from menu_select import selectionner

    rapport = analyser_deload(weights)

    print(f"\n{'═' * 60}")
    print(f"   ANALYSE DELOAD")
    print(f"{'═' * 60}\n")

    # Statut actuel
    if rapport["deload_actif"]:
        print(f"  🔄 DELOAD EN COURS depuis le {rapport['deload_since']}")
        print(f"     Raison : {rapport['deload_reason']}")
        print()
        choix = selectionner(
            "Le deload est terminé ?",
            ["Oui, reprendre l'entraînement normal", "Non, continuer le deload"]
        )
        if choix == "Oui, reprendre l'entraînement normal":
            desactiver_deload()
            print("✅ Deload terminé – retour aux poids normaux !")
        return

    # Stagnation
    if rapport["stagnants"]:
        print(f"  ⚠️  STAGNATION DÉTECTÉE sur {len(rapport['stagnants'])} exercice(s) :\n")
        for s in rapport["stagnants"]:
            print(f"    • {s['exercise']:<25} {s['weight']} lbs × {s['stagnation']} séances")
        print()
    else:
        print("  ✅ Aucune stagnation détectée\n")

    # Fatigue RPE
    fatigue = rapport["fatigue_rpe"]
    if fatigue["rpe_moyen"]:
        emoji = "🔴" if fatigue["fatigue"] else "🟢"
        print(f"  {emoji} RPE moyen (3 dernières séances) : {fatigue['rpe_moyen']}/10")
        if fatigue["fatigue"]:
            print(f"     → RPE élevé, signe de fatigue accumulée")
        print()
    else:
        print("  ℹ️  Pas assez de données RPE pour analyser la fatigue\n")

    # Recommandation
    if rapport["recommande"]:
        print(f"  💡 RECOMMANDATION : Semaine de deload suggérée\n")
        print(f"  Poids suggérés à -15% :\n")
        for ex, p in rapport["poids_deload"].items():
            print(f"    • {ex:<25} {p['poids_actuel']} lbs → {p['poids_deload']} lbs")
        print()

        choix = selectionner(
            "Activer la semaine de deload ?",
            ["Oui, activer le deload", "Non, continuer normal"]
        )

        if choix == "Oui, activer le deload":
            raison = "stagnation + RPE élevé" if fatigue["fatigue"] else "stagnation"
            activer_deload(raison)
            print(f"\n✅ Deload activé ! Les poids recommandés sont à -15%.")
            print(f"   Reviens ici en fin de semaine pour le désactiver.")
        else:
            print("OK – on continue à pousser ! 💪")
    else:
        print("  ✅ Pas besoin de deload pour l'instant – continue le grind ! 🔥")

    print(f"\n{'═' * 60}")