from planner import get_today, get_today_date
from life_stress_engine import get_life_stress_score

HEAVY = {"Push A", "Push B", "Pull A", "Pull B + Full Body", "Legs"}
LIGHT = {"Yoga / Tai Chi", "Recovery"}


def _intensity(session):
    if session in HEAVY:
        return "heavy"
    if session in LIGHT:
        return "light"
    return "moderate"  # HIIT, Cardio, etc.


def get_morning_brief():
    today    = get_today()
    lss_data = get_life_stress_score()
    lss      = lss_data.get("score")
    flags    = lss_data.get("flags", {})
    intensity = _intensity(today)

    rec, msg, adjustments = _evaluate(lss, intensity, flags)

    return {
        "date":              get_today_date(),
        "session_today":     today,
        "session_intensity": intensity,
        "lss":               lss,
        "recommendation":    rec,      # "go" | "go_caution" | "reduce" | "defer"
        "message":           msg,
        "adjustments":       adjustments,
        "flags":             flags,
        "data_coverage":     lss_data.get("data_coverage", 0),
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
