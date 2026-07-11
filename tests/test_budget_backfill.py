"""Tests backfill + sum_debt_payments + validations POST /api/budget/log.

Imports plats (conftest.py L11 ajoute api/ au sys.path) — même objet module
que celui référencé par routes/budget.py.
"""
from __future__ import annotations
import sys
from datetime import date
from unittest.mock import patch, MagicMock

import pytest

import budget
import db_budget


class FakeBudgetDB:
    def __init__(self, last_income=None):
        self.last_income = last_income
        self.inserted: list[tuple[str, int]] = []

    def get_last_income_date(self):
        return self.last_income

    def insert_income_if_absent(self, date_iso, cents):
        if any(d == date_iso for d, _ in self.inserted):
            return False
        self.inserted.append((date_iso, cents))
        return True


@pytest.fixture
def fake_db(monkeypatch):
    fake = FakeBudgetDB()
    monkeypatch.setattr(budget, "db_budget", fake)
    return fake


# ── Backfill ────────────────────────────────────────────────────────────────

def test_backfill_before_plan_start_inserts_nothing(fake_db):
    """11 juillet 2026 < PLAN_START (2026-07-15) → 0 insertion."""
    assert budget.backfill_incomes(today=date(2026, 7, 11)) == 0
    assert fake_db.inserted == []


def test_backfill_on_plan_start_inserts_one(fake_db):
    """16 juillet 2026 → une paie (2026-07-15)."""
    assert budget.backfill_incomes(today=date(2026, 7, 16)) == 1
    assert fake_db.inserted == [("2026-07-15", 174391)]


def test_backfill_multi_paies(fake_db):
    """5 août 2026 → 2 paies (15/07, 30/07)."""
    assert budget.backfill_incomes(today=date(2026, 8, 5)) == 2
    assert fake_db.inserted == [("2026-07-15", 174391), ("2026-07-30", 174391)]


def test_backfill_idempotent_second_call(fake_db):
    budget.backfill_incomes(today=date(2026, 8, 5))
    fake_db.last_income = "2026-07-30"
    assert budget.backfill_incomes(today=date(2026, 8, 5)) == 0


def test_backfill_incremental_after_last(fake_db):
    fake_db.last_income = "2026-07-15"
    n = budget.backfill_incomes(today=date(2026, 8, 5))
    assert n == 1
    assert fake_db.inserted == [("2026-07-30", 174391)]


# ── Correction 2 : fund_transfer inclus ─────────────────────────────────────

def test_sum_debt_payments_includes_fund_transfer(monkeypatch):
    """fund_transfer alimente les fonds d'épargne (fonds_voyage)."""
    import db_core

    class FakeTable:
        def select(self, *a, **k): return self
        def eq(self, k, v):        return self
        def in_(self, k, vs):      return self
        def execute(self):
            return type("R", (), {"data": [
                {"amount_cents": 5000},
                {"amount_cents": 3000},
                {"amount_cents": 2000},
            ]})()

    class FakeClient:
        def table(self, name): return FakeTable()

    monkeypatch.setattr(db_core, "_client", FakeClient())
    monkeypatch.setattr(db_core, "MODE", "SUPABASE")
    assert db_budget.sum_debt_payments("fonds_voyage") == 10000


# ── POST /api/budget/log validations ────────────────────────────────────────

_MODULES_TO_EVICT_FOR_APP = {
    "index", "routes", "routes.budget", "budget", "db_budget",
}


@pytest.fixture
def client():
    """Flask test client — pattern conftest.BaseRouteTest : mock db_mock global
    + eviction pour forcer re-import propre + stub de db_budget.insert_log."""
    db_mock = MagicMock()
    db_patch = patch.dict("sys.modules", {"db": db_mock})
    db_patch.start()
    try:
        for mod in list(sys.modules.keys()):
            if mod in _MODULES_TO_EVICT_FOR_APP:
                del sys.modules[mod]

        import db_budget as _dbb
        _dbb.insert_log = lambda entry: True

        import index
        app = index.app
        app.config["TESTING"] = True
        yield app.test_client()
    finally:
        db_patch.stop()


def test_post_expense_missing_envelope_returns_400(client):
    r = client.post("/api/budget/log", json={
        "date": "2026-07-16", "type": "expense", "amount_cents": 1500,
    })
    assert r.status_code == 400


def test_post_expense_with_debt_key_returns_400(client):
    r = client.post("/api/budget/log", json={
        "date": "2026-07-16", "type": "expense", "amount_cents": 1500,
        "envelope_key": "epicerie", "debt_key": "carte",
    })
    assert r.status_code == 400


def test_post_debt_payment_missing_debt_returns_400(client):
    r = client.post("/api/budget/log", json={
        "date": "2026-07-16", "type": "debt_payment", "amount_cents": 10000,
    })
    assert r.status_code == 400


def test_post_fund_transfer_with_envelope_returns_400(client):
    r = client.post("/api/budget/log", json={
        "date": "2026-07-16", "type": "fund_transfer", "amount_cents": 5000,
        "envelope_key": "variable", "debt_key": "fonds_voyage",
    })
    assert r.status_code == 400


def test_post_income_type_rejected(client):
    r = client.post("/api/budget/log", json={
        "date": "2026-07-16", "type": "income", "amount_cents": 174391,
    })
    assert r.status_code == 400


def test_post_negative_without_note_returns_400(client):
    r = client.post("/api/budget/log", json={
        "date": "2026-07-16", "type": "expense", "amount_cents": -500,
        "envelope_key": "epicerie",
    })
    assert r.status_code == 400


def test_post_negative_with_note_returns_201(client):
    r = client.post("/api/budget/log", json={
        "date": "2026-07-16", "type": "expense", "amount_cents": -500,
        "envelope_key": "epicerie", "note": "correction saisie doublon",
    })
    assert r.status_code == 201


def test_post_valid_expense_returns_201(client):
    r = client.post("/api/budget/log", json={
        "date": "2026-07-16", "type": "expense", "amount_cents": 2500,
        "envelope_key": "epicerie",
    })
    assert r.status_code == 201


def test_post_valid_debt_payment_returns_201(client):
    r = client.post("/api/budget/log", json={
        "date": "2026-07-16", "type": "debt_payment", "amount_cents": 5000,
        "debt_key": "decouvert",
    })
    assert r.status_code == 201


def test_post_valid_fund_transfer_returns_201(client):
    r = client.post("/api/budget/log", json={
        "date": "2026-07-16", "type": "fund_transfer", "amount_cents": 10000,
        "debt_key": "fonds_voyage",
    })
    assert r.status_code == 201
