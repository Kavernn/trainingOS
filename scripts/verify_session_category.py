"""Vérification classification force/accessory : hit /api/stats/force-vs-accessory/simulate.

Affiche :
  1) Remplissage : combien d'exos ont category vs load_profile
  2) 20 dernières séances avec breakdown catégories + 2 variantes de classification
  3) Cas limites (ratio ∈ [0.35, 0.65]) et divergences entre les variantes

Usage : python3 scripts/verify_session_category.py
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request

DEFAULT_API_BASE = "https://training-os-rho.vercel.app"


def load_env_key(env_path: str) -> str | None:
    if not os.path.isfile(env_path):
        return None
    with open(env_path) as f:
        for line in f:
            line = line.strip()
            if line.startswith("TRAININGOS_API_KEY="):
                return line.split("=", 1)[1].strip().strip('"').strip("'")
    return None


def _fetch(url: str, token: str) -> dict:
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def fetch_simulate(api_base: str, token: str) -> dict:
    return _fetch(f"{api_base.rstrip('/')}/api/stats/force-vs-accessory/simulate", token)


def fetch_view_sample(api_base: str, token: str) -> list[dict]:
    """Hit la vue réelle v_session_category via l'endpoint ?debug=1."""
    payload = _fetch(f"{api_base.rstrip('/')}/api/stats/force-vs-accessory?debug=1", token)
    return payload.get("sample") or []


def print_fill(fill: dict) -> None:
    total = fill.get("total_exercises", 0)
    wcat  = fill.get("with_category", 0)
    wlp   = fill.get("with_load_profile", 0)
    print("── REMPLISSAGE ────────────────────────────────────────────────────────")
    print(f"total exos : {total}")
    print(f"  category     : {wcat:4d} ({100*wcat/total if total else 0:.0f}%)")
    print(f"  load_profile : {wlp:4d} ({100*wlp/total if total else 0:.0f}%)")
    by_cat = fill.get("by_category") or {}
    if by_cat:
        print("  par category :")
        for k in sorted(by_cat, key=lambda x: -by_cat[x]):
            print(f"    {k:<12} {by_cat[k]}")
    print()


def _fmt_breakdown(b: dict) -> str:
    # Ordre canonique + compact : "push:3 pull:2 legs:1 core:1"
    order = ["push", "pull", "legs", "strength", "core", "(null)"]
    parts = []
    for k in order:
        if k in b:
            parts.append(f"{k[:4]}:{b[k]}")
    for k in b:
        if k not in order:
            parts.append(f"{k[:4]}:{b[k]}")
    return " ".join(parts) or "-"


def print_sample(sample: list[dict]) -> None:
    if not sample:
        print("Aucune séance trouvée.")
        return
    print("── 20 DERNIÈRES SÉANCES ───────────────────────────────────────────────")
    print(f"{'date':<12} {'session_name':<24} {'breakdown':<32} "
          f"{'A ratio→cat':<15} {'B ratio→cat':<15}")
    print("-" * 100)
    for r in sample:
        vA = r.get("variant_A") or {}
        vB = r.get("variant_B") or {}
        rA = vA.get("ratio")
        rB = vB.get("ratio")
        sA = f"{rA:.2f}→{vA.get('category', '?')}" if rA is not None else f"n/a→{vA.get('category', '?')}"
        sB = f"{rB:.2f}→{vB.get('category', '?')}" if rB is not None else f"n/a→{vB.get('category', '?')}"
        name = (r.get("session_name") or "?")[:23]
        bd = _fmt_breakdown(r.get("breakdown") or {})[:31]
        print(f"{r.get('date', '')[:10]:<12} {name:<24} {bd:<32} {sA:<15} {sB:<15}")
    print()


def print_borderline(sample: list[dict]) -> None:
    for label, key in [("A", "variant_A"), ("B", "variant_B")]:
        borderline = [
            r for r in sample
            if (r.get(key) or {}).get("ratio") is not None
            and 0.35 <= (r[key]["ratio"]) <= 0.65
        ]
        if borderline:
            print(f"⚠️  Variante {label} — {len(borderline)} cas limite(s) (ratio ∈ [0.35, 0.65]) :")
            for r in borderline:
                v = r[key]
                print(f"   {r.get('date', '')}  {r.get('session_name', '?')}  "
                      f"ratio={v['ratio']:.2f}  → {v['category']}")
        else:
            print(f"✓ Variante {label} — aucun cas limite (classification franche).")


def print_divergences(sample: list[dict]) -> None:
    diverge = [
        r for r in sample
        if (r.get("variant_A") or {}).get("category") != (r.get("variant_B") or {}).get("category")
    ]
    if diverge:
        print(f"\n⚡ {len(diverge)} séance(s) où A et B DIVERGENT (arbitre : strength = force ou accessory ?) :")
        for r in diverge:
            print(f"   {r.get('date', '')}  {r.get('session_name', '?'):<20}  "
                  f"A→{r['variant_A']['category']}  B→{r['variant_B']['category']}  "
                  f"| breakdown : {_fmt_breakdown(r.get('breakdown') or {})}")
    else:
        print("\n✓ A et B classent tout de la même façon (le sort de 'strength' ne change rien).")


def cross_check_view_vs_simulation(view_sample: list[dict], sim_sample: list[dict]) -> int:
    """Compare la vue réelle à la simulation (variante A). Appariement par session_id
    (pas par date : plusieurs séances peuvent partager le même jour). Retourne nb divergences."""
    sim_by_sid = {r.get("session_id"): r for r in sim_sample if r.get("session_id")}
    mismatches = []
    compared = 0
    for v in view_sample:
        sid = v.get("session_id")
        if not sid:
            continue
        s = sim_by_sid.get(sid)
        if not s:
            continue
        compared += 1
        view_cat = v.get("session_category")
        sim_cat  = (s.get("variant_A") or {}).get("category")
        if view_cat != sim_cat:
            mismatches.append((v.get("date"), v.get("session_name"), view_cat, sim_cat))
    print("\n── COHÉRENCE VUE ↔ SIMULATION (variante A, apparié par session_id) ────")
    if compared == 0:
        print("(aucune paire session_id partagée entre vue et simulation)")
        return 0
    if not mismatches:
        print(f"✓ Vue base et simulation identiques sur {compared} séance(s).")
    else:
        print(f"✗ {len(mismatches)} divergence(s) sur {compared} comparaison(s) :")
        for d, name, view_cat, sim_cat in mismatches:
            print(f"   {d}  {name}  vue={view_cat}  ≠  sim={sim_cat}")
    return len(mismatches)


def assert_core_mobility_is_accessory(view_sample: list[dict]) -> int:
    """Garde-fou : toute séance nommée 'Core & Mobilité' doit être 'accessory'."""
    hits = [
        r for r in view_sample
        if "core" in (r.get("session_name") or "").lower()
        and "mob" in (r.get("session_name") or "").lower()
    ]
    print("\n── ASSERTION : Core & Mobilité DOIT être 'accessory' ─────────────────")
    if not hits:
        print("(aucune séance 'Core & Mobilité' dans le sample — assertion non exercée)")
        return 0
    fails = [r for r in hits if r.get("session_category") != "accessory"]
    if not fails:
        print(f"✓ {len(hits)} séance(s) Core & Mobilité — toutes classées 'accessory'.")
    else:
        print(f"✗ {len(fails)} séance(s) Core & Mobilité MAL classée(s) :")
        for r in fails:
            print(f"   {r.get('date')}  ratio={r.get('ratio_force')}  → {r.get('session_category')}")
    return len(fails)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--api-base", default=DEFAULT_API_BASE)
    parser.add_argument("--env", default=os.path.join(os.path.dirname(__file__), "..", ".env"))
    args = parser.parse_args()

    token = os.environ.get("TRAININGOS_API_KEY") or load_env_key(args.env)
    if not token:
        print("ERROR: TRAININGOS_API_KEY absent (env ou .env).")
        return 1

    try:
        sim_payload = fetch_simulate(args.api_base, token)
        view_sample = fetch_view_sample(args.api_base, token)
    except urllib.error.HTTPError as e:
        print(f"ERROR HTTP {e.code}: {e.read().decode('utf-8', 'replace')[:200]}")
        return 1
    except urllib.error.URLError as e:
        print(f"ERROR réseau: {e}")
        return 1

    print_fill(sim_payload.get("fill") or {})
    sim_sample = sim_payload.get("sample") or []
    print_sample(sim_sample)
    print_borderline(sim_sample)
    print_divergences(sim_sample)

    divergences = cross_check_view_vs_simulation(view_sample, sim_sample)
    core_fails  = assert_core_mobility_is_accessory(view_sample)
    return 0 if (divergences == 0 and core_fails == 0) else 2


if __name__ == "__main__":
    sys.exit(main())
