"""
proactive_insights.py — /api/coach/proactive_insights

Moteur d'analyse en continu : 14 dimensions, 3 niveaux d'intervention.
Coexiste avec /api/coach/daily_insight (pas de breaking change).

Niveau 1 — push_insight     : critique, action immédiate
Niveau 2 — dashboard_insight: visible à l'ouverture de l'app
Niveau 3 — intelligence_insights: analytiques, lecture longue

Dimensions implémentées (D1, D3, D10) :
  D1  Fenêtre de surcharge optimale (HRV + readiness + ACWR + soreness)
  D3  Alerte surmenage précoce multi-signal
  D10 ACWR critique (> 1.4)
"""
from __future__ import annotations

import logging
from datetime import date as date_cls, timedelta
from flask import Blueprint, jsonify

proactive_insights_bp = Blueprint("proactive_insights", __name__)
logger = logging.getLogger("trainingos.proactive_insights")

# ── helpers ───────────────────────────────────────────────────────────────────

def _today() -> str:
    from utils import _today_mtl
    return _today_mtl()


def _recent_recovery(days: int = 7) -> list[dict]:
    """Last N recovery_log entries, newest first."""
    from db_body import get_recovery_logs
    rows = get_recovery_logs(limit=days + 5)
    cutoff = (date_cls.fromisoformat(_today()) - timedelta(days=days)).isoformat()
    return [r for r in rows if (r.get("date") or "") >= cutoff]


def _acwr_data() -> dict | None:
    try:
        from acwr import calc_acwr
        result = calc_acwr()
        if isinstance(result, dict) and "ratio" in result:
            return result
        if isinstance(result, list) and result:
            return result[-1]
    except Exception as e:
        logger.warning("_acwr_data error: %s", e)
    return None


def _hrv_analysis() -> dict | None:
    try:
        from hrv_engine import compute_hrv_analysis
        from db_body import get_recovery_logs
        rows = get_recovery_logs(limit=60)
        return compute_hrv_analysis(rows, _today())
    except Exception as e:
        logger.warning("_hrv_analysis error: %s", e)
    return None


def _readiness_score() -> float | None:
    try:
        import readiness
        data = readiness.compute()
        return data.get("overall_score") or data.get("score")
    except Exception as e:
        logger.warning("_readiness_score error: %s", e)
    return None


# ── D10 — ACWR critique ───────────────────────────────────────────────────────

def _check_d10(acwr: dict | None) -> dict | None:
    """Niveau 1 : ACWR > 1.4 → push + dashboard."""
    if not acwr:
        return None
    ratio = acwr.get("ratio", 0)
    if ratio < 1.4:
        return None
    return {
        "dimension": "acwr_critical",
        "level": 1,
        "title": "Sur-charge détectée",
        "message": f"ACWR {ratio:.2f} — risque de blessure élevé. Séance légère uniquement aujourd'hui.",
        "data": {"acwr_ratio": round(ratio, 2)},
        "action": "open_recovery",
        "icon": "exclamationmark.triangle.fill",
        "color": "red",
    }


# ── D3 — Surmenage précoce multi-signal ───────────────────────────────────────

def _check_d3(recovery: list[dict], acwr: dict | None, hrv: dict | None) -> dict | None:
    """Niveau 1 : 2+ signaux dégradés simultanément sur 3+ jours."""
    if len(recovery) < 3:
        return None

    recent = recovery[:3]  # 3 derniers jours

    signals_fired: list[str] = []

    # Signal 1 : HRV zone rouge
    if hrv and hrv.get("hrv_zone") == "red":
        signals_fired.append("HRV bas")

    # Signal 2 : resting_hr en hausse (moyenne 3j > 7j baseline si dispo)
    rhr_3j = [r["resting_hr"] for r in recent if r.get("resting_hr")]
    rhr_all = [r["resting_hr"] for r in recovery if r.get("resting_hr")]
    if len(rhr_3j) >= 2 and len(rhr_all) >= 5:
        avg_3j = sum(rhr_3j) / len(rhr_3j)
        avg_base = sum(rhr_all) / len(rhr_all)
        if avg_3j > avg_base * 1.05:
            signals_fired.append("FC repos élevée")

    # Signal 3 : soreness élevée 3 jours de suite
    sor_3j = [r["soreness"] for r in recent if r.get("soreness") is not None]
    if len(sor_3j) >= 2 and all(s >= 6 for s in sor_3j):
        signals_fired.append("douleurs musculaires persistantes")

    # Signal 4 : fatigue perçue élevée
    fat_3j = [r["fatigue_perceived"] for r in recent if r.get("fatigue_perceived") is not None]
    if len(fat_3j) >= 2 and sum(fat_3j) / len(fat_3j) >= 6.5:
        signals_fired.append("fatigue perçue élevée")

    # Signal 5 : ACWR > 1.2 (seuil prudent, pas encore critique)
    if acwr and 1.2 <= acwr.get("ratio", 0) < 1.4:
        signals_fired.append("charge d'entraînement en zone caution")

    if len(signals_fired) < 2:
        return None

    signals_str = " · ".join(signals_fired[:3])
    return {
        "dimension": "overreach_early",
        "level": 1,
        "title": "Signaux de fatigue multiples",
        "message": f"{len(signals_fired)} signaux détectés simultanément : {signals_str}. Réduis l'intensité cette semaine.",
        "data": {"signals": signals_fired},
        "action": "open_recovery",
        "icon": "waveform.path.ecg",
        "color": "orange",
    }


# ── D1 — Fenêtre de surcharge optimale ────────────────────────────────────────

def _check_d1(recovery: list[dict], acwr: dict | None, hrv: dict | None, readiness: float | None) -> dict | None:
    """Niveau 2 : HRV vert 3j+ AND readiness > 75 AND ACWR 0.9-1.2 AND soreness < 4."""
    if not hrv or not hrv.get("baseline_available"):
        return None

    # HRV au-dessus baseline 3 jours consécutifs (zone verte)
    if hrv.get("hrv_zone") != "green":
        return None
    # Vérifier trend 3j
    hrv_trend = hrv.get("hrv_trend", "")
    if hrv_trend not in ("up", "stable", ""):
        return None

    # Readiness > 75
    if readiness is not None and readiness < 75:
        return None

    # ACWR dans fenêtre optimale
    if acwr:
        ratio = acwr.get("ratio", 1.0)
        if not (0.85 <= ratio <= 1.25):
            return None

    # Soreness moyenne < 4 sur les 3 derniers jours
    sor_recent = [r["soreness"] for r in recovery[:3] if r.get("soreness") is not None]
    if sor_recent and sum(sor_recent) / len(sor_recent) >= 4:
        return None

    hrv_score = hrv.get("hrv_score")
    hrv_vs_baseline = f"+{hrv_score - 100:.0f}%" if hrv_score and hrv_score > 100 else ""
    readiness_str = f"{int(readiness)}/100" if readiness else ""

    parts = []
    if hrv_vs_baseline:
        parts.append(f"HRV {hrv_vs_baseline} vs baseline")
    if readiness_str:
        parts.append(f"readiness {readiness_str}")

    data_str = " · ".join(parts) if parts else "Tous les indicateurs au vert"

    return {
        "dimension": "optimal_window",
        "level": 2,
        "title": "Fenêtre optimale détectée",
        "message": f"Ton corps est prêt pour une surcharge. Vise +5% ce soir. {data_str}.",
        "data": {
            "hrv_score": hrv_score,
            "hrv_zone": hrv.get("hrv_zone"),
            "acwr_ratio": acwr.get("ratio") if acwr else None,
            "readiness": readiness,
        },
        "action": "open_seance",
        "icon": "bolt.fill",
        "color": "green",
    }


# ── Intelligence insights helpers ────────────────────────────────────────────

_PUSH_MUSCLES = {"chest", "pectorals", "pectoral", "triceps", "tricep",
                 "front deltoid", "anterior deltoid", "shoulders", "shoulder"}
_PULL_MUSCLES = {"back", "lats", "lat", "biceps", "bicep", "rear deltoid",
                 "posterior deltoid", "traps", "trap", "rhomboids", "rhomboid"}


def _recent_exercise_weights(days: int = 42) -> dict:
    """Return {exercise_name: [{date, weight}]} newest-first for recent sessions."""
    try:
        import db_core
        cutoff = (date_cls.fromisoformat(_today()) - timedelta(days=days)).isoformat()
        resp = (
            db_core._client.table("exercise_logs")
            .select("weight, exercises!inner(name), workout_sessions!inner(date)")
            .gte("workout_sessions.date", cutoff)
            .not_.is_("weight", "null")
            .execute()
        )
        result: dict = {}
        for r in (resp.data or []):
            name = (r.get("exercises") or {}).get("name")
            date = str((r.get("workout_sessions") or {}).get("date", ""))[:10]
            w = r.get("weight")
            if name and date and w:
                result.setdefault(name, []).append({"date": date, "weight": float(w)})
        for name in result:
            result[name].sort(key=lambda x: x["date"], reverse=True)
        return result
    except Exception as e:
        logger.warning("_recent_exercise_weights error: %s", e)
    return {}


# ── D4 — Plateau de force ──────────────────────────────────────────────────────

def _check_d4(ex_weights: dict) -> dict | None:
    """D4: strongest stagnant exercise ≥ 3 sessions over 2+ weeks."""
    best: tuple | None = None
    best_weeks = 0
    for name, entries in ex_weights.items():
        if len(entries) < 4:
            continue
        recent_max = max(e["weight"] for e in entries[:3])
        prior_max  = max((e["weight"] for e in entries[3:min(7, len(entries))]), default=0.0)
        if prior_max > 0 and recent_max <= prior_max:
            oldest_recent = entries[2]["date"]
            weeks = round((date_cls.fromisoformat(_today()) - date_cls.fromisoformat(oldest_recent)).days / 7)
            if weeks >= 2 and weeks > best_weeks:
                best_weeks = weeks
                best = (name, recent_max, weeks)
    if not best:
        return None
    name, weight, weeks = best
    return {
        "dimension": "plateau_force",
        "level": 3,
        "title": f"Plateau — {name}",
        "message": f"Stagne à {weight:.0f}lbs depuis {weeks} sem. Envisage décharge ou changement de schéma.",
        "data": {"exercise": name, "weight": weight, "weeks": weeks},
        "action": "open_stats",
        "icon": "arrow.up.right.and.arrow.down.left",
        "color": "yellow",
    }


# ── D5 — Corrélation nutrition × performance ──────────────────────────────────

def _check_d5(sessions: list, nutrition: list) -> dict | None:
    """D5: protein intake lower on training days vs rest days."""
    try:
        from db_profile import get_nutrition_settings
        ns = get_nutrition_settings()
        prot_target = float(ns.get("proteines") or 0)

        session_dates = {str(s.get("date", ""))[:10] for s in sessions if s.get("date")}
        training_prot = [float(n["proteines"]) for n in nutrition
                         if str(n.get("date", ""))[:10] in session_dates and n.get("proteines")]
        rest_prot     = [float(n["proteines"]) for n in nutrition
                         if str(n.get("date", ""))[:10] not in session_dates and n.get("proteines")]

        if len(training_prot) < 5 or len(rest_prot) < 5:
            return None
        avg_training = sum(training_prot) / len(training_prot)
        avg_rest     = sum(rest_prot) / len(rest_prot)
        if avg_training >= avg_rest * 0.9:
            return None

        deficit = int(avg_rest - avg_training)
        pct_diff = int((1 - avg_training / avg_rest) * 100)
        vs_target = f" (cible {prot_target:.0f}g)" if prot_target > 50 else ""
        return {
            "dimension": "nutrition_performance",
            "level": 3,
            "title": "Moins de protéines les jours d'entraînement",
            "message": f"Séances : {avg_training:.0f}g vs repos : {avg_rest:.0f}g{vs_target} (−{pct_diff}%). L'anabolisme post-séance exige plus.",
            "data": {"avg_training": round(avg_training, 1), "avg_rest": round(avg_rest, 1), "deficit": deficit},
            "action": "open_nutrition",
            "icon": "chart.line.downtrend.xyaxis",
            "color": "orange",
        }
    except Exception as e:
        logger.warning("_check_d5 error: %s", e)
    return None


# ── D8 — Déséquilibre musculaire push/pull ────────────────────────────────────

def _check_d8(ex_logs: list) -> dict | None:
    """D8: push/pull volume imbalance over 28 days (ratio < 0.55 or > 1.8)."""
    push_sets = 0
    pull_sets = 0
    for log in ex_logs:
        muscles = [m.lower().strip() for m in (log.get("muscles") or [])]
        sets = len(log.get("sets_json") or []) or 1
        if any(m in _PUSH_MUSCLES for m in muscles):
            push_sets += sets
        elif any(m in _PULL_MUSCLES for m in muscles):
            pull_sets += sets

    if push_sets + pull_sets < 20:
        return None
    total = push_sets + pull_sets
    ratio = push_sets / pull_sets if pull_sets > 0 else 99.0
    if 0.55 <= ratio <= 1.8:
        return None

    dominant = "Push" if ratio > 1 else "Pull"
    weaker   = "Pull" if ratio > 1 else "Push"
    dom_pct  = int(push_sets / total * 100) if ratio > 1 else int(pull_sets / total * 100)
    wk_pct   = 100 - dom_pct
    return {
        "dimension": "muscle_imbalance",
        "level": 3,
        "title": f"Déséquilibre {dominant}/{weaker}",
        "message": f"{dominant} : {dom_pct}% des séries vs {weaker} : {wk_pct}%. Équilibre cible : 50/50.",
        "data": {"push_sets": push_sets, "pull_sets": pull_sets, "ratio": round(ratio, 2)},
        "action": "open_stats",
        "icon": "arrow.left.arrow.right",
        "color": "yellow",
    }


# ── D9 — Meilleur jour de la semaine ──────────────────────────────────────────

def _check_d9(sessions: list) -> dict | None:
    """D9: identify best day of week by lowest avg RPE (≥ 3 sessions per day)."""
    day_rpe: dict[int, list] = {}
    for s in sessions:
        if not s.get("rpe") or not s.get("date"):
            continue
        try:
            d = date_cls.fromisoformat(str(s["date"])[:10])
            day_rpe.setdefault(d.weekday(), []).append(float(s["rpe"]))
        except Exception:
            continue

    reliable = {d: v for d, v in day_rpe.items() if len(v) >= 3}
    if len(reliable) < 2:
        return None
    best_day  = min(reliable, key=lambda d: sum(reliable[d]) / len(reliable[d]))
    worst_day = max(reliable, key=lambda d: sum(reliable[d]) / len(reliable[d]))
    best_avg  = sum(reliable[best_day]) / len(reliable[best_day])
    worst_avg = sum(reliable[worst_day]) / len(reliable[worst_day])
    if worst_avg - best_avg < 0.5:
        return None

    day_fr = ["Lun", "Mar", "Mer", "Jeu", "Ven", "Sam", "Dim"]
    return {
        "dimension": "best_day_pattern",
        "level": 3,
        "title": f"Meilleur jour : {day_fr[best_day]}",
        "message": f"RPE moyen {day_fr[best_day]} : {best_avg:.1f} vs {day_fr[worst_day]} : {worst_avg:.1f}. Programme tes séances clés le {day_fr[best_day]}.",
        "data": {"best_day": best_day, "best_avg_rpe": round(best_avg, 2)},
        "action": "open_stats",
        "icon": "calendar.badge.checkmark",
        "color": "teal",
    }


# ── D11 — Séances sans log nutrition ──────────────────────────────────────────

def _check_d11(sessions: list, nutrition: list) -> dict | None:
    """D11: ≥ 40% of sessions in last 14 days have no nutrition logged."""
    session_dates = {str(s.get("date", ""))[:10] for s in sessions
                     if s.get("date") and (s.get("completed") or s.get("rpe"))}
    if len(session_dates) < 3:
        return None
    logged_dates = {str(n.get("date", ""))[:10] for n in nutrition if (n.get("calories") or 0) > 100}
    unlogged = session_dates - logged_dates
    if not unlogged or len(unlogged) / len(session_dates) < 0.4:
        return None

    total = len(session_dates)
    pct = int(len(unlogged) / total * 100)
    return {
        "dimension": "post_workout_nutrition",
        "level": 3,
        "title": "Nutrition non loggée les jours de séance",
        "message": f"{len(unlogged)}/{total} séances sans log nutrition ({pct}%). Tracker ta nutrition les jours d'entraînement optimise la récupération.",
        "data": {"unlogged": len(unlogged), "total": total},
        "action": "open_nutrition",
        "icon": "fork.knife",
        "color": "orange",
    }


# ── D12 — Récupération incomplète ─────────────────────────────────────────────

def _check_d12(sessions: list, recovery: list) -> dict | None:
    """D12: 3+ consecutive session days without rest, with soreness >= 3."""
    session_dates = sorted({str(s.get("date", ""))[:10] for s in sessions if s.get("date")}, reverse=True)
    if len(session_dates) < 3:
        return None

    max_streak = current = 1
    for i in range(1, len(session_dates)):
        diff = (date_cls.fromisoformat(session_dates[i - 1]) - date_cls.fromisoformat(session_dates[i])).days
        if diff == 1:
            current += 1
            max_streak = max(max_streak, current)
        else:
            current = 1

    if max_streak < 3:
        return None

    sore_vals = [r["soreness"] for r in recovery[:3] if r.get("soreness") is not None]
    avg_soreness = sum(sore_vals) / len(sore_vals) if sore_vals else None
    if avg_soreness is not None and avg_soreness < 3:
        return None

    sore_str = f" — douleurs {avg_soreness:.1f}/10" if avg_soreness else ""
    return {
        "dimension": "incomplete_recovery",
        "level": 3,
        "title": f"{max_streak} jours consécutifs sans repos",
        "message": f"{max_streak} séances d'affilée{sore_str}. Un jour de repos actif améliore l'adaptation musculaire.",
        "data": {"consecutive": max_streak, "avg_soreness": avg_soreness},
        "action": "open_recovery",
        "icon": "moon.fill",
        "color": "orange",
    }


# ── D14 — Rapport mensuel ─────────────────────────────────────────────────────

def _check_d14(sessions: list) -> dict | None:
    """D14: this month vs last month session count and RPE comparison."""
    import calendar as _cal
    today = date_cls.fromisoformat(_today())
    if today.day < 10:
        return None

    this_month = today.strftime("%Y-%m")
    last_month = (today.replace(day=1) - timedelta(days=1)).strftime("%Y-%m")

    this_m = [s for s in sessions if str(s.get("date", ""))[:7] == this_month and (s.get("completed") or s.get("rpe"))]
    last_m = [s for s in sessions if str(s.get("date", ""))[:7] == last_month and (s.get("completed") or s.get("rpe"))]

    if len(last_m) < 3 or len(this_m) < 2:
        return None

    _, days_in_month = _cal.monthrange(today.year, today.month)
    projected = round(len(this_m) / today.day * days_in_month)
    delta = projected - len(last_m)

    this_rpe = [float(s["rpe"]) for s in this_m if s.get("rpe")]
    last_rpe = [float(s["rpe"]) for s in last_m if s.get("rpe")]
    parts = [f"{len(this_m)} séances ({'+' if delta >= 0 else ''}{delta} vs {len(last_m)} mois dernier, proj. {projected})"]
    if this_rpe and last_rpe:
        t_avg = sum(this_rpe) / len(this_rpe)
        l_avg = sum(last_rpe) / len(last_rpe)
        diff = t_avg - l_avg
        parts.append(f"RPE moy {t_avg:.1f} ({'+' if diff >= 0 else ''}{diff:.1f})")

    month_fr = ["Jan","Fév","Mar","Avr","Mai","Jun","Jul","Aoû","Sep","Oct","Nov","Déc"]
    return {
        "dimension": "monthly_report",
        "level": 3,
        "title": f"Bilan {month_fr[today.month - 1]} — proj. {projected} séances",
        "message": " · ".join(parts),
        "data": {"this_count": len(this_m), "last_count": len(last_m), "projected": projected},
        "action": "open_stats",
        "icon": "calendar",
        "color": "blue",
    }


# ── Intelligence insights endpoint ────────────────────────────────────────────

@proactive_insights_bp.route("/api/coach/intelligence_insights")
def api_intelligence_insights():
    try:
        from db_sessions import get_workout_sessions, get_exercise_logs_since
        from db_stats import get_nutrition_daily_full

        sessions   = get_workout_sessions(limit=90)
        nutrition  = get_nutrition_daily_full(days=30)
        recovery   = _recent_recovery(days=7)
        ex_weights = _recent_exercise_weights(days=42)
        cutoff_28  = (date_cls.fromisoformat(_today()) - timedelta(days=28)).isoformat()
        ex_logs    = get_exercise_logs_since(cutoff_28)

        insights = [c for c in [
            _check_d4(ex_weights),
            _check_d5(sessions, nutrition),
            _check_d8(ex_logs),
            _check_d9(sessions),
            _check_d11(sessions, nutrition),
            _check_d12(sessions, recovery),
            _check_d14(sessions),
        ] if c is not None]

        return jsonify({"insights": insights, "computed_at": _today()})
    except Exception as e:
        logger.exception("intelligence_insights error: %s", e)
        return jsonify({"error": str(e)}), 500


# ── Main endpoint ─────────────────────────────────────────────────────────────

@proactive_insights_bp.route("/api/coach/proactive_insights")
def api_proactive_insights():
    try:
        recovery = _recent_recovery(days=7)
        acwr     = _acwr_data()
        hrv      = _hrv_analysis()
        ready    = _readiness_score()

        # Évaluer les dimensions
        d10 = _check_d10(acwr)
        d3  = _check_d3(recovery, acwr, hrv)
        d1  = _check_d1(recovery, acwr, hrv, ready)

        # Niveau 1 — un seul push insight (priorité : D10 > D3)
        push_insight = d10 or d3

        # Niveau 2 — un seul dashboard insight
        # D10 et D3 sont critiques → pas de "fenêtre optimale" si surmenage
        dashboard_insight = None
        if not push_insight:
            dashboard_insight = d1

        # Niveau 3 — à venir (D4, D5, D8, D9…)
        intelligence_insights: list[dict] = []

        return jsonify({
            "push_insight":          push_insight,
            "dashboard_insight":     dashboard_insight,
            "intelligence_insights": intelligence_insights,
            "computed_at":           _today(),
        })

    except Exception as e:
        logger.exception("proactive_insights error: %s", e)
        return jsonify({"error": str(e)}), 500
