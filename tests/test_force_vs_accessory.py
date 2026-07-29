"""Tests unitaires — _aggregate_force_vs_accessory_timeline (fonction pure)."""
from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

from db_stats import _aggregate_force_vs_accessory_timeline


def test_empty():
    assert _aggregate_force_vs_accessory_timeline([]) == []


def test_single_force_session():
    # 2026-07-20 = lundi → iso_week = même jour
    rows = [{"date": "2026-07-20", "session_category": "force", "total_volume": 12000}]
    assert _aggregate_force_vs_accessory_timeline(rows) == [
        {"iso_week": "2026-07-20", "session_category": "force",
         "avg_tonnage": 12000.0, "n_sessions": 1}
    ]


def test_avg_per_session_not_sum():
    # Point clé : MOYENNE par séance, pas la somme (10k+14k → 12k moyenne, pas 24k somme)
    rows = [
        {"date": "2026-07-20", "session_category": "force", "total_volume": 10000},
        {"date": "2026-07-22", "session_category": "force", "total_volume": 14000},
    ]
    result = _aggregate_force_vs_accessory_timeline(rows)
    assert result == [
        {"iso_week": "2026-07-20", "session_category": "force",
         "avg_tonnage": 12000.0, "n_sessions": 2}
    ]


def test_force_and_accessory_split_same_week():
    rows = [
        {"date": "2026-07-20", "session_category": "force",     "total_volume": 15000},
        {"date": "2026-07-21", "session_category": "accessory", "total_volume": 3000},
        {"date": "2026-07-23", "session_category": "force",     "total_volume": 11000},
    ]
    result = _aggregate_force_vs_accessory_timeline(rows)
    force = next(r for r in result if r["session_category"] == "force")
    accessory = next(r for r in result if r["session_category"] == "accessory")
    assert force["avg_tonnage"] == 13000.0 and force["n_sessions"] == 2
    assert accessory["avg_tonnage"] == 3000.0 and accessory["n_sessions"] == 1


def test_two_weeks_bucketed_by_monday():
    rows = [
        {"date": "2026-07-13", "session_category": "force", "total_volume": 10000},  # lundi sem 1
        {"date": "2026-07-15", "session_category": "force", "total_volume": 8000},   # mer sem 1
        {"date": "2026-07-20", "session_category": "force", "total_volume": 12000},  # lundi sem 2
    ]
    result = _aggregate_force_vs_accessory_timeline(rows)
    weeks = {r["iso_week"]: r for r in result}
    assert set(weeks) == {"2026-07-13", "2026-07-20"}
    assert weeks["2026-07-13"]["avg_tonnage"] == 9000.0  # (10000+8000)/2
    assert weeks["2026-07-13"]["n_sessions"] == 2
    assert weeks["2026-07-20"]["avg_tonnage"] == 12000.0


def test_ignores_unknown_null_and_empty_date():
    rows = [
        {"date": "2026-07-20", "session_category": "force",     "total_volume": 10000},
        {"date": "2026-07-21", "session_category": "unknown",   "total_volume": 5000},
        {"date": "2026-07-22", "session_category": "force",     "total_volume": None},
        {"date": "",           "session_category": "force",     "total_volume": 8000},
    ]
    assert _aggregate_force_vs_accessory_timeline(rows) == [
        {"iso_week": "2026-07-20", "session_category": "force",
         "avg_tonnage": 10000.0, "n_sessions": 1}
    ]


def test_result_sorted_stable():
    rows = [
        {"date": "2026-07-27", "session_category": "accessory", "total_volume": 2000},
        {"date": "2026-07-20", "session_category": "force",     "total_volume": 10000},
        {"date": "2026-07-20", "session_category": "accessory", "total_volume": 3000},
    ]
    result = _aggregate_force_vs_accessory_timeline(rows)
    keys = [(r["iso_week"], r["session_category"]) for r in result]
    assert keys == [
        ("2026-07-20", "accessory"),
        ("2026-07-20", "force"),
        ("2026-07-27", "accessory"),
    ]
