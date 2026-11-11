"""Test D8 (déséquilibre push/pull) : compare les muscles via _normalize_muscle,
donc les noms FR Title Case du catalogue post-fusion ("Pectoraux", "Dos",
"Épaules"…) matchent bien les groupes push/pull. Avant 2026-11, l'insight
comparait des mots anglais bruts contre des logs FR → 0 match, D8 jamais émis."""
import os, sys
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

from routes.proactive_insights import _check_d8


def _log(muscles, sets=4):
    return {"muscles": muscles, "sets_json": [{}] * sets}


def test_fr_catalog_names_detect_push_pull_imbalance():
    # 6 sessions Pectoraux (Push) × 4 sets vs 1 session Dos (Pull) × 4 sets
    # → push/pull = 24/4 = 6.0, bien hors de la bande 0.55-1.8 → insight émis.
    ex_logs = [_log(["Pectoraux"]) for _ in range(6)] + [_log(["Dos"])]
    out = _check_d8(ex_logs)
    assert out is not None, "D8 devrait émettre un déséquilibre push>>pull"
    assert out["dimension"] == "muscle_imbalance"
    assert "Push" in out["title"]
    assert out["data"]["push_sets"] == 24
    assert out["data"]["pull_sets"] == 4


def test_balanced_fr_catalog_returns_none():
    ex_logs = [_log(["Pectoraux"]) for _ in range(3)] + [_log(["Dos"]) for _ in range(3)]
    assert _check_d8(ex_logs) is None


def test_english_names_still_work():
    # Rétrocompat : si un ancien log a "chest"/"back" bruts, la normalisation
    # les mappe aux mêmes clés canoniques (chest, lats) — même verdict.
    ex_logs = [_log(["chest"]) for _ in range(6)] + [_log(["back"])]
    out = _check_d8(ex_logs)
    assert out is not None
    assert out["data"]["push_sets"] == 24
    assert out["data"]["pull_sets"] == 4
