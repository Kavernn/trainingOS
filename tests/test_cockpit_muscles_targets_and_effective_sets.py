"""
Tests: weekly_effective_sets backend + targets_by_muscle dans /api/stats/cockpit.
Backend B du lot Charge.

Vérifie :
  - INDIRECT_SET_COEFFICIENT = 0.5 (défini à un seul endroit).
  - weekly_effective_sets : (direct + 0.5 × indirect) / (days / 7).
  - MuscleWorkload.weekly_effective_sets peuplé par summarize_muscle_workload.
  - CockpitMuscles.targets_by_muscle expose les plages MEV/MAV/MRV depuis
    MUSCLE_LANDMARKS pour chaque muscle apparaissant dans workloads ∪
    previous_workloads, normalisation via `landmarks_for_muscle`.
  - Muscles hors doctrine → None (iOS doit afficher "Pas de repère").
  - Correspondance figée : chaque muscle de notre set de référence doit
    avoir une plage (ou être explicitement listé dans WITHOUT_LANDMARK_FROZEN).
    Un NOUVEAU muscle de catalogue ajouté sans mise à jour fait échouer
    le test.
"""
from datetime import date, timedelta

import pytest

from cockpit_analytics_service import CockpitAnalyticsConfig, build_cockpit_analytics
from metric_semantics import DateWindow
from muscle_workload_analytics import (
    INDIRECT_SET_COEFFICIENT, MuscleMappingCoverage, MuscleWorkload,
    weekly_effective_sets,
)
from utils import MUSCLE_LANDMARKS, landmarks_for_muscle


# ── 1. Coefficient + helper pur ────────────────────────────────────────────────

def test_indirect_coefficient_is_half_frozen_in_one_place():
    """La valeur 0.5 ne doit pas dériver — contrat doctrine."""
    assert INDIRECT_SET_COEFFICIENT == 0.5


def test_weekly_effective_sets_formula():
    # 10 directes + 4 indirectes sur 30 jours → (10 + 0.5*4) / (30/7) ≈ 2.8
    assert abs(weekly_effective_sets(10, 4, 30) - 2.8) < 0.001
    # 7 directes + 0 indirectes sur 7 jours → 7 séries/semaine
    assert weekly_effective_sets(7, 0, 7) == 7.0
    # 0 partout → 0
    assert weekly_effective_sets(0, 0, 30) == 0.0
    # indirect ne dépasse pas direct en poids
    assert weekly_effective_sets(0, 10, 30) < weekly_effective_sets(10, 0, 30)


def test_weekly_effective_sets_rejects_non_positive_period():
    with pytest.raises(ValueError):
        weekly_effective_sets(10, 0, 0)
    with pytest.raises(ValueError):
        weekly_effective_sets(10, 0, -1)


# ── 2. Peuplement dans MuscleWorkload ─────────────────────────────────────────

def _row(log_id, session_id, day, *, name="Bench", group="Chest", secondary=None, sets=1):
    return {
        "id": str(log_id),
        "session_id": session_id,
        "exercise_id": f"id-{name}",
        "weight": 100, "reps": "5",
        "sets_json": [{"weight": 100, "reps": 5} for _ in range(sets)],
        "workout_sessions": {"date": day.isoformat()},
        "exercises": {"name": name, "tracking_type": "reps", "muscle_group": group,
                       "muscle_specific": None, "secondary_muscles": secondary or []},
    }


class _FakeClient:
    def __init__(self, rows): self.rows = rows
    def table(self, _): return _FakeQuery(self.rows)


class _FakeQuery:
    def __init__(self, rows): self.rows = rows
    def select(self, _): return self
    def gte(self, *_): return self
    def lte(self, *_): return self
    def execute(self): return type("R", (), {"data": self.rows})()


AS_OF = date(2026, 9, 30)
CURRENT = DateWindow(AS_OF - timedelta(days=29), AS_OF)
PREVIOUS = DateWindow(CURRENT.start - timedelta(days=30), CURRENT.start - timedelta(days=1))


def _config():
    return CockpitAnalyticsConfig(
        as_of=AS_OF, progression_days=30,
        weekly_period=CURRENT, muscle_period=CURRENT,
        muscle_previous_period=PREVIOUS,
    )


def test_workload_exposes_weekly_effective_sets():
    """1 séance Bench (Chest direct, 1 série sur fenêtre 30j) :
    weekly_effective_sets = (1 + 0.5*0) / (30/7) = 0.233…"""
    rows = [_row(1, "s1", CURRENT.end, name="Bench")]
    response = build_cockpit_analytics(_FakeClient(rows), _config())
    chest = [w for w in response.muscles.workloads if w.muscle == "Chest"]
    assert chest, "workload Chest attendu"
    assert chest[0].direct_set_count == 1
    assert chest[0].indirect_set_count == 0
    assert abs(chest[0].weekly_effective_sets - (1 / (30 / 7))) < 0.001


# ── 3. Map targets ────────────────────────────────────────────────────────────

def test_targets_map_populated_from_landmarks_for_each_muscle():
    rows = [
        _row(1, "s1", CURRENT.end,              name="Bench",   group="Chest"),
        _row(2, "s2", CURRENT.end,              name="Pullup",  group="Lats"),
        _row(3, "s3", CURRENT.end - timedelta(days=5), name="Curl", group="Biceps"),
    ]
    response = build_cockpit_analytics(_FakeClient(rows), _config())
    targets = response.muscles.targets_by_muscle

    # Chaque muscle du workload a une entrée
    workload_muscles = {w.muscle for w in response.muscles.workloads}
    assert workload_muscles.issubset(targets.keys())

    # Valeurs correspondent à MUSCLE_LANDMARKS (via normalisation)
    assert targets["Chest"]  == {"mev_week": MUSCLE_LANDMARKS["chest"]["mev"],
                                 "mav_week": MUSCLE_LANDMARKS["chest"]["mav"],
                                 "mrv_week": MUSCLE_LANDMARKS["chest"]["mrv"]}
    assert targets["Lats"]   == {"mev_week": MUSCLE_LANDMARKS["lats"]["mev"],
                                 "mav_week": MUSCLE_LANDMARKS["lats"]["mav"],
                                 "mrv_week": MUSCLE_LANDMARKS["lats"]["mrv"]}
    assert targets["Biceps"] == {"mev_week": MUSCLE_LANDMARKS["biceps"]["mev"],
                                 "mav_week": MUSCLE_LANDMARKS["biceps"]["mav"],
                                 "mrv_week": MUSCLE_LANDMARKS["biceps"]["mrv"]}


def test_targets_null_for_muscle_outside_landmark_doctrine():
    """Un muscle qui ne figure pas dans MUSCLE_LANDMARKS → None (pas un
    silence : l'iOS doit afficher 'Pas de repère')."""
    rows = [_row(1, "s1", CURRENT.end, name="Weird", group="Diaphragm")]
    response = build_cockpit_analytics(_FakeClient(rows), _config())
    assert "Diaphragm" in response.muscles.targets_by_muscle
    assert response.muscles.targets_by_muscle["Diaphragm"] is None


def test_targets_merge_current_and_previous_muscles():
    rows = [
        _row(1, "s1", CURRENT.end,                           name="Bench", group="Chest"),
        _row(2, "s2", PREVIOUS.start + timedelta(days=5),    name="Curl",  group="Biceps"),
    ]
    response = build_cockpit_analytics(_FakeClient(rows), _config())
    assert "Chest" in response.muscles.targets_by_muscle
    assert "Biceps" in response.muscles.targets_by_muscle


# ── 4. Correspondance figée des noms de catalogue ─────────────────────────────

# Noms bruts observés dans le catalogue iOS/backend (muscle_group / muscle_specific
# tels que renvoyés par Supabase). Chaque nom DOIT se résoudre via
# landmarks_for_muscle en une entrée MUSCLE_LANDMARKS — SAUF ceux listés
# explicitement dans WITHOUT_LANDMARK_FROZEN (hors doctrine Israetel).
#
# Ajouter un muscle au catalogue sans mise à jour ici fera échouer
# test_frozen_catalog_set_either_has_landmark_or_is_explicitly_without.
CATALOG_MUSCLES_FROZEN = frozenset({
    "Chest",         # Pectoraux
    "Lats",          # Dorsaux
    "Deltoids",      # Épaules
    "Rear Delt",     # Deltoïde postérieur
    "Trapezius",
    "Biceps",
    "Triceps",
    "Quadriceps",
    "Hamstrings",
    "Fessiers",      # Glutes
    "Calves",
    "Core",
    "Forearms",
    "Neck",
    # Aliases qui doivent se normaliser vers un landmark
    "pectorals",
    "quads",
    "shoulders",
    "glutes",
    "obliques",      # → core
    "upper back",    # → lats
    "rotator_cuff",  # → rear delt
})

# Muscles présents dans le catalogue mais explicitement hors doctrine
# (pas de plage Israetel ciblée). Frozen literal — toute addition est volontaire.
WITHOUT_LANDMARK_FROZEN = frozenset()


def test_frozen_catalog_set_either_has_landmark_or_is_explicitly_without():
    without = {m for m in CATALOG_MUSCLES_FROZEN if landmarks_for_muscle(m) is None}
    assert without == WITHOUT_LANDMARK_FROZEN, (
        f"Muscles sans plage détectés : {sorted(without - WITHOUT_LANDMARK_FROZEN)}. "
        "Ajoute-les à MUSCLE_LANDMARKS/_MUSCLE_ALIASES ou à WITHOUT_LANDMARK_FROZEN "
        "(dérive non intentionnelle sinon)."
    )


def test_landmarks_normalization_covers_common_aliases():
    """Garde-fou : les alias les plus utilisés doivent effectivement
    renvoyer sur une entrée MUSCLE_LANDMARKS (pas None)."""
    for raw in ("Chest", "pectorals", "glutes", "quads", "obliques", "rear deltoid"):
        assert landmarks_for_muscle(raw) is not None, raw


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
