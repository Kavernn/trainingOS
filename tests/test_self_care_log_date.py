"""
Tests self_care.log_for_date (date client obligatoire + validation fenêtre).

Blocs couverts :
- date valide (today, hier) → écrit sur cette date
- date future → ValueError
- date > today - 7 jours → ValueError
- date absente / mal formée → ValueError
- replay idempotent : même body → même état final (DELETE+INSERT atomique sur la date)
"""
from __future__ import annotations

import os
import sys
from datetime import date, timedelta

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

import self_care


class _FakeDB:
    def __init__(self, habits):
        self._habits = list(habits)
        self.log: dict[str, list[str]] = {}
        self._client = object()  # non-None → get_habits ne re-seed pas les defaults

    # Habits
    def get_self_care_habits(self): return list(self._habits)
    def upsert_self_care_habit(self, h): self._habits.append(h)
    def delete_self_care_habit(self, hid):
        self._habits = [h for h in self._habits if h["id"] != hid]
        return True

    # Logs
    def set_self_care_log_for_date(self, date_str, habit_ids):
        self.log[date_str] = list(habit_ids)
        return True

    def get_self_care_log(self, days):
        return dict(self.log)


@pytest.fixture
def today_iso():
    return date.today().isoformat()


@pytest.fixture
def fake_db(monkeypatch, today_iso):
    db = _FakeDB(habits=[
        {"id": "walk",  "name": "Marcher",   "icon": "figure.walk", "category": "physique", "is_default": True},
        {"id": "water", "name": "Boire 2L",  "icon": "drop.fill",   "category": "physique", "is_default": True},
    ])
    monkeypatch.setattr(self_care, "db", db)
    monkeypatch.setattr(self_care, "_today_mtl", lambda: today_iso)
    return db


def test_log_today_writes_on_that_date(fake_db, today_iso):
    out = self_care.log_for_date(today_iso, ["walk"])
    assert fake_db.log[today_iso] == ["walk"]
    assert out["completed"] == ["walk"]


def test_log_yesterday_allowed(fake_db, today_iso):
    yesterday = (date.fromisoformat(today_iso) - timedelta(days=1)).isoformat()
    self_care.log_for_date(yesterday, ["water"])
    assert fake_db.log[yesterday] == ["water"]


def test_log_future_date_raises(fake_db, today_iso):
    tomorrow = (date.fromisoformat(today_iso) + timedelta(days=1)).isoformat()
    with pytest.raises(ValueError, match="future"):
        self_care.log_for_date(tomorrow, ["walk"])


def test_log_too_old_raises(fake_db, today_iso):
    old = (date.fromisoformat(today_iso) - timedelta(days=8)).isoformat()
    with pytest.raises(ValueError, match="trop ancienne"):
        self_care.log_for_date(old, ["walk"])


def test_log_missing_date_raises(fake_db):
    with pytest.raises(ValueError, match="date invalide"):
        self_care.log_for_date("", ["walk"])


def test_log_malformed_date_raises(fake_db):
    with pytest.raises(ValueError, match="date invalide"):
        self_care.log_for_date("15/11/2026", ["walk"])


def test_replay_same_body_is_idempotent(fake_db, today_iso):
    self_care.log_for_date(today_iso, ["walk", "water"])
    state1 = dict(fake_db.log)
    self_care.log_for_date(today_iso, ["walk", "water"])
    assert fake_db.log == state1
    assert sorted(fake_db.log[today_iso]) == ["walk", "water"]


def test_filters_unknown_habit_ids(fake_db, today_iso):
    self_care.log_for_date(today_iso, ["walk", "bogus"])
    assert fake_db.log[today_iso] == ["walk"]
