# body_weight.py
import json
from pathlib import Path
from datetime import datetime

BASE_DIR        = Path(__file__).parent
BODYWEIGHT_FILE = BASE_DIR / "data" / "body_weight.json"


def load_body_weight() -> list:
    if not BODYWEIGHT_FILE.exists():
        BODYWEIGHT_FILE.parent.mkdir(parents=True, exist_ok=True)
        return []
    try:
        with open(BODYWEIGHT_FILE, "r", encoding="utf-8") as f:
            return json.load(f)
    except:
        return []


def save_body_weight(entries: list):
    with open(BODYWEIGHT_FILE, "w", encoding="utf-8") as f:
        json.dump(entries, f, indent=2, ensure_ascii=False)


def log_body_weight(poids: float, note: str = ""):
    entries = load_body_weight()
    today   = datetime.now().strftime("%Y-%m-%d")

    # Si déjà loggué aujourd'hui → on écrase
    entries = [e for e in entries if e["date"] != today]
    entries.append({
        "date":  today,
        "poids": round(poids, 1),
        "note":  note
    })

    entries = sorted(entries, key=lambda x: x["date"], reverse=True)
    save_body_weight(entries)
    print(f"✅ Poids loggué : {poids} kg le {today}")


def get_last_body_weight(n: int = 30) -> list:
    entries = load_body_weight()
    return entries[:n]


def get_tendance(entries: list) -> str:
    """Calcule la tendance sur les 7 derniers jours."""
    if len(entries) < 2:
        return "Pas assez de données"

    recent = entries[:7]
    if len(recent) < 2:
        return "Pas assez de données"

    diff = recent[0]["poids"] - recent[-1]["poids"]

    if abs(diff) < 0.3:
        return f"Stable ↔️  ({recent[0]['poids']} kg)"
    elif diff > 0:
        return f"En hausse ↑ +{diff:.1f} kg sur {len(recent)} jours"
    else:
        return f"En baisse ↓ {diff:.1f} kg sur {len(recent)} jours"


def afficher_historique_poids(max_entries: int = 14):
    entries = load_body_weight()

    if not entries:
        print("\nAucun poids loggué pour l'instant.")
        print("Utilise l'option 'Logger mon poids' pour commencer !")
        return

    print(f"\n{'═' * 50}")
    print(f"   SUIVI POIDS CORPOREL")
    print(f"{'═' * 50}")
    print(f"  Tendance : {get_tendance(entries)}\n")
    print(f"  {'Date':<12} {'Poids':<10} Note")
    print("  " + "─" * 40)

    for entry in entries[:max_entries]:
        note = entry.get("note", "") or "—"
        print(f"  {entry['date']:<12} {entry['poids']:<10} {note}")

    print("  " + "─" * 40)
    if len(entries) > max_entries:
        print(f"  ... et {len(entries) - max_entries} entrées plus anciennes")
    print(f"{'═' * 50}")