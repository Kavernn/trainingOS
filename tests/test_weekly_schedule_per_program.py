"""Migration 110 — chaque programme a SON planning ; activer un programme active son planning."""
import os
import sys
from unittest.mock import patch

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))
sys.path.insert(0, os.path.dirname(__file__))

import db_programs
from test_evening_schedule_persistence import _Client


def _client_two_programs():
    client = _Client()
    client.store["program_sessions"] += [
        {"id": "winter-a", "name": "Lundi Push A", "program_id": "winter"},
    ]
    return client


def _ctx(client, active):
    return [patch.object(db_programs.db_core, "_client", client),
            patch.object(db_programs.db_core, "MODE", "ONLINE"),
            patch.object(db_programs, "get_active_program_id", return_value=active)]


def _run(client, active, fn, *args):
    patches = _ctx(client, active)
    for p in patches:
        p.start()
    try:
        return fn(*args)
    finally:
        for p in reversed(patches):
            p.stop()


def test_each_program_keeps_its_own_schedule():
    client = _client_two_programs()
    assert _run(client, "program-1", db_programs.set_relational_week_schedule, {"Lun": "Push B", "Ven": None})
    assert _run(client, "program-1", db_programs.set_evening_week_schedule, {"Lun": "Pull B"})
    assert _run(client, "winter", db_programs.set_relational_week_schedule, {"Lun": "Lundi Push A"})

    assert _run(client, "program-1", db_programs.get_relational_week_schedule) == {"Lun": "Push B", "Ven": "Repos"}
    assert _run(client, "program-1", db_programs.get_evening_week_schedule) == {"Lun": "Pull B"}
    assert _run(client, "winter", db_programs.get_relational_week_schedule) == {"Lun": "Lundi Push A"}
    assert _run(client, "winter", db_programs.get_evening_week_schedule) == {}


def test_new_program_starts_with_empty_schedule_all_rest():
    client = _client_two_programs()
    assert _run(client, "program-1", db_programs.set_relational_week_schedule, {"Lun": "Push B"})
    # « Hiver 2027 » activé sans planning : aucun jour de v4 ne fuit.
    assert _run(client, "winter", db_programs.get_relational_week_schedule) == {}


def test_saving_one_program_never_touches_the_other():
    client = _client_two_programs()
    _run(client, "program-1", db_programs.set_evening_week_schedule, {"Lun": "Pull B", "Mar": "Push B"})
    _run(client, "winter", db_programs.set_evening_week_schedule, {})          # vide le soir d'Hiver
    assert _run(client, "program-1", db_programs.get_evening_week_schedule) == {"Lun": "Pull B", "Mar": "Push B"}
    rows = client.store["weekly_schedule"]
    assert all(r["program_id"] in ("program-1", "winter") for r in rows)
    assert {(r["program_id"], r["day_name"], r["slot"]) for r in rows} == {
        ("program-1", "Lun", "evening"), ("program-1", "Mar", "evening")}


def test_explicit_program_id_avoids_resolution_and_is_respected():
    client = _client_two_programs()
    _run(client, "program-1", db_programs.set_relational_week_schedule, {"Lun": "Push B"})
    _run(client, "winter", db_programs.set_relational_week_schedule, {"Lun": "Lundi Push A"})
    with patch.object(db_programs.db_core, "_client", client), \
         patch.object(db_programs.db_core, "MODE", "ONLINE"), \
         patch.object(db_programs, "get_active_program_id", side_effect=AssertionError("ne doit pas être appelé")):
        assert db_programs.get_relational_week_schedule(program_id="winter") == {"Lun": "Lundi Push A"}


def test_no_program_means_no_schedule_and_refused_writes():
    client = _client_two_programs()
    assert _run(client, None, db_programs.get_relational_week_schedule) == {}
    assert _run(client, None, db_programs.get_evening_week_schedule) == {}
    assert _run(client, None, db_programs.set_relational_week_schedule, {"Lun": "Push B"}) is False
    assert _run(client, None, db_programs.set_evening_week_schedule, {"Lun": "Pull B"}) is False
    assert client.store["weekly_schedule"] == []
