from __future__ import annotations
import logging
from typing import Dict, List, Optional
import db_core
from db_body import get_recovery_logs, get_body_weight_logs
from db_sessions import get_workout_sessions
from utils import _today_mtl
from db_wellness import (
    get_mood_logs, get_pss_records, get_sleep_records,
    get_self_care_habits, get_self_care_log, get_sessions_for_correlations,
    get_nutrition_entries_recent,
)


def get_weekly_tonnage(weeks: int = 8) -> list[dict]:
    """Return weekly volume from v_weekly_volume, last N weeks, oldest first."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> list[dict]:
        from datetime import date as _date, timedelta
        cutoff = (_date.fromisoformat(_today_mtl()) - timedelta(weeks=weeks)).isoformat()
        resp = (
            db_core._client.table("v_weekly_volume")
            .select("week_start, total_volume, session_count")
            .gte("week_start", cutoff)
            .order("week_start")
            .execute()
        )
        return [
            {
                "week_start": str(r["week_start"])[:10],
                "total_volume": float(r.get("total_volume") or 0),
                "session_count": int(r.get("session_count") or 0),
            }
            for r in (resp.data or [])
        ]

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_weekly_tonnage retry: %s", e2)
                return []
        db_core.logger.error("get_weekly_tonnage error: %s", e)
        return []


def get_pattern_volume(days: int = 28) -> dict:
    """Return volume (lbs×reps) per movement pattern for the last N days."""
    try:
        from weights import load_weights
        from inventory import load_inventory
        from datetime import date as _date, timedelta
        cutoff = (_date.fromisoformat(_today_mtl()) - timedelta(days=days)).isoformat()
        weights = load_weights()
        inventory = load_inventory() or {}
        pattern_vol: dict[str, float] = {}
        for name, data in weights.items():
            pattern = (inventory.get(name) or {}).get("pattern") or ""
            if not pattern:
                continue
            for entry in (data.get("history") or []):
                if str(entry.get("date", "")) < cutoff:
                    continue
                vol = float(entry.get("exercise_volume") or 0)
                pattern_vol[pattern] = pattern_vol.get(pattern, 0.0) + vol
        return {k: round(v) for k, v in pattern_vol.items()}
    except Exception as e:
        db_core.logger.error("get_pattern_volume error: %s", e)
        return {}


def get_programme_compliance(weeks: int = 8) -> list[dict]:
    """Return planned vs completed sessions per ISO week for the last N weeks."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> list[dict]:
        from datetime import date as _date, timedelta, datetime as _dt
        # Planned sessions per week (count non-null session_id in weekly_schedule)
        sched_resp = db_core._client.table("weekly_schedule").select("session_id").execute()
        planned_per_week = sum(1 for r in (sched_resp.data or []) if r.get("session_id"))
        if planned_per_week == 0:
            planned_per_week = 4

        # Completed sessions in last N weeks
        cutoff = (_date.fromisoformat(_today_mtl()) - timedelta(weeks=weeks)).isoformat()
        sess_resp = (
            db_core._client.table("workout_sessions")
            .select("date, completed")
            .gte("date", cutoff)
            .eq("completed", True)
            .execute()
        )
        week_counts: dict[str, int] = {}
        for s in (sess_resp.data or []):
            d = str(s.get("date", ""))[:10]
            try:
                dt = _dt.strptime(d, "%Y-%m-%d")
                monday = (dt - timedelta(days=dt.weekday())).strftime("%Y-%m-%d")
            except Exception:
                continue
            week_counts[monday] = week_counts.get(monday, 0) + 1

        today = _date.fromisoformat(_today_mtl())
        result = []
        for w in range(weeks):
            monday = today - timedelta(days=today.weekday()) - timedelta(weeks=weeks - 1 - w)
            ws = monday.strftime("%Y-%m-%d")
            result.append({"week_start": ws, "planned": planned_per_week, "done": week_counts.get(ws, 0)})
        return result

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_programme_compliance retry: %s", e2)
                return []
        db_core.logger.error("get_programme_compliance error: %s", e)
        return []


def get_one_rm_trend(days: int = 84) -> dict:
    """Return estimated 1RM trend per compound exercise (push/pull/hinge/squat patterns)."""
    try:
        from weights import load_weights
        from inventory import load_inventory
        from datetime import date as _date, timedelta
        cutoff = (_date.fromisoformat(_today_mtl()) - timedelta(days=days)).isoformat()
        weights = load_weights()
        inventory = load_inventory() or {}
        compound_patterns = {"squat", "hinge", "push", "pull"}
        result: dict[str, list[dict]] = {}
        for name, data in weights.items():
            pattern = (inventory.get(name) or {}).get("pattern") or ""
            if pattern not in compound_patterns:
                continue
            points = []
            for entry in (data.get("history") or []):
                d = str(entry.get("date", ""))[:10]
                if not d or d < cutoff:
                    continue
                orm = entry.get("1rm") or entry.get("oneRM")
                if orm:
                    points.append({"date": d, "one_rm": round(float(orm), 1)})
            if len(points) >= 2:
                points.sort(key=lambda x: x["date"])
                result[name] = points
        # Top 6 by data density
        return dict(sorted(result.items(), key=lambda x: len(x[1]), reverse=True)[:6])
    except Exception as e:
        db_core.logger.error("get_one_rm_trend error: %s", e)
        return {}


def get_hiit_completion(weeks: int = 8) -> list[dict]:
    """Return HIIT sessions with completion rate (rounds_completed/rounds_planned)."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> list[dict]:
        from datetime import date as _date, timedelta
        cutoff = (_date.fromisoformat(_today_mtl()) - timedelta(weeks=weeks)).isoformat()
        resp = (
            db_core._client.table("hiit_logs")
            .select("date, session_type, rounds_planned, rounds_completed, rpe")
            .gte("date", cutoff)
            .order("date")
            .execute()
        )
        result = []
        for r in (resp.data or []):
            planned   = int(r.get("rounds_planned") or 0)
            completed = int(r.get("rounds_completed") or 0)
            result.append({
                "date":             str(r.get("date", ""))[:10],
                "session_type":     r.get("session_type"),
                "rounds_planned":   planned,
                "rounds_completed": completed,
                "rate":             round(completed / planned, 2) if planned > 0 else 0.0,
                "rpe":              r.get("rpe"),
            })
        return result

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_hiit_completion retry: %s", e2)
                return []
        db_core.logger.error("get_hiit_completion error: %s", e)
        return []


def get_nutrition_daily_full(days: int = 60) -> list[dict]:
    """Return daily aggregates of all macros for the last N days."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> list[dict]:
        from datetime import date as _date, timedelta
        cutoff = (_date.fromisoformat(_today_mtl()) - timedelta(days=days)).isoformat()
        resp = (
            db_core._client.table("nutrition_entries")
            .select("date, calories, proteines, glucides, lipides")
            .gte("date", cutoff)
            .order("date", desc=True)
            .execute()
        )
        seen: dict[str, dict] = {}
        for row in (resp.data or []):
            d = str(row.get("date", ""))[:10]
            if d not in seen:
                seen[d] = {"date": d, "calories": 0.0, "proteines": 0.0, "glucides": 0.0, "lipides": 0.0}
            seen[d]["calories"]  += float(row.get("calories") or 0)
            seen[d]["proteines"] += float(row.get("proteines") or 0)
            seen[d]["glucides"]  += float(row.get("glucides") or 0)
            seen[d]["lipides"]   += float(row.get("lipides") or 0)
        return sorted(seen.values(), key=lambda x: x["date"])

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_nutrition_daily_full retry: %s", e2)
                return []
        db_core.logger.error("get_nutrition_daily_full error: %s", e)
        return []


def get_macros_by_day_type(days: int = 60) -> dict:
    """Return average macros on training days vs rest days for the last N days."""
    try:
        nutr_days = get_nutrition_daily_full(days)
        sessions_raw = get_workout_sessions(limit=days + 10)
        workout_dates = {
            str(s.get("date", ""))[:10]
            for s in sessions_raw
            if s.get("completed") or s.get("rpe") is not None
        }
        training: list[dict] = []
        rest: list[dict] = []
        for d in nutr_days:
            if d["calories"] == 0 and d["proteines"] == 0:
                continue
            bucket = training if d["date"] in workout_dates else rest
            bucket.append(d)

        def _avg(b: list[dict]) -> Optional[dict]:
            if not b:
                return None
            n = len(b)
            return {
                "avg_cal":   round(sum(x["calories"]  for x in b) / n),
                "avg_prot":  round(sum(x["proteines"] for x in b) / n, 1),
                "avg_carbs": round(sum(x["glucides"]  for x in b) / n, 1),
                "avg_fat":   round(sum(x["lipides"]   for x in b) / n, 1),
            }

        return {
            "training":   _avg(training),
            "rest":       _avg(rest),
            "n_training": len(training),
            "n_rest":     len(rest),
        }
    except Exception as e:
        db_core.logger.error("get_macros_by_day_type error: %s", e)
        return {}


def get_protein_weight_ratio(days: int = 60) -> list[dict]:
    """Return protein/bodyweight ratio per day for days with both logged.

    weight is always stored in lbs — the iOS app hardcodes the input label as
    "POIDS (LBS)" and converts HealthKit kg values via / 0.453592 before sending.
    ratio unit is therefore g_protein / lbs_bodyweight.
    """
    try:
        from datetime import date as _date, timedelta
        cutoff = (_date.fromisoformat(_today_mtl()) - timedelta(days=days)).isoformat()
        nutr_days = get_nutrition_daily_full(days)
        bw_logs = get_body_weight_logs(limit=200)
        bw_map = {str(e.get("date", ""))[:10]: float(e.get("weight") or 0) for e in bw_logs if e.get("weight")}
        result = []
        for d in nutr_days:
            date = d["date"]
            if date < cutoff:
                continue
            prot = d["proteines"]
            weight = bw_map.get(date)
            if prot > 0 and weight and weight > 0:
                result.append({"date": date, "ratio": round(prot / weight, 3), "prot_g": round(prot, 1), "weight": weight})
        return result
    except Exception as e:
        db_core.logger.error("get_protein_weight_ratio error: %s", e)
        return []


def get_mood_trend(days: int = 60) -> list[dict]:
    """Return mood score + life stress score per day for the last N days."""
    try:
        from datetime import date as _date, timedelta
        cutoff = (_date.fromisoformat(_today_mtl()) - timedelta(days=days)).isoformat()
        mood_logs = get_mood_logs(days=days)
        mood_map: dict[str, int] = {
            str(m.get("date", ""))[:10]: int(m["score"])
            for m in mood_logs if m.get("score") is not None
        }
        stress_map: dict[str, float] = {}
        if db_core._client is not None and db_core.MODE != "OFFLINE":
            try:
                resp = (
                    db_core._client.table("life_stress_scores")
                    .select("date, score")
                    .gte("date", cutoff)
                    .order("date")
                    .execute()
                )
                for r in (resp.data or []):
                    d = str(r.get("date", ""))[:10]
                    if r.get("score") is not None:
                        stress_map[d] = float(r["score"])
            except Exception as e2:
                db_core.logger.warning("get_mood_trend stress query: %s", e2)
        all_dates = sorted(set(mood_map) | set(stress_map))
        return [
            {"date": d, "mood_score": mood_map.get(d), "life_stress_score": stress_map.get(d)}
            for d in all_dates if d >= cutoff
        ]
    except Exception as e:
        db_core.logger.error("get_mood_trend error: %s", e)
        return []


def _get_session_volume_map(days: int = 200) -> dict[str, float]:
    """Return {date: total_volume} from v_session_volume view."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return {}
    try:
        from datetime import date as _date, timedelta
        cutoff = (_date.fromisoformat(_today_mtl()) - timedelta(days=days)).isoformat()
        resp = (
            db_core._client.table("v_session_volume")
            .select("date, total_volume")
            .gte("date", cutoff)
            .execute()
        )
        vol_map: dict[str, float] = {}
        for r in (resp.data or []):
            d = str(r.get("date", ""))[:10]
            vol = float(r.get("total_volume") or 0)
            if d and vol > 0:
                vol_map[d] = vol_map.get(d, 0.0) + vol
        return vol_map
    except Exception as e:
        db_core.logger.error("_get_session_volume_map error: %s", e)
        return {}


def get_soreness_volume_scatter() -> list[dict]:
    """Return scatter pairs: (volume_J-1, soreness_J) for correlation analysis."""
    try:
        from datetime import date as _date, timedelta
        recovery = get_recovery_logs(limit=200)
        vol_map = _get_session_volume_map(200)
        result = []
        for r in recovery:
            soreness = r.get("soreness")
            d = str(r.get("date", ""))[:10]
            if not d or soreness is None:
                continue
            try:
                prev_date = (_date.fromisoformat(d) - timedelta(days=1)).isoformat()
            except Exception:
                continue
            prev_vol = vol_map.get(prev_date)
            if prev_vol and prev_vol > 0:
                result.append({"x": round(prev_vol), "y": float(soreness), "date": d})
        return result
    except Exception as e:
        db_core.logger.error("get_soreness_volume_scatter error: %s", e)
        return []


def get_sleep_volume_scatter() -> list[dict]:
    """Return scatter pairs: (sleep_quality_J-1, volume_J) for correlation analysis."""
    try:
        from datetime import date as _date, timedelta
        recovery = get_recovery_logs(limit=200)
        vol_map = _get_session_volume_map(200)
        result = []
        for r in recovery:
            sleep_q = r.get("sleep_quality")
            d = str(r.get("date", ""))[:10]
            if not d or sleep_q is None:
                continue
            try:
                next_date = (_date.fromisoformat(d) + timedelta(days=1)).isoformat()
            except Exception:
                continue
            next_vol = vol_map.get(next_date)
            if next_vol and next_vol > 0:
                result.append({"x": float(sleep_q), "y": round(next_vol), "date": next_date})
        return result
    except Exception as e:
        db_core.logger.error("get_sleep_volume_scatter error: %s", e)
        return []


def get_rpe_progression() -> dict:
    """Return average weight progression % per RPE bucket (<7 / 7-8 / 8-9 / 9-10)."""
    try:
        from weights import load_weights
        sessions_raw = get_workout_sessions(limit=365)
        rpe_by_date: dict[str, float] = {
            str(s.get("date", ""))[:10]: float(s["rpe"])
            for s in sessions_raw if s.get("rpe") is not None
        }

        def _bucket(rpe: float) -> str:
            if rpe < 7: return "<7"
            if rpe < 8: return "7-8"
            if rpe < 9: return "8-9"
            return "9-10"

        weights = load_weights()
        buckets: dict[str, list[float]] = {"<7": [], "7-8": [], "8-9": [], "9-10": []}
        for data in weights.values():
            hist = sorted(data.get("history") or [], key=lambda x: str(x.get("date", "")))
            for i in range(len(hist) - 1):
                d = str(hist[i].get("date", ""))[:10]
                rpe = rpe_by_date.get(d)
                if rpe is None:
                    continue
                w0 = float(hist[i].get("weight") or 0)
                w1 = float(hist[i + 1].get("weight") or 0)
                if w0 > 0 and w1 > 0:
                    buckets[_bucket(rpe)].append((w1 - w0) / w0 * 100)

        return {
            b: (round(sum(v) / len(v), 2) if v else None)
            for b, v in buckets.items()
        }
    except Exception as e:
        db_core.logger.error("get_rpe_progression error: %s", e)
        return {}


def get_rir_by_exercise() -> list[dict]:
    """Return average RIR (Reps In Reserve) per exercise from sets_json."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> list[dict]:
        import json as _json
        logs_resp = (
            db_core._client.table("exercise_logs")
            .select("exercise_id, sets_json")
            .not_.is_("sets_json", "null")
            .limit(500)
            .execute()
        )
        ex_resp = db_core._client.table("exercises").select("id, name").execute()
        ex_names = {str(r["id"]): r["name"] for r in (ex_resp.data or [])}
        rir_data: dict[str, list[int]] = {}
        for row in (logs_resp.data or []):
            ex_id = str(row.get("exercise_id", ""))
            sets = row.get("sets_json") or []
            if isinstance(sets, str):
                try:
                    sets = _json.loads(sets)
                except Exception:
                    continue
            for s in (sets or []):
                rir = s.get("rir")
                if rir is not None:
                    rir_data.setdefault(ex_id, []).append(int(rir))
        result = [
            {"exercise": ex_names.get(eid, eid), "avg_rir": round(sum(rs) / len(rs), 1), "n_sets": len(rs)}
            for eid, rs in rir_data.items()
        ]
        result.sort(key=lambda x: x["n_sets"], reverse=True)
        return result[:20]

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_rir_by_exercise retry: %s", e2)
                return []
        db_core.logger.error("get_rir_by_exercise error: %s", e)
        return []


def get_self_care_compliance(days: int = 30) -> dict:
    """Return self-care compliance rate and daily counts for the last N days."""
    try:
        from datetime import date as _date, timedelta
        cutoff = (_date.fromisoformat(_today_mtl()) - timedelta(days=days)).isoformat()
        sc_log = get_self_care_log(days=days)
        habits = get_self_care_habits()
        total_habits = len(habits)
        if total_habits == 0:
            return {"rate_30d": 0.0, "daily": []}
        total_done = 0
        total_possible = 0
        daily = []
        for d_str in sorted(sc_log):
            if d_str < cutoff:
                continue
            done = len(sc_log[d_str])
            total_done += done
            total_possible += total_habits
            daily.append({"date": d_str, "count": done})
        rate = round(total_done / total_possible, 3) if total_possible > 0 else 0.0
        return {"rate_30d": rate, "daily": daily}
    except Exception as e:
        db_core.logger.error("get_self_care_compliance error: %s", e)
        return {"rate_30d": 0.0, "daily": []}


def get_self_care_streaks_computed() -> list[dict]:
    """Compute current and longest streak for each self-care habit."""
    try:
        from datetime import date as _date, timedelta
        habits = get_self_care_habits()
        sc_log = get_self_care_log(days=365)
        habit_dates: dict[str, set[str]] = {}
        for date_str, habit_ids in sc_log.items():
            for hid in habit_ids:
                habit_dates.setdefault(hid, set()).add(date_str)
        today = _date.fromisoformat(_today_mtl())
        result = []
        for h in habits:
            hid = h.get("id", "")
            dates = habit_dates.get(hid, set())
            # Current streak
            current, d = 0, today
            while d.isoformat() in dates:
                current += 1
                d -= timedelta(days=1)
            # Longest streak
            sorted_dates = sorted(dates)
            longest, run, prev = 0, 0, None
            for ds in sorted_dates:
                try:
                    cur_date = _date.fromisoformat(ds)
                except Exception:
                    continue
                run = (run + 1) if (prev is not None and (cur_date - prev).days == 1) else 1
                longest = max(longest, run)
                prev = cur_date
            result.append({
                "habit_id":       hid,
                "habit_name":     h.get("name", ""),
                "habit_icon":     h.get("icon", ""),
                "current_streak": current,
                "longest_streak": longest,
            })
        result.sort(key=lambda x: x["current_streak"], reverse=True)
        return result
    except Exception as e:
        db_core.logger.error("get_self_care_streaks_computed error: %s", e)
        return []


# ---------------------------------------------------------------------------
# Pain journal
# ---------------------------------------------------------------------------

def get_pain_journal(limit: int = 100) -> list[dict]:
    """Return exercise_logs with pain_zone != null, newest first."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> list[dict]:
        resp = (
            db_core._client.table("exercise_logs")
            .select("pain_zone, weight, reps, workout_sessions(date, session_name), exercises(name)")
            .not_.is_("pain_zone", "null")
            .order("workout_sessions(date)", desc=True)
            .limit(limit)
            .execute()
        )
        rows = resp.data or []
        result = []
        for r in rows:
            sess = r.get("workout_sessions") or {}
            ex   = r.get("exercises") or {}
            result.append({
                "date":         sess.get("date"),
                "session_name": sess.get("session_name"),
                "exercise":     ex.get("name"),
                "pain_zone":    r.get("pain_zone"),
                "weight":       r.get("weight"),
                "reps":         r.get("reps"),
            })
        return result

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_pain_journal retry error: %s", e2)
                return []
        db_core.logger.error("get_pain_journal error: %s", e)
        return []


def get_sessions_with_energy_pre(days: int = 90) -> list[dict]:
    """Return [{date, energy_pre, rpe, session_volume}] for correlation analysis."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []
    from datetime import date as _date, timedelta
    cutoff = (_date.fromisoformat(_today_mtl()) - timedelta(days=days)).isoformat()

    def _do() -> list[dict]:
        resp = (
            db_core._client.table("workout_sessions")
            .select("date, energy_pre, rpe")
            .gte("date", cutoff)
            .not_.is_("energy_pre", "null")
            .execute()
        )
        rows = resp.data or []
        # Get volume from v_session_volume
        vol_resp = (
            db_core._client.table("v_session_volume")
            .select("date, total_volume")
            .gte("date", cutoff)
            .execute()
        )
        vol_by_date = {str(r["date"])[:10]: r.get("total_volume") for r in (vol_resp.data or [])}
        result = []
        for r in rows:
            d = str(r.get("date", ""))[:10]
            result.append({
                "date":           d,
                "energy_pre":     r.get("energy_pre"),
                "rpe":            r.get("rpe"),
                "session_volume": vol_by_date.get(d),
            })
        return result

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_sessions_with_energy_pre retry error: %s", e2)
                return []
        db_core.logger.error("get_sessions_with_energy_pre error: %s", e)
        return []


def get_exercise_logs_with_category(days: int = 90) -> list[dict]:
    """Return exercise_logs with exercise category for push/pull ratio computation."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []
    from datetime import date as _date, timedelta
    cutoff = (_date.fromisoformat(_today_mtl()) - timedelta(days=days)).isoformat()

    def _do() -> list[dict]:
        resp = (
            db_core._client.table("exercise_logs")
            .select("weight, reps, sets_json, workout_sessions(date), exercises(name, category, load_profile)")
            .gte("workout_sessions(date)", cutoff)
            .execute()
        )
        rows = resp.data or []
        result = []
        for r in rows:
            sess = r.get("workout_sessions") or {}
            ex   = r.get("exercises") or {}
            d = str(sess.get("date", ""))[:10]
            if not d:
                continue
            result.append({
                "date":         d,
                "exercise":     ex.get("name"),
                "category":     ex.get("category"),
                "load_profile": ex.get("load_profile"),
                "weight":       r.get("weight", 0),
                "reps":         r.get("reps", ""),
                "sets_json":    r.get("sets_json"),
            })
        return result

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_exercise_logs_with_category retry error: %s", e2)
                return []
        db_core.logger.error("get_exercise_logs_with_category error: %s", e)
        return []
