import logging
import time as _time

from planner import get_today, get_today_date
from life_stress_engine import refresh_life_stress_score

logger = logging.getLogger("trainingos.morning_brief")

_CACHE: dict = {}
_CACHE_TTL = 5 * 60  # 5 min — absorbs burst calls; Watch sync propagates on next miss


def invalidate_cache() -> None:
    """Vide le cache local pour forcer un recalcul au prochain appel.
    Appelé par les mutations qui modifient un signal lu par get_morning_brief
    (recovery_logs, nutrition, mood/pss, workout_sessions...)."""
    _CACHE.clear()


def _get_hrv_zone():
    """Zone HRV du jour ("green" | "orange" | "red") ou None — SOURCE UNIQUE hrv_engine, la
    même que la readiness (_score_hrv). Avant : baseline maison (moyenne des logs à partir du
    6e), troisième calcul de « HRV vs baseline » sur la même page."""
    try:
        import db as _db_hrv
        from hrv_engine import compute_hrv_analysis
        from user_profile import load_user_profile
        from utils import _today_mtl as _tmtl
        sensitivity = str(load_user_profile().get("hrv_sensitivity") or "standard")
        analysis = compute_hrv_analysis(_db_hrv.get_recovery_logs() or [], _tmtl(), sensitivity=sensitivity)
        return analysis.get("hrv_zone") if analysis.get("baseline_available") else None
    except Exception as e:
        logger.warning("morning_brief hrv zone failed: %s", e)
        return None


HEAVY = {"Push A", "Push B", "Pull A", "Pull B + Full Body", "Legs"}
LIGHT = {"Yoga / Tai Chi", "Recovery"}


def _intensity(session):
    if session in HEAVY:
        return "heavy"
    if session in LIGHT:
        return "light"
    return "moderate"  # HIIT, Cardio, etc.


def get_morning_brief():
    now    = _time.time()
    cached = _CACHE.get("result")
    if cached and (now - cached["ts"]) < _CACHE_TTL:
        return cached["data"]

    today     = get_today()
    # Toujours recalculer : la Watch peut avoir synchro après le premier appel
    lss_data  = refresh_life_stress_score()
    lss       = lss_data.get("score")
    flags     = lss_data.get("flags", {})
    intensity = _intensity(today)
    components = lss_data.get("components", {})

    hrv_zone = _get_hrv_zone()
    rec, msg, adjustments = _evaluate(lss, intensity, flags, hrv_zone=hrv_zone, session_name=today)

    # Spirit signals — yesterday's practice (metadata only)
    breathwork_yesterday = False
    meditation_yesterday = False
    try:
        from datetime import date, timedelta
        import db as _db
        from utils import _today_mtl as _tmtl
        yesterday = (date.fromisoformat(_tmtl()) - timedelta(days=1)).isoformat()
        spirit = _db.get_spirit_metadata(days=2)
        breathwork_yesterday = yesterday in spirit.get("days_with_breathwork", [])
        meditation_yesterday = yesterday in spirit.get("days_with_meditation", [])
    except Exception as e:
        logger.exception("morning_brief spirit fetch failed: %s", e)

    # Engagement streak for momentum trigger (daily_brief)
    engagement_streak = 0
    try:
        from routes.ritual import _engagement_streak
        engagement_streak = _engagement_streak()
    except Exception as e:
        logger.exception("morning_brief engagement_streak failed: %s", e)

    result = {
        "date":                  get_today_date(),
        "session_today":         today,
        "session_intensity":     intensity,
        "lss":                   lss,
        "recommendation":        rec,      # "go" | "go_caution" | "reduce" | "defer" | "unknown" (LSS absent)
        "message":               msg,
        "adjustments":           adjustments,
        "flags":                 flags,
        "data_coverage":         lss_data.get("data_coverage", 0),
        "components":            components,
        "breathwork_yesterday":  breathwork_yesterday,
        "meditation_yesterday":  meditation_yesterday,
        "engagement_streak":     engagement_streak,
    }
    _CACHE["result"] = {"data": result, "ts": now}
    return result


def _evaluate(lss, intensity, flags, hrv_zone=None, session_name=None):
    adj = []
    if flags.get("hrv_drop"):          adj.append("HRV bas — évite les efforts maximaux")
    if flags.get("sleep_deprivation"): adj.append("Manque de sommeil — réduis l'intensité")
    if flags.get("training_overload"): adj.append("Surcharge cumulée — déload recommandé")

    # Build 9 : plus de chiffre HRV dans la phrase (la valeur du jour vit dans le hero).
    # Le LSS n'est PAS la readiness : son nom affiché est « Équilibre de vie »
    # (0 = surmenage, 100 = récupération optimale), comme dans l'app.
    lss_str = f"Équilibre de vie {lss:.0f}/100" if lss is not None else None

    def _lead():
        return lss_str or "Données limitées"

    if lss is None:
        # Anti-fantôme : sans LSS, aucune recommandation inventée (avant : "go" +
        # « Bonne séance »). Chaîne "unknown" et non null : MorningBriefData.recommendation
        # n'est pas optionnel côté iOS (affiché « Données insuffisantes » depuis le build 2a).
        return "unknown", f"{_lead()}.", adj

    if lss < 25:
        if intensity == "heavy":
            adj += ["Réduis les charges de 10-15%", "Supprime le dernier set"]
        msg = f"{_lead()} — récupération critique. Décale ou session légère."
        return "defer", msg, adj

    if lss < 40:
        if intensity == "heavy":
            adj += ["Réduis les charges de 10-15%", "Supprime le dernier set"]
            msg = f"{_lead()} — récupération faible. Allège les charges aujourd'hui."
            return "reduce", msg, adj
        if intensity == "moderate":
            adj.append("RPE cible ≤ 6")
            msg = f"{_lead()} — récupération faible. RPE ≤ 6 ce soir."
            return "reduce", msg, adj
        msg = f"{_lead()}. Bonne journée pour {session_name}." if session_name else f"{_lead()}."
        return "go", msg, adj

    if lss < 65:
        if intensity == "heavy":
            adj.append("Surveille ton RPE — arrête à 7-8 max")
            msg = f"{_lead()} — fenêtre correcte. RPE ≤ 8 ce soir."
            return "go_caution", msg, adj
        msg = f"{_lead()} — récupération correcte. Bonne séance."
        return "go", msg, adj

    # Règle (validée par Vince) : HRV en zone rouge → la récupération n'est jamais
    # qualifiée d'« optimale » (ni « Pousse fort »), avec ou sans chiffre, et le « go »
    # descend à « go_caution » — même garde-fou que le veto HRV de la readiness.
    if hrv_zone == "red":
        if "HRV bas — évite les efforts maximaux" not in adj:
            adj.append("HRV bas — évite les efforts maximaux")
        msg = f"{_lead()} — HRV bas ce matin : séance normale, sans chercher le max."
        return "go_caution", msg, adj

    if intensity == "heavy":
        msg = f"{_lead()} — fenêtre optimale. Pousse fort ce soir."
    else:
        sn = session_name or "séance"
        msg = f"{_lead()} — récupération optimale. {sn} au programme."
    return "go", msg, adj
