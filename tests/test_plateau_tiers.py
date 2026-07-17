"""Plateau detection — tests des doctrines (tiers, rep ranges, straight sets, caps).

Isole `_score` : monkeypatch _today_mtl, appelle directement avec sessions
construites à la main. Aucun accès DB, aucun fixture.
"""
import os
import sys
from datetime import date, timedelta

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

import plateau


TODAY = "2026-07-16"


def _sessions(specs):
    """specs = [(days_ago, weight, reps)] → sessions oldest→newest, e1RM pré-calculé."""
    today = date.fromisoformat(TODAY)
    out = []
    for days_ago, w, r in specs:
        d = (today - timedelta(days=days_ago)).isoformat()
        out.append({
            "date":       d,
            "weight_lbs": float(w),
            "reps":       int(r),
            "e1rm_lbs":   plateau._epley(float(w), int(r)),
        })
    out.sort(key=lambda x: x["date"])
    return out


def _freeze(monkeypatch):
    monkeypatch.setattr(plateau, "_today_mtl", lambda: TODAY)


# ── 1. compound_heavy avec reps DANS la fourchette du tier ────────────────────
def test_1_barbell_row_reps_in_range_no_ceiling(monkeypatch):
    """S4 rep_max=8 pour Barbell Row (compound_heavy 6-8). Reps 6→7→8 cyclique,
    aucune paire consécutive à 8 → ne déclenche pas ceiling. Score < 40."""
    _freeze(monkeypatch)
    sessions = _sessions([
        (21, 135, 6), (19, 135, 7), (17, 135, 8),
        (14, 135, 6), (12, 135, 7), (10, 135, 8),
        (7,  135, 6), (5,  135, 7), (3,  135, 8),
    ])
    info = plateau._score(sessions, "Barbell Row", "compound_heavy", "Dos")
    assert info["score"] < 40, f"faux positif reps dans le range : {info}"
    assert "rep_ceiling" not in info.get("flags", [])


# ── 2. compound_heavy straight sets — S3 neutralisé ───────────────────────────
def test_2_bench_repeated_sets_neutralized(monkeypatch):
    """Bench compound_heavy 6×(155,5) J-21→J-14 puis 3×(160,5) J-13→J-3.
    Sans fix : S3 +20 fait basculer à 40. Avec fix : S3=0 → score sous 40."""
    _freeze(monkeypatch)
    sessions = _sessions([
        (21, 155, 5), (19, 155, 5), (17, 155, 5),
        (16, 155, 5), (15, 155, 5), (14, 155, 5),
        (13, 160, 5), (8, 160, 5), (3, 160, 5),
    ])
    info = plateau._score(sessions, "Bench Press", "compound_heavy", "Pectoraux")
    assert info["score"] < 40, f"faux positif compound_heavy straight sets : {info}"
    assert "repeated_sets" not in info.get("flags", []), \
        "S3 doit être neutralisé pour compound_heavy"


# ── 3. wave modérée ───────────────────────────────────────────────────────────
def test_3_wave_moderate_no_alert(monkeypatch):
    """Wave 155×5 / 165×3 / 145×8 cyclique. e1RM ondulant sans progression
    réelle mais dans une bande étroite, pas de plateau."""
    _freeze(monkeypatch)
    sessions = _sessions([
        (21, 155, 5), (19, 165, 3), (17, 145, 8),
        (14, 155, 5), (12, 165, 3), (10, 145, 8),
        (7,  155, 5), (5,  165, 3), (3,  145, 8),
    ])
    info = plateau._score(sessions, "Bench Press", "compound_heavy", "Pectoraux")
    assert info["score"] < 40, f"faux positif wave : {info}"


# ── 4. vrai plateau isolation — S3 conservé ───────────────────────────────────
def test_4_isolation_true_plateau_detected(monkeypatch):
    """DB Curl isolation (30,10)×8. S3 doit rester +20 sur isolation, S1
    déclenche (aucune hausse). Vrai plateau, score ≥ 60."""
    _freeze(monkeypatch)
    sessions = _sessions([
        (21, 30, 10), (19, 30, 10), (17, 30, 10),
        (14, 30, 10), (10, 30, 10), (7, 30, 10),
        (5, 30, 10), (3, 30, 10),
    ])
    info = plateau._score(sessions, "DB Curl", "isolation", "Biceps")
    assert info["score"] >= 60, f"vrai plateau isolation raté : {info}"
    assert "repeated_sets" in info.get("flags", []), \
        "S3 doit rester actif pour isolation"


# ── 5. vrai plateau lower body — cap 5 lbs/sem ────────────────────────────────
def test_5_squat_quadriceps_true_plateau(monkeypatch):
    """Back Squat compound_heavy Quadriceps (200,5) plat 21j. Cap lower=5 →
    aucune hausse ≥ threshold → plateau détecté."""
    _freeze(monkeypatch)
    sessions = _sessions([
        (21, 200, 5), (19, 200, 5), (17, 200, 5),
        (14, 200, 5), (12, 200, 5), (10, 200, 5),
        (7,  200, 5), (5,  200, 5), (3,  200, 5),
    ])
    info = plateau._score(sessions, "Back Squat", "compound_heavy", "Quadriceps")
    assert info["score"] >= 40, f"vrai plateau lower raté : {info}"


# ── 6. cas frontière : Bench figé 21j, doit déclencher à 40 pile ──────────────
def test_6_bench_frozen_hits_advisory_threshold(monkeypatch):
    """Bench compound_heavy Pectoraux (155,5)×9 sur 21j — verrou pour vérifier
    que la neutralisation S3 ne rend PAS l'algo aveugle aux vrais plateaux
    haut du corps. Score = 40 pile (seuil advisory)."""
    _freeze(monkeypatch)
    sessions = _sessions([
        (21, 155, 5), (19, 155, 5), (17, 155, 5),
        (14, 155, 5), (12, 155, 5), (10, 155, 5),
        (7,  155, 5), (5,  155, 5), (3,  155, 5),
    ])
    info = plateau._score(sessions, "Bench Press", "compound_heavy", "Pectoraux")
    assert info["score"] == 40, f"seuil frontière raté : {info}"
