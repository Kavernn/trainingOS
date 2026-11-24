"""Plus de repli « programme le plus ancien » : seul le choix explicite fait foi."""
import os
import sys
from unittest.mock import MagicMock, patch

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

import db_programs
import planner


def _profile_client(active):
    client = MagicMock()
    chain = client.table.return_value.select.return_value.eq.return_value.limit.return_value
    chain.execute.return_value.data = [{"id": 1, "active_program_id": active}]
    return client


def test_active_program_comes_only_from_profile():
    with patch.object(db_programs.db_core, "MODE", "ONLINE"), \
         patch.object(db_programs.db_core, "_client", _profile_client("winter")):
        assert db_programs.get_active_program_id(strict=True) == "winter"
    with patch.object(db_programs.db_core, "MODE", "ONLINE"), \
         patch.object(db_programs.db_core, "_client", _profile_client(None)), \
         patch.object(db_programs, "get_profile", return_value={}):
        assert db_programs.get_active_program_id(strict=True) is None
        assert db_programs.get_active_program_id() is None


def test_oldest_program_helper_is_gone():
    assert not hasattr(db_programs, "get_default_program_id")


def test_cycle_date_without_program_uses_active_never_oldest():
    with patch.object(db_programs.db_core, "MODE", "ONLINE"), \
         patch.object(db_programs.db_core, "_client", MagicMock()), \
         patch.object(db_programs, "get_active_program_id", return_value=None):
        assert db_programs.get_cycle_start_date() is None


def test_save_full_program_without_active_program_raises():
    with patch.object(db_programs.db_core, "MODE", "ONLINE"), \
         patch.object(db_programs.db_core, "_client", MagicMock()), \
         patch.object(db_programs, "get_active_program_id", return_value=None):
        with pytest.raises(RuntimeError, match="aucun programme actif"):
            db_programs.save_full_program({"Push A": {}})


def test_load_program_without_active_program_is_empty_never_union():
    db = MagicMock()
    db.get_active_program_id.return_value = None
    with patch.dict(sys.modules, {"db": db}):
        assert planner.load_program() == {}
    db.get_full_program.assert_not_called()
