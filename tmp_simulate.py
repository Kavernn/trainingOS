"""In-memory simulation of catalogue migration effect on cockpit + DNA.

Zero writes. Fetches the current raw analytics rows (with embedded exercises
metadata), patches the 46 target rows with their new values, and re-runs
build_cockpit_analytics + _compute_muscle_dominants on the patched set.
Diffs against the snapshot captured in step 1.
"""
from __future__ import annotations

import json
import sys
from datetime import date, timedelta
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1] / "TrainingOS"
if not (ROOT / "api").exists():
    # fallback when run from /Users/vincentpinard/TrainingOS
    ROOT = Path(__file__).resolve().parents[0]
    if not (ROOT / "api").exists():
        ROOT = Path("/Users/vincentpinard/TrainingOS")

AUTH = ROOT / "docs/audits/catalogue-2026-11-08-rollout/prepared-migration.json"
OUT = ROOT / "docs/audits/catalogue-2026-11-09-migration"
sys.path.insert(0, str(ROOT / "api"))


def _patched_rows_after(client, auth_rows: list[dict]):
    """Fetch wide window raw rows once, return (rows_before, rows_after).
    Each is a list of dict compatible with fetch_raw_analytics_rows output."""
    from metric_semantics import DateWindow
    from analytics_adapter import fetch_raw_analytics_rows

    # Use a window that covers at least the 90d muscle period (needs some margin
    # for strength/progression).
    AS_OF = date(2026, 11, 9)
    raw_period = DateWindow(AS_OF - timedelta(days=180), AS_OF)
    rows = fetch_raw_analytics_rows(client, period=raw_period)
    rows_before = [json.loads(json.dumps(r)) for r in rows]  # deep copy
    target_by_id = {r["id"]: r["set"] for r in auth_rows}
    patched = []
    for r in rows:
        r2 = json.loads(json.dumps(r))
        ex = r2.get("exercises") or {}
        eid = r2.get("exercise_id")
        if eid in target_by_id:
            for k, v in target_by_id[eid].items():
                ex[k] = v
            r2["exercises"] = ex
        patched.append(r2)
    return rows_before, patched, raw_period


def _cockpit(rows: list[dict], raw_period, as_of: date):
    from metric_semantics import DateWindow
    from analytics_adapter import adapt_analytics_rows, is_deload_day
    from muscle_workload_analytics import summarize_muscle_workload
    from cockpit_analytics_service import _build_targets_map, _build_breakdown_map

    ad = adapt_analytics_rows(rows, period=raw_period)
    out = {"cockpit": {}, "dna_dominants": {}}
    for days in (30, 90):
        mp = DateWindow(as_of - timedelta(days=days - 1), as_of)
        is_dl = lambda d: is_deload_day(d)
        summary = summarize_muscle_workload(ad.training_load_exposures, ad.assignments, period=mp, is_deload=is_dl)
        detail_summary = summarize_muscle_workload(ad.training_load_exposures, ad.assignments_detail, period=mp, is_deload=is_dl) if ad.assignments_detail else None
        targets = _build_targets_map(summary.muscles, ())
        breakdown = _build_breakdown_map(summary.muscles, detail_summary.muscles if detail_summary else ())
        out["cockpit"][f"{days}d"] = {
            "by_muscle": {
                w.muscle: {
                    "weekly_effective_sets": w.weekly_effective_sets,
                    "targets": targets.get(w.muscle),
                    "breakdown": [{"muscle": b.muscle, "effective": b.weekly_effective_sets} for b in breakdown.get(w.muscle, ())],
                }
                for w in summary.muscles
            }
        }
        # DNA muscle_dominants replication from workout_dna._compute_muscle_dominants
        scored = [(m.muscle, m.weekly_effective_sets) for m in summary.muscles if (m.weekly_effective_sets or 0) > 0]
        scored.sort(key=lambda t: t[1], reverse=True)
        total = sum(v for _, v in scored) or 1.0
        out["dna_dominants"][f"{days}d"] = [
            {"muscle": n, "effective_sets": round(v, 1), "pct": round(v / total * 100)}
            for n, v in scored[:6]
        ]
    return out


def _zone(eff, landmarks):
    if landmarks is None or eff is None: return "noTarget"
    mev, mav, mrv = landmarks["mev_week"], landmarks["mav_week"], landmarks["mrv_week"]
    if eff < mev: return "belowMEV"
    if eff < mav: return "productive"
    if eff <= mrv: return "high"
    return "overMRV"


def _diff(before, after):
    diffs = []
    for days in ("30d", "90d"):
        b = before["cockpit"][days]["by_muscle"]
        a = after["cockpit"][days]["by_muscle"]
        for m in sorted(set(b) | set(a)):
            bv = b.get(m, {})
            av = a.get(m, {})
            bz = _zone(bv.get("weekly_effective_sets"), bv.get("targets"))
            az = _zone(av.get("weekly_effective_sets"), av.get("targets"))
            if bv.get("weekly_effective_sets") != av.get("weekly_effective_sets") or bz != az or (m not in b) or (m not in a):
                diffs.append((days, m, bv.get("weekly_effective_sets"), av.get("weekly_effective_sets"), bz, az))
    return diffs


def main():
    sys.path.insert(0, str(ROOT / "api"))
    import db_core
    client = db_core._client
    if client is None:
        raise RuntimeError("supabase client unavailable")

    auth = json.loads(AUTH.read_text())
    rows_before, rows_after, raw_period = _patched_rows_after(client, auth["rows"])
    as_of = date(2026, 11, 9)
    before = _cockpit(rows_before, raw_period, as_of)
    after = _cockpit(rows_after, raw_period, as_of)

    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / "simulation-before.json").write_text(json.dumps(before, ensure_ascii=False, indent=2, default=str, sort_keys=True))
    (OUT / "simulation-after.json").write_text(json.dumps(after, ensure_ascii=False, indent=2, default=str, sort_keys=True))

    diffs = _diff(before, after)
    print(f"{'WIN':4}  {'MUSCLE':34}  {'SETS_B':>8} → {'SETS_A':>8}  {'ZONE_B':>12} → {'ZONE_A':>12}")
    for days, m, bs, as_, bz, az in diffs:
        bs_s = f"{bs:.2f}" if bs is not None else "—"
        as_s = f"{as_:.2f}" if as_ is not None else "—"
        print(f"{days:4}  {m[:34]:34}  {bs_s:>8} → {as_s:>8}  {bz:>12} → {az:>12}")

    print(f"\n### DNA muscle_dominants")
    for days in ("30d", "90d"):
        print(f"{days}:")
        print(f"  AVANT: {[(m['muscle'], m['effective_sets']) for m in before['dna_dominants'][days]]}")
        print(f"  APRÈS: {[(m['muscle'], m['effective_sets']) for m in after['dna_dominants'][days]]}")


if __name__ == "__main__":
    main()
