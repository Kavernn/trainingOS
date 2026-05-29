from flask import Blueprint, jsonify
from datetime import timedelta
import logging
from utils import _today_mtl

logger = logging.getLogger("trainingos")

analytics_body_bp = Blueprint("analytics_body", __name__)


@analytics_body_bp.route("/api/pain_journal")
def api_pain_journal():
    """Return exercise pain zones history for the injury journal."""
    import db as _db
    entries = _db.get_pain_journal(limit=200)
    by_exercise: dict = {}
    for e in entries:
        ex = e.get("exercise") or "Inconnu"
        by_exercise.setdefault(ex, {"exercise": ex, "count": 0, "zones": [], "last_date": None, "entries": []})
        by_exercise[ex]["count"] += 1
        zone = e.get("pain_zone")
        if zone and zone not in by_exercise[ex]["zones"]:
            by_exercise[ex]["zones"].append(zone)
        if e.get("date") and (by_exercise[ex]["last_date"] is None or str(e["date"]) > str(by_exercise[ex]["last_date"])):
            by_exercise[ex]["last_date"] = e.get("date")
        by_exercise[ex]["entries"].append(e)
    result = sorted(by_exercise.values(), key=lambda x: (x["last_date"] or ""), reverse=True)
    return jsonify({"entries": entries, "by_exercise": result})


@analytics_body_bp.route("/api/body_projection")
def api_body_projection():
    """Linear regression on body_fat_pct and lean mass → projected goal arrival dates."""
    import db as _db
    from datetime import date as date_cls

    bw_logs = _db.get_body_weight_logs(limit=200)
    smart_goals = _db.get_smart_goals()

    bf_series = [
        {"date": str(e.get("date", ""))[:10], "value": float(e["body_fat"])}
        for e in bw_logs
        if e.get("body_fat") is not None
    ]
    lean_series = []
    for e in bw_logs:
        if e.get("weight") is not None and e.get("body_fat") is not None:
            w = float(e["weight"])
            bf = float(e["body_fat"])
            lean = w * (1 - bf / 100)
            lean_series.append({"date": str(e.get("date", ""))[:10], "value": round(lean, 1)})
    weight_series = [
        {"date": str(e.get("date", ""))[:10], "value": float(e["weight"])}
        for e in bw_logs
        if e.get("weight") is not None
    ]

    def _linreg(series: list) -> dict | None:
        series = sorted(series, key=lambda x: x["date"])
        if len(series) < 5:
            return None
        today = date_cls.fromisoformat(_today_mtl())
        def _days(d: str) -> int:
            try:
                return (date_cls.fromisoformat(d) - date_cls(2026, 1, 1)).days
            except Exception:
                return 0
        xs = [_days(p["date"]) for p in series]
        ys = [p["value"] for p in series]
        n = len(xs)
        mx = sum(xs) / n
        my = sum(ys) / n
        num = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
        den = sum((x - mx) ** 2 for x in xs)
        if abs(den) < 1e-9:
            return None
        slope = num / den
        intercept = my - slope * mx
        today_x = _days(today.isoformat())
        predicted_today = slope * today_x + intercept
        ss_res = sum((y - (slope * x + intercept)) ** 2 for x, y in zip(xs, ys))
        ss_tot = sum((y - my) ** 2 for y in ys)
        r2 = round(1 - ss_res / ss_tot, 3) if ss_tot > 1e-9 else None
        return {
            "slope_per_day": round(slope, 4),
            "current_value": round(predicted_today, 1),
            "r2":            r2,
        }

    def _days_to_target(reg: dict, target: float, lower_is_better: bool) -> str | None:
        slope = reg["slope_per_day"]
        cur   = reg["current_value"]
        if abs(slope) < 1e-6:
            return None
        if lower_is_better and slope >= 0:
            return None
        if not lower_is_better and slope <= 0:
            return None
        days_needed = (target - cur) / slope
        if days_needed < 0:
            return None
        arrival = (date_cls.fromisoformat(_today_mtl()) + timedelta(days=int(days_needed))).isoformat()
        return arrival

    bf_reg     = _linreg(bf_series)
    lean_reg   = _linreg(lean_series)
    weight_reg = _linreg(weight_series)

    projections = []
    for goal in smart_goals:
        gtype  = goal.get("type")
        target = goal.get("target_value")
        if gtype not in ("body_fat", "lean_mass") or target is None:
            continue
        if gtype == "body_fat" and bf_reg:
            arrival = _days_to_target(bf_reg, float(target), lower_is_better=True)
            projections.append({
                "goal_type":     gtype,
                "target":        target,
                "current":       bf_reg["current_value"],
                "slope_per_week": round(bf_reg["slope_per_day"] * 7, 3),
                "r2":            bf_reg["r2"],
                "projected_date": arrival,
            })
        if gtype == "lean_mass" and lean_reg:
            arrival = _days_to_target(lean_reg, float(target), lower_is_better=False)
            projections.append({
                "goal_type":     gtype,
                "target":        target,
                "current":       lean_reg["current_value"],
                "slope_per_week": round(lean_reg["slope_per_day"] * 7, 3),
                "r2":            lean_reg["r2"],
                "projected_date": arrival,
            })

    return jsonify({
        "body_fat":    bf_reg,
        "lean_mass":   lean_reg,
        "body_weight": weight_reg,
        "projections": projections,
        "bf_series":   bf_series[-30:] if bf_series else [],
        "lean_series": lean_series[-30:] if lean_series else [],
    })
