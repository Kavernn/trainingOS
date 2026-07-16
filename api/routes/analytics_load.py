from flask import Blueprint, jsonify, request
from datetime import datetime, timedelta
import logging
from utils import _today_mtl

logger = logging.getLogger("trainingos")

analytics_load_bp = Blueprint("analytics_load", __name__)


@analytics_load_bp.route("/api/sync_status")
def api_sync_status():
    """Returns count of dirty (unsynced) entries in the local SQLite cache."""
    from db import _sqlite_all_dirty
    dirty = _sqlite_all_dirty()
    return jsonify({"dirty_count": len(dirty), "dirty_keys": list(dirty.keys())})


@analytics_load_bp.route("/api/deload_status")
def api_deload_status():
    """Returns deload analysis: stagnation, RPE fatigue, recommendation."""
    from weights import load_weights
    from deload import analyser_deload
    weights = load_weights()
    rapport = analyser_deload(weights)
    logger.info(
        "Deload status — recommande=%s stagnants=%d rpe_moyen=%s",
        rapport["recommande"],
        len(rapport["stagnants"]),
        rapport["fatigue_rpe"],
    )
    return jsonify(rapport)


@analytics_load_bp.route("/api/deload")
def api_deload():
    from weights import load_weights
    from deload import analyser_deload
    return jsonify(analyser_deload(load_weights()))


@analytics_load_bp.route("/api/apply_deload", methods=["POST"])
def api_apply_deload():
    """Override current_weight for each exercise in poids_deload dict."""
    try:
        from weights import load_weights, save_weights
        data         = request.get_json(silent=True) or {}
        poids_deload = data.get("poids_deload", {})
        if not poids_deload:
            return jsonify({"error": "poids_deload manquant"}), 400

        weights = load_weights()
        updated = []
        for exercise, new_weight in poids_deload.items():
            if exercise in weights:
                weights[exercise]["current_weight"] = float(new_weight)
                updated.append(exercise)
        save_weights(weights)
        from routes.daily_brief import invalidate_cache as _brief_invalidate
        _brief_invalidate()
        return jsonify({"success": True, "updated": updated})
    except Exception:
        raise


@analytics_load_bp.route("/api/acwr")
def api_acwr():
    from acwr import calc_acwr
    return jsonify(calc_acwr())


@analytics_load_bp.route("/api/peak_prediction")
def api_peak_prediction():
    """Prédit le LSS des 7 prochains jours via régression linéaire sur les 14 derniers."""
    from life_stress_engine import get_recent_life_stress_trend
    from datetime import date as date_cls, timedelta

    history = get_recent_life_stress_trend(14)   # index 0 = today
    scores  = [h["score"] for h in history if h.get("score") is not None]

    n = len(scores)
    last_score = scores[0] if scores else 65.0

    if n < 14:
        return jsonify({
            "days": [], "slope": 0, "baseline": round(last_score, 1),
            "insufficient_data": True,
            "message": f"Minimum 14 jours de données requis ({n} disponibles).",
        })

    if n >= 14:
        xs = list(range(n))
        mx = sum(xs) / n
        my = sum(scores) / n
        num = sum((x - mx) * (y - my) for x, y in zip(xs, scores))
        den = sum((x - mx) ** 2 for x in xs)
        slope = num / den if den != 0 else 0
    else:
        slope = 0
    today = date_cls.fromisoformat(_today_mtl())

    def level(s):
        if s >= 65:   return "go"
        if s >= 45:   return "go_caution"
        if s >= 25:   return "reduce"
        return "defer"

    result = []
    peak_idx = None
    peak_val = -1
    for i in range(1, 8):
        projected = last_score + slope * i + (70 - last_score) * 0.08 * i
        projected = max(0, min(100, projected))
        d = (today + timedelta(days=i)).isoformat()
        if projected > peak_val:
            peak_val = projected
            peak_idx = i - 1
        result.append({"date": d, "predicted_lss": round(projected, 1), "level": level(projected), "is_peak": False})

    if peak_idx is not None and result:
        result[peak_idx]["is_peak"] = True

    return jsonify({"days": result, "slope": round(slope, 3), "baseline": round(last_score, 1)})


@analytics_load_bp.route("/api/hrv_baseline")
def api_hrv_baseline():
    """28-day rolling HRV baseline + rest flag if today's HRV is significantly below."""
    import db as _db
    from datetime import date as date_cls

    rec_log = _db.get_recovery_logs(limit=60)
    today   = date_cls.fromisoformat(_today_mtl()).isoformat()

    hrv_vals = []
    today_hrv = None
    for e in rec_log:
        hrv = e.get("hrv")
        d   = str(e.get("date", ""))[:10]
        if hrv is None:
            continue
        if d == today:
            today_hrv = float(hrv)
        elif d < today:
            hrv_vals.append(float(hrv))

    hrv_vals_28d = hrv_vals[:28]
    if not hrv_vals_28d:
        return jsonify({"baseline": None, "today_hrv": today_hrv, "flag_rest": False, "data_points": 0})

    baseline = round(sum(hrv_vals_28d) / len(hrv_vals_28d), 1)
    sd = (sum((v - baseline) ** 2 for v in hrv_vals_28d) / len(hrv_vals_28d)) ** 0.5

    flag_rest = False
    deviation = None
    if today_hrv is not None:
        deviation = round(today_hrv - baseline, 1)
        flag_rest = today_hrv < baseline - sd

    return jsonify({
        "baseline":    baseline,
        "sd":          round(sd, 1),
        "today_hrv":   today_hrv,
        "deviation":   deviation,
        "flag_rest":   flag_rest,
        "data_points": len(hrv_vals_28d),
        "message":     (
            f"HRV aujourd'hui ({today_hrv}) est {abs(deviation):.0f} ms sous la baseline ({baseline}) — repos recommandé."
            if flag_rest and deviation is not None else None
        ),
    })


@analytics_load_bp.route("/api/hrv/analysis")
def api_hrv_analysis():
    """
    Analyse HRV complète niveau HRV4Training :
      - RMSSD du jour (Apple Watch heartRateVariabilitySDNN = RMSSD)
      - Baselines personnelles 7j et 30j (rolling)
      - CV coefficient de variation 30j
      - Score normalisé (today/7j_avg × 100) — green/orange/red
      - Tendance linéaire 7j
      - Streak d'alerte (≥3j consécutifs sous baseline)
      - Message contextuel
    """
    import db as _db
    from datetime import date as date_cls
    from hrv_engine import compute_hrv_analysis

    rows     = _db.get_recovery_logs(limit=95)
    analysis = compute_hrv_analysis(rows, date_cls.fromisoformat(_today_mtl()).isoformat())
    return jsonify(analysis)


@analytics_load_bp.route("/api/overtraining_risk")
def api_overtraining_risk():
    """Composite overtraining risk score from RPE trend, HRV drop, mood dip, performance drop."""
    import db as _db
    from datetime import date as date_cls

    today  = date_cls.fromisoformat(_today_mtl()).isoformat()
    risk   = 0
    flags  = []
    detail = {}

    # 1. RPE trend (7j vs 21j)
    sessions_raw = _db.get_workout_sessions(limit=30)
    rpe_7  = [s["rpe"] for s in sessions_raw if s.get("rpe") and str(s.get("date","")) >= (date_cls.fromisoformat(_today_mtl()) - timedelta(days=7)).isoformat()]
    rpe_21 = [s["rpe"] for s in sessions_raw if s.get("rpe") and str(s.get("date","")) >= (date_cls.fromisoformat(_today_mtl()) - timedelta(days=21)).isoformat()]
    if len(rpe_7) >= 2 and len(rpe_21) >= 3:
        avg7  = sum(rpe_7)  / len(rpe_7)
        avg21 = sum(rpe_21) / len(rpe_21)
        detail["rpe_avg_7d"]  = round(avg7,  1)
        detail["rpe_avg_21d"] = round(avg21, 1)
        if avg7 > avg21 + 1.0:
            risk += 2
            flags.append("RPE élevé cette semaine")
        elif avg7 > avg21 + 0.5:
            risk += 1

    # 2. HRV drop (today vs 28d baseline) — direct call within same blueprint
    hrv_baseline_resp = api_hrv_baseline().get_json()
    if hrv_baseline_resp.get("flag_rest"):
        risk += 2
        flags.append(f"HRV sous baseline ({hrv_baseline_resp.get('today_hrv')} vs {hrv_baseline_resp.get('baseline')})")
    detail["hrv_flag"] = hrv_baseline_resp.get("flag_rest")

    # 3. Mood dip (last 3 days avg < 5/10)
    mood_logs = _db.get_mood_logs(days=7)
    recent_moods = [m["score"] for m in mood_logs[:3] if m.get("score") is not None]
    if recent_moods:
        avg_mood = sum(recent_moods) / len(recent_moods)
        detail["avg_mood_3d"] = round(avg_mood, 1)
        if avg_mood < 5:
            risk += 2
            flags.append(f"Humeur basse (moy. {avg_mood:.1f}/10)")
        elif avg_mood < 6.5:
            risk += 1

    # 4. Recovery score (today)
    rec_log = _db.get_recovery_logs(limit=5)
    today_rec = next((e for e in rec_log if str(e.get("date",""))[:10] == today), None)
    if today_rec:
        from health_data import compute_recovery_score
        rec_score = compute_recovery_score(today_rec)
        detail["recovery_score"] = rec_score
        if rec_score is not None:
            if rec_score < 40:
                risk += 2
                flags.append(f"Récupération faible ({rec_score}/100)")
            elif rec_score < 60:
                risk += 1

    if risk >= 5:
        level = "high"
        recommendation = "Repos obligatoire ou séance mobilité seulement."
    elif risk >= 3:
        level = "moderate"
        recommendation = "Réduis le volume de 30-40%. Priorité à la qualité."
    else:
        level = "low"
        recommendation = "Entraîne-toi normalement."

    return jsonify({
        "risk_score":     risk,
        "level":          level,
        "flags":          flags,
        "recommendation": recommendation,
        "detail":         detail,
    })


@analytics_load_bp.route("/api/one_rm_programming")
def api_one_rm_programming():
    """Return estimated 1RM and % programming table for main compound lifts."""
    from weights import load_weights
    import db as _db

    weights  = load_weights()
    compound_categories = {"chest", "back", "legs", "shoulders", "compound_push", "compound_pull", "compound"}

    result = []
    for name, data in weights.items():
        ex_info = _db.get_exercise_info(name) or {}
        cat = (ex_info.get("category") or "").lower()
        load_profile = (ex_info.get("load_profile") or "").lower()

        is_compound = (
            "compound" in load_profile
            or cat in compound_categories
            or any(k in name.lower() for k in ("squat", "deadlift", "bench", "press", "row", "pull"))
        )
        if not is_compound:
            continue

        hist = [e for e in (data.get("history") or []) if e.get("weight")]
        if len(hist) < 2:
            continue

        best_1rm = 0.0
        for entry in hist[:10]:
            w = entry.get("weight", 0)
            reps_str = entry.get("reps", "") or ""
            reps_list = [int(p.strip()) for p in reps_str.split(",") if p.strip().isdigit()]
            r = (sum(reps_list) / len(reps_list)) if reps_list else 0.0
            if r < 1 or r > 15:
                estimated = 0.0
            elif r <= 10:
                estimated = w * (1 + r / 30)
            else:
                estimated = w * (36.0 / (37.0 - r))
            if estimated > best_1rm:
                best_1rm = estimated

        if best_1rm < 10:
            continue

        percentages = [50, 60, 65, 70, 75, 80, 85, 90, 95]
        table = [{"pct": p, "weight": round(best_1rm * p / 100 / 2.5) * 2.5} for p in percentages]

        result.append({
            "exercise":      name,
            "estimated_1rm": round(best_1rm, 1),
            "current_weight": data.get("current_weight"),
            "pct_of_1rm":    round(data.get("current_weight", 0) / best_1rm * 100, 1) if best_1rm > 0 else None,
            "table":         table,
        })

    result.sort(key=lambda x: x["estimated_1rm"], reverse=True)
    return jsonify({"exercises": result[:12]})


@analytics_load_bp.route("/api/mesocycle_status")
def api_mesocycle_status():
    """Return current mesocycle phase based on training weeks since last deload."""
    from utils import get_current_week
    import db as _db

    current_week = get_current_week()

    sessions_raw = _db.get_workout_sessions(limit=60)
    last_deload_date = None
    for s in sessions_raw:
        sname = (s.get("session_name") or "").lower()
        if "deload" in sname or "décharge" in sname:
            d = str(s.get("date", ""))[:10]
            if last_deload_date is None or d > last_deload_date:
                last_deload_date = d

    from datetime import date as date_cls
    if last_deload_date:
        weeks_since = (date_cls.fromisoformat(_today_mtl()) - date_cls.fromisoformat(last_deload_date)).days // 7
    else:
        weeks_since = current_week % 8

    try:
        active_prog = _db.get_active_program()
        if active_prog and active_prog.get("cycle_start_date"):
            cycle_start = date_cls.fromisoformat(str(active_prog["cycle_start_date"])[:10])
            weeks_since = max(0, (date_cls.fromisoformat(_today_mtl()) - cycle_start).days // 7)
    except Exception:
        pass

    week_in_cycle = weeks_since % 8
    if week_in_cycle <= 2:
        phase       = "accumulation"
        phase_label = "Accumulation"
        description = "Volume élevé, intensité modérée. Construis la base."
        icon        = "📈"
        rpe_target  = "7-8"
        vol_guidance = "Vise le MAV (volume maximum adaptable)."
    elif week_in_cycle <= 5:
        phase       = "intensification"
        phase_label = "Intensification"
        description = "Volume modéré, intensité élevée. Pousse les charges."
        icon        = "💪"
        rpe_target  = "8-9"
        vol_guidance = "Réduis les séries, augmente les charges."
    elif week_in_cycle == 6:
        phase       = "realization"
        phase_label = "Réalisation"
        description = "Volume bas, intensité maximale. Teste tes PRs."
        icon        = "🏆"
        rpe_target  = "9-10"
        vol_guidance = "Volume minimal, poids maximaux."
    else:
        phase       = "deload"
        phase_label = "Décharge"
        description = "Récupération active. Réduis volume et intensité de 40-50%."
        icon        = "😴"
        rpe_target  = "5-6"
        vol_guidance = "50% du volume habituel, charges légères."

    return jsonify({
        "current_week":         current_week,
        "week_in_cycle":        week_in_cycle,
        "weeks_since_deload":   weeks_since,
        "phase":                phase,
        "phase_label":          phase_label,
        "description":          description,
        "icon":                 icon,
        "rpe_target":           rpe_target,
        "vol_guidance":         vol_guidance,
        "last_deload_date":     last_deload_date,
        "next_deload_in_weeks": max(0, 8 - weeks_since),
    })


@analytics_load_bp.route("/api/soreness_threshold")
def api_soreness_threshold():
    """Compute personal soreness response curve from volume × soreness history."""
    import db as _db
    from datetime import date as date_cls

    rec_log  = _db.get_recovery_logs(limit=90)
    sessions = _db.get_sessions_for_correlations(days=90)

    pairs = []
    sorted_logs = sorted(rec_log, key=lambda e: str(e.get("date", "")))
    for i, e in enumerate(sorted_logs):
        d = str(e.get("date", ""))[:10]
        soreness = e.get("soreness")
        if soreness is None:
            continue
        from datetime import timedelta
        prev_date = (date_cls.fromisoformat(d) - timedelta(days=1)).isoformat()
        vol = sessions.get(prev_date, {}).get("session_volume")
        if vol is not None and float(vol) > 0:
            pairs.append({"volume": float(vol), "soreness": float(soreness), "date": d})

    if len(pairs) < 5:
        return jsonify({"pairs": pairs, "threshold": None, "message": "Données insuffisantes"})

    pairs_sorted = sorted(pairs, key=lambda x: x["volume"])
    n = len(pairs_sorted)
    low_sore  = [p["soreness"] for p in pairs_sorted[:n // 2]]
    high_sore = [p["soreness"] for p in pairs_sorted[n // 2:]]
    avg_low  = sum(low_sore)  / len(low_sore)
    avg_high = sum(high_sore) / len(high_sore)
    median_vol = pairs_sorted[n // 2]["volume"]

    threshold_vol = None
    for p in pairs_sorted:
        if p["soreness"] >= 6:
            threshold_vol = p["volume"]
            break

    return jsonify({
        "pairs":           pairs[-60:],
        "median_volume":   round(median_vol),
        "avg_soreness_low_vol":  round(avg_low,  1),
        "avg_soreness_high_vol": round(avg_high, 1),
        "threshold_vol":   round(threshold_vol) if threshold_vol else None,
        "message": (
            f"Au-dessus de {round(threshold_vol):,} lbs de volume, tes courbatures dépassent 6/10."
            if threshold_vol else None
        ),
    })


@analytics_load_bp.route("/api/stats/intensity")
def api_stats_intensity():
    """Average %1RM across all working sets logged in the last 7 days."""
    import db as _db
    from datetime import date, timedelta

    cutoff = (date.fromisoformat(_today_mtl()) - timedelta(days=7)).isoformat()

    one_rms: dict[str, float] = {}
    for r in _db.get_current_1rm_estimates():
        one_rms[r["name"]] = r["estimated_1rm"]

    if not one_rms:
        return jsonify({"avg_pct_1rm": None, "zone": None, "sets_count": 0})

    from weights import load_weights
    weights = load_weights()

    pct_values: list[float] = []
    for ex_name, ex_data in weights.items():
        e1rm = one_rms.get(ex_name)
        if not e1rm or e1rm <= 0:
            continue
        for entry in (ex_data.get("history") or []):
            if (entry.get("date") or "") < cutoff:
                break
            sets = entry.get("sets") or []
            if sets:
                for s in sets:
                    w = float(s.get("weight") or 0)
                    if w > 0:
                        pct_values.append(min(w / e1rm * 100.0, 120.0))
            else:
                w = float(entry.get("weight") or 0)
                reps_str = str(entry.get("reps") or "")
                if w > 0 and reps_str:
                    n_sets = len(reps_str.split(",")) if "," in reps_str else 1
                    for _ in range(n_sets):
                        pct_values.append(min(w / e1rm * 100.0, 120.0))

    if not pct_values:
        return jsonify({"avg_pct_1rm": None, "zone": None, "sets_count": 0})

    avg = round(sum(pct_values) / len(pct_values), 1)
    if avg >= 80:
        zone = "force"
    elif avg >= 65:
        zone = "hypertrophie"
    else:
        zone = "volume"

    return jsonify({"avg_pct_1rm": avg, "zone": zone, "sets_count": len(pct_values)})
