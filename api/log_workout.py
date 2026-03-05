# log_workout.py
import json
from pathlib import Path
from datetime import datetime
from typing import Dict, Any

from progression import should_increase, next_weight, progression_status, parse_reps, estimate_1rm
from inventory import load_inventory, add_exercise

BASE_DIR  = Path(__file__).parent
DATA_FILE = BASE_DIR / "data" / "weights.json"
HIIT_FILE = BASE_DIR / "data" / "hiit_log.json"


# ─────────────────────────────────────────────────────────────
# WEIGHTS
# ─────────────────────────────────────────────────────────────

def load_weights() -> Dict[str, Any]:

    if not DATA_FILE.exists():
        DATA_FILE.parent.mkdir(parents=True, exist_ok=True)
        return {}
    try:
        with open(DATA_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
        return data if isinstance(data, dict) else {}
    except:
        return {}


def save_weights(weights: Dict[str, Any]):
    try:
        with open(DATA_FILE, "w", encoding="utf-8") as f:
            json.dump(weights, f, indent=2, ensure_ascii=False)
    except Exception as e:
        print(f"Erreur sauvegarde weights : {e}")


# ─────────────────────────────────────────────────────────────
# LOG UN EXERCICE
# ─────────────────────────────────────────────────────────────

def log_single_exercise(exercise: str, weights: Dict[str, Any]) -> Dict[str, Any]:
    data = weights.copy() if isinstance(weights, dict) else {}

    print(f"\n{'─' * 65}")
    print(f"📌 {exercise}")

    # ── Dernière séance ───────────────────────────────────
    last = data.get(exercise, {})
    if last and "history" in last and last["history"]:
        last_entry = last["history"][0]
        print(f"   Dernière : {last_entry['weight']} lbs | {last_entry['reps']} | {last_entry.get('note', '—')}")

    # ── Inventaire ────────────────────────────────────────
    inv     = load_inventory()
    ex_info = inv.get(exercise)

    if ex_info:
        ex_type = ex_info["type"]
        inc     = ex_info["increment"]
        bar_w   = ex_info.get("bar_weight", 45.0)
        print(f"   Type détecté : {ex_type} (incrément auto {inc} lbs)")
    else:
        print(f"   ⚠️ '{exercise}' pas encore dans l'inventaire (on va l'ajouter après)")
        ex_type = None
        inc     = 5.0
        bar_w   = 45.0

    # ── Échauffement ──────────────────────────────────────
    try:
        from warmup import proposer_warmup
        from planner import PROGRAM, get_today
        proposer_warmup(exercise, data, inv, PROGRAM, get_today())
    except:
        pass

    # ── Saisie du poids ───────────────────────────────────
    skip         = False
    total_weight = 0.0
    input_value  = 0.0

    if ex_type == "barbell":
        val = input(f"   Poids par côté (plaques seulement) → ").strip()
        if not val:
            skip = True
        else:
            side         = float(val.replace(",", "."))
            total_weight = side * 2 + bar_w
            input_value  = side
            print(f"   Total : {total_weight:.1f} lbs")

    elif ex_type == "dumbbell":
        val = input(f"   Poids par haltère → ").strip()
        if not val:
            skip = True
        else:
            per          = float(val.replace(",", "."))
            total_weight = per * 2
            input_value  = per
            print(f"   Total : {total_weight:.1f} lbs")

    else:
        val = input(f"   Poids total (machine etc.) → ").strip()
        if not val:
            skip = True
        else:
            total_weight = float(val.replace(",", "."))
            input_value  = total_weight
            print(f"   Total : {total_weight:.1f} lbs")

    if skip:
        print("   Exercice passé")
        return data

    # ── Reps ──────────────────────────────────────────────
    reps_input = input("\n   Reps par série (ex: 7,6,5,5) → ").strip()
    if not reps_input:
        print("   Exercice passé")
        return data

    reps_list = parse_reps(reps_input)
    reps_str  = ",".join(map(str, reps_list))

    # ── Progression ───────────────────────────────────────
    print(f"   {progression_status(reps_str, exercise)}")

    if should_increase(reps_str, exercise):
        new_weight = next_weight(exercise, total_weight)
        print(f"   ✅ Augmente → {new_weight:.1f} lbs")
    else:
        new_weight = total_weight
        print(f"   🔄 Même poids")

    print(f"   1RM estimé : {estimate_1rm(total_weight, reps_str)} lbs")

    # ── Timer de repos ────────────────────────────────────
    from timer import demander_timer
    scheme = ""
    try:
        from planner import PROGRAM, get_today
        today = get_today()
        if today in PROGRAM and exercise in PROGRAM[today]:
            scheme = PROGRAM[today][exercise]
    except:
        pass
    demander_timer(exercise, scheme)

    # ── Sauvegarde ────────────────────────────────────────
    note = f"+{new_weight - total_weight:.1f}" if should_increase(reps_str, exercise) else "stagné"

    history_entry = {
        "date":   datetime.now().strftime("%Y-%m-%d"),
        "weight": round(total_weight, 1),
        "reps":   reps_str,
        "note":   note,
        "1rm":    estimate_1rm(total_weight, reps_str)
    }

    if exercise not in data:
        data[exercise] = {"history": []}

    data[exercise].setdefault("history", []).insert(0, history_entry)
    data[exercise]["history"] = data[exercise]["history"][:20]

    data[exercise]["current_weight"] = round(new_weight, 1)
    data[exercise]["last_reps"]      = reps_str
    data[exercise]["last_logged"]    = datetime.now().strftime("%Y-%m-%d %H:%M")
    data[exercise]["input_type"]     = ex_type or "machine"
    data[exercise]["input_value"]    = round(input_value, 1)

    # ── Exercice inconnu → ajout inventaire ───────────────
    if not ex_info:
        print("\n   Ajout automatique à l'inventaire...")
        from menu_select import selectionner
        t = selectionner("Type d'exercice :", [
            "barbell", "dumbbell", "machine", "bodyweight", "cable"
        ]) or "machine"
        inc_input_str = input("   Incrément par défaut (ex: 5) → ").strip()
        inc_input     = float(inc_input_str) if inc_input_str else 5.0
        add_exercise(exercise, t, inc_input)

    return data


# ─────────────────────────────────────────────────────────────
# HISTORIQUE D'UN EXERCICE
# ─────────────────────────────────────────────────────────────

def show_exercise_history(exercise: str, weights: dict, max_entries: int = 8):
    data = weights.get(exercise)
    if not data or "history" not in data or not data["history"]:
        print(f"\nAucun historique pour {exercise} (pas encore logué).")
        return

    print(f"\n{'═' * 70}")
    print(f"  HISTORIQUE — {exercise}")
    print(f"{'═' * 70}")
    print(f"{'Date':<12} {'Poids total':<14} {'Reps':<16} {'Note':<10} {'1RM':<12} Input")
    print("─" * 70)

    for entry in data["history"][:max_entries]:
        date   = entry["date"]
        weight = f"{entry['weight']:.1f} lbs"
        reps   = entry["reps"]
        note   = entry.get("note", "—") or "—"
        onerm  = f"{entry['1rm']:.1f} lbs" if entry.get("1rm") else "—"

        input_info = ""
        if data.get("input_type") == "barbell":
            input_info = f"{data['input_value']:.1f} par côté"
        elif data.get("input_type") == "dumbbell":
            input_info = f"{data['input_value']:.1f} par haltère"

        print(f"{date:<12} {weight:<14} {reps:<16} {note:<10} {onerm:<12} {input_info}")

    print("─" * 70)
    if len(data["history"]) > max_entries:
        print(f"  ... et {len(data['history']) - max_entries} entrées plus anciennes")
    print(f"{'═' * 70}")


# ─────────────────────────────────────────────────────────────
# LOG HIIT
# ─────────────────────────────────────────────────────────────

def log_hiit_session(week: int) -> dict:
    from hiit import get_hiit_str, get_hiit
    from menu_select import selectionner

    print(f"\n{'═' * 60}")
    print(f"  LOG HIIT – Semaine {week}")
    print(f"  Programme : {get_hiit_str(week)}")
    print(f"{'═' * 60}\n")

    # Rounds complétés
    planned_rounds = get_hiit(week)["rounds"]
    rounds_str     = input(f"Rounds complétés (Entrée = {planned_rounds} planifiés) → ").strip()
    rounds         = int(rounds_str) if rounds_str.isdigit() else planned_rounds

    # Vitesse max
    speed_str = input("Vitesse max atteinte (km/h, Entrée=skip) → ").strip()
    speed     = speed_str.replace(",", ".") if speed_str else None

    # RPE
    rpe_str = input("RPE (1-10, Entrée=skip) → ").strip()
    rpe     = int(rpe_str) if rpe_str.isdigit() and 1 <= int(rpe_str) <= 10 else None

    # Ressenti
    feeling = selectionner("Ressenti global :", [
        "Facile 😎",
        "Correct 💪",
        "Difficile 😤",
        "Épuisant 💀"
    ]) or "—"

    # Commentaire libre
    comment = input("\nCommentaire libre (Entrée=rien) → ").strip()

    entry = {
        "date":             datetime.now().strftime("%Y-%m-%d"),
        "week":             week,
        "programme":        get_hiit_str(week),
        "rounds_planifiés": planned_rounds,
        "rounds_complétés": rounds,
        "vitesse_max":      speed,
        "rpe":              rpe,
        "feeling":          feeling,
        "comment":          comment
    }

    # Chargement + sauvegarde
    if HIIT_FILE.exists():
        with open(HIIT_FILE, "r", encoding="utf-8") as f:
            hiit_log = json.load(f)
    else:
        HIIT_FILE.parent.mkdir(parents=True, exist_ok=True)
        hiit_log = []

    hiit_log.insert(0, entry)

    with open(HIIT_FILE, "w", encoding="utf-8") as f:
        json.dump(hiit_log, f, indent=2, ensure_ascii=False)

    print(f"\n✅ HIIT loggué ! ({rounds}/{planned_rounds} rounds – {feeling})\n")
    return entry


# ─────────────────────────────────────────────────────────────
# HISTORIQUE HIIT
# ─────────────────────────────────────────────────────────────

def show_hiit_history(max_entries: int = 10):
    if not HIIT_FILE.exists():
        print("\nAucun HIIT loggué pour l'instant.")
        return

    with open(HIIT_FILE, "r", encoding="utf-8") as f:
        hiit_log = json.load(f)

    if not hiit_log:
        print("\nAucun HIIT loggué pour l'instant.")
        return

    print(f"\n{'═' * 75}")
    print(f"  HISTORIQUE HIIT")
    print(f"{'═' * 75}")
    print(f"{'Date':<12} {'S.':<4} {'Rounds':<10} {'Vitesse':<12} {'RPE':<6} {'Feeling':<15} Commentaire")
    print("─" * 75)

    for entry in hiit_log[:max_entries]:
        rounds  = f"{entry['rounds_complétés']}/{entry['rounds_planifiés']}"
        speed   = f"{entry['vitesse_max']} km/h" if entry.get("vitesse_max") else "—"
        rpe     = str(entry["rpe"]) if entry.get("rpe") else "—"
        feeling = entry.get("feeling", "—")
        comment = entry.get("comment", "—") or "—"
        print(f"{entry['date']:<12} {entry['week']:<4} {rounds:<10} {speed:<12} {rpe:<6} {feeling:<15} {comment}")

    print("─" * 75)
    if len(hiit_log) > max_entries:
        print(f"  ... et {len(hiit_log) - max_entries} entrées plus anciennes")
    print(f"{'═' * 75}")