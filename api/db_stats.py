from __future__ import annotations
import logging
from typing import Dict, List, Optional
import db_core
from db_body import get_recovery_logs, get_body_weight_logs, get_hiit_logs
from db_sessions import get_workout_sessions, get_exercise_logs_since
from utils import _today_mtl
from db_wellness import (
    get_mood_logs, get_pss_records,
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


# Normalise les labels capitalisés legacy vers les valeurs snake_case du schéma.
# La base mélange "Horizontal Push" (labels iOS anciens) et "push_horizontal" (schéma 063).
_PATTERN_NORMALIZE: dict[str, str] = {
    "horizontal push":  "push_horizontal",
    "vertical push":    "push_vertical",
    "horizontal pull":  "pull_horizontal",
    "vertical pull":    "pull_vertical",
    "hip hinge":        "hinge",
    "squat":            "squat",
    "lunge":            "unilateral_leg",
    "gainage":          "core",
    "elbow extension":  "isolation_arm",
    "elbow flexion":    "isolation_arm",
    "isolation":        "isolation_arm",
}

def _norm_pattern(p: str) -> str:
    return _PATTERN_NORMALIZE.get(p.strip().lower(), p.strip())


def _entry_volume(entry: dict) -> float:
    """Compute set volume from exercise_volume or weight × total_reps fallback."""
    vol = entry.get("exercise_volume")
    if vol:
        return float(vol)
    w = float(entry.get("weight") or 0)
    if not w:
        return 0.0
    reps_str = str(entry.get("reps") or "")
    try:
        if "," in reps_str:
            total_r = sum(float(x) for x in reps_str.split(",") if x.strip())
        elif reps_str:
            total_r = float(reps_str)
        else:
            total_r = 0.0
    except ValueError:
        total_r = 0.0
    return w * total_r


def get_pattern_volume(days: int = 28, weights: dict | None = None) -> dict:
    """Return volume (lbs×reps) per movement pattern for the last N days."""
    try:
        from weights import load_weights
        from inventory import load_inventory
        from datetime import date as _date, timedelta
        cutoff = (_date.fromisoformat(_today_mtl()) - timedelta(days=days)).isoformat()
        if weights is None:
            weights = load_weights()
        inventory = load_inventory() or {}
        pattern_vol: dict[str, float] = {}
        for name, data in weights.items():
            raw = (inventory.get(name) or {}).get("movement_pattern") or ""
            pattern = _norm_pattern(raw)
            if not pattern:
                continue
            for entry in (data.get("history") or []):
                if str(entry.get("date", "")) < cutoff:
                    continue
                vol = _entry_volume(entry)
                pattern_vol[pattern] = pattern_vol.get(pattern, 0.0) + vol
        _merge = {
            "push_horizontal": "push",  "push_vertical":   "push",
            "pull_horizontal": "pull",  "pull_vertical":   "pull",
            "unilateral_leg":  "squat", "press_machine":   "squat",
        }
        merged: dict[str, float] = {}
        for pat, vol in pattern_vol.items():
            key = _merge.get(pat, pat)
            merged[key] = merged.get(key, 0.0) + vol
        return {k: round(v) for k, v in merged.items()}
    except Exception as e:
        db_core.logger.error("get_pattern_volume error: %s", e)
        return {}


def get_programme_compliance(weeks: int = 8) -> list[dict]:
    """Return planned vs completed sessions per ISO week for the last N weeks."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> list[dict]:
        from datetime import date as _date, timedelta, datetime as _dt
        # Planned sessions per week — morning slot, non-null session_id (training days only)
        sched_resp = (
            db_core._client.table("weekly_schedule")
            .select("session_id")
            .eq("slot", "morning")
            .not_.is_("session_id", "null")
            .execute()
        )
        planned_per_week = len(sched_resp.data or [])
        if planned_per_week == 0:
            return []  # pas de programme actif — card masquée côté Swift

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


def get_one_rm_trend(days: int = 84, weights: dict | None = None) -> dict:
    """Return estimated 1RM trend per compound exercise (push/pull/hinge/squat patterns)."""
    try:
        from weights import load_weights
        from inventory import load_inventory
        from datetime import date as _date, timedelta
        cutoff = (_date.fromisoformat(_today_mtl()) - timedelta(days=days)).isoformat()
        if weights is None:
            weights = load_weights()
        inventory = load_inventory() or {}
        compound_patterns = {"squat", "hinge", "push_horizontal", "push_vertical", "pull_horizontal", "pull_vertical"}
        result: dict[str, list[dict]] = {}
        for name, data in weights.items():
            pattern = _norm_pattern((inventory.get(name) or {}).get("movement_pattern") or "")
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
        # Filtre jours 100 % vides à la source : trou de saisie ≠ zéro calorique.
        # Un jour à calories=0 ET proteines=0 est un jour où l'user n'a rien loggé,
        # pas un jour à zéro nutrition. Jours partiels (calories>0 OR proteines>0)
        # sont conservés — un fruit loggé et rien d'autre reste légitime.
        return sorted(
            [d for d in seen.values() if d["calories"] > 0 or d["proteines"] > 0],
            key=lambda x: x["date"],
        )

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


def get_macros_by_day_type(days: int = 60, nutr_days: list | None = None) -> dict:
    """Return average macros on training days vs rest days for the last N days.

    Training day = date has EITHER a completed workout session (rpe or completed=true),
    OR any exercise_log row, OR any hiit_log entry. Union des 3 sources — capture
    les muscu-loguées-sans-marquer, les sessions yoga marquées, le HIIT-only, et
    tout ce qui est entre les deux. Un critère plus étroit (session.completed seul)
    classait "rest" des jours d'entraînement réels dont la session n'était pas
    marquée completed/rpe (bug corrigé ici).
    """
    try:
        from datetime import date as _date, timedelta
        cutoff = (_date.fromisoformat(_today_mtl()) - timedelta(days=days)).isoformat()
        nutr_days = nutr_days if nutr_days is not None else get_nutrition_daily_full(days)

        sessions  = get_workout_sessions(limit=days + 10, since=cutoff)
        ex_logs   = get_exercise_logs_since(cutoff)
        hiit_logs = get_hiit_logs(limit=days + 10)

        workout_dates: set[str] = (
            {str(s.get("date", ""))[:10] for s in sessions
             if s.get("completed") or s.get("rpe") is not None}
            | {str(r.get("date", ""))[:10] for r in ex_logs if r.get("date")}
            | {str(h.get("date", ""))[:10] for h in hiit_logs
               if str(h.get("date", ""))[:10] >= cutoff}
        )
        workout_dates.discard("")

        training: list[dict] = []
        rest: list[dict] = []
        for d in nutr_days:
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


def get_protein_weight_ratio(days: int = 60, nutr_days: list | None = None) -> list[dict]:
    """Return protein/bodyweight ratio per day for days with both logged.

    weight is always stored in lbs — the iOS app hardcodes the input label as
    "POIDS (LBS)" and converts HealthKit kg values via / 0.453592 before sending.
    ratio unit is therefore g_protein / lbs_bodyweight.
    """
    try:
        from datetime import date as _date, timedelta
        cutoff    = (_date.fromisoformat(_today_mtl()) - timedelta(days=days)).isoformat()
        nutr_days = nutr_days if nutr_days is not None else get_nutrition_daily_full(days)
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


def get_session_volume_map(days: int = 200) -> dict[str, float]:
    return _get_session_volume_map(days)


def _aggregate_force_vs_accessory_timeline(rows: list[dict]) -> list[dict]:
    """Pure : groupe rows par (iso_week, category), moyenne total_volume.

    avg_tonnage = MOYENNE par séance dans (semaine, catégorie) — pas la somme.
    Neutralise le nombre de séances : compare la charge PAR SÉANCE (qualité),
    pas la charge totale hebdo (quantité). Exposée en top-level pour test unitaire.
    """
    from datetime import date as _date, timedelta
    buckets: dict[tuple[str, str], list[float]] = {}
    for r in rows:
        d = str(r.get("date", ""))[:10]
        cat = r.get("session_category")
        vol = r.get("total_volume")
        if not d or cat not in ("force", "accessory") or vol is None:
            continue
        try:
            dt = _date.fromisoformat(d)
        except ValueError:
            continue
        monday = (dt - timedelta(days=dt.weekday())).isoformat()
        buckets.setdefault((monday, cat), []).append(float(vol))
    result = [
        {
            "iso_week":         monday,
            "session_category": cat,
            "avg_tonnage":      round(sum(vols) / len(vols), 2),
            "n_sessions":       len(vols),
        }
        for (monday, cat), vols in buckets.items()
    ]
    result.sort(key=lambda x: (x["iso_week"], x["session_category"]))
    return result


def get_force_vs_accessory_timeline(weeks: int = 12) -> list[dict]:
    """Return [{iso_week, session_category, avg_tonnage, n_sessions}] sur N semaines.

    Source : vue v_session_category (migration 085) qui classe chaque séance
    par ratio d'exos compound. Filtre 'unknown' côté agrégation.
    """
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> list[dict]:
        from datetime import date as _date, timedelta
        cutoff = (_date.fromisoformat(_today_mtl()) - timedelta(weeks=weeks)).isoformat()
        resp = (
            db_core._client.table("v_session_category")
            .select("date, session_category, total_volume")
            .gte("date", cutoff)
            .in_("session_category", ("force", "accessory"))
            .execute()
        )
        return _aggregate_force_vs_accessory_timeline(resp.data or [])

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_force_vs_accessory_timeline retry: %s", e2)
                return []
        db_core.logger.error("get_force_vs_accessory_timeline error: %s", e)
        return []


# ponytail: endpoint temp — simule 2 variantes de classification par `category`.
# Supprimer avec l'endpoint /simulate après validation de la règle définitive.
def simulate_category_classification(limit: int = 20) -> dict:
    """Simule la classification par `exercises.category` SANS toucher à la vue 085.

    Renvoie :
      fill   — remplissage colonnes category vs load_profile (histogramme by_category)
      sample — 20 dernières séances : breakdown des exos par category + 2 variantes
               de classification (A = {push,pull,legs}, B = A ∪ {strength})

    Consommé par scripts/verify_session_category.py pour choisir la règle exacte.
    """
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return {"fill": {}, "sample": []}

    def _do() -> dict:
        # Fill counts sur exercises
        fill_resp = db_core._client.table("exercises").select("id, category, load_profile").execute()
        exos = fill_resp.data or []
        by_category: dict[str, int] = {}
        for e in exos:
            k = e.get("category") or "(null)"
            by_category[k] = by_category.get(k, 0) + 1
        fill = {
            "total_exercises":    len(exos),
            "with_category":      sum(1 for e in exos if e.get("category")),
            "with_load_profile":  sum(1 for e in exos if e.get("load_profile")),
            "by_category":        by_category,
        }

        # 20 dernières séances
        vol_resp = (
            db_core._client.table("v_session_volume")
            .select("session_id, date, total_volume")
            .order("date", desc=True)
            .limit(limit)
            .execute()
        )
        sessions = vol_resp.data or []
        if not sessions:
            return {"fill": fill, "sample": []}

        session_ids = [s["session_id"] for s in sessions]

        sess_resp = (
            db_core._client.table("workout_sessions")
            .select("id, session_name")
            .in_("id", session_ids)
            .execute()
        )
        names = {r["id"]: (r.get("session_name") or "?") for r in (sess_resp.data or [])}

        logs_resp = (
            db_core._client.table("exercise_logs")
            .select("session_id, exercise_id, exercises(category)")
            .in_("session_id", session_ids)
            .execute()
        )
        by_session: dict[str, list[str | None]] = {}
        for log in (logs_resp.data or []):
            sid = log.get("session_id")
            ex_data = log.get("exercises") or {}
            by_session.setdefault(sid, []).append(ex_data.get("category"))

        FORCE_A = {"push", "pull", "legs"}
        FORCE_B = {"push", "pull", "legs", "strength"}

        def _classify(force_count: int, classified_count: int) -> dict:
            if classified_count == 0:
                return {"force_exos": 0, "ratio": None, "category": "unknown"}
            ratio = force_count / classified_count
            return {
                "force_exos": force_count,
                "ratio":      round(ratio, 3),
                "category":   "force" if ratio >= 0.5 else "accessory",
            }

        sample = []
        for s in sessions:
            sid = s["session_id"]
            cats = by_session.get(sid, [])
            breakdown: dict[str, int] = {}
            for c in cats:
                k = c or "(null)"
                breakdown[k] = breakdown.get(k, 0) + 1
            classified = sum(1 for c in cats if c)
            force_A = sum(1 for c in cats if c in FORCE_A)
            force_B = sum(1 for c in cats if c in FORCE_B)
            sample.append({
                "session_id":   sid,
                "date":         str(s.get("date", ""))[:10],
                "session_name": names.get(sid, "?"),
                "n_exos":       len(cats),
                "classified":   classified,
                "breakdown":    breakdown,
                "total_volume": float(s.get("total_volume") or 0),
                "variant_A":    _classify(force_A, classified),
                "variant_B":    _classify(force_B, classified),
            })
        return {"fill": fill, "sample": sample}

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("simulate_category_classification retry: %s", e2)
                return {"fill": {}, "sample": []}
        db_core.logger.error("simulate_category_classification error: %s", e)
        return {"fill": {}, "sample": []}


def get_session_category_sample(limit: int = 20) -> list[dict]:
    """Renvoie les N dernières séances avec détail de classification pour vérif humaine.

    Sortie : [{date, session_name, session_category, ratio_force, force_exos,
    classified_exos, total_volume}]. Consommée par l'endpoint debug + script de vérif.
    """
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []

    def _do() -> list[dict]:
        resp = (
            db_core._client.table("v_session_category")
            .select("session_id, date, session_category, ratio_force, "
                    "force_exos, classified_exos, total_volume")
            .order("date", desc=True)
            .limit(limit)
            .execute()
        )
        rows = resp.data or []
        if not rows:
            return []
        session_ids = [r["session_id"] for r in rows]
        sess_resp = (
            db_core._client.table("workout_sessions")
            .select("id, session_name")
            .in_("id", session_ids)
            .execute()
        )
        names = {r["id"]: (r.get("session_name") or "?") for r in (sess_resp.data or [])}
        return [
            {
                "session_id":       r["session_id"],
                "date":             str(r.get("date", ""))[:10],
                "session_name":     names.get(r["session_id"], "?"),
                "session_category": r.get("session_category"),
                "ratio_force":      float(r["ratio_force"]) if r.get("ratio_force") is not None else None,
                "force_exos":       int(r.get("force_exos") or 0),
                "classified_exos":  int(r.get("classified_exos") or 0),
                "total_volume":     float(r.get("total_volume") or 0),
            }
            for r in rows
        ]

    try:
        return _do()
    except Exception as e:
        if db_core._is_disconnect(e) and db_core._reconnect():
            try:
                return _do()
            except Exception as e2:
                db_core.logger.error("get_session_category_sample retry: %s", e2)
                return []
        db_core.logger.error("get_session_category_sample error: %s", e)
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
    """Return exercise_logs with exercise metadata for push/pull + agonist/antagonist analysis."""
    if db_core._client is None or db_core.MODE == "OFFLINE":
        return []
    from datetime import date as _date, timedelta
    cutoff = (_date.fromisoformat(_today_mtl()) - timedelta(days=days)).isoformat()

    def _do() -> list[dict]:
        resp = (
            db_core._client.table("exercise_logs")
            .select("weight, reps, workout_sessions(date), exercises(name, category, load_profile, muscle_group, muscle_specific)")
            .gte("workout_sessions.date", cutoff)
            .limit(1000)
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
                "date":            d,
                "exercise":        ex.get("name"),
                "category":        ex.get("category"),
                "load_profile":    ex.get("load_profile"),
                "muscle_group":    ex.get("muscle_group") or "",
                "muscle_specific": ex.get("muscle_specific") or "",
                "weight":          r.get("weight", 0),
                "reps":            r.get("reps", ""),
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
