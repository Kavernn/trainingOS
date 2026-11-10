"""Three-state read-only simulation of catalogue state 2026-11-09.

T0 = snapshot captured before the alias push (snapshot-cockpit-dna.json)
T1 = live prod re-read AFTER the alias push, BEFORE migration apply
T2 = in-memory, migration applied on top of T1

Separates the effect of the alias change (T0→T1) from the migration
effect (T1→T2). No DB writes.

Also enforces invariants:
- No sub-region surfaces as autonomous tile in workloads
- Hanches / Autre never appear in workloads
- DNA top-6 muscles are all canonical display groups
"""
from __future__ import annotations
import json, sys
from datetime import date, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "api"))

AUTH = ROOT / "docs/audits/catalogue-2026-11-08-rollout/prepared-migration.json"
OUT = ROOT / "docs/audits/catalogue-2026-11-09-migration"
T0_FILE = OUT / "snapshot-cockpit-dna.json"

# Canonical display groups per _LANDMARK_DISPLAY_FR values. A tile with any
# other muscle name = sub-region surfacing (forbidden by the invariant).
CANONICAL_DISPLAY = {
    "Pectoraux", "Dos", "Épaules", "Arrière d'épaule", "Trapèzes",
    "Biceps", "Triceps", "Quadriceps", "Ischio-jambiers", "Fessiers",
    "Mollets", "Abdominaux", "Avant-bras", "Cou",
}


def _cockpit_full(client, as_of: date, patched_rows=None):
    """Run build_cockpit_analytics against live rows (or in-memory patched).
    Returns dict {30d, 90d} with workloads, targets, dominants."""
    from metric_semantics import DateWindow
    from analytics_adapter import adapt_analytics_rows, fetch_raw_analytics_rows
    from cockpit_analytics_service import CockpitAnalyticsConfig, build_cockpit_analytics
    from routes.analytics_stats import _serialize_cockpit
    from workout_dna import _compute_muscle_dominants

    out = {}
    for days in (30, 90):
        mp = DateWindow(as_of - timedelta(days=days - 1), as_of)
        mpr = DateWindow(mp.start - timedelta(days=days), mp.start - timedelta(days=1))
        cfg = CockpitAnalyticsConfig(
            as_of=as_of, progression_days=90,
            weekly_period=DateWindow(as_of - timedelta(days=6), as_of),
            muscle_period=mp, muscle_previous_period=mpr,
        )
        if patched_rows is not None:
            # Rebuild cockpit from patched rows via adapt_analytics_rows path.
            ad = adapt_analytics_rows(patched_rows, period=cfg.raw_period)
            from muscle_workload_analytics import summarize_muscle_workload
            from cockpit_analytics_service import _build_targets_map
            from analytics_adapter import is_deload_day
            is_dl = lambda d: is_deload_day(d)
            summary = summarize_muscle_workload(ad.training_load_exposures, ad.assignments, period=mp, is_deload=is_dl)
            serialized_workloads = [
                {"muscle": w.muscle, "weekly_effective_sets": w.weekly_effective_sets}
                for w in summary.muscles
            ]
            tbm = _build_targets_map(summary.muscles, ())
            # DNA dominants from the same summary
            scored = [(m.muscle, m.weekly_effective_sets) for m in summary.muscles if (m.weekly_effective_sets or 0) > 0]
            scored.sort(key=lambda t: t[1], reverse=True)
            total = sum(v for _, v in scored) or 1.0
            dominants = [{"muscle": n, "effective_sets": round(v, 1), "pct": round(v / total * 100)} for n, v in scored[:6]]
        else:
            resp = build_cockpit_analytics(client, cfg)
            data = _serialize_cockpit(resp)
            serialized_workloads = data["muscles"]["workloads"]
            tbm = data["muscles"]["targets_by_muscle"]
            dom, _ = _compute_muscle_dominants(client, period_days=days)
            dominants = dom
        out[f"{days}d"] = {
            "by_muscle": {
                w["muscle"]: {
                    "weekly_effective_sets": w["weekly_effective_sets"],
                    "targets": tbm.get(w["muscle"]),
                }
                for w in serialized_workloads
            },
            "dominants": dominants,
        }
    return out


def _patched_rows(client, auth_rows):
    """Fetch 180d raw_rows, patch the 46 exercises' metadata in-memory."""
    from metric_semantics import DateWindow
    from analytics_adapter import fetch_raw_analytics_rows
    AS_OF = date(2026, 11, 9)
    raw_period = DateWindow(AS_OF - timedelta(days=180), AS_OF)
    rows = fetch_raw_analytics_rows(client, period=raw_period)
    target = {r["id"]: r["set"] for r in auth_rows}
    patched = []
    for r in rows:
        r2 = json.loads(json.dumps(r))
        if r2.get("exercise_id") in target:
            ex = r2.get("exercises") or {}
            for k, v in target[r2["exercise_id"]].items():
                ex[k] = v
            r2["exercises"] = ex
        patched.append(r2)
    return patched


def _invariant_check(state_name, state):
    violations = []
    for days in ("30d", "90d"):
        tiles = state[days]["by_muscle"].keys()
        for m in tiles:
            if m not in CANONICAL_DISPLAY:
                violations.append(f"[{state_name}/{days}] tuile non-canonique : {m!r}")
        for d in state[days]["dominants"]:
            if d["muscle"] not in CANONICAL_DISPLAY:
                violations.append(f"[{state_name}/{days}] DNA top-6 non-canonique : {d['muscle']!r}")
    return violations


def _diff_table(label, before, after):
    lines = [f"\n=== {label} ==="]
    for days in ("30d", "90d"):
        b = before[days]["by_muscle"]
        a = after[days]["by_muscle"]
        all_m = sorted(set(b) | set(a))
        header = f"{'WIN':4}  {'MUSCLE':30}  {'SETS_B':>8}  {'SETS_A':>8}  {'Δ':>8}  {'PLAGE':>18}"
        hdr_printed = False
        for m in all_m:
            bv = b.get(m, {}).get("weekly_effective_sets")
            av = a.get(m, {}).get("weekly_effective_sets")
            if bv == av:
                continue
            if not hdr_printed:
                lines.append(header); hdr_printed = True
            bs = f"{bv:.2f}" if bv is not None else "—"
            as_ = f"{av:.2f}" if av is not None else "—"
            delta = f"{(av or 0) - (bv or 0):+.2f}" if (bv is not None or av is not None) else ""
            targets = (a.get(m, {}) or b.get(m, {})).get("targets") or {}
            p = f"{targets.get('mev_week')}/{targets.get('mav_week')}/{targets.get('mrv_week')}" if targets else "—"
            lines.append(f"{days:4}  {m[:30]:30}  {bs:>8}  {as_:>8}  {delta:>8}  {p:>18}")
    return "\n".join(lines)


def main():
    import db_core
    client = db_core._client
    if client is None:
        raise RuntimeError("supabase client unavailable")

    t0 = json.loads(T0_FILE.read_text())  # snapshot captured before alias push
    # Normalize t0 to our output shape (by_muscle + dominants).
    t0_norm = {}
    for days in ("30d", "90d"):
        t0_norm[days] = {
            "by_muscle": {
                w["muscle"]: {
                    "weekly_effective_sets": w.get("weekly_effective_sets"),
                    "targets": t0["cockpit"][days]["targets_by_muscle"].get(w["muscle"]),
                }
                for w in t0["cockpit"][days]["workloads"]
            },
            "dominants": t0["dna"][days],
        }

    AS_OF = date(2026, 11, 9)
    t1 = _cockpit_full(client, AS_OF)  # live after alias push

    auth = json.loads(AUTH.read_text())
    patched = _patched_rows(client, auth["rows"])
    t2 = _cockpit_full(client, AS_OF, patched_rows=patched)

    # Invariants on T1 and T2
    print("=== INVARIANTS ===")
    for name, state in (("T1 (alias live)", t1), ("T2 (alias + migration)", t2)):
        v = _invariant_check(name, state)
        if v:
            for line in v: print("  VIOLATION:", line)
        else:
            print(f"  {name}: OK — zéro tuile hors canonique, DNA top-6 canonique")

    print(_diff_table("T0 → T1 (effet alias seul, sans migration)", t0_norm, t1))
    print(_diff_table("T1 → T2 (effet migration seule)", t1, t2))
    print(_diff_table("T0 → T2 (combiné : alias + migration)", t0_norm, t2))

    print("\n=== DNA muscle_dominants top-6 ===")
    for days in ("30d", "90d"):
        print(f"{days} T0: {[(d['muscle'], d.get('effective_sets')) for d in t0_norm[days]['dominants']]}")
        print(f"{days} T1: {[(d['muscle'], d['effective_sets']) for d in t1[days]['dominants']]}")
        print(f"{days} T2: {[(d['muscle'], d['effective_sets']) for d in t2[days]['dominants']]}")

    (OUT / "simulation-v2-T1.json").write_text(json.dumps(t1, ensure_ascii=False, indent=2, default=str, sort_keys=True))
    (OUT / "simulation-v2-T2.json").write_text(json.dumps(t2, ensure_ascii=False, indent=2, default=str, sort_keys=True))


if __name__ == "__main__":
    main()
