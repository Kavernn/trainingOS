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
