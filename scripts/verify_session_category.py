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


def fetch_simulate(api_base: str, token: str) -> dict:
    url = f"{api_base.rstrip('/')}/api/stats/force-vs-accessory/simulate"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


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
        payload = fetch_simulate(args.api_base, token)
    except urllib.error.HTTPError as e:
        print(f"ERROR HTTP {e.code}: {e.read().decode('utf-8', 'replace')[:200]}")
        return 1
    except urllib.error.URLError as e:
        print(f"ERROR réseau: {e}")
        return 1

    print_fill(payload.get("fill") or {})
    sample = payload.get("sample") or []
    print_sample(sample)
    print_borderline(sample)
    print_divergences(sample)
    return 0


if __name__ == "__main__":
    sys.exit(main())
