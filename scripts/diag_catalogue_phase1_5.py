"""
Phase 1.5 — re-detection doublons (normalisation agressive), plyo reconciliation, schemes vides.
READ-ONLY. QUE des SELECT.
"""
from __future__ import annotations
import os, re, unicodedata, collections
from pathlib import Path

root = Path(__file__).resolve().parent.parent
for envf in (root / ".env", root / ".env.local"):
    if envf.exists():
        for line in envf.read_text().splitlines():
            if "=" in line and not line.strip().startswith("#"):
                k, v = line.split("=", 1)
                os.environ.setdefault(k.strip(), v.strip().strip('"').strip("'"))

from supabase import create_client
sb = create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_ANON_KEY"])

# --- normalisation aggressive ---
ABBREV = {
    "db": "dumbbell",
    "bb": "barbell",
    "ext": "extension",
    "oh": "overhead",
    "sl": "single leg",
    "rom": "range of motion",
}

def strip_accents(s: str) -> str:
    return "".join(c for c in unicodedata.normalize("NFD", s)
                   if unicodedata.category(c) != "Mn")

def norm_aggressive(s: str) -> str:
    if not s:
        return ""
    s = s.lower().strip()
    s = strip_accents(s)
    # remplace / - ( ) . et autres ponct. par espace
    s = re.sub(r"[^a-z0-9]+", " ", s)
    s = re.sub(r"\s+", " ", s).strip()
    # deplier abreviations token par token
    tokens = []
    for tok in s.split():
        tokens.append(ABBREV.get(tok, tok))
    # rejoindre puis re-split (abreviations multi-mots)
    s = " ".join(tokens)
    tokens = s.split()
    # strip trailing 's' de chaque token >= 4 chars (evite 'ass'→'as', 'ups'→'up' ok)
    tokens = [t[:-1] if len(t) >= 4 and t.endswith("s") else t for t in tokens]
    return " ".join(tokens)

def fetch_all(table, cols, page=1000):
    out, off = [], 0
    while True:
        res = sb.table(table).select(cols).range(off, off+page-1).execute().data or []
        out.extend(res)
        if len(res) < page:
            break
        off += page
    return out

print("== Charger catalogue + logs + sessions + pbe ==")
ex_all = fetch_all("exercises",
    "id,name,alternate_name,movement_pattern,muscle_group,muscle_specific,"
    "weight_type,tracking_type,default_scheme,deleted_at")
ex = [e for e in ex_all if not e.get("deleted_at")]
print(f"actifs : {len(ex)}")

logs = fetch_all("exercise_logs", "id,exercise_id,session_id")
by_ex_logs = collections.defaultdict(list)
for l in logs:
    by_ex_logs[l["exercise_id"]].append(l)

sess = fetch_all("workout_sessions", "id,date")
sess_date = {s["id"]: s.get("date") for s in sess}

pbe = fetch_all("program_block_exercises", "id,exercise_id,scheme,block_id")
by_ex_pbe = collections.defaultdict(list)
for p in pbe:
    by_ex_pbe[p["exercise_id"]].append(p)

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

# =========================================
# PHASE A : re-detection agressive doublons
# =========================================
print("\n" + "="*70)
print("PHASE A — Doublons via normalisation agressive (name + alternate_name)")
print("="*70)

# Chaque exo genere jusqu'a 2 cles (name, alternate_name), on regroupe sur toutes
buckets = collections.defaultdict(list)  # key -> list[(exo, source)]
seen_pair = set()  # evite d'ajouter 2x le meme exo au meme bucket
for e in ex:
    for source in ("name", "alternate_name"):
        raw = e.get(source)
        if not raw:
            continue
        key = norm_aggressive(raw)
        if not key:
            continue
        pair = (key, e["id"])
        if pair in seen_pair:
            continue
        seen_pair.add(pair)
        buckets[key].append((e, source))

# Un groupe est un bucket contenant >= 2 exos DISTINCTS
groups = {}
for key, lst in buckets.items():
    exids = {e["id"] for e, _ in lst}
    if len(exids) >= 2:
        # dedupe par id (au cas ou meme exo entre par name ET alternate_name)
        by_id = {}
        for e, src in lst:
            by_id.setdefault(e["id"], []).append(src)
        groups[key] = by_id  # id -> list[source]

print(f"\ngroupes trouves : {len(groups)}\n")

for key in sorted(groups.keys()):
    id_to_srcs = groups[key]
    print(f"--- key_norm = {key!r}  ({len(id_to_srcs)} exos)")
    for exid, sources in id_to_srcs.items():
        e = next(x for x in ex if x["id"] == exid)
        st = ex_stats(exid)
        print(f"    • id={exid[:8]}  name={e['name']!r}  alt={e.get('alternate_name')!r}  matched_via={sources}")
        print(f"      mp={e.get('movement_pattern')}  mg={e.get('muscle_group')}  ms={e.get('muscle_specific')}")
        print(f"      wt={e.get('weight_type')}  track={e.get('tracking_type')}  scheme={e.get('default_scheme')!r}")
        print(f"      logs={st['logs']}  sessions={st['sessions']}  dates={st['min']}→{st['max']}  pbe={st['pbe']}")

# Confirmations explicites
print("\n-- confirmations explicites --")
def find_key_containing(sub):
    return [k for k in groups.keys() if sub in k]
tri = find_key_containing("tricep")
neck = find_key_containing("neck curl")
print(f"clefs contenant 'tricep'      : {tri}")
print(f"clefs contenant 'neck curl'   : {neck}")

# =========================================
# PHASE B : reconciliation plyometric
# =========================================
print("\n" + "="*70)
print("PHASE B — Reconciliation movement_pattern='Plyometric'")
print("="*70)
plyo_mp = [e for e in ex if (e.get("movement_pattern") or "").strip().lower() == "plyometric"]
print(f"\nexos avec movement_pattern='Plyometric' (case-insensitive) : {len(plyo_mp)}")
for e in plyo_mp:
    st = ex_stats(e["id"])
    print(f"    • id={e['id'][:8]}  name={e['name']!r}  track={e.get('tracking_type')}  "
          f"mp_exact={e.get('movement_pattern')!r}  mg={e.get('muscle_group')}  "
          f"scheme={e.get('default_scheme')!r}  logs={st['logs']}  pbe={st['pbe']}")

# Variants de casse eventuels
mp_variants = collections.Counter((e.get("movement_pattern") or "") for e in ex)
plyo_variants = {k: v for k, v in mp_variants.items() if "plyo" in k.lower()}
print(f"\nvariantes exactes 'plyo' rencontrees : {dict(plyo_variants)}")

# Cross-check tracking_type='plyo'
plyo_track = [e for e in ex if e.get("tracking_type") == "plyo"]
print(f"\nexos avec tracking_type='plyo' : {len(plyo_track)}")
for e in plyo_track:
    print(f"    • {e['name']!r}  mp={e.get('movement_pattern')!r}")

# =========================================
# PHASE C : schemes vides
# =========================================
print("\n" + "="*70)
print("PHASE C — default_scheme vide ou NULL")
print("="*70)
empty = [e for e in ex if e.get("default_scheme") in (None, "")]
print(f"\ntrouves : {len(empty)}\n")
for e in empty:
    st = ex_stats(e["id"])
    print(f"    • id={e['id']}")
    print(f"      name={e['name']!r}  alternate_name={e.get('alternate_name')!r}")
    print(f"      default_scheme={e.get('default_scheme')!r}  (None si NULL, '' si vide)")
    print(f"      movement_pattern={e.get('movement_pattern')!r}  muscle_group={e.get('muscle_group')!r}  tracking_type={e.get('tracking_type')!r}")
    print(f"      logs={st['logs']}  sessions={st['sessions']}  pbe={st['pbe']}")

print("\n== FIN ==")
