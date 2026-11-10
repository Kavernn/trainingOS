"""Per-exercise contribution trace for Dos and Épaules deltas T1 → T2.

For each exercise whose migration changes direct/indirect muscles OR which
targets Dos / Épaules as primary, computes:
  - direct/indirect sets before and after migration
  - effective_sets contribution to the Dos / Épaules bucket

Confirms whether the ExerciseMuscleAssignment post_init dedup correctly
removes an indirect muscle that collapses to the same canonical group as
the direct muscle.
"""
from __future__ import annotations
import json, sys
from datetime import date, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "api"))

AUTH = ROOT / "docs/audits/catalogue-2026-11-08-rollout/prepared-migration.json"


def run():
    import db_core
    from metric_semantics import DateWindow
    from analytics_adapter import fetch_raw_analytics_rows, _muscle_assignment
    from muscle_workload_analytics import summarize_muscle_workload, INDIRECT_SET_COEFFICIENT
    from analytics_adapter import adapt_analytics_rows, is_deload_day
    client = db_core._client

    AS_OF = date(2026, 11, 9)
    raw_period = DateWindow(AS_OF - timedelta(days=180), AS_OF)
    mp_30 = DateWindow(AS_OF - timedelta(days=29), AS_OF)
    rows = fetch_raw_analytics_rows(client, period=raw_period)
    auth = json.loads(AUTH.read_text())
    target = {r["id"]: r["set"] for r in auth["rows"]}

    patched = []
    for r in rows:
        r2 = json.loads(json.dumps(r))
        if r2.get("exercise_id") in target:
            ex = r2.get("exercises") or {}
            for k, v in target[r2["exercise_id"]].items():
                ex[k] = v
            r2["exercises"] = ex
        patched.append(r2)

    # Both adapt passes
    ad1 = adapt_analytics_rows(rows, period=raw_period)
    ad2 = adapt_analytics_rows(patched, period=raw_period)
    s1 = summarize_muscle_workload(ad1.training_load_exposures, ad1.assignments, period=mp_30, is_deload=lambda d: is_deload_day(d))
    s2 = summarize_muscle_workload(ad2.training_load_exposures, ad2.assignments, period=mp_30, is_deload=lambda d: is_deload_day(d))

    # Per-exercise assignments (before, after)
    asg1 = {a.exercise_name: a for a in ad1.assignments}
    asg2 = {a.exercise_name: a for a in ad2.assignments}
    changed = sorted(set(asg1) | set(asg2))

    print("=== Per-exercise contribution to Dos & Épaules ===\n")
    print(f"{'EXERCISE':34} | {'BEFORE':70} | AFTER")
    print("-" * 160)
    for name in changed:
        a1 = asg1.get(name); a2 = asg2.get(name)
        before = f"direct={a1.direct_muscles if a1 else '—'} indirect={a1.indirect_muscles if a1 else '—'}" if a1 else "—"
        after  = f"direct={a2.direct_muscles if a2 else '—'} indirect={a2.indirect_muscles if a2 else '—'}" if a2 else "—"
        touches_dos_epaules = any(
            m in ("Dos", "Épaules") for asg in (a1, a2) if asg is not None
            for m in (asg.direct_muscles + asg.indirect_muscles)
        )
        if before != after and touches_dos_epaules:
            print(f"{name[:34]:34} | {before[:70]:70} | {after}")

    print("\n=== Muscle workload deltas (30d) — Dos & Épaules ===")
    by1 = {w.muscle: w for w in s1.muscles}
    by2 = {w.muscle: w for w in s2.muscles}
    for m in ("Dos", "Épaules"):
        w1 = by1.get(m); w2 = by2.get(m)
        print(f"{m:10}  before direct={w1.direct_set_count if w1 else 0} indirect={w1.indirect_set_count if w1 else 0}  effective={w1.weekly_effective_sets if w1 else 0:.3f}")
        print(f"{m:10}  after  direct={w2.direct_set_count if w2 else 0} indirect={w2.indirect_set_count if w2 else 0}  effective={w2.weekly_effective_sets if w2 else 0:.3f}")
        print(f"{m:10}  Δ direct=+{(w2.direct_set_count if w2 else 0) - (w1.direct_set_count if w1 else 0)} Δ indirect=+{(w2.indirect_set_count if w2 else 0) - (w1.indirect_set_count if w1 else 0)}  Δ effective=+{(w2.weekly_effective_sets if w2 else 0) - (w1.weekly_effective_sets if w1 else 0):.3f}")
        print()


if __name__ == "__main__":
    run()
