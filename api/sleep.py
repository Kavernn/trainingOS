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

from db import get_json, set_json

_KV_KEY = "sleep_records"

_QUALITY_LABELS = {1: "Très mauvais", 2: "Mauvais", 3: "Moyen", 4: "Bon", 5: "Excellent"}
_QUALITY_EMOJIS = {1: "😫", 2: "😕", 3: "😐", 4: "😊", 5: "🌟"}


# ── Stockage ──────────────────────────────────────────────────────────────────

def _load() -> list:
    return get_json(_KV_KEY) or []

def _save(records: list) -> None:
    set_json(_KV_KEY, records)


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
    records  = _load()
    today    = date_cls.today().isoformat()
    duration = _calc_duration(bedtime, wake_time)

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
        "insights":         _insights(duration, quality, records),
        "logged_at":        datetime.now().isoformat(),
    }

    # Remplace si déjà loggé aujourd'hui
    records = [r for r in records if r.get("date") != today]
    records.insert(0, entry)
    _save(records)
    return entry


def get_history(limit: int = 20, offset: int = 0) -> dict:
    all_records = _load()
    page = all_records[offset: offset + limit]
    return {
        "items":       page,
        "offset":      offset,
        "limit":       limit,
        "total":       len(all_records),
        "has_more":    offset + limit < len(all_records),
        "next_offset": offset + limit if offset + limit < len(all_records) else None,
    }


def get_today() -> dict | None:
    today = date_cls.today().isoformat()
    return next((r for r in _load() if r.get("date") == today), None)


def get_stats() -> dict:
    records = _load()
    if not records:
        return {"avg_duration": None, "avg_quality": None, "total": 0, "streak": 0}

    recent7  = [r for r in records[:7] if r.get("duration_hours") is not None]
    recent7q = [r for r in records[:7] if r.get("quality") is not None]

    avg_duration = round(sum(r["duration_hours"] for r in recent7) / len(recent7), 1) if recent7 else None
    avg_quality  = round(sum(r["quality"] for r in recent7q) / len(recent7q), 1) if recent7q else None

    # Streak consécutif
    streak = 0
    day    = date_cls.today()
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
    records = _load()
    before  = len(records)
    records = [r for r in records if r.get("id") != record_id]
    if len(records) < before:
        _save(records)
        return True
    return False
