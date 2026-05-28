# deload.py
import json
from pathlib import Path
from sessions import load_sessions
import db as _db


BASE_DIR      = Path(__file__).parent
DATA_FILE     = BASE_DIR / "data" / "weights.json"
DELOAD_FILE   = BASE_DIR / "data" / "deload.json"

STAGNATION_THRESHOLD  = 5    # 5 sessions = signal fiable; 3 = bruit possible (plateau.py est la référence principale)
RPE_FATIGUE_THRESHOLD = 8.5  # RPE moyen au dessus de ça = fatigue
DELOAD_WEIGHT_FACTOR  = 0.90 # -10% max sur le poids (maintien des adaptations neurales)
DELOAD_SETS_FACTOR    = 0.50 # -50% des sets (réduction du volume = mécanisme réel du deload)

# Prescriptions différenciées selon le type de fatigue (Meeusen et al. 2013, ECSS/ACSM consensus)
_DELOAD_PRESCRIPTION = {
    "peripheral": {
        "weight_factor":          0.90,   # -10% — maintien neural
        "sets_factor":            0.50,   # -50% volume
        "duration_days":          7,
        "exclude_compound_heavy": False,
    },
    "central": {
        "weight_factor":          0.65,   # -35% — le SNC a besoin de repos
        "sets_factor":            0.40,   # -60% volume
        "duration_days":          10,
        "exclude_compound_heavy": True,   # éviter la stimulation neurale lourde
    },
    "overreaching": {
        "weight_factor":          0.0,    # repos complet
        "sets_factor":            0.0,
        "duration_days":          14,
        "exclude_compound_heavy": True,
    },
}

_DELOAD_WEEKS_BY_LEVEL = {
    "beginner":      8,  # Israetel : 6-8 semaines (learning curve + dommages sans RBE)
    "intermediate":  6,  # recommandation principale (Israetel, Baker)
    "advanced":      4,  # charge élevée → deload plus fréquent
}
_DELOAD_WEEKS_DEFAULT = 6   # profil intermédiaire = cas le plus courant


def _planned_deload_weeks() -> int:
    """Retourne l'intervalle de deload planifié selon training_experience du profil user."""
    try:
        from user_profile import load_user_profile
        level = (load_user_profile().get("training_experience") or "").lower()
        return _DELOAD_WEEKS_BY_LEVEL.get(level, _DELOAD_WEEKS_DEFAULT)
    except Exception:
        return _DELOAD_WEEKS_DEFAULT


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

def _parse_sets_from_scheme(scheme: str) -> int:
    """Parse '3x8-12' → 3. Returns 0 on failure."""
    try:
        return int(str(scheme).strip().split("x")[0])
    except Exception:
        return 0


def calculer_poids_deload(weights: dict, exercices: list[str] = None,
                           fatigue_type: str = "peripheral") -> dict:
    """
    Prescription de deload selon le type de fatigue détecté.

    peripheral  : -10% poids, -50% sets, 7j (Israetel, Helms)
    central     : -35% poids, -60% sets, 10j — pas de compound heavy
                  (Meeusen et al. 2013 — SNC a besoin de repos, pas de stimulation)
    overreaching: repos complet — aucun exercice prescrit
    """
    if fatigue_type not in _DELOAD_PRESCRIPTION:
        fatigue_type = "peripheral"

    presc = _DELOAD_PRESCRIPTION[fatigue_type]

    if fatigue_type == "overreaching":
        return {}  # repos complet — coach_message dans le rapport explique

    result = {}
    cibles = exercices or [k for k in weights if k != "sessions"]

    for ex in cibles:
        data = weights.get(ex, {})
        poids_actuel = data.get("current_weight", data.get("weight", 0))
        if not poids_actuel:
            continue

        if presc["exclude_compound_heavy"]:
            if data.get("load_profile") == "compound_heavy":
                continue

        sets_normaux = _parse_sets_from_scheme(data.get("default_scheme", "")) or 3
        sets_deload  = max(1, round(sets_normaux * presc["sets_factor"]))
        result[ex] = {
            "poids_actuel":  round(poids_actuel, 1),
            "poids_deload":  round(poids_actuel * presc["weight_factor"], 1),
            "sets_normaux":  sets_normaux,
            "sets_deload":   sets_deload,
            "fatigue_type":  fatigue_type,
            "duration_days": presc["duration_days"],
            "note": (
                f"Fatigue centrale — -35% poids, -60% sets, {presc['duration_days']}j"
                if fatigue_type == "central"
                else f"Fatigue musculaire — -10% poids, -50% sets"
            ),
        }

    return result


# ─────────────────────────────────────────────────────────────
# SAUVEGARDE / CHARGEMENT ÉTAT DELOAD
# ─────────────────────────────────────────────────────────────

def load_deload_state() -> dict:
    return _db.get_deload_state()

def save_deload_state(state: dict):
    _db.set_deload_state(
        active=state.get("active", False),
        started_at=state.get("started_at"),
        reason=state.get("reason"),
    )


_fatigue_cache: dict = {}

def get_cached_fatigue_score() -> int:
    """Return today's fatigue score (0–100). Cached in memory for the request lifetime."""
    from datetime import date
    today = date.today().isoformat()
    if _fatigue_cache.get("date") == today:
        return int(_fatigue_cache.get("score", 0))
    result = compute_fatigue_score()
    _fatigue_cache["date"] = today
    _fatigue_cache["score"] = result["score"]
    return result["score"]


def check_planned_deload() -> dict:
    """
    Check if a planned deload is due based on time elapsed since last deload.
    Returns {due: bool, weeks_since: float | None, weeks_target: int}.
    """
    from datetime import date
    state = load_deload_state()
    last_str = state.get("last_completed")
    weeks_target = _planned_deload_weeks()
    if not last_str:
        return {"due": False, "weeks_since": None, "weeks_target": weeks_target}
    try:
        last        = date.fromisoformat(last_str)
        weeks_since = (date.today() - last).days / 7
        return {
            "due":          weeks_since >= weeks_target,
            "weeks_since":  round(weeks_since, 1),
            "weeks_target": weeks_target,
        }
    except Exception:
        return {"due": False, "weeks_since": None, "weeks_target": weeks_target}


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
# DIAGNOSTIC FATIGUE CENTRALE VS PÉRIPHÉRIQUE
# ─────────────────────────────────────────────────────────────

_CENTRAL_FATIGUE_THRESHOLD  = 3   # ≥3 marqueurs → fatigue centrale
_OVERREACHING_THRESHOLD     = 4   # ≥4 marqueurs + durée >14j → overreaching


def _load_weights_safe() -> dict:
    """Charge weights.json sans crasher si absent."""
    try:
        import json
        with open(DATA_FILE) as f:
            return json.load(f)
    except Exception:
        return {}


def _estimate_fatigue_duration(sessions: dict, log_by_date: dict, today) -> int:
    """Estime depuis combien de jours les signaux de fatigue sont présents (max 28j)."""
    from datetime import timedelta
    for i in range(28, 0, -1):
        d   = (today - timedelta(days=i)).isoformat()
        s   = sessions.get(d, {})
        rec = log_by_date.get(d, {})
        rpe   = float(s.get("rpe") or 0)
        sleep = _adjusted_sleep_quality(rec) if rec else 10.0
        mood  = float(rec.get("mood") or 10)
        if rpe >= 8.5 or sleep <= 4.0 or mood <= 3.0:
            return i
    return 0


def _adjusted_sleep_quality(rec: dict) -> float:
    """Retourne la qualité de sommeil ajustée avec priorité aux données HealthKit.

    Si HealthKit fournit une durée objective très courte, le score subjectif est
    plafonné pour refléter la réalité physiologique — indépendamment du slider.

    Seuils de durée (Watson et al. 2015, AASM) :
      <5h → qualité forcée à ≤4.0 (mauvais)
      <6h → qualité plafonnée à ≤6.0 (dégradé)
    """
    quality = float(rec.get("sleep_quality") or 10)
    sleep_hours = float(rec.get("sleep_hours") or 0)
    source = rec.get("sleep_source", "manual")
    if source == "healthkit" and sleep_hours > 0:
        if sleep_hours < 5:
            quality = min(quality, 4.0)
        elif sleep_hours < 6:
            quality = min(quality, 6.0)
    return quality


def diagnose_fatigue_type(weights: dict | None = None) -> dict:
    """
    Distingue fatigue périphérique (musculaire) vs centrale (SNC).

    Marqueurs centraux (Meeusen et al. 2013 — ECSS/ACSM consensus) :
      RPE élevé malgré charge stable, humeur basse persistante,
      sommeil perturbé persistant, HRV sous baseline, RHR au-dessus
      baseline, performance en baisse malgré repos suffisant.

    Retourne :
        fatigue_type    : "peripheral" | "central" | "overreaching" | "none"
        central_markers : int
        markers_detail  : dict
        duration_days   : int
    """
    from datetime import date, timedelta
    from health_data import _load_recovery_log
    # Import lazily pour éviter la circularité (life_stress_engine importe deload)
    from life_stress_engine import detect_hrv_drop

    if weights is None:
        weights = _load_weights_safe()

    today    = date.today()
    sessions = load_sessions()
    log_by_date = {e["date"]: e for e in _load_recovery_log() if "date" in e}

    markers: dict[str, bool] = {
        "rpe_high_stable_load": False,
        "mood_low":             False,
        "sleep_poor":           False,
        "hrv_below_baseline":   False,
        "rhr_above_baseline":   False,
        "performance_decline":  False,
    }

    dates_14j = [(today - timedelta(days=i)).isoformat() for i in range(14)]

    # ── Marqueur 1 : RPE ≥8.5 malgré charge stable ───────────────────────────
    rpes_recent = [float(sessions[d]["rpe"]) for d in dates_14j[:7]
                   if d in sessions and sessions[d].get("rpe")]
    vols_recent = [float(sessions[d].get("session_volume") or 0)
                   for d in dates_14j[:7] if d in sessions]
    vols_prior  = [float(sessions[d].get("session_volume") or 0)
                   for d in dates_14j[7:] if d in sessions]
    if rpes_recent and sum(rpes_recent) / len(rpes_recent) >= 8.5:
        if not vols_prior:
            markers["rpe_high_stable_load"] = True
        else:
            vol_ratio = (sum(vols_recent) / max(len(vols_recent), 1)) / (sum(vols_prior) / max(len(vols_prior), 1) or 1)
            if vol_ratio <= 1.1:
                markers["rpe_high_stable_load"] = True

    # ── Marqueur 2 : Humeur basse persistante (≥5 jours sur 7) ──────────────
    # Échelle : 0–10 (wellness slider, auto-rapporté).
    # ⚠️  Ce marqueur seul ne suffit PAS à diagnostiquer la fatigue centrale.
    #     Il faut ≥3 marqueurs cumulés (Meeusen et al. 2013 — ECSS/ACSM consensus).
    #     Les sliders sont des indicateurs de tendance, non des instruments validés
    #     (POMS / RESTQ-Sport / DALDA). Ils sont utilisés en combinaison uniquement.
    moods_7j = [
        float(log_by_date[d].get("mood") or 0)
        for d in dates_14j[:7]
        if d in log_by_date and log_by_date[d].get("mood") is not None
    ]
    if len(moods_7j) >= 5 and sum(moods_7j) / len(moods_7j) <= 3.0:
        markers["mood_low"] = True

    # ── Marqueur 3 : Sommeil perturbé persistant (≥5 jours sur 7) ───────────
    # Échelle : 1–10. Seuil : moyenne ≤4.0 = "mauvaise qualité persistante".
    # Priorité aux données objectives HealthKit : si la durée est <5h, la qualité
    # est plafonnée à 4 même si le slider subjektif est plus élevé.
    # Référence durée : Watson et al. 2015, AASM — <6h = dégradé, <5h = mauvais.
    sleeps_7j = [
        _adjusted_sleep_quality(log_by_date[d])
        for d in dates_14j[:7]
        if d in log_by_date and log_by_date[d].get("sleep_quality") is not None
    ]
    if len(sleeps_7j) >= 5 and sum(sleeps_7j) / len(sleeps_7j) <= 4.0:
        markers["sleep_poor"] = True

    # ── Marqueur 4 : HRV sous la baseline personnelle ────────────────────────
    try:
        markers["hrv_below_baseline"] = detect_hrv_drop(today.isoformat())
    except Exception:
        pass

    # ── Marqueur 5 : RHR au-dessus de la baseline (+5%) ─────────────────────
    rhr_window = [(today - timedelta(days=i)).isoformat() for i in range(8)]
    rhr_vals = [
        float(log_by_date[d]["resting_hr"])
        for d in rhr_window
        if d in log_by_date and log_by_date[d].get("resting_hr") is not None
    ]
    if len(rhr_vals) >= 4:
        baseline_rhr = sum(rhr_vals[1:]) / len(rhr_vals[1:])
        if rhr_vals[0] > baseline_rhr * 1.05:
            markers["rhr_above_baseline"] = True

    # ── Marqueur 6 : Performance en baisse malgré RPE non explosif ───────────
    if weights:
        drops = detect_performance_drop(weights, threshold=0.05)
        if drops and not markers["rpe_high_stable_load"]:
            markers["performance_decline"] = True

    n_central     = sum(markers.values())
    duration_days = _estimate_fatigue_duration(sessions, log_by_date, today)

    if n_central == 0:
        fatigue_type = "none"
    elif n_central >= _OVERREACHING_THRESHOLD and duration_days >= 14:
        fatigue_type = "overreaching"
    elif n_central >= _CENTRAL_FATIGUE_THRESHOLD:
        fatigue_type = "central"
    else:
        fatigue_type = "peripheral"

    return {
        "fatigue_type":    fatigue_type,
        "central_markers": n_central,
        "markers_detail":  markers,
        "duration_days":   duration_days,
    }


_COACH_MESSAGES = {
    "peripheral": (
        "Fatigue musculaire accumulée. On réduit le volume, on garde l'intensité. "
        "Tu reviens plus fort dans 7 jours."
    ),
    "central": (
        "Ton corps montre des signes de fatigue profonde — pas musculaire, nerveuse. "
        "On baisse tout pendant 10 jours. C'est pas de la faiblesse, c'est de la stratégie. "
        "Les athlètes pro font ça."
    ),
    "overreaching": (
        "Tes données montrent un pattern de surmenage depuis plus de 2 semaines. "
        "Repos complet recommandé — pas de deload, du repos. "
        "Si les symptômes persistent, consulte un professionnel de santé."
    ),
    "none": None,
}


def _deload_coach_message(fatigue_type: str) -> str | None:
    return _COACH_MESSAGES.get(fatigue_type)


# ─────────────────────────────────────────────────────────────
# ANALYSE COMPLÈTE + RAPPORT
# ─────────────────────────────────────────────────────────────

def analyser_deload(weights: dict) -> dict:
    """
    Analyse complète — retourne un rapport avec :
    - stagnations détectées
    - fatigue RPE
    - diagnostic fatigue centrale vs périphérique (Meeusen et al. 2013)
    - ACWR EWMA (Gabbett 2016) — trigger additionnel si ratio > 1.5
    - recommandation deload oui/non
    - poids suggérés adaptés au type de fatigue
    """
    stagnants    = detect_stagnation(weights)
    fatigue      = detect_fatigue_rpe()
    fatigue_data = compute_fatigue_score()
    fatigue_diag = diagnose_fatigue_type(weights)
    drops        = detect_performance_drop(weights)
    planned      = check_planned_deload()
    state        = load_deload_state()

    # ── ACWR EWMA (Gabbett 2016, Williams et al. 2017) ──────────────────────
    acwr_ratio = 0.0
    acwr_zone  = "unknown"
    acwr_confidence = "low"
    try:
        from acwr import calc_acwr
        acwr_data       = calc_acwr()
        acwr_ratio      = float(acwr_data.get("ratio") or 0)
        acwr_zone       = (acwr_data.get("zone") or {}).get("code", "unknown")
        acwr_confidence = acwr_data.get("confidence", "low")
    except Exception:
        pass

    # ACWR danger (>1.5) avec données fiables → trigger de déload additionnel
    acwr_trigger = (
        acwr_zone == "danger"
        and acwr_confidence in ("moderate", "high")
    )

    recommande = (
        len(stagnants) >= 2
        or fatigue["fatigue"]
        or len(drops) > 0
        or planned["due"]
        or acwr_trigger
    )

    stagnant_names = [s["exercise"] for s in stagnants]
    drop_names     = [d["exercise"] for d in drops]
    deload_targets = list(dict.fromkeys(stagnant_names + drop_names))

    fatigue_type = fatigue_diag["fatigue_type"]
    prescription = calculer_poids_deload(weights, deload_targets, fatigue_type=fatigue_type) if recommande else {}

    rapport = {
        "deload_actif":          state["active"],
        "deload_since":          state.get("since"),
        "deload_reason":         state.get("reason"),
        "stagnants":             stagnant_names,
        "performance_drops":     drop_names,
        "fatigue_rpe":           fatigue["fatigue"],
        "recommande":            recommande,
        "planned_deload_due":    planned["due"],
        "weeks_since_deload":    planned.get("weeks_since"),
        "deload_prescription":   prescription,
        "poids_deload":          {ex: data["poids_deload"] for ex, data in prescription.items()},
        "fatigue_score":         fatigue_data["score"],
        "fatigue_components":    fatigue_data["components"],
        "streak_days":           fatigue_data["streak_days"],
        "rpe_avg_7j":            fatigue_data.get("rpe_avg_7j"),
        "fatigue_type":          fatigue_type,
        "central_markers":       fatigue_diag["central_markers"],
        "markers_detail":        fatigue_diag["markers_detail"],
        "fatigue_duration_days": fatigue_diag["duration_days"],
        "coach_message":         _deload_coach_message(fatigue_type),
        "acwr":                  round(acwr_ratio, 2),
        "acwr_zone":             acwr_zone,
        "acwr_trigger":          acwr_trigger,
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
        print(f"  Prescription (même poids -10%, 50% des sets) :\n")
        for ex, presc in rapport["deload_prescription"].items():
            print(f"    • {ex:<25} → {presc['poids_deload']} lbs × {presc['sets_deload']} sets ({presc['note']})")
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