from flask import Blueprint, jsonify, request
import logging

logger = logging.getLogger("trainingos")
nutrition_analytics_bp = Blueprint("nutrition_analytics", __name__)

_CORR_MIN_N = 12  # minimum statistique valide (Curran-Everett 2018)


@nutrition_analytics_bp.route("/api/nutrition/correlations")
def api_nutrition_correlations():
    """Join 90 days of nutrition + workout RPE + recovery to surface correlations."""
    import db as _db
    from datetime import date as _date, timedelta
    from nutrition import get_recent_days, load_settings

    settings    = load_settings()
    cal_target  = float(settings.get("limite_calories", 2400)    or 2400)
    prot_target = float(settings.get("objectif_proteines", 180)  or 180)

    nutr_days    = get_recent_days(90)
    nutr_by_date = {d["date"]: d for d in nutr_days}
    sessions     = _db.get_sessions_for_correlations(days=90)
    recovery     = _db.get_recovery_logs(limit=90)
    rec_by_date  = {str(r.get("date", ""))[:10]: r for r in recovery}

    # ── 1. Protein adherence D → next-day RPE ─────────────────────────────
    high_prot_rpe, low_prot_rpe = [], []
    for d_str in sorted(nutr_by_date):
        try:
            next_d = (_date.fromisoformat(d_str) + timedelta(days=1)).isoformat()
        except Exception:
            continue
        rpe = (sessions.get(next_d) or {}).get("rpe")
        if rpe is None:
            continue
        prot = nutr_by_date[d_str].get("proteines", 0) or 0
        (high_prot_rpe if prot >= prot_target * 0.9 else low_prot_rpe).append(float(rpe))

    prot_rpe = None
    if len(high_prot_rpe) >= _CORR_MIN_N and len(low_prot_rpe) >= _CORR_MIN_N:
        avg_h = round(sum(high_prot_rpe) / len(high_prot_rpe), 1)
        avg_l = round(sum(low_prot_rpe)  / len(low_prot_rpe),  1)
        prot_rpe = {
            "high_prot_avg_rpe": avg_h,
            "low_prot_avg_rpe":  avg_l,
            "diff":              round(avg_h - avg_l, 1),
            "sample_high":       len(high_prot_rpe),
            "sample_low":        len(low_prot_rpe),
        }

    # ── 2. Calorie adherence D → same-day recovery score ─────────────────
    on_target_rec, off_target_rec = [], []
    for d_str, nutr in nutr_by_date.items():
        rec = rec_by_date.get(d_str)
        if not rec:
            continue
        scores = []
        if rec.get("soreness") is not None: scores.append(10 - float(rec["soreness"]))
        if rec.get("fatigue")  is not None: scores.append(10 - float(rec["fatigue"]))
        if rec.get("mood")     is not None: scores.append(float(rec["mood"]))
        if len(scores) < 2:
            continue
        rec_score = sum(scores) / len(scores)
        cal = nutr.get("calories", 0) or 0
        (on_target_rec if cal_target * 0.85 <= cal <= cal_target * 1.15 else off_target_rec).append(rec_score)

    cal_rec = None
    if len(on_target_rec) >= _CORR_MIN_N and len(off_target_rec) >= _CORR_MIN_N:
        avg_on  = round(sum(on_target_rec)  / len(on_target_rec),  1)
        avg_off = round(sum(off_target_rec) / len(off_target_rec), 1)
        cal_rec = {
            "on_target_avg":  avg_on,
            "off_target_avg": avg_off,
            "diff":           round(avg_on - avg_off, 1),
            "sample_on":      len(on_target_rec),
            "sample_off":     len(off_target_rec),
        }

    # ── 3. Session volume D → next-day calorie intake ────────────────────
    vols = [v["session_volume"] for v in sessions.values() if v.get("session_volume")]
    vol_cal = None
    if vols:
        vol_median   = sorted(vols)[len(vols) // 2]
        high_vol_cal, low_vol_cal = [], []
        for d_str, sess in sessions.items():
            sv = sess.get("session_volume")
            if sv is None:
                continue
            try:
                next_d = (_date.fromisoformat(d_str) + timedelta(days=1)).isoformat()
            except Exception:
                continue
            cal = (nutr_by_date.get(next_d) or {}).get("calories", 0) or 0
            if cal == 0:
                continue
            (high_vol_cal if sv >= vol_median else low_vol_cal).append(float(cal))
        if len(high_vol_cal) >= _CORR_MIN_N and len(low_vol_cal) >= _CORR_MIN_N:
            avg_h = round(sum(high_vol_cal) / len(high_vol_cal))
            avg_l = round(sum(low_vol_cal)  / len(low_vol_cal))
            vol_cal = {
                "high_vol_avg_cal": avg_h,
                "low_vol_avg_cal":  avg_l,
                "diff":             avg_h - avg_l,
            }

    return jsonify({
        "prot_rpe":          prot_rpe,
        "cal_rec":           cal_rec,
        "vol_cal":           vol_cal,
        "sample_days":       len(nutr_by_date),
        "insufficient_data": prot_rpe is None and cal_rec is None and vol_cal is None,
        "min_n_required":    _CORR_MIN_N,
    })
