"""Backfill TUT — zéro-ise set_volume pour les rows exercise_logs d'exos time.

DRY-RUN par défaut (aucune écriture). Passer --execute pour appliquer.

Usage :
  python3 scripts/backfill_tut.py             # dry-run, montre impact
  python3 scripts/backfill_tut.py --execute   # applique (irréversible)
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


def post(url: str, token: str) -> dict:
    req = urllib.request.Request(
        url, method="POST",
        headers={"Authorization": f"Bearer {token}"},
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read().decode("utf-8"))


def print_report(r: dict) -> None:
    if r.get("error"):
        print(f"ERROR: {r['error']}")
        return
    mode = "DRY-RUN" if r.get("dry_run") else "EXÉCUTÉ"
    print(f"── {mode} ──")
    print(f"Exos time détectés ({len(r.get('time_exercises') or [])}) :")
    for name in r.get("time_exercises") or []:
        print(f"  • {name}")
    print()
    print(f"Rows affectées      : {r.get('affected_rows', 0)}")
    print(f"Volume avant        : {r.get('volume_before', 0):,.1f} lbs·s (gonflé)")
    print(f"Volume après        : {r.get('volume_after', 0):,.1f} lbs·s")
    print()
    per_exo = r.get("per_exercise") or {}
    if per_exo:
        print(f"{'exo':<32} {'rows':>6} {'volume avant':>16}")
        print("-" * 60)
        for name, v in per_exo.items():
            print(f"{name[:31]:<32} {v['rows']:>6} {v['volume_before']:>16,.1f}")


def main() -> int:
    execute = "--execute" in sys.argv
    env_path = os.path.join(os.path.dirname(__file__), "..", ".env")
    token = os.environ.get("TRAININGOS_API_KEY") or load_env_key(env_path)
    if not token:
        print("ERROR: TRAININGOS_API_KEY absent (env ou .env).")
        return 1

    dry = "0" if execute else "1"
    url = f"{DEFAULT_API_BASE}/api/stats/tut-backfill?dry_run={dry}"
    try:
        r = post(url, token)
    except urllib.error.HTTPError as e:
        print(f"ERROR HTTP {e.code}: {e.read().decode('utf-8', 'replace')[:200]}")
        return 1
    except urllib.error.URLError as e:
        print(f"ERROR réseau: {e}")
        return 1

    print_report(r)

    if not execute:
        print()
        print("Aperçu seul. Pour appliquer :")
        print("  python3 scripts/backfill_tut.py --execute")
    else:
        print()
        print("Fait. Relance `python3 scripts/audit_pattern_core.py core 28` pour vérifier.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
