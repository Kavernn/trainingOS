"""Garde anti-régression pour _SpecGuardedMock (conftest.py hardening 2026-07).

Prouve que le db_mock refuse l'injection dynamique d'un attribut fantôme —
exactement ce qui aurait attrapé le bug mesocycle (get_active_program qui
n'existe pas, appelé par analytics_load.py:376). Sans cette garde, la refonte
du conftest peut régresser silencieusement.
"""
import sys, os
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

from unittest.mock import MagicMock
from conftest import BaseRouteTest


class TestSpecGuardBlocksGhostAttribute(BaseRouteTest):
    """Un nom absent du vrai module db doit lever AttributeError au setattr."""

    def test_ghost_attribute_setattr_raises(self):
        db_mod = sys.modules["db"]
        # get_active_program n'existe pas — seul get_active_program_id existe.
        # C'est le bug exact du commit mesocycle (analytics_load.py:376 pré-fix).
        with self.assertRaises(AttributeError) as ctx:
            db_mod.get_active_program = MagicMock(return_value={"cycle_start_date": "2026-01-01"})
        self.assertIn("typo", str(ctx.exception).lower())

    def test_typo_variant_raises(self):
        db_mod = sys.modules["db"]
        with self.assertRaises(AttributeError):
            db_mod.get_cyle_start_date = MagicMock()  # typo: cyle au lieu de cycle


class TestSpecGuardAllowsRealAttribute(BaseRouteTest):
    """Les vrais noms du module db passent — le guard ne casse pas les tests légit."""

    def test_real_attribute_setattr_succeeds(self):
        db_mod = sys.modules["db"]
        db_mod.get_active_program_id = MagicMock(return_value="fake-program-id")
        self.assertEqual("fake-program-id", db_mod.get_active_program_id())

    def test_real_cycle_start_date_setattr_succeeds(self):
        db_mod = sys.modules["db"]
        db_mod.get_cycle_start_date = MagicMock(return_value="2026-04-25")
        self.assertEqual("2026-04-25", db_mod.get_cycle_start_date())
