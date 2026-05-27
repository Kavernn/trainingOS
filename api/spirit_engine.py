"""spirit_engine.py — Spirit axis for Phoenix Score + pattern insights."""
from __future__ import annotations
import logging
import math
from datetime import date, timedelta

logger = logging.getLogger("trainingos.spirit")


def _today() -> date:
    try:
        from zoneinfo import ZoneInfo
        from datetime import datetime
        return datetime.now(ZoneInfo("America/Montreal")).date()
    except Exception:
        return date.today()


# ── Spirit Phoenix axis ───────────────────────────────────────────────────────

def compute_spirit_axis(last7_dates: set[str], prior7_dates: set[str]) -> tuple[float, dict]:
    """Returns (delta%, details) for optional 4th Phoenix axis."""
    import db

    bw  = db.get_breathwork_sessions_spirit_alias(limit=60)  or []
    med = db.get_meditation_sessions(limit=60)  or []
    journals = db.get_spirit_journal_entries(limit=30) or []

    bw_dates  = {s["started_at"][:10] for s in bw}
    med_dates = {s["started_at"][:10] for s in med}
    j_dates   = {j["date"] for j in journals}

    bw_last   = sum(1 for d in last7_dates  if d in bw_dates)
    bw_prior  = sum(1 for d in prior7_dates if d in bw_dates)
    med_last  = sum(1 for d in last7_dates  if d in med_dates)
    med_prior = sum(1 for d in prior7_dates if d in med_dates)
    j_last    = sum(1 for d in last7_dates  if d in j_dates)
    j_prior   = sum(1 for d in prior7_dates if d in j_dates)

    has_baseline = bw_prior > 0 or med_prior > 0 or j_prior > 0

    details = {
        "breathwork_last":  bw_last,   "breathwork_prior": bw_prior,
        "meditation_last":  med_last,  "meditation_prior": med_prior,
        "journal_last":     j_last,    "journal_prior":    j_prior,
        "has_baseline":     has_baseline,
    }

    if not has_baseline:
        return 0.0, details

    # Empty week → neutral rather than full -100% penalty
    if bw_last == 0 and med_last == 0 and j_last == 0:
        return 0.0, details

    def _delta(last: int, prior: int) -> float:
        if last == 0 and prior == 0:
            return 0.0
        return ((last - prior) / max(prior, 1)) * 100.0

    delta = (
        _delta(bw_last,  bw_prior)  * 0.40
        + _delta(med_last, med_prior) * 0.40
        + _delta(j_last,   j_prior)   * 0.20
    )
    return round(delta, 1), details


# ── Pattern insights ──────────────────────────────────────────────────────────

def compute_spirit_patterns() -> dict:
    """Correlate spirit practices with PSS and workout data — 90-day window."""
    import db

    today  = _today()
    cutoff = (today - timedelta(days=90)).isoformat()

    bw  = db.get_breathwork_sessions_spirit_alias(limit=200) or []
    med = db.get_meditation_sessions(limit=200) or []

    bw_recent  = [s for s in bw  if s.get("started_at", "")[:10] >= cutoff]
    med_recent = [s for s in med if s.get("started_at", "")[:10] >= cutoff]

    total = len(bw_recent) + len(med_recent)
    if total < 3:
        return {"insights": [], "total_sessions": total, "enough_data": False}

    insights = []

    # 1. Protocol distribution
    if bw_recent:
        counts: dict[str, int] = {}
        for s in bw_recent:
            p = s.get("protocol", "calm_storm")
            counts[p] = counts.get(p, 0) + 1
        top_p, top_n = max(counts.items(), key=lambda x: x[1])
        labels = {"calm_storm": "Calm the Storm", "ignite": "Ignite", "stillness": "Stillness"}
        insights.append({
            "type":   "protocol_dominant",
            "title":  "Protocole dominant",
            "body":   f"{labels.get(top_p, top_p)} : {top_n} sessions",
            "detail": f"Sur {len(bw_recent)} séances de breathwork.",
        })

    # 2. Breathwork × PSS correlation
    pss_records = db.get_pss_records(limit=90) or []
    pss_by_date = {
        r.get("date", ""): float(r.get("pss_score") or r.get("score") or 0)
        for r in pss_records
    }
    bw_days     = {s["started_at"][:10] for s in bw_recent}
    all_pss_days = set(pss_by_date.keys())
    bw_pss      = [pss_by_date[d] for d in bw_days     if d in pss_by_date]
    non_bw_pss  = [pss_by_date[d] for d in all_pss_days if d not in bw_days]

    if len(bw_pss) >= 3 and len(non_bw_pss) >= 3:
        avg_bw     = round(sum(bw_pss)     / len(bw_pss),     1)
        avg_non_bw = round(sum(non_bw_pss) / len(non_bw_pss), 1)
        if avg_non_bw > avg_bw + 3:
            pct = round((avg_non_bw - avg_bw) / max(avg_non_bw, 1) * 100)
            insights.append({
                "type":   "breathwork_pss",
                "title":  "Breathwork × Stress",
                "body":   f"Jours avec breathwork : PSS {avg_bw} vs {avg_non_bw} sans.",
                "detail": f"~{pct}% de réduction sur les 90 derniers jours.",
            })

    # 3. Morning breathwork pattern
    morning_bw = [s for s in bw_recent if _local_hour(s.get("started_at", "")) < 10]
    if len(morning_bw) >= 3:
        insights.append({
            "type":   "morning_breathwork",
            "title":  "Breathwork matinal",
            "body":   f"{len(morning_bw)} séances avant 10h sur 90 jours.",
            "detail": "Le matin reste la fenêtre la plus efficace.",
        })

    # 4. Meditation consistency
    med_dates_sorted = sorted({s["started_at"][:10] for s in med_recent}, reverse=True)
    if len(med_dates_sorted) >= 3:
        streak = 1
        for i in range(1, len(med_dates_sorted)):
            d1 = date.fromisoformat(med_dates_sorted[i - 1])
            d2 = date.fromisoformat(med_dates_sorted[i])
            if (d1 - d2).days <= 2:
                streak += 1
            else:
                break
        if streak >= 3:
            insights.append({
                "type":   "meditation_streak",
                "title":  "Consistance méditation",
                "body":   f"{streak} sessions rapprochées.",
                "detail": "La régularité compte plus que la durée.",
            })

    # 5. Arsenal trigger usage
    arsenal_bw = [s for s in bw_recent if s.get("triggered_from") == "arsenal"]
    if len(arsenal_bw) >= 2:
        insights.append({
            "type":   "arsenal_usage",
            "title":  "Calm the Storm déployé",
            "body":   f"{len(arsenal_bw)} fois depuis l'Arsenal.",
            "detail": "Tu utilises le breathwork comme première ligne de défense.",
        })

    return {
        "insights":       insights,
        "total_sessions": total,
        "enough_data":    True,
    }


def _local_hour(ts: str) -> int:
    if "T" in ts:
        try:
            return (int(ts.split("T")[1][:2]) - 4) % 24
        except Exception:
            pass
    return 12
