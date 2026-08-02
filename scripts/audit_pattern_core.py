"""Audit pattern volume — décompose le 227K core suspect par exo contributeur.

Hit /api/stats/pattern-volume-breakdown?pattern=core&days=28 et affiche le top
avec tracking_type + weight + reps + volume. Si un exo TIME (Copenhagen Plank,
Deadhang, 90/90) est en tête avec un volume énorme, la formule
calc_exercise_volume (weight × reps sans regarder tracking_type) est coupable.

Usage : python3 scripts/audit_pattern_core.py [pattern] [days]
        pattern défaut = core, days défaut = 28.
"""
from __future__ import annotations

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


def main() -> int:
    pattern = sys.argv[1] if len(sys.argv) > 1 else "core"
    days    = int(sys.argv[2]) if len(sys.argv) > 2 else 28

    env_path = os.path.join(os.path.dirname(__file__), "..", ".env")
    token = os.environ.get("TRAININGOS_API_KEY") or load_env_key(env_path)
    if not token:
        print("ERROR: TRAININGOS_API_KEY absent (env ou .env).")
        return 1

    url = f"{DEFAULT_API_BASE}/api/stats/pattern-volume-breakdown?pattern={pattern}&days={days}"
    try:
        payload = _fetch(url, token)
    except urllib.error.HTTPError as e:
        print(f"ERROR HTTP {e.code}: {e.read().decode('utf-8', 'replace')[:200]}")
        return 1

    breakdown = payload.get("breakdown") or []
    if not breakdown:
        print(f"Aucune contribution pour pattern='{pattern}' sur {days}j.")
        return 0

    total = sum(r["total_volume"] for r in breakdown)
    print(f"── Pattern '{pattern}' — {days}j — total = {total:,} lbs·reps ──")
    print(f"{'name':<28} {'raw pattern':<18} {'track':<7} {'entries':>7} "
          f"{'volume':>10} {'%':>6}")
    print("-" * 90)
    for r in breakdown:
        share = 100 * r["total_volume"] / total if total > 0 else 0
        print(f"{r['name'][:27]:<28} {r.get('movement_pattern_raw', '')[:17]:<18} "
              f"{r.get('tracking_type', '?'):<7} {r['n_entries']:>7} "
              f"{r['total_volume']:>10,} {share:>5.1f}%")

    # Détail sample des 3 top pour voir les valeurs brutes
    print("\n── Sample entries (top 3) ──")
    for r in breakdown[:3]:
        print(f"\n  {r['name']}  ({r.get('tracking_type', '?')})")
        for e in r.get("sample_entries") or []:
            print(f"    {e.get('date')}  w={e.get('weight')}  r={e.get('reps')}  "
                  f"→ vol={e.get('volume')}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
