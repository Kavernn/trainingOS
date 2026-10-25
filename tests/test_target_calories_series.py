"""Invariant lot A1 : la série target_calories et compute_target_calories
donnent la MÊME valeur pour une date.

Les deux lisent `energy.compute_energy_history` et appliquent le même
`_GOAL_ADJ`. Protège contre une divergence future dans l'implémentation.
"""
from __future__ import annotations

import sys
from datetime import date, timedelta
from pathlib import Path
from unittest.mock import patch

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "api"))


TODAY = date(2026, 10, 25)


def _fake_energy_history(days: int, end_date: str | None = None):
    """Série TDEE synthétique : 2800 kcal constant, un entry par jour."""
    end = date.fromisoformat(end_date) if end_date else TODAY
    return [
        {"date": (end - timedelta(days=i)).isoformat(), "tdee": 2800}
        for i in range(days - 1, -1, -1)
    ]


@pytest.fixture
def pinned_today(monkeypatch):
    monkeypatch.setattr("utils._today_mtl", lambda: TODAY.isoformat())
    monkeypatch.setattr("tdee._today_mtl", lambda: TODAY.isoformat())
    return TODAY


@pytest.fixture
def stubbed_dependencies(monkeypatch):
    """Stub des deps lourdes partagées par les deux fonctions."""
    monkeypatch.setattr("energy.compute_energy_history", _fake_energy_history)
    monkeypatch.setattr("db.get_profile", lambda: {"goal": "maintain"})


def test_series_matches_point_target_for_three_sample_dates(pinned_today, stubbed_dependencies):
    import tdee
    series = tdee.compute_target_calories_series(days=60, end_date=TODAY.isoformat())
    assert len(series) == 60

    for days_back in (1, 30, 59):
        d = (TODAY - timedelta(days=days_back)).isoformat()
        point = tdee.compute_target_calories(date=d)
        assert series[d] == point, (
            f"series[{d}]={series[d]} ≠ compute_target_calories({d})={point}"
        )


def test_series_null_when_prior_tdee_insufficient(pinned_today, monkeypatch):
    """TDEE series vide ou <7 → target_calories = None pour chaque date."""
    monkeypatch.setattr("energy.compute_energy_history",
                        lambda days, end_date=None: [])
    monkeypatch.setattr("db.get_profile", lambda: {"goal": "maintain"})
    import tdee
    series = tdee.compute_target_calories_series(days=10, end_date=TODAY.isoformat())
    assert len(series) == 10
    assert all(v is None for v in series.values())


def test_series_consecutive_dates_no_gaps(pinned_today, stubbed_dependencies):
    import tdee
    series = tdee.compute_target_calories_series(days=14, end_date=TODAY.isoformat())
    dates = sorted(series.keys())
    assert len(dates) == 14
    for i in range(1, len(dates)):
        prev = date.fromisoformat(dates[i - 1])
        curr = date.fromisoformat(dates[i])
        assert (curr - prev).days == 1, f"gap {prev} → {curr}"


def test_single_energy_history_call(pinned_today, monkeypatch):
    """compute_target_calories_series ne doit faire QU'UN appel à
    compute_energy_history (pas N appels comme compute_target_calories × N)."""
    call_count = {"n": 0}

    def _counting(days, end_date=None):
        call_count["n"] += 1
        return _fake_energy_history(days, end_date)

    monkeypatch.setattr("energy.compute_energy_history", _counting)
    monkeypatch.setattr("db.get_profile", lambda: {"goal": "maintain"})
    import tdee
    _ = tdee.compute_target_calories_series(days=60, end_date=TODAY.isoformat())
    assert call_count["n"] == 1, (
        f"compute_target_calories_series doit faire 1 appel energy, got {call_count['n']}"
    )


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
