"""Post-apply smoke : read prod cockpit + DNA, compare to T2 simulation values.
Any mismatch > tolerance → report, suggest rollback."""
import json, os, subprocess, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "docs/audits/catalogue-2026-11-09-migration"
BASE = "https://training-os-rho.vercel.app"

def _curl(path: str) -> dict:
    out = subprocess.check_output([
        "curl", "-sS", "-H", f"Authorization: Bearer {os.environ['TRAININGOS_API_KEY']}",
        f"{BASE}{path}",
    ])
    return json.loads(out)


def main():
    t2 = json.loads((OUT / "simulation-v2-T2.json").read_text())
    mismatches = []

    # Cockpit 30d and 90d
    for days in (30, 90):
        prod = _curl(f"/api/stats/cockpit?as_of=2026-11-09&progression_days=90&weekly_days=7&muscle_days={days}")
        prod_by = {w["muscle"]: w["weekly_effective_sets"] for w in prod["muscles"]["workloads"]}
        sim_by = {m: v["weekly_effective_sets"] for m, v in t2[f"{days}d"]["by_muscle"].items()}
        all_muscles = sorted(set(prod_by) | set(sim_by))
        for m in all_muscles:
            p = prod_by.get(m); s = sim_by.get(m)
            ok = p == s or (isinstance(p, float) and isinstance(s, float) and abs(p - s) < 0.001)
            if not ok:
                mismatches.append(("cockpit", f"{days}d", m, s, p))

    # DNA 30d and 90d (top 6)
    for days in (30, 90):
        prod = _curl(f"/api/workout_dna?period={days}")
        prod_dom = [(d["muscle"], d.get("effective_sets")) for d in prod["muscle_dominants"]]
        sim_dom = [(d["muscle"], d.get("effective_sets")) for d in t2[f"{days}d"]["dominants"]]
        if prod_dom != sim_dom:
            mismatches.append(("dna_dominants", f"{days}d", None, sim_dom, prod_dom))

    print(f"Mismatches: {len(mismatches)}")
    for scope, win, muscle, sim, prod in mismatches:
        print(f"  [{scope}/{win}] {muscle}: sim={sim!r} prod={prod!r}")

    (OUT / "post-apply-smoke.json").write_text(json.dumps({"mismatches": mismatches}, ensure_ascii=False, indent=2, default=str))
    if mismatches:
        sys.exit(2)


if __name__ == "__main__":
    main()
