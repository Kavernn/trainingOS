"""Tests fallback héritage get_today_evening (commit 1 séance soir héritée).

3 cas :
 - evening vide/Repos + matin défini → renvoie le nom matin (héritage)
 - evening défini (override) → renvoie l'override, matin ignoré
 - evening vide + matin Repos → renvoie None (vrai repos)
"""
import os
import sys
from unittest.mock import patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

import planner  # noqa: E402


def _mock_monday():
    """Force weekday() = 0 (Lundi) pour déterminisme."""
    class _FakeNow:
        def weekday(self):
            return 0
    return patch.object(planner, "_montreal_now", return_value=_FakeNow())


def test_evening_vide_herite_du_matin():
    with _mock_monday(), \
         patch.object(planner, "get_evening_schedule", return_value={}), \
         patch.object(planner, "get_today", return_value="Upper A"):
        assert planner.get_today_evening() == "Upper A"


def test_evening_repos_herite_du_matin():
    with _mock_monday(), \
         patch.object(planner, "get_evening_schedule", return_value={"Lun": "Repos"}), \
         patch.object(planner, "get_today", return_value="Upper A"):
        assert planner.get_today_evening() == "Upper A"


def test_evening_override_gagne():
    with _mock_monday(), \
         patch.object(planner, "get_evening_schedule", return_value={"Lun": "Yoga"}), \
         patch.object(planner, "get_today", return_value="Upper A"):
        assert planner.get_today_evening() == "Yoga"


def test_les_deux_repos_renvoie_none():
    with _mock_monday(), \
         patch.object(planner, "get_evening_schedule", return_value={}), \
         patch.object(planner, "get_today", return_value="Repos"):
        assert planner.get_today_evening() is None


if __name__ == "__main__":
    test_evening_vide_herite_du_matin()
    test_evening_repos_herite_du_matin()
    test_evening_override_gagne()
    test_les_deux_repos_renvoie_none()
    print("OK — 4 cas de fallback héritage soir validés")
