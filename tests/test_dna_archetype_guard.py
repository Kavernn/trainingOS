"""DNA _archetype — garde-fou piliers (lot f).

Garantit :
  1. Archétype calculé uniquement si PPL + Intensité + Constance sont
     tous `insufficient_data=False` et sans `error`.
  2. Si un pilier est insufficient ou en erreur → sentinel "insufficient"
     avec available=False. Zéro fallback 50 silencieux (ancien bug
     "builder" fantôme).
  3. Zéro valeur par défaut (.get("score", 50)) : si un pilier valide
     n'expose pas son score, archetype devient insufficient aussi.
"""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "api"))


def _ok_ppl(balance_score=70, legs_pct=30):
    return {
        "push_pct":          33, "pull_pct": 33, "legs_pct": legs_pct,
        "core_pct":          5,  "other_pct": 0,
        "balance_score":     balance_score,
        "verdict":           "Équilibré",
        "insufficient_data": False, "n_sessions": 20, "invalid_dates": 0,
    }


def _ok_intensity(score=65):
    return {
        "score":                    score,
        "label":                    "Power Builder",
        "force_pct":                50, "hypertrophy_pct": 40, "endurance_pct": 10,
        "compound_pct":             60, "isolation_pct":   40,
        "insufficient_data":        False, "n_sessions": 20,
        "excluded_no_load_profile": 0, "invalid_dates": 0,
    }


def _ok_consistency(score=70, spw=4.0):
    return {
        "score":                 score,
        "sessions_per_week":     spw,
        "cv":                    0.3,
        "archetype":             "Régulier",
        "weekly_streak_current": 3,
        "weekly_streak_best":    5,
        "active_weeks_pct":      90,
        "weekly_counts":         [4] * 13,
    }


def _insufficient():
    return {"insufficient_data": True, "n_sessions": 3}


def _error():
    return {"error": "DB down", "n_sessions": 0}


# ── 1. Archétype calculé quand les 3 piliers sont OK ────────────────────────

def test_archetype_available_when_three_pillars_ok():
    import workout_dna as _dna
    arch = _dna._archetype(_ok_ppl(), _ok_intensity(), _ok_consistency())
    assert arch["available"] is True
    assert arch["key"] != "insufficient"
    assert "label" in arch


# ── 2. Insufficient / error dans un pilier → sentinel ───────────────────────

def test_archetype_insufficient_when_ppl_insufficient():
    import workout_dna as _dna
    arch = _dna._archetype(_insufficient(), _ok_intensity(), _ok_consistency())
    assert arch["available"] is False
    assert arch["key"] == "insufficient"


def test_archetype_insufficient_when_intensity_insufficient():
    import workout_dna as _dna
    arch = _dna._archetype(_ok_ppl(), _insufficient(), _ok_consistency())
    assert arch["available"] is False
    assert arch["key"] == "insufficient"


def test_archetype_insufficient_when_consistency_insufficient():
    import workout_dna as _dna
    arch = _dna._archetype(_ok_ppl(), _ok_intensity(), _insufficient())
    assert arch["available"] is False


def test_archetype_insufficient_when_any_pillar_errored():
    import workout_dna as _dna
    assert _dna._archetype(_error(), _ok_intensity(), _ok_consistency())["available"] is False
    assert _dna._archetype(_ok_ppl(), _error(), _ok_consistency())["available"] is False
    assert _dna._archetype(_ok_ppl(), _ok_intensity(), _error())["available"] is False


# ── 3. Pas de fallback 50 : score manquant → sentinel ───────────────────────

def test_archetype_insufficient_when_any_score_missing():
    """Pilier valide mais sans score → plus de fallback 50 fantôme qui
    forçait le résultat sur 'builder'. Doit être traité comme insufficient."""
    import workout_dna as _dna

    ppl_no_balance = {**_ok_ppl(), "balance_score": None}
    arch = _dna._archetype(ppl_no_balance, _ok_intensity(), _ok_consistency())
    assert arch["available"] is False
    assert arch["key"] == "insufficient"

    intensity_no_score = {**_ok_intensity(), "score": None}
    arch = _dna._archetype(_ok_ppl(), intensity_no_score, _ok_consistency())
    assert arch["available"] is False

    consistency_no_score = {**_ok_consistency(), "score": None}
    arch = _dna._archetype(_ok_ppl(), _ok_intensity(), consistency_no_score)
    assert arch["available"] is False


# ── 4. Chaque archétype peut encore être atteint quand les scores sont là ──

def test_archetype_powerlifter_route():
    import workout_dna as _dna
    arch = _dna._archetype(_ok_ppl(balance_score=70), _ok_intensity(score=75), _ok_consistency(score=70))
    assert arch["key"] == "powerlifter"
    assert arch["available"] is True


def test_archetype_builder_route_when_no_other_match():
    """Scores "entre deux" → tombe sur builder par défaut. Toujours available
    tant que les 3 piliers sont valides."""
    import workout_dna as _dna
    arch = _dna._archetype(
        _ok_ppl(balance_score=50, legs_pct=15),
        _ok_intensity(score=35),
        _ok_consistency(score=55, spw=3.0),
    )
    assert arch["key"] == "builder"
    assert arch["available"] is True


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
