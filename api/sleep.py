"""
sleep.py — Suivi du sommeil quotidien.

Clé KV : "sleep_records" → list[dict] DESC par date

Endpoints exposés dans index.py :
  POST /api/sleep/log
  GET  /api/sleep/history
  GET  /api/sleep/today
  GET  /api/sleep/stats
  POST /api/sleep/delete
"""
from __future__ import annotations

from datetime import date as date_cls, datetime, timedelta
import uuid

import db
from utils import _today_mtl as _today_local

_QUALITY_LABELS = {1: "Très mauvais", 2: "Mauvais", 3: "Moyen", 4: "Bon", 5: "Excellent"}
_QUALITY_EMOJIS = {1: "😫", 2: "😕", 3: "😐", 4: "😊", 5: "🌟"}


# ── Durée ─────────────────────────────────────────────────────────────────────

def _calc_duration(bedtime: str, wake_time: str) -> float:
    """Durée en heures. Gère le passage minuit (ex: 23:30 → 07:00 = 7.5h)."""
    bh, bm = [int(x) for x in bedtime.split(":")]
    wh, wm = [int(x) for x in wake_time.split(":")]
    bed_mins  = bh * 60 + bm
    wake_mins = wh * 60 + wm
    if wake_mins <= bed_mins:   # passage minuit
        wake_mins += 24 * 60
    return round((wake_mins - bed_mins) / 60, 2)


# ── Catégorie durée ───────────────────────────────────────────────────────────

def _duration_category(h: float) -> str:
    if h < 6:   return "insuffisant"
    if h < 7:   return "court"
    if h <= 9:  return "optimal"
    return "long"

def _duration_color(h: float) -> str:
    if h < 6:   return "red"
    if h < 7:   return "yellow"
    if h <= 9:  return "green"
    return "blue"


def _sleep_date(bedtime: str) -> str:
    """Date du coucher : si bedtime ≥ 12:00, le sommeil appartient à la nuit précédente."""
    bh = int(bedtime.split(":")[0])
    today = date_cls.fromisoformat(_today_local())
    return (today - timedelta(days=1)).isoformat() if bh >= 12 else today.isoformat()


# ── Insights ──────────────────────────────────────────────────────────────────

def _insights(hours: float, quality: int, history: list) -> list[str]:
    msgs = []

    if not history:
        msgs.append("Premier bilan sommeil enregistré — bonne habitude à maintenir 👍")

    if hours < 6:
        msgs.append(f"⚠️ {hours:.1f}h de sommeil — sous le minimum recommandé (7h). Récupère cette semaine.")
    elif hours < 7:
        msgs.append(f"😐 {hours:.1f}h — légèrement insuffisant. Vise 7-9h pour une récupération optimale.")
    elif hours <= 9:
        msgs.append(f"✅ {hours:.1f}h de sommeil — dans la zone optimale (7-9h).")
    else:
        msgs.append(f"😴 {hours:.1f}h de sommeil — long. Assure-toi que la qualité est bonne aussi.")

    if quality <= 2:
        msgs.append("Qualité faible : pense à réduire les écrans 1h avant de dormir, à réguler la température.")
    elif quality == 5:
        msgs.append("Qualité excellente 🌟 — note ce qui a aidé pour reproduire ça.")

    recent = [r for r in history[:6] if r.get("duration_hours")]
    if len(recent) >= 3:
        avg = sum(r["duration_hours"] for r in recent) / len(recent)
        if hours < avg - 1.0:
            msgs.append(f"Nuit plus courte que ta moyenne récente ({avg:.1f}h) — prévoie de te coucher tôt ce soir.")
        elif hours > avg + 1.0:
            msgs.append(f"Bonne nuit par rapport à ta moyenne ({avg:.1f}h) 🙌")

    return msgs


# ── CRUD ──────────────────────────────────────────────────────────────────────

def save_sleep_entry(
    bedtime: str,
    wake_time: str,
    quality: int,
    notes: str | None = None,
) -> dict:
    today    = _sleep_date(bedtime)
    duration = _calc_duration(bedtime, wake_time)
    history  = _get_all_records()[:6]

    entry = {
        "id":               str(uuid.uuid4()),
        "date":             today,
        "bedtime":          bedtime,
        "wake_time":        wake_time,
        "duration_hours":   duration,
        "quality":          quality,
        "quality_label":    _QUALITY_LABELS.get(quality, "—"),
        "quality_emoji":    _QUALITY_EMOJIS.get(quality, ""),
        "duration_category": _duration_category(duration),
        "duration_color":   _duration_color(duration),
        "notes":            notes,
        "insights":         _insights(duration, quality, history),
        "logged_at":        datetime.now().isoformat(),
    }

    # Source de vérité : recovery_logs — sleep_records est archivée, ne plus alimenter.
    # source="manual" empêche l'écrasement par HealthKit.
    # sleep_quality converti 1-5 → 1-10 pour cohérence avec recovery_logs.
    existing_rec = next((r for r in db.get_recovery_logs(limit=7) if r.get("date") == today), {})
    existing_rec["date"]          = today
    existing_rec["sleep_hours"]   = duration
    existing_rec["sleep_quality"] = round((quality - 1) / 4 * 9 + 1)
    existing_rec["source"]        = "manual"
    ok = db.upsert_recovery_log(existing_rec)
    if not ok:
        import logging as _logging
        _logging.getLogger(__name__).error(
            "sleep write to recovery_logs failed for date=%s — readiness sleep modules will return None",
            today,
        )

    return entry


def _recovery_to_sleep(entry: dict) -> dict:
    """Convert a recovery_log entry to a sleep-compatible SleepEntry dict.

    Manual entries (source='manual') carry sleep_quality on 1-10 scale →
    mapped to 1-5 to match SleepLogSheet convention.
    HealthKit entries have no quality → quality=0 (excluded from avg stats,
    decodes safely as Int in Swift).
    """
    h      = entry.get("sleep_hours") or 0.0
    source = entry.get("source") or "healthkit"
    sq_raw = entry.get("sleep_quality")  # 1-10 in recovery_logs

    if sq_raw and source == "manual":
        quality = max(1, min(5, round(sq_raw / 2)))
        q_label = _QUALITY_LABELS.get(quality, "—")
        q_emoji = _QUALITY_EMOJIS.get(quality, "")
    else:
        quality = 0
        q_label = "Auto (Apple Watch)"
        q_emoji = "⌚"

    return {
        "id":                entry["date"],
        "date":              entry["date"],
        "bedtime":           "—",
        "wake_time":         "—",
        "duration_hours":    h,
        "quality":           quality,
        "quality_label":     q_label,
        "quality_emoji":     q_emoji,
        "duration_category": _duration_category(h),
        "duration_color":    _duration_color(h),
        "notes":             entry.get("notes") or None,
        "insights":          _insights(h, quality if quality else 3, []),
        "source":            source,
        "logged_at":         entry.get("date"),
    }


def _get_all_records() -> list:
    """Source de vérité unique : recovery_logs.sleep_hours (saisie manuelle)."""
    recovery = db.get_recovery_logs(limit=90) or []
    return sorted(
        [_recovery_to_sleep(r) for r in recovery if r.get("sleep_hours") is not None],
        key=lambda r: r["date"],
        reverse=True,
    )


def get_history(limit: int = 20, offset: int = 0) -> dict:
    all_records = _get_all_records()
    total = len(all_records)
    page  = all_records[offset: offset + limit]
    return {
        "items":       page,
        "offset":      offset,
        "limit":       limit,
        "total":       total,
        "has_more":    offset + limit < total,
        "next_offset": offset + limit if offset + limit < total else None,
    }




def get_today() -> dict | None:
    today     = _today_local()
    yesterday = (date_cls.fromisoformat(today) - timedelta(days=1)).isoformat()
    recovery  = db.get_recovery_logs(limit=7) or []
    entry = next(
        (r for r in recovery
         if r.get("date") in (today, yesterday) and r.get("sleep_hours") is not None),
        None,
    )
    return _recovery_to_sleep(entry) if entry else None


def get_stats() -> dict:
    records = _get_all_records()
    if not records:
        return {"avg_duration": None, "avg_quality": None, "total": 0, "streak": 0}

    recent7  = [r for r in records[:7] if r.get("duration_hours") is not None]
    recent7q = [r for r in records[:7] if r.get("quality")]

    avg_duration = round(sum(r["duration_hours"] for r in recent7) / len(recent7), 1) if recent7 else None
    avg_quality  = round(sum(r["quality"] for r in recent7q) / len(recent7q), 1) if recent7q else None

    streak = 0
    day    = date_cls.fromisoformat(_today_local())
    dates  = {r["date"] for r in records}
    while day.isoformat() in dates:
        streak += 1
        day -= timedelta(days=1)

    return {
        "avg_duration": avg_duration,
        "avg_quality":  avg_quality,
        "total":        len(records),
        "streak":       streak,
    }


def delete_entry(record_id: str) -> bool:
    """record_id est la date ISO. Efface sleep_hours/sleep_quality uniquement.
    Les autres métriques (HRV, FC, steps) sont préservées.
    """
    logs  = db.get_recovery_logs(limit=90) or []
    entry = next((r for r in logs if r.get("date") == record_id), None)
    if not entry:
        return False
    entry["sleep_hours"]   = None
    entry["sleep_quality"] = None
    return db.upsert_recovery_log(entry)
