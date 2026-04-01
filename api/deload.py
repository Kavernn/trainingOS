# deload.py
import json
from pathlib import Path
from sessions import load_sessions
from db import get_json, set_json


BASE_DIR      = Path(__file__).parent
DATA_FILE     = BASE_DIR / "data" / "weights.json"
DELOAD_FILE   = BASE_DIR / "data" / "deload.json"

STAGNATION_THRESHOLD  = 3    # nb de séances au même poids = stagnation
RPE_FATIGUE_THRESHOLD = 8.5  # RPE moyen au dessus de ça = fatigue
DELOAD_FACTOR         = 0.85 # -15% pendant le deload
PLANNED_DELOAD_WEEKS  = 8    # deload planifié toutes les N semaines


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
# DÉTECTION CHUTE DE PERFORMANCE (1RM)
# ─────────────────────────────────────────────────────────────

def detect_performance_drop(weights: dict, threshold: float = 0.10) -> list[dict]:
    """
    Détecte les exercices où le 1RM a chuté d'au moins `threshold` (défaut 10%)
    sur les 3 dernières séances.
    """
    drops = []
    for ex, data in weights.items():
        if ex == "sessions":
            continue
        hist = data.get("history", [])
        onerm_vals = [float(e["1rm"]) for e in hist[:3] if e.get("1rm")]
        if len(onerm_vals) < 2:
            continue
        best_recent = onerm_vals[0]   # séance la plus récente
        oldest      = onerm_vals[-1]  # la plus ancienne des 3
        if oldest > 0 and (oldest - best_recent) / oldest >= threshold:
            drops.append({
                "exercise":   ex,
                "drop_pct":   round((oldest - best_recent) / oldest * 100, 1),
                "1rm_recent": best_recent,
                "1rm_prev":   oldest,
            })
    return drops


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
    return get_json("deload_state", {"active": False})

def save_deload_state(state: dict):
    set_json("deload_state", state)


def get_cached_fatigue_score() -> int:
    """
    Return today's fatigue score (0–100). Cached in KV daily to avoid
    redundant Supabase reads on every exercise log.
    """
    from datetime import date
    today = date.today().isoformat()
    cached = get_json("fatigue_score_cache", {})
    if isinstance(cached, dict) and cached.get("date") == today:
        return int(cached.get("score", 0))
    result = compute_fatigue_score()
    set_json("fatigue_score_cache", {"date": today, "score": result["score"]})
    return result["score"]


def check_planned_deload() -> dict:
    """
    Check if a planned deload is due based on time elapsed since last deload.
    Returns {due: bool, weeks_since: float | None}.
    """
    from datetime import date
    state = load_deload_state()
    last_str = state.get("last_completed")
    if not last_str:
        return {"due": False, "weeks_since": None}
    try:
        last = date.fromisoformat(last_str)
        weeks_since = (date.today() - last).days / 7
        return {
            "due":         weeks_since >= PLANNED_DELOAD_WEEKS,
            "weeks_since": round(weeks_since, 1),
        }
    except Exception:
        return {"due": False, "weeks_since": None}


def activer_deload(reason: str):
    from datetime import datetime
    state = {
        "active": True,
        "since":  datetime.now().strftime("%Y-%m-%d"),
        "reason": reason
    }
    save_deload_state(state)


def desactiver_deload():
    from datetime import date
    state = load_deload_state()
    save_deload_state({
        "active":         False,
        "since":          None,
        "reason":         None,
        "last_completed": date.today().isoformat(),
        # Preserve previous last_completed if already set (only overwrite on actual deload end)
    })


# ─────────────────────────────────────────────────────────────
# SCORE DE FATIGUE CONTINU (0–100)
# ─────────────────────────────────────────────────────────────

def compute_fatigue_score() -> dict:
    """
    Score de fatigue 0–100 basé sur 4 composantes :
      - RPE 7j vs baseline 30j         (0–40 pts)
      - Streak consécutif sans repos   (0–20 pts)
      - Volume 7j vs moyenne hebdo 4s  (0–20 pts)
      - Fréquence 7j vs baseline 30j   (0–20 pts)
    """
    from datetime import date, timedelta

    sessions = load_sessions()
    if not sessions:
        return {"score": 0, "components": {"rpe": 0, "streak": 0, "volume": 0, "frequency": 0}, "streak_days": 0}

    today = date.today()
    dates_7j  = [(today - timedelta(days=i)).isoformat() for i in range(7)]
    dates_30j = [(today - timedelta(days=i)).isoformat() for i in range(30)]

    # ── RPE (0–40 pts) ───────────────────────────────────────
    rpes_7j  = [float(sessions[d]["rpe"]) for d in dates_7j  if d in sessions and sessions[d].get("rpe")]
    rpes_30j = [float(sessions[d]["rpe"]) for d in dates_30j if d in sessions and sessions[d].get("rpe")]
    rpe_score = 0
    rpe_avg_7j = None
    if rpes_7j:
        rpe_avg_7j = sum(rpes_7j) / len(rpes_7j)
        if rpes_30j:
            baseline = sum(rpes_30j) / len(rpes_30j)
            delta = rpe_avg_7j - baseline
            rpe_score = min(40, max(0, int(delta * 20)))
        # Plancher absolu selon le RPE moyen récent
        if rpe_avg_7j >= 9.0:
            rpe_score = max(rpe_score, 40)
        elif rpe_avg_7j >= 8.5:
            rpe_score = max(rpe_score, 30)
        elif rpe_avg_7j >= 8.0:
            rpe_score = max(rpe_score, 20)

    # ── Streak consécutif (0–20 pts) ─────────────────────────
    streak = 0
    check = today
    for _ in range(31):
        if check.isoformat() in sessions:
            streak += 1
            check = check - timedelta(days=1)
        else:
            break
    streak_score = min(20, streak * 2)

    # ── Volume hebdo vs moyenne 4 semaines (0–20 pts) ────────
    vol_7j = sum(float(sessions[d].get("session_volume") or 0) for d in dates_7j if d in sessions)
    dates_28j = [(today - timedelta(days=i)).isoformat() for i in range(28)]
    vol_28j = sum(float(sessions[d].get("session_volume") or 0) for d in dates_28j if d in sessions)
    avg_weekly_vol = vol_28j / 4
    vol_score = 0
    if avg_weekly_vol > 0 and vol_7j > 0:
        ratio = vol_7j / avg_weekly_vol
        vol_score = min(20, max(0, int((ratio - 1.0) * 30)))

    # ── Fréquence (0–20 pts) ─────────────────────────────────
    n_7j  = sum(1 for d in dates_7j  if d in sessions)
    n_30j = sum(1 for d in dates_30j if d in sessions)
    freq_score = 0
    if n_30j > 0:
        avg_per_week = (n_30j / 30) * 7
        if avg_per_week > 0:
            ratio_freq = n_7j / avg_per_week
            freq_score = min(20, max(0, int((ratio_freq - 1.0) * 20)))

    total = min(100, rpe_score + streak_score + vol_score + freq_score)

    return {
        "score": total,
        "components": {
            "rpe":       rpe_score,
            "streak":    streak_score,
            "volume":    vol_score,
            "frequency": freq_score,
        },
        "rpe_avg_7j":  round(rpe_avg_7j, 1) if rpe_avg_7j else None,
        "streak_days": streak,
    }


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
    stagnants     = detect_stagnation(weights)
    fatigue       = detect_fatigue_rpe()
    fatigue_data  = compute_fatigue_score()
    drops         = detect_performance_drop(weights)
    planned       = check_planned_deload()
    state         = load_deload_state()

    recommande = (
        len(stagnants) >= 2
        or fatigue["fatigue"]
        or len(drops) > 0
        or planned["due"]
    )

    stagnant_names = [s["exercise"] for s in stagnants]
    drop_names     = [d["exercise"] for d in drops]
    deload_targets = list(dict.fromkeys(stagnant_names + drop_names))

    rapport = {
        "deload_actif":        state["active"],
        "deload_since":        state.get("since"),
        "deload_reason":       state.get("reason"),
        "stagnants":           stagnants,
        "performance_drops":   drop_names,
        "fatigue_rpe":         fatigue["fatigue"],
        "recommande":          recommande,
        "planned_deload_due":  planned["due"],
        "weeks_since_deload":  planned.get("weeks_since"),
        "poids_deload":        {ex: round((weights.get(ex, {}).get("current_weight") or
                                           weights.get(ex, {}).get("weight") or 0) * DELOAD_FACTOR, 1)
                                for ex in deload_targets
                                if (weights.get(ex, {}).get("current_weight") or
                                    weights.get(ex, {}).get("weight"))} if recommande else {},
        "fatigue_score":       fatigue_data["score"],
        "fatigue_components":  fatigue_data["components"],
        "streak_days":         fatigue_data["streak_days"],
        "rpe_avg_7j":          fatigue_data.get("rpe_avg_7j"),
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
        for item in rapport["stagnants"]:
            name = item["exercise"] if isinstance(item, dict) else item
            print(f"    • {name}")
        print()
    else:
        print("  ✅ Aucune stagnation détectée\n")

    # Fatigue
    score = rapport.get("fatigue_score", 0)
    rpe_avg = rapport.get("rpe_avg_7j")
    if rpe_avg:
        emoji = "🔴" if rapport["fatigue_rpe"] else "🟢"
        print(f"  {emoji} RPE moyen 7j : {rpe_avg}/10  |  Score fatigue : {score}/100")
        if rapport["fatigue_rpe"]:
            print(f"     → RPE élevé, signe de fatigue accumulée")
        print()
    else:
        print(f"  ℹ️  Score fatigue : {score}/100\n")

    # Recommandation
    if rapport["recommande"]:
        print(f"  💡 RECOMMANDATION : Semaine de deload suggérée\n")
        print(f"  Poids suggérés à -15% :\n")
        for ex, w in rapport["poids_deload"].items():
            print(f"    • {ex:<25} → {w} lbs")
        print()

        choix = selectionner(
            "Activer la semaine de deload ?",
            ["Oui, activer le deload", "Non, continuer normal"]
        )

        if choix == "Oui, activer le deload":
            raison = "stagnation + RPE élevé" if rapport["fatigue_rpe"] else "stagnation"
            activer_deload(raison)
            print(f"\n✅ Deload activé ! Les poids recommandés sont à -15%.")
            print(f"   Reviens ici en fin de semaine pour le désactiver.")
        else:
            print("OK – on continue à pousser ! 💪")
    else:
        print("  ✅ Pas besoin de deload pour l'instant – continue le grind ! 🔥")

    print(f"\n{'═' * 60}")