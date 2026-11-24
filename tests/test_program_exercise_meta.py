"""Build 3 / Serveur A : valeurs propres de l'exercice de programme (migration 111).

Règle : la bibliothèque fournit des défauts (copiés à l'ajout) ; l'exercice de séance
possède ses valeurs ; la bibliothèque ne réécrit jamais un programme, et inversement.
"""
import sys
from types import SimpleNamespace
from unittest.mock import patch

import pytest

from conftest import BaseRouteTest
import db_programs


class _Q:
    def __init__(self, client, table):
        self.c, self.t, self.f, self.op, self.payload = client, table, [], "select", None

    def select(self, *_):
        return self

    def eq(self, k, v):
        self.f.append(lambda r, k=k, v=v: r.get(k) == v); return self

    def in_(self, k, vs):
        self.f.append(lambda r, k=k, vs=tuple(vs): r.get(k) in vs); return self

    def is_(self, k, _null):
        self.f.append(lambda r, k=k: r.get(k) is None); return self

    def order(self, *_):
        return self

    def limit(self, _n):
        return self

    def update(self, payload):
        self.op, self.payload = "update", dict(payload); return self

    def execute(self):
        rows = [r for r in self.c.rows[self.t] if all(f(r) for f in self.f)]
        if self.op == "update":
            for r in rows:
                r.update(self.payload)
        return SimpleNamespace(data=[dict(r) for r in rows])


class _Client:
    def __init__(self):
        self.rows = {
            "program_sessions": [{"id": "s-lun", "name": "Lundi", "program_id": "hiver"},
                                 {"id": "s-sam", "name": "Samedi", "program_id": "hiver"},
                                 {"id": "s-v4", "name": "Lundi", "program_id": "v4"}],
            "program_blocks": [{"id": "b-lun", "session_id": "s-lun", "type": "strength"},
                               {"id": "b-sam", "session_id": "s-sam", "type": "strength"},
                               {"id": "b-v4", "session_id": "s-v4", "type": "strength"}],
            "exercises": [{"id": "squat", "name": "Back Squat", "deleted_at": None}],
            "program_block_exercises": [
                {"block_id": b, "exercise_id": "squat", "scheme": "3x5-8", "rest_seconds": 180,
                 "target_rir_min": None, "target_rir_max": None, "is_optional": False}
                for b in ("b-lun", "b-sam", "b-v4")],
        }

    def table(self, name):
        return _Q(self, name)


def _with(client, fn, *a):
    with patch.object(db_programs.db_core, "_client", client), \
         patch.object(db_programs.db_core, "MODE", "ONLINE"):
        return fn(*a)


def test_meta_targets_one_session_of_one_program_only():
    c = _Client()
    assert _with(c, db_programs.set_program_exercise_meta, "hiver", "Samedi", "Back Squat",
                 {"rest_seconds": 120, "target_rir_min": 2, "target_rir_max": 2})
    by_block = {r["block_id"]: r for r in c.rows["program_block_exercises"]}
    assert (by_block["b-sam"]["rest_seconds"], by_block["b-sam"]["target_rir_min"]) == (120, 2)
    assert by_block["b-lun"]["rest_seconds"] == 180          # même exercice, autre séance
    assert by_block["b-v4"]["rest_seconds"] == 180           # même nom de séance, autre programme


def test_meta_unknown_session_or_exercise_writes_nothing():
    c = _Client()
    assert _with(c, db_programs.set_program_exercise_meta, "hiver", "Dimanche", "Back Squat", {"is_optional": True}) is False
    assert _with(c, db_programs.set_program_exercise_meta, "hiver", "Samedi", "Plate Pinch Hold", {"is_optional": True}) is False
    assert not any(r["is_optional"] for r in c.rows["program_block_exercises"])


def test_meta_refuses_unknown_field():
    with pytest.raises(ValueError):
        _with(_Client(), db_programs.set_program_exercise_meta, "hiver", "Samedi", "Back Squat", {"scheme": "1x1"})


def test_get_full_program_exposes_exercise_meta():
    rows = [{"id": "s", "name": "Samedi", "order_index": 0, "program_blocks": [
        {"id": "b", "type": "strength", "order_index": 0, "program_block_exercises": [
            {"scheme": "2x12-15", "order_index": 0, "rest_seconds": None, "target_rir_min": None,
             "target_rir_max": None, "is_optional": True, "exercises": {"id": "x", "name": "Hip Thrust"}}]}]}]
    q = SimpleNamespace(select=lambda *_: q, order=lambda *_: q, eq=lambda *_: q,
                        execute=lambda: SimpleNamespace(data=rows))
    with patch.object(db_programs.db_core, "_client", SimpleNamespace(table=lambda _n: q)), \
         patch.object(db_programs.db_core, "MODE", "ONLINE"):
        prog = db_programs.get_full_program("hiver")
    from blocks import get_strength_exercise_meta
    assert get_strength_exercise_meta(prog["Samedi"]) == {"Hip Thrust": {
        "rest_seconds": None, "target_rir_min": None, "target_rir_max": None, "is_optional": True}}


class TestProgrammeMetaRoutes(BaseRouteTest):
    def setUp(self):
        super().setUp()
        self.meta = patch.object(sys.modules["db"], "set_program_exercise_meta", return_value=True).start()
        self.addCleanup(patch.stopall)

    def post_meta(self, **kw):
        return self.post("/api/programme", {"action": "meta", "jour": "Upper A", "exercise": "Bench Press", **kw})

    def test_meta_writes_only_given_fields(self):
        r = self.post_meta(target_rir_min=1, target_rir_max=2, is_optional=True)
        self.assertEqual(200, r.status_code)
        _pid, jour, ex, fields = self.meta.call_args.args
        self.assertEqual((jour, ex, fields), ("Upper A", "Bench Press",
                         {"target_rir_min": 1, "target_rir_max": 2, "is_optional": True}))

    def test_meta_validation(self):
        for bad in ({"rest_seconds": 0}, {"rest_seconds": "90"}, {"target_rir_min": 3, "target_rir_max": 1},
                    {"target_rir_min": 1}, {"target_rir_min": 6, "target_rir_max": 6},
                    {"is_optional": "oui"}, {}):
            self.assertEqual(400, self.post_meta(**bad).status_code, bad)
        self.meta.assert_not_called()
        self.assertEqual(200, self.post_meta(rest_seconds=None, target_rir_min=None, target_rir_max=None).status_code)

    def test_meta_unknown_exercise_404(self):
        self.assertEqual(404, self.post("/api/programme", {"action": "meta", "jour": "Upper A",
                                                           "exercise": "Inconnu", "is_optional": True}).status_code)

    def test_add_copies_library_rest_as_program_default(self):
        self.store["inventory"]["Cable Fly"]["rest_seconds"] = 75
        r = self.post("/api/programme", {"action": "add", "jour": "Upper A", "exercise": "Cable Fly", "scheme": "2x12"})
        self.assertEqual(200, r.status_code)
        self.assertEqual(self.meta.call_args.args[1:], ("Upper A", "Cable Fly", {"rest_seconds": 75}))

    def test_replace_keeps_slot_bonus_and_rir_and_takes_new_exercise_rest(self):
        block = self.store["program"]["Upper A"]["blocks"][0]
        block["exercise_meta"] = {"Bench Press": {"rest_seconds": 200, "target_rir_min": 1,
                                                  "target_rir_max": 2, "is_optional": True}}
        self.store["inventory"]["Cable Fly"]["rest_seconds"] = 75
        r = self.post("/api/programme", {"action": "replace", "jour": "Upper A", "old_exercise": "Bench Press",
                                         "new_exercise": "Cable Fly", "scheme": "2x12"})
        self.assertEqual(200, r.status_code)
        self.assertEqual(self.meta.call_args.args[3], {"rest_seconds": 75, "is_optional": True,
                                                       "target_rir_min": 1, "target_rir_max": 2})


class TestLibraryNeverRewritesProgram(BaseRouteTest):
    def test_library_scheme_edit_leaves_programs_untouched(self):
        before = dict(self.store["program"]["Upper A"]["blocks"][0]["exercises"])
        r = self.post("/api/save_exercise", {"name": "Bench Press", "type": "barbell",
                                             "default_scheme": "5x5", "rest_seconds": 120})
        self.assertEqual(200, r.status_code)
        self.assertEqual("5x5", self.store["inventory"]["Bench Press"]["default_scheme"])
        self.assertEqual(before, self.store["program"]["Upper A"]["blocks"][0]["exercises"])

    def test_library_exercise_never_without_rest(self):
        for rest in (None, 0, "90", True):
            body = {"name": "Z-Move", "type": "machine"}
            if rest is not None:
                body["rest_seconds"] = rest
            self.assertEqual(400, self.post("/api/save_exercise", body).status_code, rest)
        self.assertNotIn("Z-Move", self.store["inventory"])


class TestPayloadsExposeExerciseMeta(BaseRouteTest):
    def test_programme_and_seance_payloads_carry_per_session_meta(self):
        self.store["program"]["Upper A"]["blocks"][0]["exercise_meta"] = {
            "Bench Press": {"rest_seconds": 150, "target_rir_min": 2, "target_rir_max": 2, "is_optional": False}}
        for path in ("/api/programme_data", "/api/seance_data?date=2088-09-25"):
            meta = self.json(self.get(path))["exercise_meta"]
            self.assertEqual(150, meta["Upper A"]["Bench Press"]["rest_seconds"], path)
