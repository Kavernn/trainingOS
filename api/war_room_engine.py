"""war_room_engine.py — Correlation patterns + integration hooks for The War Room."""
from __future__ import annotations
import logging
import math
from datetime import date, timedelta
from utils import _today_mtl_date as _today

logger = logging.getLogger("trainingos.war_room")


def _pearson(xs: list[float], ys: list[float]) -> float:
    """Pearson r on paired lists. Returns 0 on invalid input."""
    n = len(xs)
    if n < 4 or len(ys) != n:
        return 0.0
    mx, my = sum(xs) / n, sum(ys) / n
    num = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    dx  = math.sqrt(sum((x - mx) ** 2 for x in xs))
    dy  = math.sqrt(sum((y - my) ** 2 for y in ys))
    if dx == 0 or dy == 0:
        return 0.0
    return round(num / (dx * dy), 3)


# ── Pattern correlation ───────────────────────────────────────────────────────

def compute_patterns() -> dict:
    """
    Cross triggers with workout, PSS, and nutrition to find personal patterns.
    Returns factual observations (no moralizing).
    """
    import db

    today     = _today()
    cutoff    = (today - timedelta(days=90)).isoformat()
    triggers  = db.get_war_room_triggers(limit=200) or []
    recent    = [t for t in triggers if t.get("date", "") >= cutoff]

    if len(recent) < 3:
        return {"insights": [], "total_triggers": len(recent), "enough_data": False}

    insights = []

    # 1. Context breakdown
    contexts = [t.get("context", "custom") for t in recent]
    ctx_counts: dict[str, int] = {}
    for c in contexts:
        ctx_counts[c] = ctx_counts.get(c, 0) + 1
    total = len(contexts)
    top_ctx = sorted(ctx_counts.items(), key=lambda x: -x[1])
    if top_ctx:
        label, cnt = top_ctx[0]
        pct = round(cnt / total * 100)
        ctx_labels = {
            "stress": "Stress", "social": "Social", "boredom": "Ennui",
            "pain": "Douleur", "celebration": "Célébration",
            "exhaustion": "Fatigue", "custom": "Autre",
        }
        insights.append({
            "type": "context_dominant",
            "title": "Contexte dominant",
            "body": f"{ctx_labels.get(label, label)} : {pct}% des tentations",
            "detail": ", ".join(f"{ctx_labels.get(k,k)} {round(v/total*100)}%" for k, v in top_ctx[1:3]),
        })

    # 2. Workout correlation
    sessions  = db.get_workout_sessions(limit=90) or []
    sess_dates = {s.get("date") for s in sessions if s.get("completed")}
    trigger_dates = {t.get("date") for t in recent}
    trigger_no_workout = sum(1 for d in trigger_dates if d not in sess_dates)
    if len(trigger_dates) > 0:
        pct_no_workout = round(trigger_no_workout / len(trigger_dates) * 100)
        if pct_no_workout >= 55:
            insights.append({
                "type": "workout_correlation",
                "title": "Corrélation entraînement",
                "body": f"{trigger_no_workout} des {len(trigger_dates)} tentations : jour sans séance.",
                "detail": f"{pct_no_workout}% des tentations arrivent sans workout.",
            })

    # 3. PSS correlation
    pss_records = db.get_pss_records(limit=90) or []
    pss_by_date: dict[str, float] = {
        r.get("date", ""): float(r.get("pss_score") or r.get("score") or 0)
        for r in pss_records
    }
    trigger_pss = [pss_by_date[t["date"]] for t in recent if t.get("date") in pss_by_date]
    all_pss = list(pss_by_date.values())
    if trigger_pss and len(trigger_pss) >= 3:
        avg_trigger_pss = round(sum(trigger_pss) / len(trigger_pss), 1)
        avg_all_pss     = round(sum(all_pss) / len(all_pss), 1) if all_pss else 0
        if avg_trigger_pss > avg_all_pss + 4:
            # Find personal risk threshold (75th percentile of trigger PSS)
            sorted_pss = sorted(trigger_pss)
            threshold  = round(sorted_pss[int(len(sorted_pss) * 0.60)])
            insights.append({
                "type": "pss_correlation",
                "title": "Corrélation stress (PSS)",
                "body": f"PSS moyen lors d'une tentation : {avg_trigger_pss} vs {avg_all_pss} les jours calmes.",
                "detail": f"Seuil de risque personnel estimé : {threshold}+",
            })

    # 4. Time of day pattern
    hour_counts: dict[int, int] = {}
    for t in recent:
        logged = t.get("logged_at") or t.get("created_at") or ""
        if "T" in logged:
            try:
                hour = int(logged.split("T")[1][:2])
                # Approximate Montreal offset (-4 or -5)
                local_hour = (hour - 4) % 24
                bucket = local_hour // 3 * 3  # 3-hour buckets
                hour_counts[bucket] = hour_counts.get(bucket, 0) + 1
            except Exception as e:
                logger.exception("trigger_insights hour parse failed: %s", e)
    if hour_counts:
        peak_hour = max(hour_counts, key=hour_counts.get)
        peak_label = f"{peak_hour}h–{peak_hour+3}h"
        insights.append({
            "type": "time_pattern",
            "title": "Heure à risque",
            "body": f"Heure de pic : entre {peak_label}",
            "detail": f"{hour_counts[peak_hour]} des {total} tentations dans ce créneau.",
        })

    # 5. Intensity distribution
    intensities = [t.get("intensity", 3) for t in recent]
    high_intensity = sum(1 for i in intensities if i >= 4)
    if high_intensity > 0:
        pct_high = round(high_intensity / total * 100)
        insights.append({
            "type": "intensity",
            "title": "Intensité",
            "body": f"Intensité 4–5 : {pct_high}% des tentations",
            "detail": f"{high_intensity} sur {total} étaient des batailles difficiles.",
        })

    return {
        "insights":       insights,
        "total_triggers": total,
        "enough_data":    True,
    }


# ── Resilience axis for Phoenix Score ─────────────────────────────────────────

def resilience_axis(last7_dates: set[str], prior7_dates: set[str]) -> tuple[float, dict]:
    """Optional 4th axis for PhoenixScore. Returns (delta%, details)."""
    import db

    battles = db.get_war_room_battles(limit=30) or []
    battles_by_date = {b["date"]: b["status"] for b in battles}

    def _victories(dates: set[str]) -> int:
        return sum(1 for d in dates if battles_by_date.get(d) == "victory")

    last_v  = _victories(last7_dates)
    prior_v = _victories(prior7_dates)

    details = {"last_victories": last_v, "prior_victories": prior_v}
    if prior_v == 0 and last_v == 0:
        return 0.0, {**details, "has_baseline": False}

    delta = ((last_v - prior_v) / max(prior_v, 1)) * 100
    return delta, {**details, "has_baseline": True}


# ── AI coach context ──────────────────────────────────────────────────────────

def get_coach_context() -> str | None:
    """
    Returns a vague, non-specific note for the AI coach if war room data warrants it.
    Never reveals the nature of the struggle — only the coaching implication.
    """
    import db

    battles = db.get_war_room_battles(limit=7) or []
    if not battles:
        return None

    recent = sorted(battles, key=lambda b: b.get("date", ""), reverse=True)[:7]
    lost_count = sum(1 for b in recent if b.get("status") == "lost")

    if lost_count >= 3:
        return (
            "Contexte additionnel : l'utilisateur traverse une période de résistance "
            "comportementale active. Adapter les recommandations : prioriser la régularité "
            "sur l'intensité, éviter les suggestions qui augmentent la charge cognitive, "
            "valoriser la présence aux séances plus que la performance."
        )
    if lost_count >= 1:
        return (
            "Contexte additionnel : période légèrement difficile sur le plan comportemental. "
            "Maintenir le cap, ne pas sur-corriger."
        )
    return None


# ── Battle counter summary ────────────────────────────────────────────────────

def compute_summary() -> dict:
    """Returns streak + ratio data for the main War Room dashboard."""
    import db

    battles  = db.get_war_room_battles(limit=365) or []
    config   = db.get_war_room_config() or {}
    today    = _today()

    if not battles:
        return {
            "victory_streak": 0, "best_streak": 0,
            "total_victories": 0, "total_battles": 0,
            "today_status": None,
            "war_start_date": config.get("war_start_date"),
            "war_days": 0,
        }

    battles_by_date = {b["date"]: b["status"] for b in battles}

    # Today's status
    today_iso    = today.isoformat()
    today_status = battles_by_date.get(today_iso)

    # Current victory streak (backward from today)
    current_streak = 0
    for i in range(365):
        d = (today - timedelta(days=i)).isoformat()
        s = battles_by_date.get(d)
        if s == "victory":
            current_streak += 1
        elif s == "lost":
            break
        # 'active' or missing = don't break, but don't count

    # Best streak
    sorted_dates = sorted(battles_by_date.keys())
    best, run = 0, 0
    for d in sorted_dates:
        if battles_by_date[d] == "victory":
            run += 1; best = max(best, run)
        elif battles_by_date[d] == "lost":
            run = 0

    total_victories = sum(1 for s in battles_by_date.values() if s == "victory")
    total_logged    = len(battles_by_date)

    # 30-day and 90-day win rates — resilience metric, unaffected by a single lapse
    def _win_rate(days: int) -> int | None:
        window = {(today - timedelta(days=i)).isoformat() for i in range(days)}
        logged    = sum(1 for d in window if battles_by_date.get(d) in ("victory", "lost"))
        victories = sum(1 for d in window if battles_by_date.get(d) == "victory")
        return round(victories / logged * 100) if logged > 0 else None

    win_rate_30d = _win_rate(30)
    win_rate_90d = _win_rate(90)

    war_start = config.get("war_start_date")
    war_days  = 0
    if war_start:
        try:
            start = date.fromisoformat(str(war_start))
            war_days = (today - start).days + 1
        except Exception as e:
            logger.exception("battle_stats war_start parse failed: %s", e)

    return {
        "victory_streak":  current_streak,
        "best_streak":     best,
        "total_victories": total_victories,
        "total_battles":   total_logged,
        "today_status":    today_status,
        "war_start_date":  war_start,
        "war_days":        war_days,
        "win_rate_30d":    win_rate_30d,
        "win_rate_90d":    win_rate_90d,
    }
