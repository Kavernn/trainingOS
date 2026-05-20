"""time_capsule.py — Time Capsule snapshot capture + CRUD."""
from __future__ import annotations

import logging
import uuid
from calendar import monthrange
from datetime import datetime, timezone, date as date_cls, timedelta
from typing import Optional

import db

logger = logging.getLogger("trainingos.time_capsule")

_PR_KEYS = [
    "bench press", "squat", "deadlift",
    "overhead press", "incline press",
    "barbell row", "pull-up", "rdl",
]


def _add_months(dt: datetime, months: int) -> datetime:
    month = dt.month - 1 + months
    year  = dt.year + month // 12
    month = month % 12 + 1
    day   = min(dt.day, monthrange(year, month)[1])
    return dt.replace(year=year, month=month, day=day)


# ── Snapshot helpers ──────────────────────────────────────────────────────────

def _compute_prs(history: dict) -> dict:
    prs: dict = {}
    for target in _PR_KEYS:
        best_weight = 0.0
        best_entry: Optional[dict] = None
        best_name = ""
        for ex_name, entries in history.items():
            if target not in ex_name.lower():
                continue
            for e in entries:
                w = float(e.get("weight") or 0)
                if w > best_weight:
                    best_weight = w
                    best_entry  = e
                    best_name   = ex_name
        if best_entry and best_weight > 0:
            key = target.replace(" ", "_")
            prs[key] = {
                "weight": best_weight,
                "reps":   int(best_entry.get("reps") or 1),
                "date":   best_entry.get("date", ""),
                "name":   best_name,
            }
    return prs


def _compute_weekly_volume(history: dict) -> float:
    """Average weekly volume (kg × reps × sets) over the last 4 weeks."""
    cutoff = (date_cls.today() - timedelta(weeks=4)).isoformat()
    total  = 0.0
    for entries in history.values():
        for e in entries:
            if (e.get("date") or "") < cutoff:
                continue
            w         = float(e.get("weight") or 0)
            r         = int(e.get("reps") or 1)
            sets_list = e.get("sets")
            s         = len(sets_list) if isinstance(sets_list, list) else 1
            total    += w * r * s
    return round(total / 4, 1)


def _compute_sessions_per_month() -> float:
    if db._client is None:
        return 0.0
    cutoff = (date_cls.today() - timedelta(days=30)).isoformat()
    try:
        resp = (
            db._client.table("workout_sessions")
            .select("id")
            .gte("date", cutoff)
            .execute()
        )
        return float(len(resp.data or []))
    except Exception as e:
        logger.error("sessions_per_month error: %s", e)
        return 0.0


def _compute_total_sessions() -> int:
    if db._client is None:
        return 0
    try:
        resp = db._client.table("workout_sessions").select("id").execute()
        return len(resp.data or [])
    except Exception as e:
        logger.error("total_sessions error: %s", e)
        return 0


def _compute_macros_avg() -> dict:
    base = db.get_nutrition_entries_recent(30)
    n    = len(base)
    cal  = round(sum(e.get("calories", 0) for e in base) / n, 1) if n else 0.0
    prot = round(sum(e.get("proteines", 0) for e in base) / n, 1) if n else 0.0

    carbs = fat = 0.0
    if db._client is not None:
        try:
            cutoff = (date_cls.today() - timedelta(days=60)).isoformat()
            resp   = (
                db._client.table("nutrition_entries")
                .select("date, glucides, lipides")
                .gte("date", cutoff)
                .execute()
            )
            by_date: dict = {}
            for row in resp.data or []:
                d = row["date"]
                by_date.setdefault(d, {"g": 0.0, "l": 0.0})
                by_date[d]["g"] += float(row.get("glucides") or 0)
                by_date[d]["l"] += float(row.get("lipides")  or 0)
            days = sorted(by_date.items(), key=lambda x: x[0], reverse=True)[:30]
            if days:
                carbs = round(sum(v["g"] for _, v in days) / len(days), 1)
                fat   = round(sum(v["l"] for _, v in days) / len(days), 1)
        except Exception as e:
            logger.error("macros carbs/fat error: %s", e)

    return {"calories": cal, "protein_g": prot, "carbs_g": carbs, "fat_g": fat}


def _compute_body_weight() -> Optional[float]:
    for log in db.get_recovery_logs(limit=7):
        for field in ("weight_kg", "body_weight", "poids_kg", "weight"):
            val = log.get(field)
            if val:
                return float(val)
    return None


def _compute_pss_avg() -> Optional[float]:
    records = db.get_pss_records(limit=10)
    scores  = [
        float(r.get("total_score") or r.get("score") or 0)
        for r in records
        if r.get("total_score") or r.get("score")
    ]
    return round(sum(scores) / len(scores), 1) if scores else None


def _get_active_programme() -> Optional[str]:
    try:
        from planner import get_today
        result = get_today()
        return result if isinstance(result, str) else None
    except Exception:
        return None


def capture_snapshot() -> dict:
    """Current-state snapshot — called at creation AND at reveal."""
    history = db.get_all_exercise_history()
    return {
        "captured_at":            datetime.now(timezone.utc).isoformat(),
        "active_programme":       _get_active_programme(),
        "total_sessions_to_date": _compute_total_sessions(),
        "prs":                    _compute_prs(history),
        "weekly_volume_avg_kg":   _compute_weekly_volume(history),
        "sessions_per_month_avg": _compute_sessions_per_month(),
        "body_weight_kg":         _compute_body_weight(),
        "macros_avg":             _compute_macros_avg(),
        "pss_avg":                _compute_pss_avg(),  # private — excluded from share export
    }


# ── CRUD ──────────────────────────────────────────────────────────────────────

def create_capsule(duration_months: int, message: Optional[str]) -> dict:
    if db._client is None:
        raise RuntimeError("Supabase not connected")
    if duration_months not in (1, 3, 6):
        raise ValueError("duration_months must be 1, 3 or 6")

    now       = datetime.now(timezone.utc)
    unlock_at = _add_months(now, duration_months)

    row = {
        "id":              str(uuid.uuid4()),
        "created_at":      now.isoformat(),
        "unlock_at":       unlock_at.isoformat(),
        "duration_months": duration_months,
        "message":         (message or "").strip() or None,
        "snapshot":        capture_snapshot(),
        "is_opened":       False,
    }
    resp = db._client.table("time_capsules").insert(row).execute()
    return (resp.data or [row])[0]


def list_capsules() -> list:
    if db._client is None:
        return []
    try:
        resp = (
            db._client.table("time_capsules")
            .select("id, created_at, unlock_at, unlocked_at, duration_months, message, is_opened, snapshot")
            .order("created_at", desc=True)
            .execute()
        )
        return resp.data or []
    except Exception as e:
        logger.error("list_capsules error: %s", e)
        return []


def get_capsule_detail(capsule_id: str) -> Optional[dict]:
    if db._client is None:
        return None
    try:
        resp = (
            db._client.table("time_capsules")
            .select("*")
            .eq("id", capsule_id)
            .limit(1)
            .execute()
        )
        rows = resp.data or []
        if not rows:
            return None
        capsule = rows[0]
        # Attach live snapshot only when capsule is unlockable
        if (capsule.get("unlock_at") or "9999") <= datetime.now(timezone.utc).isoformat():
            capsule["current"] = capture_snapshot()
        return capsule
    except Exception as e:
        logger.error("get_capsule_detail error: %s", e)
        return None


def open_capsule(capsule_id: str) -> Optional[dict]:
    """Mark as opened and return capsule + live current snapshot."""
    if db._client is None:
        return None
    try:
        now  = datetime.now(timezone.utc).isoformat()
        resp = (
            db._client.table("time_capsules")
            .update({"is_opened": True, "unlocked_at": now})
            .eq("id", capsule_id)
            .execute()
        )
        rows = resp.data or []
        if not rows:
            return None
        capsule = rows[0]
        capsule["current"] = capture_snapshot()
        return capsule
    except Exception as e:
        logger.error("open_capsule error: %s", e)
        return None
