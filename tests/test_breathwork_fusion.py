"""
Tests fusion breathwork (migrations 104/105) — unit level, no DB.

Couvre :
- log valide → session complète retournée
- replay idempotent → même started_at = réutilise l'existant
- technique_id inconnu → ValueError
- started_at absent/invalide → ValueError
- history retourne les séances ex-spirit (technique_id='478'/'box')
- spirit_engine.compute_spirit_axis fonctionne sur des séances SANS colonne protocol
"""
from __future__ import annotations

import os
import sys
from unittest.mock import patch

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

import breathwork
import db_wellness
import spirit_engine


# ── log_session : écriture et validation ─────────────────────────────────────

class _InMemoryBW:
    """Fake table breathwork_sessions avec UNIQUE(started_at).

    Reproduit le comportement PostgREST : upsert(ignore_duplicates=True) en
    conflit renvoie data = [] (pas la ligne existante). Le vrai code gère ça
    en relisant par started_at, ce chemin doit être exercé par les tests.
    """
    def __init__(self):
        self.rows: list[dict] = []

    def _find(self, started_at: str):
        return next((r for r in self.rows if r["started_at"] == started_at), None)

    def upsert(self, entry: dict):
        if self._find(entry["started_at"]) is not None:
            return []  # comportement PostgREST sur conflit
        self.rows.append(dict(entry))
        return [dict(entry)]

    def select_by_started_at(self, started_at: str):
        row = self._find(started_at)
        return [row] if row else []


@pytest.fixture
def fake_db(monkeypatch):
    table = _InMemoryBW()

    def _insert(entry: dict) -> dict | None:
        upserted = table.upsert(entry)
        if upserted:
            return upserted[0]
        existing = table.select_by_started_at(entry["started_at"])
        if not existing:
            raise RuntimeError("no row after conflict")
        return existing[0]

    monkeypatch.setattr(breathwork.db, "insert_breathwork_session", _insert)
    monkeypatch.setattr(
        breathwork._db_wellness, "get_breathwork_sessions", lambda days=30: list(table.rows)
    )
    return table


def test_log_valid_returns_session(fake_db):
    session = breathwork.log_session(
        technique_id="coherence",
        duration_sec=150,
        cycles=15,
        started_at="2026-11-15T09:00:00+00:00",
    )
    assert session["technique_id"] == "coherence"
    assert session["technique"] == "Cohérence cardiaque"
    assert session["duration_sec"] == 150
    assert session["cycles"] == 15
    assert session["date"] == "2026-11-15"
    assert len(fake_db.rows) == 1


def test_log_replay_same_started_at_is_idempotent(fake_db):
    s1 = breathwork.log_session("box", 64, 4, "2026-11-15T10:00:00+00:00")
    s2 = breathwork.log_session("box", 64, 4, "2026-11-15T10:00:00+00:00")
    assert s1["id"] == s2["id"]
    assert len(fake_db.rows) == 1


def test_log_unknown_technique_raises():
    with pytest.raises(ValueError, match="Technique inconnue"):
        breathwork.log_session("calm_storm", 60, 6, "2026-11-15T09:00:00+00:00")


def test_log_missing_started_at_raises():
    with pytest.raises(ValueError, match="started_at"):
        breathwork.log_session("coherence", 150, 15, "")


def test_log_naive_started_at_raises():
    with pytest.raises(ValueError, match="fuseau"):
        breathwork.log_session("coherence", 150, 15, "2026-11-15T09:00:00")


def test_history_returns_migrated_spirit_sessions(fake_db):
    breathwork.log_session("478",      76, 4, "2026-05-24T18:00:00+00:00")  # ex calm_storm
    breathwork.log_session("box",      64, 4, "2026-05-25T20:00:00+00:00")  # ex stillness
    breathwork.log_session("coherence", 150, 15, "2026-11-15T07:30:00+00:00")
    history = breathwork.get_history(days=365)
    tids = sorted(s["technique_id"] for s in history)
    assert tids == ["478", "box", "coherence"]


# ── spirit_engine : fonctionne sans colonne protocol ─────────────────────────

def test_compute_spirit_axis_no_protocol_column(monkeypatch):
    """Simule la DB post-migration 105 : rows sans clé 'protocol'."""
    bw_rows = [
        {"id": "a", "date": "2026-11-10", "technique_id": "coherence", "started_at": "2026-11-10T07:00:00+00:00"},
        {"id": "b", "date": "2026-11-11", "technique_id": "box",       "started_at": "2026-11-11T07:00:00+00:00"},
        {"id": "c", "date": "2026-11-03", "technique_id": "coherence", "started_at": "2026-11-03T07:00:00+00:00"},
    ]
    import db as _db
    monkeypatch.setattr(_db, "get_breathwork_sessions",       lambda days=30: bw_rows)
    monkeypatch.setattr(_db, "get_meditation_sessions",       lambda limit=60: [])
    monkeypatch.setattr(_db, "get_spirit_journal_entries",    lambda limit=30: [])

    last7  = {"2026-11-10", "2026-11-11", "2026-11-12", "2026-11-13"}
    prior7 = {"2026-11-03", "2026-11-04", "2026-11-05"}
    delta, details = spirit_engine.compute_spirit_axis(last7, prior7)
    assert details["breathwork_last"]  == 2
    assert details["breathwork_prior"] == 1
    assert isinstance(delta, float)


def test_compute_spirit_patterns_uses_technique_id(monkeypatch):
    """Vérifie que l'insight protocol_dominant est remplacé par technique_dominant."""
    bw_rows = [
        {"date": "2026-11-10", "technique_id": "coherence", "started_at": "2026-11-10T07:00:00+00:00"},
        {"date": "2026-11-11", "technique_id": "coherence", "started_at": "2026-11-11T07:00:00+00:00"},
        {"date": "2026-11-12", "technique_id": "box",       "started_at": "2026-11-12T07:00:00+00:00"},
    ]
    import db as _db
    monkeypatch.setattr(_db, "get_breathwork_sessions", lambda days=90: bw_rows)
    monkeypatch.setattr(_db, "get_meditation_sessions", lambda limit=200: [])
    monkeypatch.setattr(_db, "get_pss_records",         lambda limit=90: [])

    out = spirit_engine.compute_spirit_patterns()
    types = [i["type"] for i in out["insights"]]
    assert "technique_dominant" in types
    assert "protocol_dominant"  not in types
    dominant = next(i for i in out["insights"] if i["type"] == "technique_dominant")
    assert "Cohérence cardiaque" in dominant["body"]
