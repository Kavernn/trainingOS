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


# ── Correction 2 : fund_transfer inclus dans paid_by_debt ───────────────────

def test_paid_by_debt_includes_fund_transfer():
    """fund_transfer alimente fonds_voyage — même sommation que debt_payment.
    Remplace sum_debt_payments : agrégation Python sur un SELECT unique."""
    from budget_projection import _paid_by_debt
    logs = [
        {"date": "2026-07-16", "type": "fund_transfer", "debt_key": "fonds_voyage", "amount_cents": 5000},
        {"date": "2026-07-17", "type": "fund_transfer", "debt_key": "fonds_voyage", "amount_cents": 3000},
        {"date": "2026-07-18", "type": "fund_transfer", "debt_key": "fonds_voyage", "amount_cents": 2000},
        {"date": "2026-07-19", "type": "debt_payment",  "debt_key": "decouvert",    "amount_cents": 12345},
    ]
    result = _paid_by_debt(logs)
    assert result["fonds_voyage"] == 10000
    assert result["decouvert"] == 12345


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


# ── POST windfall (revenu surprise, split 80/20 côté iOS) ────────────────────

def test_post_windfall_missing_debt_returns_400(client):
    r = client.post("/api/budget/log", json={
        "date": "2026-07-16", "type": "windfall", "amount_cents": 8000,
    })
    assert r.status_code == 400


def test_post_windfall_with_envelope_returns_400(client):
    r = client.post("/api/budget/log", json={
        "date": "2026-07-16", "type": "windfall", "amount_cents": 8000,
        "debt_key": "decouvert", "envelope_key": "variable",
    })
    assert r.status_code == 400


def test_post_windfall_negative_returns_400(client):
    """Pas de contre-écriture windfall — corriger via debt_payment négatif + note."""
    r = client.post("/api/budget/log", json={
        "date": "2026-07-16", "type": "windfall", "amount_cents": -8000,
        "debt_key": "decouvert", "note": "test",
    })
    assert r.status_code == 400


def test_post_windfall_zero_returns_400(client):
    r = client.post("/api/budget/log", json={
        "date": "2026-07-16", "type": "windfall", "amount_cents": 0,
        "debt_key": "decouvert",
    })
    assert r.status_code == 400


def test_post_valid_windfall_returns_201(client):
    r = client.post("/api/budget/log", json={
        "date": "2026-07-16", "type": "windfall", "amount_cents": 8000,
        "debt_key": "decouvert",
    })
    assert r.status_code == 201


# ── Payload : is_payday_today + today_transfers ─────────────────────────────

class FakeStatusDB:
    """Fake db_budget pour compute_status — logs paramétrables, DB vide sinon."""
    def __init__(self, logs=None):
        self.logs = logs or []
    def get_envelopes(self): return []
    def get_debt_accounts(self): return []
    def list_debt_and_fund_logs_since(self, _iso): return self.logs
    def sum_expenses_by_envelope(self, _s, _e): return {}
    def get_last_income_date(self): return None
    # False = backfill no-op dans les tests, voulu (aucun effet de bord DB).
    def insert_income_if_absent(self, _iso, _cents): return False


@pytest.fixture
def status_db(monkeypatch):
    fake = FakeStatusDB()
    monkeypatch.setattr(budget, "db_budget", fake)
    return fake


def _set_today(monkeypatch, today):
    monkeypatch.setattr(budget, "_today_mtl_date", lambda: today)


def test_is_payday_today_true_on_payday(status_db, monkeypatch):
    """2026-07-15 = paie du 15 → is_payday_today True (start == today)."""
    _set_today(monkeypatch, date(2026, 7, 15))
    payload = budget.compute_status()
    assert payload["is_payday_today"] is True


def test_is_payday_today_false_off_payday(status_db, monkeypatch):
    """2026-07-20 = milieu de période → is_payday_today False."""
    _set_today(monkeypatch, date(2026, 7, 20))
    payload = budget.compute_status()
    assert payload["is_payday_today"] is False


def test_today_transfers_empty(status_db, monkeypatch):
    _set_today(monkeypatch, date(2026, 7, 20))
    payload = budget.compute_status()
    assert payload["today_transfers"] == []


def test_today_transfers_includes_fund_transfer(status_db, monkeypatch):
    _set_today(monkeypatch, date(2026, 7, 20))
    status_db.logs = [
        {"date": "2026-07-20", "type": "fund_transfer",
         "debt_key": "fonds_voyage", "envelope_key": None, "amount_cents": 37500},
    ]
    payload = budget.compute_status()
    assert payload["today_transfers"] == [
        {"type": "fund_transfer", "debt_key": "fonds_voyage",
         "envelope_key": None, "amount_cents": 37500},
    ]


def test_today_transfers_includes_debt_payment(status_db, monkeypatch):
    _set_today(monkeypatch, date(2026, 7, 20))
    status_db.logs = [
        {"date": "2026-07-20", "type": "debt_payment",
         "debt_key": "decouvert", "envelope_key": None, "amount_cents": 45781},
    ]
    payload = budget.compute_status()
    assert payload["today_transfers"] == [
        {"type": "debt_payment", "debt_key": "decouvert",
         "envelope_key": None, "amount_cents": 45781},
    ]


def test_today_transfers_includes_expense(status_db, monkeypatch):
    """Expense (hypothèque payday) doit être coché comme les transferts."""
    _set_today(monkeypatch, date(2026, 7, 20))
    status_db.logs = [
        {"date": "2026-07-20", "type": "expense",
         "debt_key": None, "envelope_key": "fixes", "amount_cents": 45000},
    ]
    payload = budget.compute_status()
    assert payload["today_transfers"] == [
        {"type": "expense", "debt_key": None,
         "envelope_key": "fixes", "amount_cents": 45000},
    ]


def test_today_transfers_excludes_windfall(status_db, monkeypatch):
    """Windfall n'est pas un transfert planifié — exclu même s'il est loggé aujourd'hui."""
    _set_today(monkeypatch, date(2026, 7, 20))
    status_db.logs = [
        {"date": "2026-07-20", "type": "windfall",
         "debt_key": "decouvert", "amount_cents": 8000},
    ]
    payload = budget.compute_status()
    assert payload["today_transfers"] == []


def test_today_transfers_excludes_negative_amounts(status_db, monkeypatch):
    """Contre-écriture seule ne doit pas cocher un item payday (transfert net nul)."""
    _set_today(monkeypatch, date(2026, 7, 20))
    status_db.logs = [
        {"date": "2026-07-20", "type": "fund_transfer",
         "debt_key": "fonds_voyage", "amount_cents": -37500},
    ]
    payload = budget.compute_status()
    assert payload["today_transfers"] == []


def test_today_net_spent_nets_contre_ecriture(status_db, monkeypatch):
    """Positif + contre-écriture même montant → net 0 (solde live intact)."""
    _set_today(monkeypatch, date(2026, 7, 20))
    status_db.logs = [
        {"date": "2026-07-20", "type": "debt_payment",
         "debt_key": "decouvert", "amount_cents": 57000},
        {"date": "2026-07-20", "type": "debt_payment",
         "debt_key": "decouvert", "amount_cents": -57000},
    ]
    payload = budget.compute_status()
    assert payload["today_net_spent_cents"] == 0


def test_today_net_spent_excludes_windfall_and_income(status_db, monkeypatch):
    """Windfall (surprise) et income (entrée paie) hors somme."""
    _set_today(monkeypatch, date(2026, 7, 20))
    status_db.logs = [
        {"date": "2026-07-20", "type": "windfall",
         "debt_key": "decouvert", "amount_cents": 8000},
        {"date": "2026-07-20", "type": "expense",
         "envelope_key": "fixes", "amount_cents": 45000},
    ]
    payload = budget.compute_status()
    assert payload["today_net_spent_cents"] == 45000
