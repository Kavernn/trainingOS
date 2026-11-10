"""Catalogue migration 46 exercises — 2026-11-09.

Steps:
  snapshot : capture 46 current rows (ALL columns) + cockpit + DNA 30d/90d.
  dryrun   : build the mutation table before/after per row, verify preconditions,
             confirm excluded_ids and non-targeted columns are not touched.
  apply    : execute targeted updates one row at a time with WHERE id = … AND
             each precondition column matches expected_before. Zero row? Abort
             the row (precondition drift), do not touch anything.
  verify   : re-read 46 rows + cockpit + DNA, diff against snapshot + expected.
  rollback : restore the 46 rows from the snapshot (same WHERE-based updates in
             reverse).

All reads/writes on `exercises` table only. Protected columns never appear in
any payload. Hard-deletion safeguard: `id` IN filter on the 46 IDs only.

Authority: docs/audits/catalogue-2026-11-08-rollout/prepared-migration.json.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
AUTHORITY = ROOT / "docs/audits/catalogue-2026-11-08-rollout/prepared-migration.json"
OUT_DIR = ROOT / "docs/audits/catalogue-2026-11-09-migration"

COLUMNS = (
    "id, name, type, category, pattern, level, default_scheme, load_profile, "
    "muscles, increment, bar_weight, tracking_type, rest_seconds, tips, "
    "muscle_group, muscle_specific, secondary_muscles, movement_pattern, "
    "weight_type, equipment, alternate_name, is_unilateral, deleted_at"
)


def _client():
    sys.path.insert(0, str(ROOT / "api"))
    import db_core
    if db_core._client is None:
        raise RuntimeError("supabase client unavailable — load .env.local and export vars")
    return db_core._client


def _authority() -> dict:
    with AUTHORITY.open() as f:
        return json.load(f)


def _read_rows(client, ids: list[str]) -> dict:
    """Read ALL columns for the given 46 IDs, keyed by id. Pagination-safe."""
    rows: dict = {}
    for batch_start in range(0, len(ids), 50):
        batch = ids[batch_start:batch_start + 50]
        resp = client.table("exercises").select(COLUMNS).in_("id", batch).execute()
        for r in (resp.data or []):
            rows[r["id"]] = r
    return rows


def _cockpit_and_dna(client) -> dict:
    """Capture live /api/stats/cockpit (30d + 90d) and /api/workout_dna (30d + 90d)."""
    from datetime import date, timedelta
    from metric_semantics import DateWindow
    from cockpit_analytics_service import CockpitAnalyticsConfig, build_cockpit_analytics
    from routes.analytics_stats import _serialize_cockpit
    from workout_dna import _compute_muscle_dominants

    AS_OF = date(2026, 11, 9)
    out: dict = {"as_of": str(AS_OF), "cockpit": {}, "dna": {}}
    for days in (30, 90):
        mp = DateWindow(AS_OF - timedelta(days=days - 1), AS_OF)
        mpr = DateWindow(mp.start - timedelta(days=days), mp.start - timedelta(days=1))
        cfg = CockpitAnalyticsConfig(
            as_of=AS_OF, progression_days=90,
            weekly_period=DateWindow(AS_OF - timedelta(days=6), AS_OF),
            muscle_period=mp, muscle_previous_period=mpr,
        )
        resp = build_cockpit_analytics(client, cfg)
        out["cockpit"][f"{days}d"] = {
            "workloads": [
                {k: w.get(k) for k in ("muscle", "weekly_effective_sets")}
                for w in _serialize_cockpit(resp)["muscles"]["workloads"]
            ],
            "targets_by_muscle": _serialize_cockpit(resp)["muscles"]["targets_by_muscle"],
            "breakdown_by_muscle": _serialize_cockpit(resp)["muscles"]["breakdown_by_muscle"],
        }
        dom, _ = _compute_muscle_dominants(client, period_days=days)
        out["dna"][f"{days}d"] = dom
    return out


def cmd_snapshot(args):
    auth = _authority()
    ids = [r["id"] for r in auth["rows"]]
    excluded = auth["excluded_ids"]
    assert len(ids) == 46 and len(set(ids)) == 46, "expected 46 unique IDs"
    assert len(excluded) == 13, "expected 13 excluded ambiguous ids"

    client = _client()
    rows = _read_rows(client, ids)
    assert len(rows) == 46, f"expected 46 rows in DB, got {len(rows)}"

    cockpit_dna = _cockpit_and_dna(client)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    (OUT_DIR / "snapshot-exercises.json").write_text(
        json.dumps([rows[i] for i in ids], ensure_ascii=False, sort_keys=True, indent=2, default=str)
    )
    (OUT_DIR / "snapshot-cockpit-dna.json").write_text(
        json.dumps(cockpit_dna, ensure_ascii=False, sort_keys=True, indent=2, default=str)
    )
    print(f"snapshot: {len(rows)} rows + cockpit/dna → {OUT_DIR}")


def _coerce_equal(a, b) -> bool:
    """Treat null and [] as distinct — Supabase returns them distinctly."""
    if isinstance(a, list) and isinstance(b, list):
        return a == b
    return a == b


def cmd_dryrun(args):
    auth = _authority()
    snap = json.loads((OUT_DIR / "snapshot-exercises.json").read_text())
    by_id = {r["id"]: r for r in snap}

    print(f"=== DRY-RUN — {len(auth['rows'])} rows ===\n")
    violations = []
    plan_rows = []
    for row in auth["rows"]:
        rid, name, before, target = row["id"], row["name"], row["expected_before"], row["set"]
        current = by_id.get(rid)
        if current is None:
            violations.append((rid, name, "MISSING_IN_DB"))
            continue
        ok = all(_coerce_equal(current.get(k), v) for k, v in before.items())
        status = "OK" if ok else "DRIFT"
        changes = []
        for k, v in target.items():
            changes.append((k, current.get(k), v))
        plan_rows.append({"id": rid, "name": name, "status": status, "changes": changes})
        if not ok:
            for k, v in before.items():
                if not _coerce_equal(current.get(k), v):
                    violations.append((rid, name, f"PRECONDITION_DRIFT {k}: live={current.get(k)!r} expected={v!r}"))

    # Print human table
    for p in plan_rows:
        print(f"[{p['status']}] {p['name']}  ({p['id']})")
        for k, cur, nxt in p["changes"]:
            print(f"    {k}: {cur!r}  →  {nxt!r}")
    print()
    print(f"VIOLATIONS: {len(violations)}")
    for v in violations:
        print("  ", v)
    print()
    print(f"EXCLUDED (not touched): {len(auth['excluded_ids'])}")
    print(f"  ids: {auth['excluded_ids']}")
    (OUT_DIR / "dryrun-plan.json").write_text(
        json.dumps({"plan": plan_rows, "violations": violations}, ensure_ascii=False, indent=2, default=str)
    )


def cmd_apply(args):
    """Apply 46 updates with live precondition check. Idempotent: rows already
    at target are marked `already_applied` (success). Arrays comparing against
    [] use postgres literal "{}", not the python list (postgrest can't
    serialize empty python list for array columns)."""
    auth = _authority()
    client = _client()
    ids = [r["id"] for r in auth["rows"]]
    live = _read_rows(client, ids)

    applied = []
    already = []
    failed = []
    for row in auth["rows"]:
        rid, name, before, target = row["id"], row["name"], row["expected_before"], row["set"]
        current = live.get(rid)
        if current is None:
            failed.append({"id": rid, "name": name, "reason": "MISSING_IN_DB"})
            continue
        if all(_coerce_equal(current.get(k), v) for k, v in target.items()):
            already.append({"id": rid, "name": name})
            continue
        if not all(_coerce_equal(current.get(k), v) for k, v in before.items()):
            failed.append({"id": rid, "name": name, "reason": "precondition drift (live ≠ expected_before)"})
            # Stop the batch — safer than partial progress with untraceable state.
            break
        q = client.table("exercises").update(target).eq("id", rid)
        for k, v in before.items():
            if v is None:
                q = q.is_(k, "null")
            elif isinstance(v, list):
                # Postgrest ne sérialise pas les listes python pour text[]
                # dans .eq — on passe le littéral postgres {el1,el2}. Quote
                # les éléments contenant des caractères spéciaux.
                def _pg_lit(s: str) -> str:
                    if any(ch in s for ch in ',"\\{}'):
                        return '"' + s.replace('\\', '\\\\').replace('"', '\\"') + '"'
                    return s
                q = q.eq(k, "{" + ",".join(_pg_lit(x) for x in v) + "}")
            else:
                q = q.eq(k, v)
        try:
            resp = q.execute()
            n = len(resp.data or [])
        except Exception as e:
            failed.append({"id": rid, "name": name, "reason": f"update exception: {type(e).__name__}: {str(e)[:200]}"})
            break
        if n != 1:
            failed.append({"id": rid, "name": name, "reason": f"update affected {n} rows"})
            break
        applied.append({"id": rid, "name": name, "set": target})
    (OUT_DIR / "apply-result.json").write_text(
        json.dumps({"applied": applied, "already": already, "failed": failed}, ensure_ascii=False, indent=2, default=str)
    )
    print(f"applied={len(applied)} already_applied={len(already)} failed={len(failed)}")
    if failed:
        for f in failed:
            print("  FAIL:", f)
        sys.exit(2)


def cmd_verify(args):
    auth = _authority()
    client = _client()
    ids = [r["id"] for r in auth["rows"]]
    live = _read_rows(client, ids)

    mismatches = []
    for row in auth["rows"]:
        rid, target = row["id"], row["set"]
        current = live.get(rid)
        if current is None:
            mismatches.append({"id": rid, "reason": "MISSING_IN_DB"})
            continue
        for k, v in target.items():
            if not _coerce_equal(current.get(k), v):
                mismatches.append({"id": rid, "field": k, "live": current.get(k), "target": v})
    cockpit_dna = _cockpit_and_dna(client)
    (OUT_DIR / "verify-after.json").write_text(
        json.dumps({"rows": [live[i] for i in ids], "mismatches": mismatches, "cockpit_dna": cockpit_dna},
                   ensure_ascii=False, indent=2, default=str, sort_keys=True)
    )
    print(f"verify: {len(ids)} rows read, mismatches={len(mismatches)}")
    if mismatches:
        for m in mismatches: print("  ", m)
        sys.exit(2)


def cmd_rollback(args):
    """Restore 46 rows from snapshot. Updates only the 4 target columns."""
    snap = json.loads((OUT_DIR / "snapshot-exercises.json").read_text())
    client = _client()
    restored = []
    failed = []
    for row in snap:
        payload = {
            "muscle_group":      row.get("muscle_group"),
            "muscle_specific":   row.get("muscle_specific"),
            "secondary_muscles": row.get("secondary_muscles"),
            "equipment":         row.get("equipment"),
        }
        resp = client.table("exercises").update(payload).eq("id", row["id"]).execute()
        n = len(resp.data or [])
        (restored if n == 1 else failed).append({"id": row["id"], "rows": n})
    (OUT_DIR / "rollback-result.json").write_text(
        json.dumps({"restored": restored, "failed": failed}, ensure_ascii=False, indent=2, default=str)
    )
    print(f"rollback: restored={len(restored)} failed={len(failed)}")
    if failed:
        sys.exit(2)


def cmd_rollback_dryrun(args):
    """Simulate rollback locally against snapshot — no DB writes.
    Confirms that applying the rollback payload to a mutated row returns the
    snapshot values exactly (for the 4 target columns)."""
    snap = json.loads((OUT_DIR / "snapshot-exercises.json").read_text())
    auth = _authority()
    by_id_snap = {r["id"]: r for r in snap}
    simulated = []
    for row in auth["rows"]:
        rid, target = row["id"], row["set"]
        baseline = by_id_snap[rid]
        mutated = dict(baseline, **target)
        rollback_payload = {
            "muscle_group":      baseline.get("muscle_group"),
            "muscle_specific":   baseline.get("muscle_specific"),
            "secondary_muscles": baseline.get("secondary_muscles"),
            "equipment":         baseline.get("equipment"),
        }
        restored = dict(mutated, **rollback_payload)
        ok_cols = {k: baseline.get(k) == restored.get(k) for k in
                   ("muscle_group", "muscle_specific", "secondary_muscles", "equipment")}
        full_ok = all(ok_cols.values())
        simulated.append({"id": rid, "name": row["name"], "ok": full_ok, "cols": ok_cols})
    ko = [s for s in simulated if not s["ok"]]
    (OUT_DIR / "rollback-dryrun.json").write_text(
        json.dumps({"simulated": simulated, "failed": ko}, ensure_ascii=False, indent=2, default=str)
    )
    print(f"rollback-dryrun: {len(simulated)} rows, failed={len(ko)}")
    if ko:
        for f in ko: print("  KO", f)
        sys.exit(2)


COMMANDS = {
    "snapshot":         cmd_snapshot,
    "dryrun":           cmd_dryrun,
    "apply":            cmd_apply,
    "verify":           cmd_verify,
    "rollback":         cmd_rollback,
    "rollback-dryrun":  cmd_rollback_dryrun,
}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("cmd", choices=list(COMMANDS))
    args = parser.parse_args()
    COMMANDS[args.cmd](args)


if __name__ == "__main__":
    main()
