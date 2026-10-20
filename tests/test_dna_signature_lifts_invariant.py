"""DNA signature lifts (lot c, après corrections) :

  1. pr_e1rm_lbs identique à la table exercise_prs → identique à ce que
     lit PR tracker.
  2. Classement par FRÉQUENCE (séances distinctes dans la fenêtre DNA,
     hors décharge) ; égalité départagée par la récence (last_date).
  3. progression_pct dérivé des strength_exposures (meilleur e1RM des 30
     premiers jours de la fenêtre DNA vs 30 derniers). Si une des deux
     bornes est vide → None (jamais 0).
  4. first_date / last_date = vraies dates observées dans la fenêtre.
"""
from __future__ import annotations

import sys
from datetime import date, timedelta
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "api"))


TODAY = date(2026, 10, 15)
PERIOD_DAYS = 90


@pytest.fixture
def pinned_today(monkeypatch):
    monkeypatch.setattr("utils._today_mtl", lambda: TODAY.isoformat())
    return TODAY


@pytest.fixture
def no_deload(monkeypatch):
    monkeypatch.setattr("db.get_deload_periods", lambda: [])


def _pr_row(name, *, pr_weight, pr_e1rm, pr_reps, pr_date, baseline=5):
    return {
        "exercise_name":  name,
        "pr_weight_lbs":  float(pr_weight),
        "pr_e1rm_lbs":    float(pr_e1rm),
        "pr_date":        pr_date,
        "pr_reps":        int(pr_reps),
        "baseline_count": int(baseline),
        "current_weight": float(pr_weight),
    }


def _log(log_id, session_id, day, *, name, weight, reps):
    return {
        "id":            str(log_id),
        "session_id":    session_id,
        "exercise_id":   f"id-{name}",
        "weight":        weight,
        "reps":          str(reps),
        "sets_json":     [{"weight": weight, "reps": reps}],
        "workout_sessions": {"date": day.isoformat()},
        "exercises":    {
            "name":              name,
            "tracking_type":     "reps",
            "muscle_group":      "Chest",
            "muscle_specific":   None,
            "secondary_muscles": [],
        },
    }


class _FakeQuery:
    def __init__(self, rows): self.rows = rows
    def select(self, _): return self
    def gte(self, *_): return self
    def lte(self, *_): return self
    def execute(self): return type("R", (), {"data": self.rows})()


class _FakeClient:
    def __init__(self, rows): self.rows = rows
    def table(self, _): return _FakeQuery(self.rows)


def test_dna_pr_e1rm_matches_pr_tracker(pinned_today, no_deload, monkeypatch):
    """DNA.pr_e1rm_lbs == PR tracker last_pr.est_1rm pour le même lift —
    les deux lisent la table exercise_prs par construction."""
    pr_rows = [
        _pr_row("Bench Press", pr_weight=225, pr_e1rm=262.5, pr_reps=5, pr_date="2026-09-20"),
        _pr_row("Squat",       pr_weight=315, pr_e1rm=354.4, pr_reps=3, pr_date="2026-10-01"),
    ]
    monkeypatch.setattr("db.get_exercise_prs", lambda: pr_rows)

    # Exposures : au moins 2 séances chacun dans la fenêtre DNA.
    rows = []
    log_id = 0
    for i in range(3):
        log_id += 1
        rows.append(_log(log_id, f"s-bp-{i}", TODAY - timedelta(days=i * 7),
                         name="Bench Press", weight=225, reps=5))
    for i in range(3):
        log_id += 1
        rows.append(_log(log_id, f"s-sq-{i}", TODAY - timedelta(days=i * 7),
                         name="Squat", weight=315, reps=3))
    # history fourni par get_all_exercise_history n'est pas utilisé par la
    # nouvelle version — reste pour compat au cas où.
    monkeypatch.setattr("db.get_all_exercise_history", lambda **_: {})

    import workout_dna as _dna
    lifts = _dna._compute_signature_lifts(_FakeClient(rows), period_days=PERIOD_DAYS)
    dna_by_name = {l["name"]: l for l in lifts}

    import pr_tracker_engine as _pr
    pr_payload = _pr.compute()
    last_pr = pr_payload["last_pr"]
    assert last_pr is not None
    assert last_pr["name"] == "Squat"

    assert dna_by_name["Squat"]["pr_e1rm_lbs"] == last_pr["est_1rm"], (
        f"DNA.Squat.pr_e1rm_lbs={dna_by_name['Squat']['pr_e1rm_lbs']} "
        f"≠ PR tracker last_pr.est_1rm={last_pr['est_1rm']}"
    )
    for row in pr_rows:
        name = row["exercise_name"]
        if name in dna_by_name:
            assert dna_by_name[name]["pr_e1rm_lbs"] == round(row["pr_e1rm_lbs"], 1)


def test_dna_ranks_by_frequency_not_by_e1rm(pinned_today, no_deload, monkeypatch):
    """Deux lifts : A a 2 séances mais un e1RM élevé, B a 5 séances avec un
    e1RM plus bas. Le ranking par FRÉQUENCE place B en premier."""
    pr_rows = [
        _pr_row("Rare Heavy",  pr_weight=405, pr_e1rm=405, pr_reps=1, pr_date="2026-10-01"),
        _pr_row("Daily Driver", pr_weight=135, pr_e1rm=150, pr_reps=5, pr_date="2026-09-15"),
    ]
    monkeypatch.setattr("db.get_exercise_prs", lambda: pr_rows)

    rows = []
    log_id = 0
    for i in range(2):
        log_id += 1
        rows.append(_log(log_id, f"s-rare-{i}", TODAY - timedelta(days=10 + i * 20),
                         name="Rare Heavy", weight=405, reps=1))
    for i in range(5):
        log_id += 1
        rows.append(_log(log_id, f"s-dd-{i}", TODAY - timedelta(days=5 + i * 7),
                         name="Daily Driver", weight=135, reps=5))
    monkeypatch.setattr("db.get_all_exercise_history", lambda **_: {})

    import workout_dna as _dna
    lifts = _dna._compute_signature_lifts(_FakeClient(rows), period_days=PERIOD_DAYS)
    names = [l["name"] for l in lifts]
    assert names == ["Daily Driver", "Rare Heavy"], (
        f"Ranking attendu [Daily Driver, Rare Heavy] par fréquence desc, obtenu {names}"
    )
    assert lifts[0]["session_count"] == 5
    assert lifts[1]["session_count"] == 2


def test_dna_tiebreak_by_recency(pinned_today, no_deload, monkeypatch):
    """Deux lifts avec la MÊME fréquence → tie-break par last_date desc."""
    pr_rows = [
        _pr_row("Older",  pr_weight=200, pr_e1rm=215, pr_reps=3, pr_date="2026-08-01"),
        _pr_row("Newer",  pr_weight=200, pr_e1rm=215, pr_reps=3, pr_date="2026-10-10"),
    ]
    monkeypatch.setattr("db.get_exercise_prs", lambda: pr_rows)
    monkeypatch.setattr("db.get_all_exercise_history", lambda **_: {})

    rows = []
    log_id = 0
    for i in range(3):
        log_id += 1
        rows.append(_log(log_id, f"s-old-{i}", TODAY - timedelta(days=70 + i * 3),
                         name="Older", weight=200, reps=3))
    for i in range(3):
        log_id += 1
        rows.append(_log(log_id, f"s-new-{i}", TODAY - timedelta(days=5 + i * 3),
                         name="Newer", weight=200, reps=3))

    import workout_dna as _dna
    lifts = _dna._compute_signature_lifts(_FakeClient(rows), period_days=PERIOD_DAYS)
    names = [l["name"] for l in lifts]
    assert names == ["Newer", "Older"], (
        f"Fréquence égale (3/3), tie-break par last_date desc : Newer avant Older. Obtenu {names}"
    )


def test_dna_deload_sessions_excluded_from_frequency(pinned_today, monkeypatch):
    """Séances pendant une période de décharge enregistrée ne comptent pas
    dans session_count (fréquence hors décharge)."""
    pr_rows = [_pr_row("Bench Press", pr_weight=225, pr_e1rm=262, pr_reps=5, pr_date="2026-09-20")]
    monkeypatch.setattr("db.get_exercise_prs", lambda: pr_rows)
    monkeypatch.setattr("db.get_all_exercise_history", lambda **_: {})
    monkeypatch.setattr("db.get_deload_periods", lambda: [{
        "started_at":    "2026-10-01",
        "scheduled_end": "2026-10-07",
        "completed_at":  "2026-10-07",
        "duration_days": 7,
        "reason":        "test",
    }])

    rows = []
    log_id = 0
    # 3 séances hors décharge
    for i in range(3):
        log_id += 1
        rows.append(_log(log_id, f"s-ok-{i}", TODAY - timedelta(days=20 + i * 5),
                         name="Bench Press", weight=225, reps=5))
    # 2 séances DANS la décharge
    for i in range(2):
        log_id += 1
        rows.append(_log(log_id, f"s-del-{i}", date(2026, 10, 3 + i),
                         name="Bench Press", weight=135, reps=5))

    import workout_dna as _dna
    lifts = _dna._compute_signature_lifts(_FakeClient(rows), period_days=PERIOD_DAYS)
    bench = next(l for l in lifts if l["name"] == "Bench Press")
    assert bench["session_count"] == 3, (
        f"Attendu 3 séances hors décharge, obtenu {bench['session_count']}"
    )


def test_dna_progression_null_when_subwindow_empty(pinned_today, no_deload, monkeypatch):
    """Lift uniquement actif dans la deuxième moitié de la fenêtre →
    sous-fenêtre early vide → progression_pct=None (jamais 0)."""
    pr_rows = [_pr_row("Late Bloomer", pr_weight=185, pr_e1rm=210, pr_reps=3, pr_date="2026-10-10")]
    monkeypatch.setattr("db.get_exercise_prs", lambda: pr_rows)
    monkeypatch.setattr("db.get_all_exercise_history", lambda **_: {})

    # Toutes les séances dans les 30 derniers jours seulement — rien dans les
    # 30 premiers jours de la fenêtre.
    rows = []
    for i in range(3):
        rows.append(_log(i + 1, f"s-{i}", TODAY - timedelta(days=5 + i * 5),
                         name="Late Bloomer", weight=185, reps=3))

    import workout_dna as _dna
    lifts = _dna._compute_signature_lifts(_FakeClient(rows), period_days=PERIOD_DAYS)
    lift = next(l for l in lifts if l["name"] == "Late Bloomer")
    assert lift["progression_pct"] is None, (
        f"Sous-fenêtre early vide → progression_pct None attendu, obtenu {lift['progression_pct']}"
    )


def test_dna_progression_computed_when_both_subwindows_have_data(pinned_today, no_deload, monkeypatch):
    """Lift actif dans early ET late → progression_pct = (late - early) / early × 100."""
    pr_rows = [_pr_row("Progressing", pr_weight=200, pr_e1rm=215, pr_reps=5, pr_date="2026-10-10")]
    monkeypatch.setattr("db.get_exercise_prs", lambda: pr_rows)
    monkeypatch.setattr("db.get_all_exercise_history", lambda **_: {})

    # Fenêtre DNA 90j = [2026-07-18, 2026-10-15]. Early = jours 1-30
    # (2026-07-18 → 2026-08-16). Late = jours 61-90 (2026-09-16 → 2026-10-15).
    rows = []
    # Early : 150 lbs × 5 reps  → e1RM Epley ≈ 175
    rows.append(_log(1, "s-e1", date(2026, 7, 25), name="Progressing", weight=150, reps=5))
    # Late  : 200 lbs × 5 reps  → e1RM Epley ≈ 233
    rows.append(_log(2, "s-l1", date(2026, 10, 5),  name="Progressing", weight=200, reps=5))
    # Un filler milieu pour éviter session_count=2 (il faut quand même 1 en milieu)
    rows.append(_log(3, "s-m1", date(2026, 9, 1),   name="Progressing", weight=180, reps=5))

    import workout_dna as _dna
    lifts = _dna._compute_signature_lifts(_FakeClient(rows), period_days=PERIOD_DAYS)
    lift = next(l for l in lifts if l["name"] == "Progressing")
    assert lift["progression_pct"] is not None, "les deux sous-fenêtres ont des données"
    assert lift["progression_pct"] > 0, (
        f"Late (200×5) > Early (150×5) → progression > 0, obtenu {lift['progression_pct']}"
    )
    assert lift["first_date"] == "2026-07-25"
    assert lift["last_date"]  == "2026-10-05"


def test_dna_excludes_prs_under_baseline_threshold(pinned_today, no_deload, monkeypatch):
    """baseline_count < 2 (seuil PR tracker) → lift exclu."""
    pr_rows = [
        _pr_row("Qualified", pr_weight=200, pr_e1rm=215, pr_reps=3, pr_date="2026-09-10", baseline=5),
        _pr_row("JustOnce",  pr_weight=100, pr_e1rm=108, pr_reps=3, pr_date="2026-09-11", baseline=1),
    ]
    monkeypatch.setattr("db.get_exercise_prs", lambda: pr_rows)
    monkeypatch.setattr("db.get_all_exercise_history", lambda **_: {})

    rows = []
    for i in range(2):
        rows.append(_log(i + 1, f"s-q-{i}", TODAY - timedelta(days=10 + i * 5),
                         name="Qualified", weight=200, reps=3))
    rows.append(_log(99, "s-jo", TODAY - timedelta(days=5),
                     name="JustOnce", weight=100, reps=3))

    import workout_dna as _dna
    lifts = _dna._compute_signature_lifts(_FakeClient(rows), period_days=PERIOD_DAYS)
    names = {l["name"] for l in lifts}
    assert "Qualified" in names
    assert "JustOnce" not in names


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
