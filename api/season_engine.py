"""season_engine.py — Seasons: narrative chapters of the transformation journey."""
from __future__ import annotations
import logging
from datetime import date, timedelta, datetime, timezone
from typing import Optional

import db
from utils import _today_mtl_date as _today

logger = logging.getLogger("trainingos.seasons")

ARC_TITLES = {
    "rebirth":     "REBIRTH",
    "comeback":    "THE COMEBACK",
    "war":         "THE WAR",
    "breakthrough": "BREAKTHROUGH",
    "ascent":      "THE ASCENT",
    "foundation":  "FOUNDATION",
    "plateau":     "THE PLATEAU",
    "descent":     "THE DESCENT",
}


def _fmt(v, precision: int = 0) -> str:
    if v is None:
        return "—"
    return f"{round(v, precision)}" if precision > 0 else f"{int(round(v))}"


# ── Snapshot computation ───────────────────────────────────────────────────────

def compute_snapshot(as_of_date: str | None = None, season_start: str | None = None) -> dict:
    """Capture all key metrics at a point in time for the season snapshot."""
    today = str(_today()) if as_of_date is None else as_of_date
    snap: dict = {}

    # Phoenix score — computed on the fly, reflects current week
    try:
        import phoenix_engine as _ph
        ph = _ph.compute()
        snap["phoenix_avg"] = ph.get("score")
        axes = ph.get("axes") or {}
        snap["phoenix_workout_avg"]    = (axes.get("workout") or {}).get("delta")
        snap["phoenix_stress_avg"]     = (axes.get("stress") or {}).get("delta")
        snap["phoenix_nutrition_avg"]  = (axes.get("nutrition") or {}).get("delta")
        snap["phoenix_resilience_avg"] = (axes.get("resilience") or {}).get("delta")
        snap["phoenix_spirit_avg"]     = (axes.get("spirit") or {}).get("delta")
    except Exception as e:
        logger.warning("Phoenix snapshot failed: %s", e)

    # Body weight — most recent entry
    weights = db.get_body_weight_logs(limit=5)
    if weights:
        snap["weight_lbs"] = weights[0].get("weight")

    # PSS — most recent score
    pss = db.get_pss_records(limit=1)
    if pss:
        snap["pss_score"] = pss[0].get("score")

    # War Room streak — compute from recent battles
    snap["war_room_streak"] = _current_war_room_streak()

    # Top PRs (top 5 exercises by max weight, all time up to today)
    snap["top_prs"] = _compute_top_prs()

    # Ritual completion last 30 days
    snap["ritual_completion_rate"] = _ritual_rate_last_n_days(30)

    # Sleep avg last 30 days
    snap["avg_sleep_hrs"] = _sleep_avg_last_n_days(30)

    # Spirit totals since season start
    if season_start:
        snap["breathwork_sessions_total"] = _spirit_breathwork_count(season_start, today)
        snap["meditation_minutes_total"]  = _spirit_meditation_minutes(season_start, today)
        snap["journal_entries_total"]     = _spirit_journal_count(season_start, today)

    return snap


def _current_war_room_streak() -> int:
    battles = db.get_war_room_battles(limit=180)
    # battles ordered by date DESC from db
    streak = 0
    for b in sorted(battles, key=lambda x: x.get("date", ""), reverse=True):
        if b.get("status") == "victory":
            streak += 1
        else:
            break
    return streak


def _compute_top_prs() -> list[dict]:
    """Top 5 exercises by PR weight — read from exercise_prs table (O(1), no history scan)."""
    prs = db.get_exercise_prs()
    prs.sort(key=lambda x: x["pr_weight_lbs"], reverse=True)
    return [
        {"exercise": p["exercise_name"], "weight_lbs": p["pr_weight_lbs"], "reps": p["pr_reps"]}
        for p in prs[:5]
    ]


def _ritual_rate_last_n_days(days: int) -> float:
    history = db.get_ritual_history(limit=days + 5)
    cutoff = str(_today() - timedelta(days=days))
    recent = [r for r in history if r.get("date", "") >= cutoff]
    if not recent:
        return 0.0
    completed = sum(1 for r in recent if r.get("outcome") in ("burned", "survived"))
    return round(completed / days, 3)


def _sleep_avg_last_n_days(days: int) -> Optional[float]:
    records = db.get_sleep_records(limit=days + 5)
    cutoff = str(_today() - timedelta(days=days))
    hrs = [r.get("sleep_hours") for r in records
           if r.get("date", "") >= cutoff and r.get("sleep_hours")]
    return round(sum(hrs) / len(hrs), 2) if hrs else None


def _spirit_breathwork_count(start: str, end: str) -> int:
    sessions = db.get_breathwork_sessions_spirit(limit=500)
    return sum(1 for s in sessions
               if start <= (s.get("started_at") or "")[:10] <= end)


def _spirit_meditation_minutes(start: str, end: str) -> int:
    sessions = db.get_meditation_sessions(limit=500)
    total_sec = sum(s.get("actual_sec") or 0 for s in sessions
                    if start <= (s.get("started_at") or "")[:10] <= end)
    return total_sec // 60


def _spirit_journal_count(start: str, end: str) -> int:
    entries = db.get_spirit_journal_entries(limit=500)
    return sum(1 for e in entries if start <= e.get("date", "") <= end)


# ── Season stats (arc detection inputs) ───────────────────────────────────────

def compute_season_stats(start_date: str, end_date: str, start_prs: list) -> dict:
    """War Room stats + PRs broken + ritual totals for the season period."""
    # War Room
    all_battles = db.get_war_room_battles(limit=500)
    period = [b for b in all_battles
              if start_date <= b.get("date", "") <= end_date]
    period.sort(key=lambda x: x.get("date", ""))

    victories = sum(1 for b in period if b.get("status") == "victory")
    battles   = len(period)
    best_streak, cur_streak, resets = 0, 0, 0
    for b in period:
        if b.get("status") == "victory":
            cur_streak += 1
            best_streak = max(best_streak, cur_streak)
        else:
            if cur_streak > 0:
                resets += 1
            cur_streak = 0

    # PRs broken — compare start PRs vs best achieved during period
    try:
        _days = (_today() - date.fromisoformat(start_date)).days + 1
    except (ValueError, TypeError, AttributeError):
        _days = 0
    history = db.get_all_exercise_history(cutoff_days=max(_days, 365)) if _days > 0 else db.get_all_exercise_history(cutoff_days=365)
    history = history or {}
    start_pr_map = {p["exercise"]: p.get("weight_lbs", 0) for p in (start_prs or [])}
    prs_broken = []
    for name, data in history.items():
        best_in_period = 0.0
        for entry in (data if isinstance(data, list) else (data.get("history") or [])):
            if not (start_date <= entry.get("date", "") <= end_date):
                continue
            for s in (entry.get("sets") or []):
                w = s.get("weight") or 0
                if w > best_in_period:
                    best_in_period = w
        old = start_pr_map.get(name, 0)
        if best_in_period > old and old > 0:
            prs_broken.append({
                "exercise": name,
                "old_weight_lbs": old,
                "new_weight_lbs": best_in_period,
            })

    # Ritual
    ritual_history = db.get_ritual_history(limit=500)
    period_ritual = [r for r in ritual_history
                     if start_date <= r.get("date", "") <= end_date]
    total_days = max((date.fromisoformat(end_date) - date.fromisoformat(start_date)).days + 1, 1)
    done = sum(1 for r in period_ritual if r.get("outcome") in ("burned", "survived"))
    ritual_rate = round(done / total_days, 3)

    # Spirit
    breathwork = _spirit_breathwork_count(start_date, end_date)
    meditation = _spirit_meditation_minutes(start_date, end_date)
    journal    = _spirit_journal_count(start_date, end_date)

    return {
        "war_room_victories":   victories,
        "war_room_battles":     battles,
        "war_room_best_streak": best_streak,
        "war_room_resets":      resets,
        "prs_broken_count":     len(prs_broken),
        "prs_broken":           prs_broken,
        "ritual_completion_rate": ritual_rate,
        "breathwork_sessions":  breathwork,
        "meditation_minutes":   meditation,
        "journal_entries":      journal,
    }


# ── Arc detection ──────────────────────────────────────────────────────────────

def detect_arc(
    start_snap: dict,
    end_snap: dict,
    season_stats: dict,
    season_number: int,
    prev_had_reset: bool,
) -> str:
    def _n(d: dict, k: str) -> float:
        v = d.get(k)
        return float(v) if v is not None else 0.0

    delta_phoenix = _n(end_snap, "phoenix_avg") - _n(start_snap, "phoenix_avg")
    delta_pss     = _n(end_snap, "pss_score")   - _n(start_snap, "pss_score")
    delta_weight  = _n(end_snap, "weight_lbs")  - _n(start_snap, "weight_lbs")

    best_streak   = season_stats.get("war_room_best_streak", 0)
    resets        = season_stats.get("war_room_resets", 0)
    victories     = season_stats.get("war_room_victories", 0)
    battles       = season_stats.get("war_room_battles", 0)
    prs_count     = season_stats.get("prs_broken_count", 0)
    ritual_rate   = season_stats.get("ritual_completion_rate", 0.0)
    victory_rate  = victories / battles if battles > 0 else 0.0

    if prev_had_reset and best_streak >= 30 and delta_phoenix >= 10:
        return "rebirth"
    if (_n(start_snap, "pss_score") >= 24 or _n(start_snap, "war_room_streak") == 0) \
            and delta_pss <= -6 and delta_phoenix >= 8:
        return "comeback"
    if resets == 0 and best_streak >= 45 and victory_rate >= 0.80 and battles >= 60:
        return "war"
    if prs_count >= 5 and delta_phoenix >= 12:
        return "breakthrough"
    if delta_phoenix >= 8 and delta_pss <= -5 and ritual_rate >= 0.70:
        return "ascent"
    if delta_phoenix <= -8 or delta_pss >= 8 or resets >= 3:
        return "descent"
    if abs(delta_weight) < 2 and abs(delta_phoenix) < 5 and prs_count == 0:
        return "plateau"
    return "foundation"


# ── Narrative ─────────────────────────────────────────────────────────────────

def build_narrative(arc: str, start_snap: dict, end_snap: dict,
                    season_stats: dict, season_number: int) -> str:
    sw  = _fmt(start_snap.get("weight_lbs"))
    ew  = _fmt(end_snap.get("weight_lbs"))
    sp  = _fmt(start_snap.get("pss_score"))
    ep  = _fmt(end_snap.get("pss_score"))
    sph = _fmt(start_snap.get("phoenix_avg"), 1)
    eph = _fmt(end_snap.get("phoenix_avg"), 1)
    dph = (end_snap.get("phoenix_avg") or 0) - (start_snap.get("phoenix_avg") or 0)
    dph_s = f"{'−' if dph < 0 else '+'}{abs(round(dph, 1))}pts"
    best  = _fmt(season_stats.get("war_room_best_streak"))
    victories = _fmt(season_stats.get("war_room_victories"))
    battles   = _fmt(season_stats.get("war_room_battles"))
    resets    = season_stats.get("war_room_resets", 0)
    prs       = season_stats.get("prs_broken_count", 0)
    rate      = int(round((season_stats.get("ritual_completion_rate") or 0) * 100))
    prs_s     = f"{prs} record{'s' if prs > 1 else ''} tombé{'s' if prs > 1 else ''}"

    if arc == "comeback":
        r  = f"Tu as commencé cette saison à {sw} lbs, PSS {sp}, streak War Room à zéro. "
        r += f"Tu finis à {ew} lbs, PSS {ep}, {best} jours consécutifs."
        if prs > 0:
            r += f" {prs_s}."
        r += " La personne du Jour 1 n'existe plus."
        return r
    if arc == "rebirth":
        r  = f"Tu connaissais déjà la chute. Cette fois tu ne t'es pas laissé emporter. "
        r += f"{best} jours consécutifs — ton record cette saison. "
        r += f"Phoenix {sph} → {eph} ({dph_s}). "
        r += "Ce n'est pas un comeback. C'est une transformation."
        return r
    if arc == "war":
        r  = f"{battles} batailles. {victories} victoires. Aucun abandon. "
        r += f"Le streak maximum : {best} jours. "
        r += "Tu as choisi, chaque matin, de tenir. C'est tout ce qu'il fallait faire."
        return r
    if arc == "breakthrough":
        r  = f"Les plafonds ont bougé. {prs_s} ce trimestre. "
        r += f"Phoenix {sph} → {eph} ({dph_s}). "
        r += "Quand tu as commencé cette saison, c'était ta limite. Ce n'est plus ta limite."
        return r
    if arc == "ascent":
        r  = "Chaque mois meilleur que le précédent. "
        r += f"Phoenix {sph} → {eph} ({dph_s}). PSS {sp} → {ep}. "
        r += "C'est la forme la plus rare de discipline — la constance sans pic. Continue."
        return r
    if arc == "foundation":
        r  = f"Season {season_number}. Pas spectaculaire — intentionnel. "
        r += f"{rate}% de rituels complétés. "
        r += "Les habitudes s'installent avant les résultats. La base est là."
        return r
    if arc == "plateau":
        r  = "Les chiffres n'ont pas beaucoup bougé. "
        r += f"Phoenix {sph} → {eph}. PSS {sp} → {ep}. "
        r += f"C'est souvent là que le travail invisible se fait. "
        r += f"Season {season_number + 1} dira si tu avais raison de tenir."
        return r
    if arc == "descent":
        r  = f"Une saison dure. Phoenix {sph} → {eph} ({dph_s}). PSS {sp} → {ep}. "
        if resets > 0:
            r += f"War Room : {resets} reset{'s' if resets > 1 else ''}. "
        r += f"Ces données existent. Elles font partie du parcours. "
        r += f"Season {season_number + 1} commence demain."
        return r
    return f"Season {season_number} terminée. Phoenix {sph} → {eph}."


def generate_headline_delta(start_snap: dict, end_snap: dict, season_stats: dict) -> str:
    candidates: list[tuple[float, str]] = []

    dw = (end_snap.get("weight_lbs") or 0) - (start_snap.get("weight_lbs") or 0)
    if abs(dw) >= 3:
        sign = "−" if dw < 0 else "+"
        candidates.append((abs(dw), f"{sign}{abs(round(dw))} lbs."))

    streak = season_stats.get("war_room_best_streak", 0)
    if streak >= 21:
        candidates.append((streak / 2, f"{streak} jours consécutifs War Room."))

    prs = season_stats.get("prs_broken_count", 0)
    if prs >= 3:
        s = f"{prs} record{'s' if prs > 1 else ''} tombé{'s' if prs > 1 else ''}."
        candidates.append((prs * 3.0, s))

    dph = (end_snap.get("phoenix_avg") or 0) - (start_snap.get("phoenix_avg") or 0)
    if abs(dph) >= 8:
        sign = "+" if dph > 0 else "−"
        candidates.append((abs(dph), f"Phoenix {sign}{abs(round(dph, 1))}pts."))

    dp = (end_snap.get("pss_score") or 0) - (start_snap.get("pss_score") or 0)
    if abs(dp) >= 6:
        sign = "−" if dp < 0 else "+"
        candidates.append((abs(dp), f"PSS {sign}{abs(int(dp))}."))

    if not candidates:
        return "Season terminée."
    return max(candidates, key=lambda x: x[0])[1]


# ── Close flow ────────────────────────────────────────────────────────────────

def close_season(season_id: str) -> Optional[dict]:
    """Compute end snapshot, detect arc, generate report, persist close."""
    season = db.get_season_by_id(season_id)
    if not season:
        return None

    today      = str(_today())
    start_date = season["started_at"]
    number     = season["number"]

    snapshots  = db.get_season_snapshots(season_id)
    start_snap = next((s for s in snapshots if s["type"] == "start"), {})
    start_prs  = start_snap.get("top_prs") or []

    end_snap = compute_snapshot(as_of_date=today, season_start=start_date)
    db.save_season_snapshot(season_id, "end", end_snap)

    stats         = compute_season_stats(start_date, today, start_prs)
    stats["ritual_completion_rate"] = end_snap.get("ritual_completion_rate", 0.0)

    prev_reset = db.get_prev_season_had_reset(season_id)
    arc        = detect_arc(start_snap, end_snap, stats, number, prev_reset)
    title      = f"SEASON {number} — {ARC_TITLES.get(arc, 'THE JOURNEY')}"
    narrative  = build_narrative(arc, start_snap, end_snap, stats, number)
    headline   = generate_headline_delta(start_snap, end_snap, stats)

    closed = db.close_season(season_id, ended_at=today, generated_title=title, dominant_arc=arc)

    return {
        "season":         closed or season,
        "start_snapshot": start_snap,
        "end_snapshot":   end_snap,
        "stats":          stats,
        "narrative":      narrative,
        "headline_delta": headline,
        "arc":            arc,
        "title":          title,
    }
