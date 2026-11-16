"""
Tests idempotence méditation (migration 106) — unit level, no DB.

Couvre :
- POST valide → 201, started_at normalisé transmis à la DB
- started_at absent / naïf / invalide → 400 (rien écrit)
- replay du même body → même ligne (chemin PostgREST data=[] + relecture)
- upsert sans data ET relecture vide → None (500), pas de succès inventé
- GET : erreur DB → 500 explicite ; aucune séance → [] ; limit invalide → 400
"""
from __future__ import annotations

import os
import sys

import pytest
from flask import Flask

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

import db
import db_core
import db_features
from routes.spirit import spirit_bp


# ── Fake client PostgREST (table meditation_sessions, UNIQUE started_at) ──────

class _Resp:
    def __init__(self, data): self.data = data


class _Query:
    def __init__(self, table, op, payload=None):
        self.t, self.op, self.payload, self.filters = table, op, payload, {}

    def eq(self, col, val): self.filters[col] = val; return self
    def limit(self, _n):    return self

    def execute(self):
        if self.op == "upsert":
            if any(r["started_at"] == self.payload["started_at"] for r in self.t.rows):
                return _Resp([])  # comportement PostgREST sur conflit ignore_duplicates
            row = {"id": f"id-{len(self.t.rows) + 1}", **self.payload}
            self.t.rows.append(row)
            return _Resp([dict(row)])
        if self.t.lose_rows:
            return _Resp([])
        return _Resp([dict(r) for r in self.t.rows
                      if all(r.get(k) == v for k, v in self.filters.items())])


class _Table:
    def __init__(self):
        self.rows: list[dict] = []
        self.lose_rows = False
        self.upsert_kwargs: dict = {}

    def upsert(self, payload, **kw):
        self.upsert_kwargs = kw
        return _Query(self, "upsert", payload)

    def select(self, *_a): return _Query(self, "select")


class _Client:
    def __init__(self): self.med = _Table()
    def table(self, name):
        assert name == "meditation_sessions"
        return self.med


@pytest.fixture
def client_db(monkeypatch):
    c = _Client()
    monkeypatch.setattr(db_core, "_client", c)
    monkeypatch.setattr(db_core, "MODE", "ONLINE")
    return c


@pytest.fixture
def http(monkeypatch):
    app = Flask(__name__)
    app.register_blueprint(spirit_bp)
    return app.test_client()


BODY = {"planned_sec": 600, "actual_sec": 600, "bell_interval": 300,
        "completed": True, "started_at": "2026-11-16T07:30:00-05:00"}


# ── log_meditation_session (vrai code DB, client simulé) ─────────────────────

def test_replay_same_started_at_returns_same_row(client_db):
    payload = {**BODY, "started_at": "2026-11-16T12:30:00+00:00"}
    r1 = db_features.log_meditation_session(dict(payload))
    r2 = db_features.log_meditation_session(dict(payload))
    assert r1["id"] == r2["id"]
    assert len(client_db.med.rows) == 1
    assert client_db.med.upsert_kwargs == {"on_conflict": "started_at", "ignore_duplicates": True}


def test_conflict_without_row_returns_none(client_db):
    payload = {**BODY, "started_at": "2026-11-16T12:30:00+00:00"}
    db_features.log_meditation_session(dict(payload))
    client_db.med.lose_rows = True  # upsert data=[] ET relecture vide
    assert db_features.log_meditation_session(dict(payload)) is None


# ── POST /api/spirit/meditation ──────────────────────────────────────────────

def test_post_valid_201_and_replay_same_id(http, client_db):
    r1 = http.post("/api/spirit/meditation", json=BODY)
    r2 = http.post("/api/spirit/meditation", json=BODY)
    assert r1.status_code == 201 and r2.status_code == 201
    assert r1.get_json()["id"] == r2.get_json()["id"]
    assert len(client_db.med.rows) == 1
    assert client_db.med.rows[0]["started_at"] == "2026-11-16T07:30:00-05:00"


def test_post_abandon_keeps_completed_false(http, client_db):
    r = http.post("/api/spirit/meditation",
                  json={**BODY, "actual_sec": 123, "completed": False})
    assert r.status_code == 201
    assert client_db.med.rows[0]["completed"] is False
    assert client_db.med.rows[0]["actual_sec"] == 123


@pytest.mark.parametrize("started_at", [None, "", "2026-11-16T07:30:00", "pas-une-date"])
def test_post_bad_started_at_400(http, client_db, started_at):
    body = {**BODY}
    if started_at is None:
        body.pop("started_at")
    else:
        body["started_at"] = started_at
    r = http.post("/api/spirit/meditation", json=body)
    assert r.status_code == 400
    assert client_db.med.rows == []


def test_post_db_failure_500(http, monkeypatch):
    monkeypatch.setattr(db, "log_meditation_session", lambda _p: None)
    assert http.post("/api/spirit/meditation", json=BODY).status_code == 500


# ── GET /api/spirit/meditation ───────────────────────────────────────────────

def test_get_db_error_is_500_not_empty_list(http, monkeypatch):
    monkeypatch.setattr(db, "get_meditation_sessions", lambda limit=60: None)
    r = http.get("/api/spirit/meditation")
    assert r.status_code == 500


def test_get_empty_is_empty_list(http, monkeypatch):
    monkeypatch.setattr(db, "get_meditation_sessions", lambda limit=60: [])
    r = http.get("/api/spirit/meditation")
    assert r.status_code == 200 and r.get_json() == []


def test_get_bad_limit_400(http):
    assert http.get("/api/spirit/meditation?limit=abc").status_code == 400
