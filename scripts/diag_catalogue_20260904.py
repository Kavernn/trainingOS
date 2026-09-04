"""
Diagnostic READ-ONLY du catalogue exercises.
Phases : 1 doublons + historique, 2 plyometrie, 3 schemes.
QUE des SELECT. Aucun UPDATE/DELETE/INSERT.
"""
from __future__ import annotations
import os, sys, re, unicodedata, json, collections
from pathlib import Path
root = Path(__file__).resolve().parent.parent
for envf in (root / ".env", root / ".env.local"):
    if envf.exists():
        for line in envf.read_text().splitlines():
            if "=" in line and not line.strip().startswith("#"):
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))
from supabase import create_client

URL = os.environ["SUPABASE_URL"]
KEY = os.environ["SUPABASE_ANON_KEY"]
sb = create_client(URL, KEY)

def norm(s: str) -> str:
    if not s: return ""
    s = s.lower().strip()
    s = unicodedata.normalize("NFD", s)
    s = "".join(c for c in s if unicodedata.category(c) != "Mn")
    s = re.sub(r"[^a-z0-9]+", " ", s).strip()
    s = re.sub(r"\s+", " ", s)
    return s

def fetch_all(table, cols, filters=None, page=1000):
    out, off = [], 0
    while True:
        q = sb.table(table).select(cols).range(off, off+page-1)
        if filters:
            for k, v in filters.items():
                q = q.eq(k, v) if v is not None else q.is_(k, "null")
        res = q.execute().data or []
        out.extend(res)
        if len(res) < page: break
        off += page
    return out

print("== Phase 0 : totaux ==")
ex_all = fetch_all("exercises",
    "id,name,alternate_name,category,pattern,movement_pattern,muscle_group,muscle_specific,weight_type,tracking_type,default_scheme,deleted_at,equipment,is_unilateral")
print(f"exercises total (incl deleted) : {len(ex_all)}")
ex = [e for e in ex_all if not e.get("deleted_at")]
print(f"exercises actifs               : {len(ex)}")

# Historique
logs = fetch_all("exercise_logs", "id,exercise_id,session_id")
by_ex_logs = collections.defaultdict(list)
for l in logs:
    by_ex_logs[l["exercise_id"]].append(l)
# dates via workout_sessions
sess = fetch_all("workout_sessions", "id,date")
sess_date = {s["id"]: s.get("date") for s in sess}
# pbe (programme)
pbe = fetch_all("program_block_exercises", "id,exercise_id,scheme,block_id")
by_ex_pbe = collections.defaultdict(list)
for p in pbe:
    by_ex_pbe[p["exercise_id"]].append(p)
print(f"exercise_logs total            : {len(logs)}")
print(f"workout_sessions               : {len(sess)}")
print(f"program_block_exercises rows   : {len(pbe)}")

def ex_stats(exid):
    lst = by_ex_logs.get(exid, [])
    if not lst:
        return {"logs": 0, "sessions": 0, "min": None, "max": None,
                "pbe": len(by_ex_pbe.get(exid, []))}
    sids = {l["session_id"] for l in lst}
    dates = sorted(d for d in (sess_date.get(sid) for sid in sids) if d)
    return {
        "logs": len(lst),
        "sessions": len(sids),
        "min": dates[0] if dates else None,
        "max": dates[-1] if dates else None,
        "pbe": len(by_ex_pbe.get(exid, [])),
    }

# ============ PHASE 1 : doublons ============
print("\n== Phase 1 : doublons (nom_normalise + movement_pattern + muscle_group) ==")
groups = collections.defaultdict(list)
for e in ex:
    key = (norm(e["name"]), (e.get("movement_pattern") or "").lower(),
           (e.get("muscle_group") or "").lower())
    groups[key].append(e)

dupes = {k: v for k, v in groups.items() if len(v) > 1}
print(f"groupes de doublons : {len(dupes)}\n")

for (n, mp, mg), lst in sorted(dupes.items()):
    print(f"--- key = ({n!r}, mp={mp or '∅'}, mg={mg or '∅'}) — {len(lst)} exos")
    for e in lst:
        st = ex_stats(e["id"])
        print(f"    • {e['name']!r}  id={e['id'][:8]}  wt={e.get('weight_type')}  "
              f"track={e.get('tracking_type')}  scheme={e.get('default_scheme')!r}  "
              f"logs={st['logs']}  sessions={st['sessions']}  "
              f"dates={st['min']}→{st['max']}  pbe={st['pbe']}")

# Doublons SUPPLEMENTAIRES : nom normalise seul (peut recouper mp/mg differents)
print("\n== Phase 1b : collisions sur nom normalise SEUL (mp/mg ignores) ==")
by_name = collections.defaultdict(list)
for e in ex:
    by_name[norm(e["name"])].append(e)
name_dupes = {k: v for k, v in by_name.items() if len(v) > 1}
extra = {k: v for k, v in name_dupes.items()
         if not any(k == dk[0] for dk in dupes.keys())}
print(f"collisions nom seul (non listees Phase 1) : {len(extra)}\n")
for n, lst in sorted(extra.items()):
    print(f"--- name_norm={n!r} — {len(lst)} exos")
    for e in lst:
        st = ex_stats(e["id"])
        print(f"    • {e['name']!r}  id={e['id'][:8]}  "
              f"mp={e.get('movement_pattern')}  mg={e.get('muscle_group')}  "
              f"wt={e.get('weight_type')}  scheme={e.get('default_scheme')!r}  "
              f"logs={st['logs']}  sessions={st['sessions']}  pbe={st['pbe']}")

# ============ PHASE 2 : plyometrie ============
print("\n== Phase 2 : plyometrie ==")
PLYO_RE = re.compile(r"\b(jump|saut|box|bond|plyo|drop|clap|depot|explosif|broad|lateral bound|hop|skater|burpee|slam|throw)\b")
plyo_flagged = [e for e in ex if PLYO_RE.search(norm(e["name"]))]
print(f"exos matches heuristiques plyo : {len(plyo_flagged)}\n")

deja_plyo, non_plyo = [], []
for e in plyo_flagged:
    (deja_plyo if e.get("tracking_type") == "plyo" else non_plyo).append(e)

print(f"-- deja tracking_type='plyo' ({len(deja_plyo)}) --")
for e in deja_plyo:
    print(f"    • {e['name']!r}  mp={e.get('movement_pattern')}  "
          f"mg={e.get('muscle_group')}  scheme={e.get('default_scheme')!r}")

print(f"\n-- matches plyo MAIS tracking_type != 'plyo' ({len(non_plyo)}) --")
for e in non_plyo:
    st = ex_stats(e["id"])
    print(f"    • {e['name']!r}  track={e.get('tracking_type')}  "
          f"mp={e.get('movement_pattern')}  mg={e.get('muscle_group')}  "
          f"scheme={e.get('default_scheme')!r}  logs={st['logs']}  pbe={st['pbe']}")

# Verifier : autres exos deja en tracking_type='plyo' non captes par regex
extra_plyo = [e for e in ex if e.get("tracking_type") == "plyo"
              and not PLYO_RE.search(norm(e["name"]))]
print(f"\n-- tracking_type='plyo' NON captes par heuristique nom ({len(extra_plyo)}) --")
for e in extra_plyo:
    print(f"    • {e['name']!r}  mp={e.get('movement_pattern')}")

# ============ PHASE 3 : schemes ============
print("\n== Phase 3 : schemes ==")
scheme_dist = collections.Counter(e.get("default_scheme") for e in ex)
print("Distribution default_scheme (exercises actifs) :")
for s, n in scheme_dist.most_common():
    print(f"    {n:4d}  {s!r}")

# Distribution scheme dans program_block_exercises (utilisation reelle programme)
pbe_scheme_dist = collections.Counter(p.get("scheme") for p in pbe)
print("\nDistribution scheme (program_block_exercises — plans actifs) :")
for s, n in pbe_scheme_dist.most_common():
    print(f"    {n:4d}  {s!r}")

# Croise plyo x scheme
print("\n-- Exos plyo (tracking_type='plyo') + leur default_scheme --")
all_plyo = [e for e in ex if e.get("tracking_type") == "plyo"]
for e in all_plyo:
    pbe_schemes = [p.get("scheme") for p in by_ex_pbe.get(e["id"], [])]
    print(f"    • {e['name']!r}  default_scheme={e.get('default_scheme')!r}  "
          f"pbe_schemes={pbe_schemes}")

# Heuristique hypertrophie : cible ~ 3-4 series x 8-15 reps
HYPER_RE = re.compile(r"^\s*[34]\s*x\s*(?:8|9|10|11|12|13|14|15)(?:\s*-\s*(?:8|9|10|11|12|13|14|15))?\s*$", re.I)
def is_hyper(s):
    return bool(HYPER_RE.match(s or ""))

not_hyper = [(e, e.get("default_scheme")) for e in ex if not is_hyper(e.get("default_scheme"))]
print(f"\n-- exos dont default_scheme n'est PAS hypertrophie (heur 3-4 x 8-15) : {len(not_hyper)} / {len(ex)} --")
buckets = collections.Counter(s for _, s in not_hyper)
for s, n in buckets.most_common(30):
    print(f"    {n:4d}  {s!r}")

print("\n== FIN ==")
