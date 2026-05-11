"""
Tests unitaires — ACWR EWMA Engine
Toutes les fonctions testées sont pures (pas d'appels DB).
"""
from __future__ import annotations

import math
import sys
import os
from datetime import date, timedelta

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

# Import des fonctions internes (toutes pures, testables sans DB)
from api.acwr import (
    _session_load,
    _aggregate_daily,
    _spike_cap,
    _run_ewma,
    _weekly_snapshots,
    _zone_code,
    ACUTE_DAYS,
    CHRONIC_DAYS,
    RATIO_MAX,
)

TODAY = date.today()


def make_row(days_ago: int, rpe: float = 7.0, dur: float = 60.0,
             tonnage: float = 0.0) -> dict:
    return {
        "date": (TODAY - timedelta(days=days_ago)).isoformat(),
        "rpe": rpe,
        "duration_min": dur,
        "session_volume": tonnage,
    }


def steady_rows(n_days: int, rpe=7.0, dur=60.0, step=2) -> list[dict]:
    """Entraînement régulier tous les `step` jours."""
    return [make_row(i, rpe, dur) for i in range(0, n_days, step)]


# ─────────────────────────────────────────────────────────────
# Session Load
# ─────────────────────────────────────────────────────────────

class TestSessionLoad:
    def test_srpe_method(self):
        assert _session_load(7.0, 60.0, None) == pytest.approx(420.0)

    def test_srpe_method_zero_duration(self):
        assert _session_load(7.0, 0.0, None) == 0.0

    def test_tonnage_fallback(self):
        load = _session_load(None, None, 1000.0)
        assert load > 0
        assert load == pytest.approx(math.log1p(1000.0) * 10)

    def test_no_data_returns_zero(self):
        assert _session_load(None, None, None) == 0.0
        assert _session_load(None, None, 0.0) == 0.0

    def test_srpe_takes_priority_over_tonnage(self):
        load_srpe    = _session_load(7.0, 60.0, 5000.0)
        load_tonnage = _session_load(None, None, 5000.0)
        assert load_srpe == pytest.approx(420.0)
        assert load_srpe != load_tonnage


# ─────────────────────────────────────────────────────────────
# Agrégation journalière
# ─────────────────────────────────────────────────────────────

class TestAggregateDaily:
    def test_single_session(self):
        rows = [make_row(1, rpe=7, dur=60)]
        daily = _aggregate_daily(rows)
        assert len(daily) == 1
        assert list(daily.values())[0] == pytest.approx(420.0)

    def test_two_sessions_same_day(self):
        d = (TODAY - timedelta(days=1)).isoformat()
        rows = [
            {"date": d, "rpe": 6.0, "duration_min": 45.0, "session_volume": 0},
            {"date": d, "rpe": 5.0, "duration_min": 30.0, "session_volume": 0},
        ]
        daily = _aggregate_daily(rows)
        assert daily[d] == pytest.approx(6 * 45 + 5 * 30)

    def test_missing_date_skipped(self):
        rows = [{"date": None, "rpe": 7.0, "duration_min": 60.0, "session_volume": 0}]
        assert _aggregate_daily(rows) == {}


# ─────────────────────────────────────────────────────────────
# Spike Cap
# ─────────────────────────────────────────────────────────────

class TestSpikeCap:
    def test_none_with_few_points(self):
        assert _spike_cap([100, 200, 300]) is None

    def test_cap_computed_with_enough_points(self):
        loads = [400.0] * 10
        cap = _spike_cap(loads)
        assert cap is not None
        # std=0 → cap = 400 + 3×0 = 400
        assert cap == pytest.approx(400.0)

    def test_outlier_would_exceed_cap(self):
        normal = [400.0] * 10
        cap = _spike_cap(normal)
        outlier = 2000.0
        assert outlier > cap


# ─────────────────────────────────────────────────────────────
# EWMA Engine
# ─────────────────────────────────────────────────────────────

class TestEWMA:
    def test_empty_returns_empty(self):
        assert _run_ewma({}) == []

    def test_insufficient_data_neutral_ratio(self):
        """< ACUTE_DAYS jours → ratio=1.0, zone=insufficient_data."""
        rows = [make_row(3)]
        daily = _aggregate_daily(rows)
        series = _run_ewma(daily)
        last = series[-1]
        assert last["ratio"] == pytest.approx(1.0)
        assert last["zone_code"] == "insufficient_data"
        assert last["confidence"] == "low"

    def test_moderate_confidence_after_acute_window(self):
        rows = steady_rows(ACUTE_DAYS + 2)
        daily = _aggregate_daily(rows)
        series = _run_ewma(daily)
        last = series[-1]
        assert last["confidence"] == "moderate"

    def test_high_confidence_after_chronic_window(self):
        rows = steady_rows(CHRONIC_DAYS + 2)
        daily = _aggregate_daily(rows)
        series = _run_ewma(daily)
        last = series[-1]
        assert last["confidence"] == "high"

    def test_steady_training_optimal_zone(self):
        """4 semaines d'entraînement régulier → zone optimale."""
        rows = steady_rows(60, rpe=7.0, dur=60.0, step=2)
        daily = _aggregate_daily(rows)
        series = _run_ewma(daily)
        last = series[-1]
        assert last["zone_code"] == "optimal"
        assert last["confidence"] == "high"

    def test_rest_days_decay_acute(self):
        """EWMA acute décroît naturellement sur les jours de repos."""
        rows = [make_row(10, rpe=9, dur=90)]
        daily = _aggregate_daily(rows)
        series = _run_ewma(daily)
        # Trouver le jour de la séance et aujourd'hui
        first_loaded = next(p for p in series if p["acute_load"] > 0)
        last = series[-1]
        assert last["acute_load"] < first_loaded["acute_load"]

    def test_spike_triggers_caution_or_danger(self):
        """Base solide + semaine intensive → caution ou danger."""
        base  = [make_row(i, rpe=6.0, dur=60.0) for i in range(7, 45, 2)]
        spike = [make_row(i, rpe=9.5, dur=120.0) for i in range(0, 7)]
        daily = _aggregate_daily(base + spike)
        series = _run_ewma(daily)
        last = series[-1]
        assert last["zone_code"] in ("caution", "danger")

    def test_ratio_hard_clamped_at_max(self):
        """Ratio ne dépasse jamais RATIO_MAX=3.0."""
        base    = [make_row(i, rpe=2.0, dur=20.0) for i in range(5, 40)]
        extreme = [make_row(0, rpe=10.0, dur=300.0)]
        daily   = _aggregate_daily(base + extreme)
        series  = _run_ewma(daily)
        assert all(p["ratio"] <= RATIO_MAX for p in series)

    def test_no_division_by_zero(self):
        """Nouvel utilisateur avec 1 seule séance — pas de crash."""
        daily = _aggregate_daily([make_row(1)])
        series = _run_ewma(daily)
        assert len(series) > 0
        assert series[-1]["ratio"] == pytest.approx(1.0)

    def test_chronic_floor_prevents_absurd_ratio(self):
        """ewma_c < CHRONIC_FLOOR → ratio forcé à 1.0."""
        # 1 séance il y a 25 jours (ewma_c très bas car peu de données)
        daily = _aggregate_daily([make_row(25, rpe=9, dur=90)])
        series = _run_ewma(daily)
        for pt in series:
            if pt["confidence"] == "low":
                assert pt["ratio"] == pytest.approx(1.0)


# ─────────────────────────────────────────────────────────────
# Weekly Snapshots
# ─────────────────────────────────────────────────────────────

class TestWeeklySnapshots:
    def test_max_8_weeks(self):
        rows = steady_rows(90)
        daily = _aggregate_daily(rows)
        series = _run_ewma(daily)
        snaps = _weekly_snapshots(series, n_weeks=8)
        assert len(snaps) <= 8

    def test_correct_keys(self):
        rows = steady_rows(60)
        daily = _aggregate_daily(rows)
        series = _run_ewma(daily)
        snaps = _weekly_snapshots(series)
        assert all({"week", "ratio", "acute", "chronic"} <= set(s.keys()) for s in snaps)

    def test_weeks_labeled_sequentially(self):
        rows = steady_rows(60)
        daily = _aggregate_daily(rows)
        series = _run_ewma(daily)
        snaps = _weekly_snapshots(series, n_weeks=4)
        assert [s["week"] for s in snaps] == ["W1", "W2", "W3", "W4"]


# ─────────────────────────────────────────────────────────────
# Zone Classification
# ─────────────────────────────────────────────────────────────

class TestZoneCode:
    @pytest.mark.parametrize("ratio,expected", [
        (0.0,  "under"),
        (0.79, "under"),
        (0.80, "optimal"),
        (1.30, "optimal"),
        (1.31, "caution"),
        (1.50, "caution"),
        (1.51, "danger"),
        (2.50, "danger"),
    ])
    def test_thresholds(self, ratio, expected):
        assert _zone_code(ratio) == expected


# ─────────────────────────────────────────────────────────────
# Exemple chiffré commenté
# ─────────────────────────────────────────────────────────────

def test_example_printed(capsys):
    """
    Athlète type : 5 semaines de base (RPE 7 × 60 min, 3×/sem)
    puis 1 semaine intensive (RPE 9 × 90 min, 5×/sem).

    Attendu :
      - chronic stable ≈ 120-150 AU (régime permanent ~λ/(1-(1-λ)^28))
      - acute monte rapidement avec λ=0.25
      - ratio > 1.3 → caution ou danger
    """
    base  = [make_row(i, rpe=7.0, dur=60.0) for i in range(7, 42, 2)]
    spike = [make_row(i, rpe=9.0, dur=90.0) for i in range(0, 7)]
    daily = _aggregate_daily(base + spike)
    series = _run_ewma(daily)
    last = series[-1]

    print(f"\nAcute:   {last['acute_load']:.1f} AU")
    print(f"Chronic: {last['chronic_load']:.1f} AU")
    print(f"Ratio:   {last['ratio']:.3f}")
    print(f"Zone:    {last['zone_code']}")
    print(f"Confiance: {last['confidence']}")

    assert last["zone_code"] in ("caution", "danger")
    assert last["confidence"] == "high"
    assert last["acute_load"] > last["chronic_load"]
