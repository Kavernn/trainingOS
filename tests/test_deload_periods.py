"""Tests du prédicat is_deload_day sur deload_periods (migration 080).

Exigences validées (lot Vue d'ensemble / Bien-être, commit 0) :
- Jour dans [started_at, scheduled_end] période active → True.
- Jour > completed_at (arrêt anticipé) → False, même si scheduled_end postérieur.
- Jour > scheduled_end période terminée → False.
- Jour entre deux périodes → False.
- Période active bornée à aujourd'hui (future > today → False).
- Jour S11 calendaire sans décharge enregistrée → False (formule 77j supprimée).
- Multiples appels de is_deload_day → UNE seule requête SQL via cache per-request.
"""
from __future__ import annotations

import sys
from datetime import date
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "api"))

import analytics_adapter


# ── Fixtures ─────────────────────────────────────────────────────────────────

@pytest.fixture
def today(monkeypatch):
    """Pin today = 2026-10-15 pour borner les périodes actives."""
    pinned = "2026-10-15"
    monkeypatch.setattr("utils._today_mtl", lambda: pinned)
    return date.fromisoformat(pinned)


def _period(started: str, scheduled_end: str, completed: str | None = None, reason: str = "test"):
    return {
        "started_at":    started,
        "scheduled_end": scheduled_end,
        "completed_at":  completed,
        "reason":        reason,
        "duration_days": 7,
    }


# ── Prédicat is_deload_day ───────────────────────────────────────────────────

def test_day_inside_active_period_returns_true(today):
    periods = [_period("2026-10-10", "2026-10-17", completed=None)]
    assert analytics_adapter.is_deload_day(date(2026, 10, 12), periods) is True


def test_day_after_early_completion_returns_false(today):
    """Arrêt anticipé le 10-13, scheduled_end initial 10-17 : jour 10-14 → False."""
    periods = [_period("2026-10-10", "2026-10-17", completed="2026-10-13")]
    assert analytics_adapter.is_deload_day(date(2026, 10, 14), periods) is False
    # Jour <= completed_at reste True
    assert analytics_adapter.is_deload_day(date(2026, 10, 13), periods) is True


def test_day_after_scheduled_end_of_completed_period_returns_false(today):
    """Période terminée à sa date prévue : jour postérieur → False."""
    periods = [_period("2026-09-01", "2026-09-07", completed="2026-09-07")]
    assert analytics_adapter.is_deload_day(date(2026, 9, 8), periods) is False


def test_day_between_two_periods_returns_false(today):
    periods = [
        _period("2026-08-01", "2026-08-07", completed="2026-08-07"),
        _period("2026-10-01", "2026-10-07", completed="2026-10-07"),
    ]
    assert analytics_adapter.is_deload_day(date(2026, 9, 15), periods) is False


def test_active_period_bounded_to_today(today):
    """Décharge active, scheduled_end future : jour futur > today → False."""
    periods = [_period("2026-10-14", "2026-10-21", completed=None)]
    assert analytics_adapter.is_deload_day(date(2026, 10, 20), periods) is False
    # Aujourd'hui et avant : True
    assert analytics_adapter.is_deload_day(date(2026, 10, 15), periods) is True
    assert analytics_adapter.is_deload_day(date(2026, 10, 14), periods) is True


def test_s11_calendar_day_without_period_returns_false(today):
    """Scénario fantôme passé : jour qui tombait en S11 calendaire (ancien cycle
    = 2026-07-20 → S11 = 2026-09-28..10-04). Sans décharge enregistrée → False.
    Garantit la suppression de la formule 77-jours."""
    periods: list[dict] = []
    for ghost_day in [date(2026, 9, 28), date(2026, 9, 30), date(2026, 10, 4)]:
        assert analytics_adapter.is_deload_day(ghost_day, periods) is False


def test_empty_periods_always_false(today):
    assert analytics_adapter.is_deload_day(date(2026, 10, 15), []) is False
    assert analytics_adapter.is_deload_day(date(2020, 1, 1), []) is False


# ── Cache per-request : UNE seule requête SQL ────────────────────────────────

def test_periods_fetched_once_per_request(today, monkeypatch):
    """Hors Flask, _get_periods_cached fetch à chaque appel (pas de g).
    Dans Flask, mêmes conditions → une seule lecture via g."""
    call_count = {"n": 0}

    def fake_get():
        call_count["n"] += 1
        return [_period("2026-10-10", "2026-10-17")]

    monkeypatch.setattr("db.get_deload_periods", fake_get)

    try:
        from flask import Flask  # type: ignore
    except Exception:
        pytest.skip("Flask not available")

    app = Flask(__name__)
    with app.test_request_context("/"):
        # 10 appels dans le même request context → 1 fetch
        for d in range(10, 20):
            analytics_adapter.is_deload_day(date(2026, 10, d))
        assert call_count["n"] == 1

    # Nouveau request context → nouveau fetch
    with app.test_request_context("/"):
        analytics_adapter.is_deload_day(date(2026, 10, 15))
        assert call_count["n"] == 2


# ── Helper _period_bounds (contrat interne) ──────────────────────────────────

def test_period_bounds_active_bounded_to_today(today):
    bounds = analytics_adapter._period_bounds(
        _period("2026-10-10", "2026-10-20", completed=None), today
    )
    assert bounds == (date(2026, 10, 10), date(2026, 10, 15))


def test_period_bounds_completed_uses_completion_date(today):
    bounds = analytics_adapter._period_bounds(
        _period("2026-10-10", "2026-10-17", completed="2026-10-12"), today
    )
    assert bounds == (date(2026, 10, 10), date(2026, 10, 12))


def test_period_bounds_malformed_returns_none(today):
    assert analytics_adapter._period_bounds({"started_at": "nope", "scheduled_end": "2026-10-17"}, today) is None
    assert analytics_adapter._period_bounds({"started_at": "2026-10-10"}, today) is None


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
