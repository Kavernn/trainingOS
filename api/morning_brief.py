import logging

from planner import get_today, get_today_date
from life_stress_engine import refresh_life_stress_score

logger = logging.getLogger("trainingos.morning_brief")

HEAVY = {"Push A", "Push B", "Pull A", "Pull B + Full Body", "Legs"}
LIGHT = {"Yoga / Tai Chi", "Recovery"}


def _intensity(session):
    if session in HEAVY:
        return "heavy"
    if session in LIGHT:
        return "light"
    return "moderate"  # HIIT, Cardio, etc.


def get_morning_brief():
    today     = get_today()
    # Toujours recalculer : la Watch peut avoir synchro après le premier appel
    lss_data  = refresh_life_stress_score()
    lss       = lss_data.get("score")
    flags     = lss_data.get("flags", {})
    intensity = _intensity(today)
    components = lss_data.get("components", {})

    rec, msg, adjustments = _evaluate(lss, intensity, flags)

    # Spirit signals — yesterday's practice (metadata only)
    breathwork_yesterday = False
    meditation_yesterday = False
    try:
        from datetime import date, timedelta
        import db as _db
        yesterday = (date.today() - timedelta(days=1)).isoformat()
        spirit = _db.get_spirit_metadata(days=2)
        breathwork_yesterday = yesterday in spirit.get("days_with_breathwork", [])
        meditation_yesterday = yesterday in spirit.get("days_with_meditation", [])
    except Exception as e:
        logger.exception("morning_brief spirit fetch failed: %s", e)

    # G1: ritual rate for coaching context
    ritual_rate_7d = 0.0
    phoenix_streak = 0
    try:
        import db as _db_r
        from routes.ritual import _compute_phoenix
        ritual_history = _db_r.get_ritual_history(limit=7)
        if ritual_history:
            completed = sum(1 for r in ritual_history if r.get("outcome") in ("burned", "survived"))
            ritual_rate_7d = round(completed / 7, 2)
        phoenix_streak, _, _ = _compute_phoenix()
    except Exception as e:
        logger.exception("morning_brief ritual fetch failed: %s", e)

    return {
        "date":                  get_today_date(),
        "session_today":         today,
        "session_intensity":     intensity,
        "lss":                   lss,
        "recommendation":        rec,      # "go" | "go_caution" | "reduce" | "defer"
        "message":               msg,
        "adjustments":           adjustments,
        "flags":                 flags,
        "data_coverage":         lss_data.get("data_coverage", 0),
        "components":            components,
        "breathwork_yesterday":  breathwork_yesterday,
        "meditation_yesterday":  meditation_yesterday,
        "ritual_rate_7d":        ritual_rate_7d,
        "phoenix_streak":        phoenix_streak,
    }


def _evaluate(lss, intensity, flags):
    adj = []
    if flags.get("hrv_drop"):          adj.append("HRV bas — évite les efforts maximaux")
    if flags.get("sleep_deprivation"): adj.append("Manque de sommeil — réduis l'intensité")
    if flags.get("training_overload"): adj.append("Surcharge cumulée — déload recommandé")

    if lss is None:
        return "go", "Données insuffisantes — bonne séance !", adj

    if lss < 40:
        if intensity == "heavy":
            adj += ["Réduis les charges de 10-15%", "Supprime le dernier set"]
            if lss < 25:
                return "defer", f"LSS {lss:.0f} — récupération critique. Décale ou opte pour une session légère.", adj
            return "reduce", f"LSS {lss:.0f} — récupération faible. Allège la charge aujourd'hui.", adj
        if intensity == "moderate":
            adj.append("RPE cible ≤ 6")
            return "reduce", f"LSS {lss:.0f} — récupération faible. Session allégée conseillée.", adj
        return "go", f"LSS {lss:.0f} — bonne journée pour une session légère.", adj

    if lss < 65:
        if intensity == "heavy":
            adj.append("Surveille ton RPE — arrête à 7-8 max")
            return "go_caution", f"LSS {lss:.0f} — récupération modérée. Séance possible, reste dans les limites.", adj
        return "go", f"LSS {lss:.0f} — récupération correcte. Bonne séance !", adj

    return "go", f"LSS {lss:.0f} — récupération optimale. Vas-y à fond !", adj
