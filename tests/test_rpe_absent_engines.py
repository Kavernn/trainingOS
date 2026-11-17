"""
Build H — séance sans RPE de séance : jamais comptée 0, jamais de valeur magique.
session_load (ACWR + stress + volume progression), energy, velocity.
"""
import math
import os
import sys
from datetime import date, timedelta

import pytest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "api"))

import acwr
import energy
import stress_load_engine
import velocity_engine
import volume_progression_engine

AFTER = acwr.REAL_SET_RPE_SINCE          # 1er jour de RPE de séries fiables
BEFORE = (date.fromisoformat(AFTER) - timedelta(days=1)).isoformat()


# ── session_load ─────────────────────────────────────────────────────────────

class TestSessionLoad:
    def test_real_session_rpe(self):
        assert acwr.session_load(8, 41, 12915) == pytest.approx(328)

    def test_real_set_rpe_when_no_session_rpe(self):
        assert acwr.session_load(None, 40, 12000, set_rpe_mean=7.5) == pytest.approx(300)

    def test_calibrated_tonnage_estimation(self):
        assert acwr.session_load(None, None, 12915, k=0.0236) == pytest.approx(12915 * 0.0236)

    def test_uncalibrated_tonnage_is_positive_estimation(self):
        assert acwr.session_load(None, 41, 12915) == pytest.approx(math.log1p(12915) * 10)

    def test_no_usable_data_is_excluded_not_zero(self):
        assert acwr.session_load(None, None, None) is None
        assert acwr.session_load(None, 41, 0) is None


class TestRealSetRPE:
    SETS = [[{"rpe": 7}, {"rpe": 8}], [{"reps": "5"}]]

    def test_after_cutoff_mean_of_entered_only(self):
        assert acwr.real_set_rpe_mean(self.SETS, AFTER) == pytest.approx(7.5)

    def test_before_cutoff_never_used(self):
        # Avant 8ea233f7 : RPE 7 inventés sur chaque série → ignorés.
        assert acwr.real_set_rpe_mean(self.SETS, BEFORE) is None

    def test_no_entered_rpe(self):
        assert acwr.real_set_rpe_mean([[{"reps": "5"}]], AFTER) is None


class TestTonnageK:
    TODAY = "2026-11-17"

    def _row(self, d, rpe=8, dur=40, vol=10000):
        return {"date": d, "rpe": rpe, "duration_min": dur, "total_volume": vol}

    def test_needs_min_sessions(self):
        rows = [self._row("2026-11-10")] * (acwr.K_MIN_SESSIONS - 1)
        assert acwr.tonnage_k(rows, self.TODAY) is None

    def test_median_over_recent_window_only(self):
        rows = [self._row("2026-11-10", vol=v) for v in (8000, 10000, 16000, 20000, 32000)]
        rows.append(self._row("2026-08-01", rpe=7, dur=60, vol=100))   # hors fenêtre de 60 j
        assert acwr.tonnage_k(rows, self.TODAY) == pytest.approx(8 * 40 / 16000)


class TestACWRAggregate:
    def test_session_without_rpe_counts_positive(self):
        rows = [{"date": AFTER, "rpe": None, "duration_min": 40, "total_volume": 12000}]
        daily = acwr._aggregate_daily(rows, k=0.0236)
        assert daily[AFTER] == pytest.approx(12000 * 0.0236) and daily[AFTER] > 0

    def test_empty_stub_excluded(self):
        rows = [{"date": AFTER, "rpe": None, "duration_min": None, "total_volume": 0}]
        assert acwr._aggregate_daily(rows) == {}


# ── stress_load_engine / volume_progression : même règle ─────────────────────

def test_stress_week_of_rpe_less_sessions_is_positive(monkeypatch):
    today = stress_load_engine._today_iso()
    monkeypatch.setattr(stress_load_engine.db, "get_workout_sessions",
                        lambda limit=400: [{"id": "s1", "date": today, "rpe": None, "completed": True}])
    monkeypatch.setattr(stress_load_engine.db, "get_pss_records", lambda limit=200: [])
    monkeypatch.setattr(stress_load_engine, "session_loads_by_id", lambda days: {"s1": 300.0})
    out = stress_load_engine.compute()
    assert out["has_data"] is True
    assert out["weeks"][-1]["training_stress"] > 0


def test_volume_progression_excludes_missing_never_zero_fills():
    monday = date(2026, 11, 16)
    sessions = [{"id": "a", "date": "2026-11-17", "completed": True, "rpe": None},
                {"id": "b", "date": "2026-11-18", "completed": True, "rpe": None}]
    assert volume_progression_engine._week_load(sessions, {"a": 250.0}, monday) == pytest.approx(250)


# ── energy ───────────────────────────────────────────────────────────────────

class TestEnergy:
    def test_real_session_rpe(self):
        assert energy._lifting_rpe({"rpe": 7.5, "id": "x", "date": AFTER}) == (7.5, "session")

    def test_real_set_rpe(self, monkeypatch):
        monkeypatch.setattr(energy.db, "get_exercise_logs_for_session_with_names",
                            lambda sid: [{"sets_json": [{"rpe": 7}, {"rpe": 8}]}])
        assert energy._lifting_rpe({"rpe": None, "id": "x", "date": AFTER}) == (7.5, "sets")

    def test_before_cutoff_sets_ignored_neutral(self, monkeypatch):
        monkeypatch.setattr(energy.db, "get_exercise_logs_for_session_with_names",
                            lambda sid: [{"sets_json": [{"rpe": 7}]}])
        assert energy._lifting_rpe({"rpe": None, "id": "x", "date": BEFORE}) == (
            energy._NEUTRAL_LIFTING_RPE_UNKNOWN, "neutral")

    def test_neutral_is_marked_and_not_sent_as_rpe(self, monkeypatch):
        monkeypatch.setattr(energy.db, "get_workout_session_by_type",
                            lambda d, t: {"id": "x", "date": AFTER, "rpe": None, "completed": True,
                                          "duration_min": 60, "session_name": "Pull"} if t == "morning" else None)
        monkeypatch.setattr(energy.db, "get_exercise_logs_for_session_with_names", lambda sid: [])
        [entry] = energy._eat_from_workouts(AFTER, 80.0)
        assert entry["rpe"] is None and entry["rpe_source"] == "neutral"
        assert entry["met"] == energy._met_lifting(energy._NEUTRAL_LIFTING_RPE_UNKNOWN)
        assert entry["calories"] == round(entry["met"] * 80.0 * 60 / 60)

    def test_real_rpe_sent_as_rounded_int(self, monkeypatch):
        monkeypatch.setattr(energy.db, "get_workout_session_by_type",
                            lambda d, t: {"id": "x", "date": AFTER, "rpe": 7.5, "completed": True,
                                          "duration_min": 60} if t == "morning" else None)
        [entry] = energy._eat_from_workouts(AFTER, 80.0)
        assert entry["rpe"] == 8 and isinstance(entry["rpe"], int) and entry["rpe_source"] == "session"


# ── velocity ─────────────────────────────────────────────────────────────────

class TestVelocity:
    W = {"2026-11-17", "2026-11-16", "2026-11-15"}

    def _sessions(self, rpes):
        return [{"date": "2026-11-17", "completed": True, "rpe": r} for r in rpes]

    def test_identical_to_old_formula_when_all_known(self):
        rpes = [8, 7, 9]
        old_workout = (min(1.0, 3 / 5) * 0.5 + min(1.0, sum(r / 10 for r in rpes) / 5) * 0.5) * 100
        assert velocity_engine._score_window(self.W, self._sessions(rpes), [], [], []) == pytest.approx(old_workout)

    def test_missing_rpe_uses_window_mean_not_7(self):
        got = velocity_engine._score_window(self.W, self._sessions([9, None]), [], [], [])
        expected = (min(1.0, 2 / 5) * 0.5 + min(1.0, (9 / 10) * (2 / 5)) * 0.5) * 100
        with_seven = (min(1.0, 2 / 5) * 0.5 + min(1.0, (9 / 10 + 7 / 10) / 5) * 0.5) * 100
        assert got == pytest.approx(expected) and got != pytest.approx(with_seven)

    def test_no_rpe_at_all_is_frequency_only(self):
        got = velocity_engine._score_window(self.W, self._sessions([None, None]), [], [], [])
        assert got == pytest.approx(min(1.0, 2 / 5) * 100)
