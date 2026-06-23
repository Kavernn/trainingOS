import logging
import time as _time

from planner import get_today, get_today_date
from life_stress_engine import refresh_life_stress_score

logger = logging.getLogger("trainingos.morning_brief")

_CACHE: dict = {}
_CACHE_TTL = 5 * 60  # 5 min — absorbs burst calls; Watch sync propagates on next miss


def _get_hrv_context():
    """Return (today_hrv_ms, pct_vs_baseline) or (None, None)."""
    try:
        import db as _db_hrv
        logs = _db_hrv.get_recovery_logs(limit=35)
        if not logs:
            return None, None
        today_hrv = None
        for log in logs[:3]:
            if log.get("hrv") is not None:
                today_hrv = float(log["hrv"])
                break
        if today_hrv is None:
            return None, None
        baseline_vals = [float(l["hrv"]) for l in logs[5:] if l.get("hrv") is not None]
        if len(baseline_vals) < 5:
            baseline_vals = [float(l["hrv"]) for l in logs[1:] if l.get("hrv") is not None]
        if not baseline_vals:
            return round(today_hrv), None
        baseline = sum(baseline_vals) / len(baseline_vals)
        pct = round((today_hrv - baseline) / baseline * 100)
        return round(today_hrv), pct
    except Exception:
        return None, None


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

    hrv_ms, hrv_pct = _get_hrv_context()
    rec, msg, adjustments = _evaluate(lss, intensity, flags, hrv_ms=hrv_ms, hrv_pct=hrv_pct, session_name=today)

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
        "recommendation":        rec,      # "go" | "go_caution" | "reduce" | "defer"
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


def _evaluate(lss, intensity, flags, hrv_ms=None, hrv_pct=None, session_name=None):
    adj = []
    if flags.get("hrv_drop"):          adj.append("HRV bas — évite les efforts maximaux")
    if flags.get("sleep_deprivation"): adj.append("Manque de sommeil — réduis l'intensité")
    if flags.get("training_overload"): adj.append("Surcharge cumulée — déload recommandé")

    def _hrv_str():
        if hrv_ms is None:
            return None
        if hrv_pct is not None:
            sign = "+" if hrv_pct >= 0 else ""
            return f"HRV {hrv_ms}ms ({sign}{hrv_pct}% vs baseline)"
        return f"HRV {hrv_ms}ms"

    hrv_str = _hrv_str()
    lss_str = f"Readiness {lss:.0f}/100" if lss is not None else None

    def _lead():
        return hrv_str if hrv_str else lss_str or "Données limitées"

    if lss is None:
        msg = f"{_lead()}. Bonne séance." if session_name else f"{_lead()}."
        return "go", msg, adj

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

    if intensity == "heavy":
        msg = f"{_lead()} — fenêtre optimale. Pousse fort ce soir."
    else:
        sn = session_name or "séance"
        msg = f"{_lead()} — récupération optimale. {sn} au programme."
    return "go", msg, adj
