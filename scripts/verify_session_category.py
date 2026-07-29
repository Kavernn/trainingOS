"""Vérification post-migration 085 : classification force/accessory des 20 dernières séances.

Hit l'API déployée (pas la DB directe) avec TRAININGOS_API_KEY du .env.
Signale les cas limites (ratio ∈ [0.35, 0.65]) — candidats à ajuster le seuil.

Usage :
    python3 scripts/verify_session_category.py
    python3 scripts/verify_session_category.py --api-base http://localhost:5000
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


def fetch_debug(api_base: str, token: str) -> dict:
    url = f"{api_base.rstrip('/')}/api/stats/force-vs-accessory?weeks=12&debug=1"
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        return json.loads(resp.read().decode("utf-8"))


def print_table(sample: list[dict]) -> None:
    if not sample:
        print("Aucune séance dans v_session_category (migration appliquée ? séances loggées ?).")
        return
    print(f"{'date':<12} {'session_name':<28} {'category':<10} "
          f"{'ratio':<7} {'force/tot':<10} {'volume':>10}")
    print("-" * 82)
    for r in sample:
        ratio = r.get("ratio_force")
        ratio_str = f"{ratio:.2f}" if ratio is not None else "n/a"
        force_tot = f"{r.get('force_exos', 0)}/{r.get('classified_exos', 0)}"
        name = (r.get("session_name") or "?")[:27]
        print(f"{str(r.get('date', ''))[:10]:<12} {name:<28} "
              f"{r.get('session_category', '?'):<10} {ratio_str:<7} "
              f"{force_tot:<10} {float(r.get('total_volume') or 0):>10.0f}")


def print_borderline(sample: list[dict]) -> None:
    borderline = [
        r for r in sample
        if r.get("ratio_force") is not None and 0.35 <= float(r["ratio_force"]) <= 0.65
    ]
    if borderline:
        print(f"\n⚠️  {len(borderline)} séance(s) proche(s) du seuil 0.5 :")
        for r in borderline:
            print(f"   {str(r.get('date', ''))[:10]}  "
                  f"{(r.get('session_name') or '?')}  "
                  f"ratio={float(r['ratio_force']):.2f}  → {r.get('session_category')}")
    else:
        print("\n✓ Aucun cas limite (ratio ∈ [0.35, 0.65]) — classification franche.")


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
        payload = fetch_debug(args.api_base, token)
    except urllib.error.HTTPError as e:
        print(f"ERROR HTTP {e.code}: {e.read().decode('utf-8', 'replace')[:200]}")
        return 1
    except urllib.error.URLError as e:
        print(f"ERROR réseau: {e}")
        return 1

    sample = payload.get("sample") or []
    print_table(sample)
    print_borderline(sample)

    tl = payload.get("timeline") or []
    if tl:
        weeks = sorted({r["iso_week"] for r in tl})
        print(f"\nTimeline agrégée : {len(tl)} points sur {len(weeks)} semaine(s) "
              f"({weeks[0]} → {weeks[-1]}).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
