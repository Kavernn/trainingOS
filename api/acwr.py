"""
acwr.py — Acute:Chronic Workload Ratio (ACWR)

ACWR = Acute Load (7 days) / Chronic Load (28-day average weekly)

Zones:
  < 0.8   → Sous-charge       (blue)
  0.8-1.3 → Zone optimale     (green)
  1.3-1.5 → Zone de risque    (orange)
  > 1.5   → Surcharge         (red)

Load = total_volume per session (weight × reps across all exercises).
Primary source: v_session_volume view. KV fallback if unavailable.
"""
from __future__ import annotations
from datetime import date as date_cls, timedelta
import db


def _volumes_from_view(days: int = 35) -> dict[str, float]:
    """Query v_session_volume → {date_str: total_volume}."""
    if db._client is None:
        return {}
    try:
        cutoff = (date_cls.today() - timedelta(days=days)).isoformat()
        resp = (
            db._client.table("v_session_volume")
            .select("date, total_volume")
            .gte("date", cutoff)
            .execute()
        )
        result: dict[str, float] = {}
        for row in (resp.data or []):
            d = str(row.get("date", ""))[:10]
            v = float(row.get("total_volume") or 0)
            if d:
                result[d] = result.get(d, 0) + v
        return result
    except Exception as e:
        db.logger.warning("acwr: view error: %s", e)
        return {}


def _get_volumes(days: int = 35) -> dict[str, float]:
    return _volumes_from_view(days)


def _zone(ratio: float) -> dict:
    if ratio == 0:
        return {
            "code": "unknown", "label": "Données insuffisantes", "color": "gray",
            "recommendation": "Enregistre au moins 4 semaines de séances pour activer l'ACWR.",
        }
    if ratio < 0.8:
        return {
            "code": "under", "label": "Sous-charge", "color": "blue",
            "recommendation": "Volume insuffisant. Augmente progressivement la charge.",
        }
    if ratio <= 1.3:
        return {
            "code": "optimal", "label": "Zone optimale", "color": "green",
            "recommendation": "Charge idéale. Maintiens ce rythme pour progresser.",
        }
    if ratio <= 1.5:
        return {
            "code": "risk", "label": "Zone de risque", "color": "orange",
            "recommendation": "Augmentation rapide. Surveille la récupération cette semaine.",
        }
    return {
        "code": "danger", "label": "Surcharge", "color": "red",
        "recommendation": "Risque de blessure élevé. Réduis le volume cette semaine.",
    }


def calc_acwr() -> dict:
    """Return current ACWR ratio, zone, and 8-week trend."""
    today = date_cls.today()
    volumes = _get_volumes(days=35)

    acute_start  = (today - timedelta(days=6)).isoformat()
    chronic_start = (today - timedelta(days=27)).isoformat()

    acute_load   = sum(v for d, v in volumes.items() if d >= acute_start)
    chronic_load = sum(v for d, v in volumes.items() if d >= chronic_start) / 4.0

    ratio = round(acute_load / chronic_load, 2) if chronic_load > 0 else 0.0
    zone  = _zone(ratio)

    # 8-week rolling trend
    trend = []
    for w in range(7, -1, -1):
        week_end   = today - timedelta(weeks=w)
        a_start    = (week_end - timedelta(days=6)).isoformat()
        c_start    = (week_end - timedelta(days=27)).isoformat()
        w_end_str  = week_end.isoformat()

        a = sum(v for d, v in volumes.items() if a_start <= d <= w_end_str)
        c = sum(v for d, v in volumes.items() if c_start <= d <= w_end_str) / 4.0
        r = round(a / c, 2) if c > 0 else 0.0
        trend.append({
            "week":    week_end.strftime("%Y-W%V"),
            "ratio":   r,
            "acute":   round(a),
            "chronic": round(c),
        })

    return {
        "ratio":        ratio,
        "acute_load":   round(acute_load),
        "chronic_load": round(chronic_load),
        "zone":         zone,
        "trend":        trend,
    }
