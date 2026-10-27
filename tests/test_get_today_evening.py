"""Tests fallback héritage get_today_evening (commit 1 séance soir héritée).

4 cas :
 - evening vide + matin défini → renvoie le nom matin (héritage)
 - evening Repos + matin défini → renvoie le nom matin (héritage)
 - evening override → renvoie l'override, matin ignoré
 - evening vide + matin Repos → renvoie None (vrai repos)

Refactor planner : get_today_evening route via sessions_for_date qui lit
directement db (_db.get_relational_week_schedule, _db.get_evening_week_schedule,
_db.get_session_override). Mock de ces 3 sources, pas de planner.get_today
ni planner.get_evening_schedule (surfaces plus utilisées par la route).
"""
import os
import sys
from unittest.mock import patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

import planner  # noqa: E402


# Lundi 2026-03-09 arbitraire — _today_mtl figé pour que sessions_for_date
# produise toujours day = "Lun".
_MONDAY = "2026-03-09"


def _patches(morning_schedule, evening_schedule):
    """Patche les 3 sources DB consommées par sessions_for_date, plus la date."""
    def apply(stack):
        stack.enter_context(patch.object(planner, "get_today_date", return_value=_MONDAY))
        import db as _db
        stack.enter_context(patch.object(_db, "get_relational_week_schedule",
                                         return_value=morning_schedule))
        stack.enter_context(patch.object(_db, "get_evening_week_schedule",
                                         return_value=evening_schedule))
        stack.enter_context(patch.object(_db, "get_session_override", return_value=None))
    return apply


def _run(morning_schedule, evening_schedule):
    from contextlib import ExitStack
    with ExitStack() as stack:
        _patches(morning_schedule, evening_schedule)(stack)
        return planner.get_today_evening()


def test_evening_vide_herite_du_matin():
    assert _run({"Lun": "Upper A"}, {}) == "Upper A"


def test_evening_repos_herite_du_matin():
    assert _run({"Lun": "Upper A"}, {"Lun": "Repos"}) == "Upper A"


def test_evening_override_gagne():
    assert _run({"Lun": "Upper A"}, {"Lun": "Yoga"}) == "Yoga"


def test_les_deux_repos_renvoie_none():
    assert _run({"Lun": "Repos"}, {}) is None


if __name__ == "__main__":
    test_evening_vide_herite_du_matin()
    test_evening_repos_herite_du_matin()
    test_evening_override_gagne()
    test_les_deux_repos_renvoie_none()
    print("OK — 4 cas de fallback héritage soir validés")
