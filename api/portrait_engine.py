"""
portrait_engine.py — Portrait J-90: multi-dimensional snapshot today vs 90 days ago.

7 dimensions computed over a 7-day window:
  volume      — weekly workout volume (sets × weight proxy via RPE × sessions)
  frequency   — sessions per week
  hrv         — average HRV
  sleep       — average sleep quality (0–10)
  stress      — PSS average (lower = better → inverted for delta)
  body_weight — latest vs 90-day reference (lbs)
  nutrition   — logged days per 7-day window

Reference window: J-87 to J-93 (7 days centered on J-90).
Current window:   J-0  to J-6  (last 7 days).

Data read only. No writes.
"""
from __future__ import annotations
import logging
from datetime import date, timedelta

import db
from utils import _today_mtl as _today_iso

logger = logging.getLogger("trainingos.portrait")

_SPAN = 7


def _window(anchor_offset: int) -> set[str]:
    today = date.fromisoformat(_today_iso())
    center = today - timedelta(days=anchor_offset)
    half = _SPAN // 2
    return {(center - timedelta(days=half - i)).isoformat() for i in range(_SPAN)}


def _mean(vals: list[float]) -> float | None:
    return sum(vals) / len(vals) if vals else None


def _dim(name: str, recent: float | None, ref: float | None,
         higher_is_better: bool = True) -> dict:
    has_baseline = ref is not None and recent is not None
    if not has_baseline:
        return {"name": name, "recent": recent, "ref": ref,
                "delta": None, "delta_pct": None, "has_baseline": False,
                "improving": None}

    raw_delta = recent - ref
    delta_pct = (raw_delta / ref * 100) if ref != 0 else 0.0
    improving = (raw_delta > 0) if higher_is_better else (raw_delta < 0)
    return {
        "name":          name,
        "recent":        round(recent, 2),
        "ref":           round(ref, 2),
        "delta":         round(raw_delta, 2),
        "delta_pct":     round(delta_pct, 1),
        "has_baseline":  True,
        "improving":     improving,
    }


def compute() -> dict:
    today = date.fromisoformat(_today_iso())

    recent_window = {(today - timedelta(days=i)).isoformat() for i in range(_SPAN)}
    ref_window    = _window(90)

    sessions  = db.get_workout_sessions(limit=200) or []
    pss       = db.get_pss_records(limit=60) or []
    recovery  = db.get_recovery_logs(limit=200) or []
    nutrition = db.get_nutrition_entries_recent(200) or []
    weights   = db.get_body_weight_logs(limit=200) or []

    # ── Frequency ────────────────────────────────────────────────────────────
    def _freq(window: set[str]) -> float:
        return len([s for s in sessions if s.get("date") in window and s.get("completed")])

    # ── Volume proxy (RPE × frequency, normalised) ───────────────────────────
    def _volume(window: set[str]) -> float:
        total = 0.0
        for s in sessions:
            if s.get("date") in window and s.get("completed"):
                total += float(s.get("rpe") or 7)
        return total

    # ── HRV ──────────────────────────────────────────────────────────────────
    def _hrv(window: set[str]) -> float | None:
        vals = [float(r["hrv"]) for r in recovery if r.get("date") in window and r.get("hrv")]
        return _mean(vals)

    # ── Sleep quality ─────────────────────────────────────────────────────────
    def _sleep(window: set[str]) -> float | None:
        vals = [float(r["sleep_quality"]) for r in recovery
                if r.get("date") in window and r.get("sleep_quality")]
        return _mean(vals)

    # ── Stress (PSS, inverted: lower = better) ────────────────────────────────
    def _pss(window: set[str]) -> float | None:
        vals = [float(r.get("pss_score") or r.get("score") or 0)
                for r in pss if r.get("date") in window]
        return _mean(vals)

    # ── Body weight ──────────────────────────────────────────────────────────
    def _weight(window: set[str]) -> float | None:
        w_in_window = [float(w["weight"]) for w in weights
                       if w.get("date") in window and w.get("weight")]
        return _mean(w_in_window)

    # ── Nutrition days ────────────────────────────────────────────────────────
    def _nutr(window: set[str]) -> float:
        return float(len({e["date"] for e in nutrition if e.get("date") in window}))

    dimensions = [
        _dim("frequency",   _freq(recent_window),   _freq(ref_window)),
        _dim("volume",      _volume(recent_window),  _volume(ref_window)),
        _dim("hrv",         _hrv(recent_window),     _hrv(ref_window)),
        _dim("sleep",       _sleep(recent_window),   _sleep(ref_window)),
        _dim("stress",      _pss(recent_window),     _pss(ref_window),    higher_is_better=False),
        _dim("nutrition",   _nutr(recent_window),    _nutr(ref_window)),
        _dim("body_weight", _weight(recent_window),  _weight(ref_window), higher_is_better=False),
    ]

    active = [d for d in dimensions if d["has_baseline"] and d["improving"] is not None]
    improving_count = sum(1 for d in active if d["improving"])
    transformation_score = round(improving_count / len(active) * 100) if active else None

    days_active = (today - date.fromisoformat(_today_iso())).days  # always 0
    # Use earliest workout date instead
    all_dates = sorted([s["date"] for s in sessions if s.get("completed") and s.get("date")])
    inception_date = all_dates[0] if all_dates else None

    return {
        "dimensions":           dimensions,
        "transformation_score": transformation_score,
        "improving_count":      improving_count,
        "total_with_baseline":  len(active),
        "reference_offset_days": 90,
        "has_baseline":         len(active) >= 2,
        "inception_date":       inception_date,
    }
