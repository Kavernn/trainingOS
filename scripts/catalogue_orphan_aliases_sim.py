"""OLD = curl prod (pre-orphan-alias code, migrated DB).
NEW = local in-memory run (new orphan aliases) against same DB.
Report : muscles avec plage dont séries/zone changent + tuiles orphelines restantes.
"""
import json, os, subprocess, sys
from datetime import date, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "api"))
BASE = "https://training-os-rho.vercel.app"

CANONICAL_WITH_PLAGE = {"Pectoraux","Dos","Épaules","Arrière d'épaule","Trapèzes","Biceps","Triceps","Quadriceps","Ischio-jambiers","Fessiers","Avant-bras","Abdominaux"}
CANONICAL_NO_PLAGE = {"Mollets","Cou","Adducteurs"}
CANONICAL_ALL = CANONICAL_WITH_PLAGE | CANONICAL_NO_PLAGE


def _zone(eff, lmk):
    if lmk is None or eff is None: return "noTarget"
    mev, mav, mrv = lmk["mev_week"], lmk["mav_week"], lmk["mrv_week"]
    if eff < mev: return "belowMEV"
    if eff < mav: return "productive"
    if eff <= mrv: return "high"
    return "overMRV"


def _old_from_prod():
    out = {}
    for days in (30, 90):
        r = subprocess.check_output(["curl","-sS","-H",f"Authorization: Bearer {os.environ['TRAININGOS_API_KEY']}",
            f"{BASE}/api/stats/cockpit?as_of=2026-11-09&progression_days=90&weekly_days=7&muscle_days={days}"])
        d = json.loads(r)
        tbm = d["muscles"]["targets_by_muscle"]
        out[f"{days}d"] = {w["muscle"]: {"eff": w["weekly_effective_sets"], "lmk": tbm.get(w["muscle"])} for w in d["muscles"]["workloads"]}
    return out


def _new_local(client):
    from metric_semantics import DateWindow
    from cockpit_analytics_service import CockpitAnalyticsConfig, build_cockpit_analytics
    from routes.analytics_stats import _serialize_cockpit
    AS_OF = date(2026, 11, 9)
    out = {}
    for days in (30, 90):
        mp = DateWindow(AS_OF - timedelta(days=days-1), AS_OF)
        mpr = DateWindow(mp.start - timedelta(days=days), mp.start - timedelta(days=1))
        cfg = CockpitAnalyticsConfig(as_of=AS_OF, progression_days=90,
            weekly_period=DateWindow(AS_OF - timedelta(days=6), AS_OF),
            muscle_period=mp, muscle_previous_period=mpr)
        d = _serialize_cockpit(build_cockpit_analytics(client, cfg))
        tbm = d["muscles"]["targets_by_muscle"]
        out[f"{days}d"] = {w["muscle"]: {"eff": w["weekly_effective_sets"], "lmk": tbm.get(w["muscle"])} for w in d["muscles"]["workloads"]}
    return out


def main():
    import db_core
    OLD = _old_from_prod()
    NEW = _new_local(db_core._client)

    print("=== Muscles avec plage — Δ séries ou zone ===")
    plage_changes = []
    for days in ("30d","90d"):
        for m in sorted(set(OLD[days]) | set(NEW[days])):
            if m not in CANONICAL_WITH_PLAGE: continue
            o = OLD[days].get(m, {}); n = NEW[days].get(m, {})
            oe, ne = o.get("eff"), n.get("eff")
            oz, nz = _zone(oe, o.get("lmk")), _zone(ne, n.get("lmk"))
            if (oe or 0) != (ne or 0) or oz != nz:
                plage_changes.append(f"  {days} {m:20} {oe or 0:.2f} → {ne or 0:.2f}  zone {oz} → {nz}")
    print("\n".join(plage_changes) if plage_changes else "  (aucun)")

    print("\n=== Tuiles hors canoniques (NEW, après aliases orphelines) ===")
    orphans = set()
    for days in ("30d","90d"):
        for m in NEW[days]:
            if m not in CANONICAL_ALL:
                orphans.add(m)
    print("\n".join(f"  {o}" for o in sorted(orphans)) if orphans else "  (vide)")


if __name__ == "__main__":
    main()
