"""OP6b — Recompute PR canonique Neck Curl (complément OP6) + constat lest.

1. SELECT exercise_prs AVANT recompute pour Neck Curl (canon 10254163)
2. recompute_exercise_pr('Neck Curl')
3. SELECT exercise_prs APRÈS
4. LECTURE SEULE : dump des exercise_logs de Neck Curl pour vérifier si le PR
   weight=45 vient de logs réels avec lest, ou d'une incohérence historique.
"""
from __future__ import annotations
import os, sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
for envf in (root / ".env", root / ".env.local"):
    if envf.exists():
        for line in envf.read_text().splitlines():
            if "=" in line and not line.strip().startswith("#"):
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))

sys.path.insert(0, str(root / "api"))
import db_sessions  # noqa: E402
from supabase import create_client  # noqa: E402

sb = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_ANON_KEY"])
CANON_ID = "10254163-84fd-4bd6-8187-132c40992e72"
NAME = "Neck Curl"


def snapshot_pr():
    pr = (sb.table("exercise_prs")
            .select("exercise_id,pr_e1rm_lbs,pr_weight_lbs,pr_reps,pr_date")
            .eq("exercise_id", CANON_ID)
            .execute()).data or []
    return pr[0] if pr else None


def print_pr(label, pr):
    print(f"\n[{label}] Neck Curl (canon {CANON_ID[:8]})")
    if not pr:
        print("  (aucune ligne exercise_prs)")
    else:
        for k, v in pr.items():
            if k != "exercise_id":
                print(f"  {k:14} = {v}")


print("OP6b — Recompute Neck Curl + constat weight_type=bodyweight vs PR weight=45")

print_pr("AVANT", snapshot_pr())

print(f"\n>>> recompute_exercise_pr({NAME!r}) → ", end="")
print(db_sessions.recompute_exercise_pr(NAME))

print_pr("APRÈS", snapshot_pr())

# ================ LECTURE SEULE : dump logs pour constat lest ================
print(f"\n{'='*66}\nCONSTAT — logs Neck Curl (weight_type=bodyweight)\n{'='*66}")
ex = (sb.table("exercises").select("id,name,weight_type,tracking_type,is_unilateral")
        .eq("id", CANON_ID).execute()).data[0]
print(f"  catalogue: weight_type={ex['weight_type']!r}  tracking_type={ex['tracking_type']!r}  "
      f"is_unilateral={ex.get('is_unilateral')}")

logs = (sb.table("exercise_logs")
          .select("id,session_id,weight,reps,sets_json,workout_sessions(date)")
          .eq("exercise_id", CANON_ID)
          .execute()).data or []

print(f"\n  {len(logs)} log(s) total. Détail (trié par date) :\n")
def date_of(l):
    return (l.get("workout_sessions") or {}).get("date") or ""
logs.sort(key=date_of)
for l in logs:
    d = date_of(l) or "??"
    w = l.get("weight")
    r = l.get("reps")
    sj = l.get("sets_json") or []
    sj_summary = ", ".join(f"{s.get('weight',0)}×{s.get('reps',0)}" for s in sj) if sj else "—"
    print(f"  {d}  weight={w!s:>6}  reps={r!s:<12}  sets_json=[{sj_summary}]")

# Signal : weights uniques (autres que 0/None) dans les logs
weights_non_zero = sorted({float(l["weight"]) for l in logs
                           if l.get("weight") not in (None, 0, "0")})
print(f"\n  Weights non nuls distincts : {weights_non_zero}")
print(f"  PR pr_weight_lbs (post-recompute) : {(snapshot_pr() or {}).get('pr_weight_lbs')}")

print("\n== FIN ==")
