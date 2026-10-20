"""DNA signature lifts = exercise_prs.pr_e1rm_lbs (même source que PR tracker).

Invariant du lot c : pour un même lift, DNA.pr_e1rm_lbs == PR tracker
`last_pr.est_1rm`. Les deux lisent la même table via db.get_exercise_prs
→ égalité par construction, le test protège contre un futur recalcul
divergent dans workout_dna.
"""
from __future__ import annotations

import sys
from datetime import date, timedelta
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "api"))


TODAY = date(2026, 10, 15)


@pytest.fixture
def pinned_today(monkeypatch):
    pinned = TODAY.isoformat()
    monkeypatch.setattr("utils._today_mtl", lambda: pinned)
    return TODAY


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


def _history_entries(dates_weights_reps):
    """[(date_iso, weight, reps_str)] → entries format db.get_all_exercise_history."""
    return [{"date": d, "weight": w, "reps": r, "sets": []} for d, w, r in dates_weights_reps]


def test_dna_pr_e1rm_matches_pr_tracker(pinned_today, monkeypatch):
    """DNA.pr_e1rm_lbs == PR tracker last_pr.est_1rm pour le même lift."""
    pr_rows = [
        _pr_row("Bench Press", pr_weight=225, pr_e1rm=262.5, pr_reps=5, pr_date="2026-09-20"),
        _pr_row("Squat",       pr_weight=315, pr_e1rm=354.4, pr_reps=3, pr_date="2026-10-01"),
    ]
    history = {
        "Bench Press": _history_entries([
            ("2026-04-10", 185, "5"),
            ("2026-09-20", 225, "5"),
        ]),
        "Squat": _history_entries([
            ("2026-05-01", 275, "5"),
            ("2026-10-01", 315, "3"),
        ]),
    }

    monkeypatch.setattr("db.get_exercise_prs", lambda: pr_rows)
    monkeypatch.setattr("db.get_all_exercise_history", lambda **_: history)

    import workout_dna as _dna
    lifts = _dna._compute_signature_lifts(history)
    dna_by_name = {l["name"]: l for l in lifts}

    import pr_tracker_engine as _pr
    pr_payload = _pr.compute()
    last_pr = pr_payload["last_pr"]

    # last_pr pointe sur le lift à pr_date la plus récente — Squat ici.
    assert last_pr is not None, "PR tracker doit renvoyer un last_pr"
    assert last_pr["name"] == "Squat"
    assert dna_by_name["Squat"]["pr_e1rm_lbs"] == last_pr["est_1rm"], (
        f"DNA.Squat.pr_e1rm_lbs={dna_by_name['Squat']['pr_e1rm_lbs']} "
        f"≠ PR tracker last_pr.est_1rm={last_pr['est_1rm']}"
    )

    # Vérification croisée directe : chaque lift DNA == exercise_prs.pr_e1rm_lbs
    for row in pr_rows:
        name = row["exercise_name"]
        if name not in dna_by_name:
            continue
        assert dna_by_name[name]["pr_e1rm_lbs"] == round(row["pr_e1rm_lbs"], 1), (
            f"DNA.{name}.pr_e1rm_lbs={dna_by_name[name]['pr_e1rm_lbs']} "
            f"≠ exercise_prs.pr_e1rm_lbs={row['pr_e1rm_lbs']}"
        )


def test_dna_ranks_by_e1rm_not_raw_weight(pinned_today, monkeypatch):
    """Deux lifts : A avec PR 100 lbs × 10 reps (e1RM ≈ 133), B avec
    PR 150 lbs × 1 rep (e1RM = 150). Max weight dirait A < B, mais le
    ranking par e1RM place B en premier. On vérifie que l'ordre DNA
    correspond au ranking e1RM."""
    pr_rows = [
        _pr_row("Light Reps",  pr_weight=100, pr_e1rm=133.3, pr_reps=10, pr_date="2026-09-01"),
        _pr_row("Heavy Single", pr_weight=150, pr_e1rm=150.0, pr_reps=1,  pr_date="2026-09-02"),
    ]
    history = {
        "Light Reps":   _history_entries([("2026-06-01", 85, "10"), ("2026-09-01", 100, "10")]),
        "Heavy Single": _history_entries([("2026-07-01", 135, "1"), ("2026-09-02", 150, "1")]),
    }
    monkeypatch.setattr("db.get_exercise_prs", lambda: pr_rows)

    import workout_dna as _dna
    lifts = _dna._compute_signature_lifts(history)
    assert len(lifts) == 2
    assert lifts[0]["name"] == "Heavy Single", (
        "Ranking par e1RM : Heavy Single (150) doit passer avant Light Reps (133.3)"
    )
    assert lifts[1]["name"] == "Light Reps"


def test_dna_excludes_prs_under_baseline_threshold(pinned_today, monkeypatch):
    """Lift avec baseline_count < 2 (seuil PR tracker) → exclu."""
    pr_rows = [
        _pr_row("Qualified",    pr_weight=200, pr_e1rm=215, pr_reps=3, pr_date="2026-09-10", baseline=5),
        _pr_row("JustOnce",     pr_weight=100, pr_e1rm=108, pr_reps=3, pr_date="2026-09-11", baseline=1),
    ]
    history = {
        "Qualified": _history_entries([("2026-05-01", 180, "3"), ("2026-09-10", 200, "3")]),
        "JustOnce":  _history_entries([("2026-09-11", 100, "3")]),
    }
    monkeypatch.setattr("db.get_exercise_prs", lambda: pr_rows)

    import workout_dna as _dna
    lifts = _dna._compute_signature_lifts(history)
    names = {l["name"] for l in lifts}
    assert "Qualified" in names
    assert "JustOnce" not in names, "baseline_count=1 doit exclure du top signature"


if __name__ == "__main__":
    pytest.main([__file__, "-v"])
