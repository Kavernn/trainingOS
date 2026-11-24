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
