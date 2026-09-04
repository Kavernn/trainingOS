"""OP6 — Recompute des PR canoniques après merges OP4/OP5.

Cible :
  - Triceps Pushdown  (canon fc506d23 ← 6f0a128f)
  - Reverse curls     (canon b953ce24 ← 62d0bf52)
Le PR canon est stale : il indexe l'ancien historique, avant absorption des logs
du dup. recompute_exercise_pr() rejoue estimate_1rm() (source unique Python) sur
tous les logs de l'exo — ceux du canon + les repointés — et upsert le meilleur.

Idempotent : re-run = même résultat.
READ + WRITE (upsert exercise_prs). Aucune écriture ailleurs.
"""
from __future__ import annotations
import os, sys
from pathlib import Path

# Load env (ordre : .env puis .env.local — surchargeable)
root = Path(__file__).resolve().parent.parent
for envf in (root / ".env", root / ".env.local"):
    if envf.exists():
        for line in envf.read_text().splitlines():
            if "=" in line and not line.strip().startswith("#"):
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))

# Import api layer (les env doivent être settled AVANT — db_core lit les env à l'import)
sys.path.insert(0, str(root / "api"))
import db_sessions  # noqa: E402
from supabase import create_client  # noqa: E402

sb = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_ANON_KEY"])

NAMES = ["Triceps Pushdown", "Reverse curls"]


def snapshot_pr(names):
    out = []
    for name in names:
        rows = (
            sb.table("exercises")
              .select("id,name")
              .eq("name", name)
              .is_("deleted_at", "null")
              .execute()
        ).data or []
        if not rows:
            out.append({"name": name, "id": None, "pr": None,
                        "error": f"exercice ''{name}'' introuvable (deleted_at IS NULL)"})
            continue
        if len(rows) > 1:
            out.append({"name": name, "id": None, "pr": None,
                        "error": f"exercice ''{name}'' ambigu ({len(rows)} rows)"})
            continue
        exid = rows[0]["id"]
        pr = (
            sb.table("exercise_prs")
              .select("exercise_id,pr_e1rm_lbs,pr_weight_lbs,pr_reps,pr_date")
              .eq("exercise_id", exid)
              .execute()
        ).data or []
        out.append({"name": name, "id": exid, "pr": pr[0] if pr else None})
    return out


def print_snapshot(label, snap):
    print(f"\n{'='*66}\n{label}\n{'='*66}")
    for e in snap:
        head = f"{e['name']!r}  id={e['id'][:8] if e.get('id') else '——'}"
        print(f"\n  {head}")
        if e.get("error"):
            print(f"    ⚠ {e['error']}")
            continue
        pr = e.get("pr")
        if not pr:
            print(f"    (aucune ligne exercise_prs)")
            continue
        print(f"    pr_e1rm_lbs   = {pr.get('pr_e1rm_lbs')}")
        print(f"    pr_weight_lbs = {pr.get('pr_weight_lbs')}")
        print(f"    pr_reps       = {pr.get('pr_reps')}")
        print(f"    pr_date       = {pr.get('pr_date')}")


print("OP6 — Recompute des PR canoniques (Pushdown + Reverse curls)")

before = snapshot_pr(NAMES)
print_snapshot("[AVANT] recompute", before)

print(f"\n{'='*66}\nRECOMPUTE (source unique estimate_1rm côté Python)\n{'='*66}")
for name in NAMES:
    ok = db_sessions.recompute_exercise_pr(name)
    print(f"  recompute_exercise_pr({name!r}) → {ok}")

after = snapshot_pr(NAMES)
print_snapshot("[APRÈS] recompute", after)

print(f"\n{'='*66}\nDELTA\n{'='*66}")
for b, a in zip(before, after):
    name = b["name"]
    bpr = b.get("pr") or {}
    apr = a.get("pr") or {}
    b_e1 = bpr.get("pr_e1rm_lbs")
    a_e1 = apr.get("pr_e1rm_lbs")
    if b_e1 is None or a_e1 is None:
        change = "N/A"
    else:
        b_f, a_f = float(b_e1), float(a_e1)
        if a_f > b_f:
            change = f"↑ +{a_f - b_f:.2f}  (un log fusionné bat l'ancien PR)"
        elif a_f < b_f:
            change = f"↓ {a_f - b_f:.2f}  (⚠ recompute LOWER — investigation requise)"
        else:
            change = "= (inchangé — aucun log fusionné ne bat)"
    print(f"  {name!r:22}  e1rm {b_e1} → {a_e1}   {change}")

print("\n== FIN ==")
