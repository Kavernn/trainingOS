"""L5 : séries de décharge PAR SÉANCE du programme actif ; charge par exercice ; jamais de 3 inventé."""
from deload import calculer_poids_deload

WEIGHTS = {"Back Squat": {"current_weight": 200}, "Deadhang": {"current_weight": 10},
           "Hors Programme": {"current_weight": 50}}
SCHEMES = {"Mercredi": {"Back Squat": "4x5-8", "Deadhang": "1xmax"}, "Samedi": {"Back Squat": "2x6-8"}}


def test_sets_are_per_session_and_weight_per_exercise():
    out = calculer_poids_deload(WEIGHTS, ["Back Squat"], "peripheral", session_schemes=SCHEMES)
    squat = out["Back Squat"]
    assert squat["poids_deload"] == 180.0
    assert squat["sets_by_session"] == {"Mercredi": {"sets_normaux": 4, "sets_deload": 2},
                                        "Samedi": {"sets_normaux": 2, "sets_deload": 1}}


def test_no_line_outside_active_program_or_unreadable_scheme():
    out = calculer_poids_deload(WEIGHTS, ["Hors Programme", "Deadhang"], "peripheral", session_schemes=SCHEMES)
    assert out == {}


def test_no_program_means_no_prescription():
    assert calculer_poids_deload(WEIGHTS, ["Back Squat"], "peripheral", session_schemes={}) == {}


def _analyse(active: bool, recommended: bool):
    from unittest.mock import patch
    import deload
    p = [patch.object(deload, "detect_stagnation", return_value=[]),
         patch.object(deload, "detect_fatigue_rpe", return_value={"fatigue": False}),
         patch.object(deload, "compute_fatigue_score", return_value={"score": 80 if recommended else 10, "components": {}, "streak_days": 0}),
         patch.object(deload, "diagnose_fatigue_type", return_value={"fatigue_type": "peripheral", "central_markers": 0, "markers_detail": [], "duration_days": 0}),
         patch.object(deload, "detect_performance_drop", return_value=[]),
         patch.object(deload, "check_planned_deload", return_value={"due": False}),
         patch.object(deload._db, "get_active_deload_period", return_value={"started_at": "2026-11-24"} if active else None),
         patch.object(deload, "active_program_session_schemes", return_value=SCHEMES)]
    for x in p: x.start()
    try:
        return deload.analyser_deload(WEIGHTS)["deload_prescription"]
    finally:
        for x in p: x.stop()


def test_active_deload_prescribes_whole_program_even_if_not_recommended():
    out = _analyse(active=True, recommended=False)
    assert out["Back Squat"]["sets_by_session"]["Samedi"] == {"sets_normaux": 2, "sets_deload": 1}


def test_no_active_deload_and_no_recommendation_means_nothing():
    assert _analyse(active=False, recommended=False) == {}
