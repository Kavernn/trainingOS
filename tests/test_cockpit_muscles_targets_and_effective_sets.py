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
    """1 séance Bench (chest → Pectoraux via fusion, 1 série sur 30j) :
    weekly_effective_sets = (1 + 0.5*0) / (30/7) = 0.233…"""
    rows = [_row(1, "s1", CURRENT.end, name="Bench")]
    response = build_cockpit_analytics(_FakeClient(rows), _config())
    chest = [w for w in response.muscles.workloads if w.muscle == "Pectoraux"]
    assert chest, "workload Pectoraux attendu"
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

    # Valeurs correspondent à MUSCLE_LANDMARKS, clefs via display name FR canonique
    assert targets["Pectoraux"] == {"mev_week": MUSCLE_LANDMARKS["chest"]["mev"],
                                     "mav_week": MUSCLE_LANDMARKS["chest"]["mav"],
                                     "mrv_week": MUSCLE_LANDMARKS["chest"]["mrv"]}
    assert targets["Dos"]       == {"mev_week": MUSCLE_LANDMARKS["lats"]["mev"],
                                     "mav_week": MUSCLE_LANDMARKS["lats"]["mav"],
                                     "mrv_week": MUSCLE_LANDMARKS["lats"]["mrv"]}
    assert targets["Biceps"]    == {"mev_week": MUSCLE_LANDMARKS["biceps"]["mev"],
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
    assert "Pectoraux" in response.muscles.targets_by_muscle
    assert "Biceps"    in response.muscles.targets_by_muscle


# ── 4. Correspondance figée des noms de catalogue ─────────────────────────────

# Noms bruts observés dans le catalogue Supabase `exercises`
# (colonnes muscle_group / muscle_specific / secondary_muscles) extraits
# des migrations 070, 088, 090, 093. Chaque nom passe par
# `landmarks_for_muscle` → soit il résout vers une entrée MUSCLE_LANDMARKS,
# soit il est listé dans WITHOUT_LANDMARK_FROZEN (hors doctrine Israetel).
#
# Ajouter un muscle au catalogue sans mise à jour ici fera échouer
# test_frozen_catalog_set_either_has_landmark_or_is_explicitly_without.
CATALOG_MUSCLES_FROZEN = frozenset({
    # muscle_group minuscules (anglais)
    "chest", "lats", "back", "legs", "quads", "hamstrings", "glutes",
    "triceps", "biceps", "forearms", "calves", "shoulders", "arms",
    "adductors", "brachialis", "abdominaux",
    # muscle_specific Title Case (français et anglais, migration 090)
    "Pectoraux", "Pectoral supérieur", "Pectoral moyen", "Pectoral inférieur",
    "Dos", "Grand dorsal",
    "Jambes", "Quadriceps",
    "Trapèzes", "Trapèze supérieur", "Trapèze inférieur",
    "Deltoïde antérieur", "Deltoïde postérieur",
    "Thoracique", "Moyen fessier",
    "Gainage", "Droit abdominal", "Core", "Obliques", "Abdominaux",
    "Brachioradialis",
    # Référencé dans Views/Stats/StatsComponents.swift pour la logique
    # biceps-femoral-under-hamstrings — doit apparaître dans workloads.
    "Biceps fémoral",
})

# Muscles présents dans le catalogue mais sans plage MEV/MAV/MRV connue
# (groupes génériques ambigus par nature — plusieurs muscles réels avec
# plages différentes). Frozen literal — toute addition DOIT être volontaire.
WITHOUT_LANDMARK_FROZEN = frozenset({
    "legs",        # Englobe quads + hams + glutes + calves → ambigu
    "arms",        # Englobe biceps + triceps + forearms → ambigu
    "Jambes",      # Idem "legs" en FR
    "Thoracique",  # Utilisé par un exo mobility (Cat-Cow + Thoracic Rotation),
                    # filtré en amont par tracking_type='mobility'. Si réemployé
                    # pour un muscle réel, décision à prendre.
})


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


# ── 5. Fusion canonique (migration 090 variantes FR) ─────────────────────────

def _row_with_specific(log_id, session_id, day, *, name, group, specific, secondary=None, sets=1):
    """Variante de _row qui expose muscle_specific séparément."""
    return {
        "id": str(log_id),
        "session_id": session_id,
        "exercise_id": f"id-{name}",
        "weight": 100, "reps": "5",
        "sets_json": [{"weight": 100, "reps": 5} for _ in range(sets)],
        "workout_sessions": {"date": day.isoformat()},
        "exercises": {
            "name": name, "tracking_type": "reps",
            "muscle_group": group, "muscle_specific": specific,
            "secondary_muscles": secondary or [],
        },
    }


def test_fusion_canonical_merges_subregion_and_group_into_one_workload():
    """Un exercice "chest" sans muscle_specific + un "Incline Cable Fly"
    (muscle_specific="Pectoral supérieur") la même semaine → UNE ligne
    "Pectoraux" dont direct_set_count = somme des deux."""
    rows = [
        # Exo 1 : muscle_group="chest" (lowercase EN), muscle_specific absent
        _row_with_specific(1, "s1", CURRENT.end - timedelta(days=1),
                           name="Flat Bench", group="chest", specific=None, sets=3),
        # Exo 2 : muscle_group="Pectoraux", muscle_specific="Pectoral supérieur"
        _row_with_specific(2, "s2", CURRENT.end,
                           name="Incline Cable Fly", group="Pectoraux",
                           specific="Pectoral supérieur", sets=2),
    ]
    response = build_cockpit_analytics(_FakeClient(rows), _config())
    muscles = [w.muscle for w in response.muscles.workloads]
    # UNE SEULE ligne, nom canonique FR
    assert muscles == ["Pectoraux"], f"attendu une ligne 'Pectoraux', trouvé {muscles}"
    chest = response.muscles.workloads[0]
    # 3 + 2 = 5 séries directes agrégées
    assert chest.direct_set_count == 5
    assert chest.session_count == 2
    # Targets map utilise le nom canonique
    assert response.muscles.targets_by_muscle["Pectoraux"] is not None


def test_fusion_no_double_count_when_group_and_specific_fuse_to_same_key():
    """Un exercice dont muscle_group="Pectoraux" ET muscle_specific="Pectoral
    supérieur" (déjà fusionnés par `specific or group` dans l'adapter) ne doit
    compter qu'UNE fois. Pas de double-compte si direct ET indirect fusionnent
    vers la même clé non plus."""
    rows = [
        _row_with_specific(1, "s1", CURRENT.end,
                           name="Incline Cable Fly", group="Pectoraux",
                           specific="Pectoral supérieur", sets=4),
    ]
    response = build_cockpit_analytics(_FakeClient(rows), _config())
    chest = response.muscles.workloads[0]
    assert chest.muscle == "Pectoraux"
    assert chest.direct_set_count == 4  # pas 8


def test_fusion_direct_wins_over_indirect_when_same_canonical_key():
    """Un exercice direct "Pectoral supérieur" (→ Pectoraux) avec
    secondary_muscles=["chest", "triceps"] (chest → Pectoraux, triceps → Triceps)
    compte en DIRECT seulement sur Pectoraux (pas d'indirect Pectoraux), et
    en indirect sur Triceps. Garantit la règle `indirect = indirect - direct`
    après fusion canonique."""
    rows = [
        _row_with_specific(1, "s1", CURRENT.end,
                           name="Incline Cable Fly", group="Pectoraux",
                           specific="Pectoral supérieur",
                           secondary=["chest", "triceps"], sets=2),
    ]
    response = build_cockpit_analytics(_FakeClient(rows), _config())
    by_name = {w.muscle: w for w in response.muscles.workloads}
    assert "Pectoraux" in by_name
    assert "Triceps" in by_name
    # Pectoraux : direct uniquement, pas d'indirect (fusion absorbe le secondary chest)
    assert by_name["Pectoraux"].direct_set_count == 2
    assert by_name["Pectoraux"].indirect_set_count == 0
    # Triceps : indirect uniquement
    assert by_name["Triceps"].indirect_set_count == 2
    assert by_name["Triceps"].direct_set_count == 0


def test_display_names_match_canonical_fr_mapping():
    """Les display names FR exposés dans workloads sont tirés de
    _LANDMARK_DISPLAY_FR (une seule source). Vérifie les choix validés :
    deltoids → Épaules, rear delt → Arrière d'épaule, core → Abdominaux."""
    rows = [
        _row_with_specific(1, "s1", CURRENT.end, name="OHP",
                           group="shoulders", specific=None, sets=1),
        _row_with_specific(2, "s2", CURRENT.end, name="Rear Fly",
                           group="Deltoïde postérieur", specific=None, sets=1),
        _row_with_specific(3, "s3", CURRENT.end, name="Plank",
                           group="Gainage", specific=None, sets=1),
    ]
    response = build_cockpit_analytics(_FakeClient(rows), _config())
    muscles = {w.muscle for w in response.muscles.workloads}
    assert "Épaules" in muscles
    assert "Arrière d'épaule" in muscles
    assert "Abdominaux" in muscles


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
